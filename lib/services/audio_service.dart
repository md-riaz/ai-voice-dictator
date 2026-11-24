import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../guardrails.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

Future<Duration> normalizedWavDuration(File file) async {
  final bytes = await file.readAsBytes();
  final data = ByteData.sublistView(bytes);
  final channels = data.getUint16(22, Endian.little);
  final rate = data.getUint32(24, Endian.little);
  final sampleBytes = data.getUint32(40, Endian.little);
  if (channels == 0 ||
      rate == 0 ||
      sampleBytes > bytes.length - 44 ||
      sampleBytes % (channels * 2) != 0) {
    throw const FormatException('Invalid normalized WAV');
  }
  return Duration(
    microseconds: ((sampleBytes ~/ (channels * 2)) * 1000000 / rate).round(),
  );
}

/// Preserves the recorder's negotiated 16-bit PCM sample rate and channels.
Future<({Duration captured, Duration submitted})> normalizeRecordedWav(
  File file,
) async {
  if (await file.length() > 12 * 1024 * 1024) {
    throw const DictationException(
      'audio_too_large',
      'Recording exceeds the 12 MiB inline audio limit.',
    );
  }
  final bytes = await file.readAsBytes();
  final data = ByteData.sublistView(bytes);
  bool tag(int at, String text) =>
      at + text.length <= bytes.length &&
      List.generate(text.length, (i) => bytes[at + i]).join(',') ==
          text.codeUnits.join(',');
  if (bytes.length < 44 || !tag(0, 'RIFF') || !tag(8, 'WAVE')) {
    throw const DictationException(
      'audio_format',
      'The recording has an unsupported audio format.',
    );
  }
  var pos = 12;
  int? sampleOffset;
  int? sampleLength;
  var formatValid = false;
  var channels = 0;
  var sampleRate = 0;
  while (pos + 8 <= bytes.length) {
    final size = data.getUint32(pos + 4, Endian.little);
    final start = pos + 8;
    if (size > bytes.length - start) {
      throw const DictationException(
        'audio_format',
        'The recording is damaged.',
      );
    }
    if (tag(pos, 'fmt ') && size >= 16) {
      channels = data.getUint16(start + 2, Endian.little);
      sampleRate = data.getUint32(start + 4, Endian.little);
      final format = data.getUint16(start, Endian.little);
      const pcmGuid = [
        1,
        0,
        0,
        0,
        0,
        0,
        16,
        0,
        128,
        0,
        0,
        170,
        0,
        56,
        155,
        113,
      ];
      final extensiblePcm =
          format == 0xfffe &&
          size >= 40 &&
          data.getUint16(start + 16, Endian.little) >= 22 &&
          List.generate(16, (i) => bytes[start + 24 + i]).join(',') ==
              pcmGuid.join(',');
      formatValid =
          (format == 1 || extensiblePcm) &&
          (channels == 1 || channels == 2) &&
          sampleRate >= 8000 &&
          sampleRate <= 192000 &&
          data.getUint16(start + 14, Endian.little) == 16;
    } else if (tag(pos, 'data')) {
      sampleOffset = start;
      sampleLength = size;
    }
    pos = start + size + (size & 1);
  }
  if (!formatValid ||
      sampleOffset == null ||
      sampleLength == null ||
      channels == 0 ||
      sampleLength % (channels * 2) != 0) {
    throw const DictationException(
      'audio_format',
      'The recording has an unsupported audio format.',
    );
  }
  final samples = sampleLength ~/ (channels * 2);
  var peak = 0;
  var first = samples;
  var last = -1;
  final frameSize = sampleRate ~/ 50;
  var previousActive = false;
  for (var start = 0; start < samples; start += frameSize) {
    final end = math.min(samples, start + frameSize);
    var energy = 0.0;
    for (var i = start; i < end; i++) {
      for (var channel = 0; channel < channels; channel++) {
        final value = data.getInt16(
          sampleOffset + (i * channels + channel) * 2,
          Endian.little,
        );
        peak = math.max(peak, value.abs());
        energy += value * value;
      }
    }
    final active = energy / ((end - start) * channels) >= 8100;
    if (active && previousActive) {
      first = math.min(first, start - frameSize);
      last = end - 1;
    }
    previousActive = active;
  }
  if (last < 0) {
    throw const DictationException(
      'audio_silent',
      'No speech detected. Speak louder or check your microphone.',
    );
  }
  // shortcut: threshold can miss very quiet speech; use VAD for better detection.
  first = math.max(0, first - sampleRate * 3 ~/ 4);
  last = math.min(samples - 1, last + sampleRate * 3 ~/ 4);
  final outSize = (last - first + 1) * channels * 2;
  final output = Uint8List(44 + outSize);
  final out = ByteData.sublistView(output);
  void writeTag(int offset, String value) =>
      output.setRange(offset, offset + value.length, value.codeUnits);
  writeTag(0, 'RIFF');
  out.setUint32(4, output.length - 8, Endian.little);
  writeTag(8, 'WAVE');
  writeTag(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, channels, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * channels * 2, Endian.little);
  out.setUint16(32, channels * 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  writeTag(36, 'data');
  out.setUint32(40, outSize, Endian.little);
  final gain = math.min(4.0, 31128 / peak);
  for (var i = first; i <= last; i++) {
    for (var channel = 0; channel < channels; channel++) {
      final sample = data.getInt16(
        sampleOffset + (i * channels + channel) * 2,
        Endian.little,
      );
      out.setInt16(
        44 + ((i - first) * channels + channel) * 2,
        (sample * gain).round().clamp(-32768, 32767),
        Endian.little,
      );
    }
  }
  await file.writeAsBytes(output, flush: true);
  return (
    captured: Duration(microseconds: (samples * 1000000 / sampleRate).round()),
    submitted: Duration(
      microseconds: ((last - first + 1) * 1000000 / sampleRate).round(),
    ),
  );
}

class RecordedAudioResult {
  const RecordedAudioResult({
    required this.file,
    required this.durationMs,
    this.capturedAudio,
    this.submittedAudio,
  });
  final File file;
  final int durationMs;
  final Duration? capturedAudio;
  final Duration? submittedAudio;
  int get durationSec => (durationMs / 1000).ceil();
}

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _clock = Stopwatch();
  String? _path;

  Future<List<InputDevice>> listDevices() => _recorder.listInputDevices();
  Future<Amplitude> amplitude() => _recorder.getAmplitude();

  Future<void> start({String? deviceId}) async {
    if (_path != null) throw StateError('A recording is already active.');
    if (!await _recorder.hasPermission()) {
      throw Exception('Microphone permission denied.');
    }
    InputDevice? device;
    if (deviceId != null && deviceId.isNotEmpty) {
      final devices = await listDevices();
      device = devices.where((item) => item.id == deviceId).firstOrNull;
      if (device == null) {
        throw Exception('The selected microphone is unavailable.');
      }
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(
        dir.path,
        'dictation_${DateTime.now().microsecondsSinceEpoch}.wav',
      ),
    );
    _path = file.path;
    try {
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          device: device,
        ),
        path: file.path,
      );
      _clock
        ..reset()
        ..start();
    } catch (_) {
      _path = null;
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<RecordedAudioResult?> stop() async {
    final originalPath = _path;
    if (originalPath == null) return null;
    _clock.stop();
    final duration = _clock.elapsedMilliseconds;
    try {
      final path = await _recorder.stop();
      if (path == null) {
        final file = File(originalPath);
        if (await file.exists()) await file.delete();
        return null;
      }
      final file = File(path);
      DictationGuardrails.validateAudio(file, duration);
      final metrics = await normalizeRecordedWav(file);
      return RecordedAudioResult(
        file: file,
        durationMs: duration,
        capturedAudio: metrics.captured,
        submittedAudio: metrics.submitted,
      );
    } catch (_) {
      final file = File(originalPath);
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      _path = null;
    }
  }

  Future<void> dispose() async {
    final path = _path;
    try {
      await _recorder.dispose();
    } finally {
      _path = null;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }
}
