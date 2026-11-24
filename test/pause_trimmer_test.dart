import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_voice_dictator/services/pause_trimmer.dart';

Uint8List fixture(int rate, int channels, List<(int, int)> speech) {
  final frames = rate * 6;
  final bytes = Uint8List(44 + frames * channels * 2);
  final data = ByteData.sublistView(bytes);
  void tag(int offset, String value) =>
      bytes.setRange(offset, offset + 4, value.codeUnits);
  tag(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * channels * 2, Endian.little);
  data.setUint16(32, channels * 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, bytes.length - 44, Endian.little);
  for (final (start, end) in speech) {
    for (var frame = start; frame < end; frame++) {
      for (var c = 0; c < channels; c++) {
        data.setInt16(44 + (frame * channels + c) * 2, 150, Endian.little);
      }
    }
  }
  return bytes;
}

void main() {
  test('shortens internal digital silence and preserves WAV format', () {
    for (final (rate, channels) in [(8000, 1), (48000, 2)]) {
      final input = fixture(rate, channels, [(0, rate), (rate * 3, rate * 6)]);
      final result = shortenSilentPcmWav(input);
      final data = ByteData.sublistView(result);
      expect(
        (result.length - 44) ~/ (channels * 2),
        rate * 4 + rate * 650 ~/ 1000,
      );
      expect(data.getUint32(40, Endian.little), result.length - 44);
      expect(data.getUint32(24, Endian.little), rate);
      expect(data.getUint16(22, Endian.little), channels);
    }
  });
  test('preserves short pauses and edge silence', () {
    final input = fixture(8000, 1, [(8000, 16000), (24000, 32000)]);
    expect(identical(shortenSilentPcmWav(input), input), isTrue);
  });
  test('shortens a noisy three-second pause without changing tones', () {
    const rate = 8000;
    final input = fixture(rate, 1, [(0, rate), (rate * 4, rate * 5)]);
    final data = ByteData.sublistView(input);
    var seed = 12345;
    for (var i = rate; i < rate * 4; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      data.setInt16(44 + i * 2, (seed % 41) - 20, Endian.little);
    }
    // Remove the unused trailing second to obtain tone + 3s noise + tone.
    final original = Uint8List.fromList(input.sublist(0, 44 + rate * 5 * 2));
    final header = ByteData.sublistView(original);
    header.setUint32(4, original.length - 8, Endian.little);
    header.setUint32(40, original.length - 44, Endian.little);
    final result = shortenSilentPcmWav(original);
    expect((result.length - 44) ~/ 2, rate * 2 + rate * 650 ~/ 1000);
    expect(
      result.sublist(44, 44 + rate * 2),
      original.sublist(44, 44 + rate * 2),
    );
    expect(
      result.sublist(result.length - rate * 2),
      original.sublist(original.length - rate * 2),
    );
  });
  test('leaves low-SNR audio unchanged', () {
    final input = fixture(8000, 1, [(0, 48000)]);
    final data = ByteData.sublistView(input);
    for (var i = 8000; i < 32000; i++) {
      data.setInt16(44 + i * 2, 120, Endian.little);
    }
    expect(identical(shortenSilentPcmWav(input), input), isTrue);
  });
  test('unsupported data passes unchanged', () {
    final bytes = Uint8List(20);
    expect(identical(shortenSilentPcmWav(bytes), bytes), isTrue);
  });
  test('replaces file with shortened audio', () async {
    final dir = await Directory.systemTemp.createTemp('pause_test_');
    try {
      final file = File('${dir.path}/record.wav');
      await file.writeAsBytes(fixture(8000, 1, [(0, 8000), (24000, 48000)]));
      await shortenInternalPauses(file);
      expect((await file.length() - 44) ~/ 2, 37200);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
