import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Conservatively shortens low-energy pauses in a normalized PCM WAV.
Future<void> shortenInternalPauses(File file) async {
  File? temporary;
  try {
    final bytes = await file.readAsBytes();
    final result = shortenSilentPcmWav(bytes);
    if (identical(result, bytes)) return;
    temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.pause.tmp',
    );
    await temporary.writeAsBytes(result, flush: true);
    await temporary.rename(file.path);
  } catch (_) {
    // Keep the original recording if optional processing fails.
  } finally {
    try {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    } catch (_) {}
  }
}

Uint8List shortenSilentPcmWav(Uint8List bytes) {
  if (bytes.length < 44) return bytes;
  bool tag(int at, String text) =>
      text.codeUnits.asMap().entries.every((e) => bytes[at + e.key] == e.value);
  final data = ByteData.sublistView(bytes);
  if (!tag(0, 'RIFF') ||
      !tag(8, 'WAVE') ||
      !tag(12, 'fmt ') ||
      !tag(36, 'data') ||
      data.getUint32(16, Endian.little) != 16 ||
      data.getUint16(20, Endian.little) != 1 ||
      data.getUint16(34, Endian.little) != 16 ||
      data.getUint32(4, Endian.little) != bytes.length - 8 ||
      data.getUint32(40, Endian.little) != bytes.length - 44) {
    return bytes;
  }
  final channels = data.getUint16(22, Endian.little);
  final rate = data.getUint32(24, Endian.little);
  if ((channels != 1 && channels != 2) || rate < 8000 || rate > 192000) {
    return bytes;
  }
  final frameBytes = channels * 2;
  if ((bytes.length - 44) % frameBytes != 0) return bytes;
  final frames = (bytes.length - 44) ~/ frameBytes;
  final samplesPerWindow = rate ~/ 50;
  final windowCount = frames ~/ samplesPerWindow;
  if (windowCount < 2) return bytes;
  final energies = <double>[];
  for (var window = 0; window < windowCount; window++) {
    var sum = 0.0;
    for (var i = 0; i < samplesPerWindow * channels; i++) {
      final sample = data.getInt16(
        44 + window * samplesPerWindow * frameBytes + i * 2,
        Endian.little,
      );
      sum += sample * sample;
    }
    energies.add(sum / (samplesPerWindow * channels));
  }
  final sorted = List<double>.of(energies)..sort();
  final floor = sorted[((sorted.length - 1) * 0.1).floor()];
  if (sorted.last < floor * 2 || sorted.last < 2500) return bytes;
  final threshold = floor + math.max(2500.0, floor * 1.5);

  final cuts = <(int, int)>[];
  var window = 0;
  var activeWindows = 0;
  while (window < windowCount) {
    if (energies[window] > threshold) {
      activeWindows++;
      window++;
      continue;
    }
    final start = window;
    while (window < windowCount && energies[window] <= threshold) {
      window++;
    }
    if (start > 0 &&
        window < windowCount &&
        (window - start) * samplesPerWindow > rate * 3 ~/ 2) {
      cuts.add((
        start * samplesPerWindow + rate * 400 ~/ 1000,
        window * samplesPerWindow - rate * 250 ~/ 1000,
      ));
    }
  }
  if (cuts.isEmpty || activeWindows * samplesPerWindow < rate * 3 ~/ 10) {
    return bytes;
  }
  final removed = cuts.fold<int>(0, (sum, cut) => sum + cut.$2 - cut.$1);
  final output = Uint8List(bytes.length - removed * frameBytes);
  output.setRange(0, 44, bytes);
  var source = 0;
  var target = 44;
  for (final cut in cuts) {
    final end = 44 + cut.$1 * frameBytes;
    final begin = 44 + source * frameBytes;
    output.setRange(target, target + end - begin, bytes, begin);
    target += end - begin;
    // Blend only retained pause samples to avoid a click at the splice.
    for (var i = 0; i < 16; i++) {
      for (var channel = 0; channel < channels; channel++) {
        final outOffset = target - (16 - i) * frameBytes + channel * 2;
        final inputOffset = 44 + (cut.$2 + i) * frameBytes + channel * 2;
        final left = ByteData.sublistView(output)
            .getInt16(outOffset, Endian.little);
        final right = data.getInt16(inputOffset, Endian.little);
        ByteData.sublistView(output).setInt16(
          outOffset,
          (left * (16 - i) / 16 + right * i / 16).round(),
          Endian.little,
        );
      }
    }
    source = cut.$2;
  }
  output.setRange(target, output.length, bytes, 44 + source * frameBytes);
  final header = ByteData.sublistView(output);
  header.setUint32(4, output.length - 8, Endian.little);
  header.setUint32(40, output.length - 44, Endian.little);
  return output;
}
