import 'dart:io';
import 'dart:typed_data';

import 'package:ai_voice_dictator/guardrails.dart';
import 'package:ai_voice_dictator/services/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List wav({bool silent = false}) {
  final bytes = Uint8List(44 + 32000);
  final data = ByteData.sublistView(bytes);
  void tag(int at, String value) =>
      bytes.setRange(at, at + value.length, value.codeUnits);
  tag(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, 32000, Endian.little);
  if (!silent) {
    for (var i = 6000; i < 10000; i++) {
      data.setInt16(44 + 2 * i, 1000, Endian.little);
    }
  }
  return bytes;
}

void main() {
  test('accepts extensible PCM WAV produced by Windows', () async {
    final dir = await Directory.systemTemp.createTemp('audio_test_');
    try {
      final original = wav();
      final bytes = Uint8List(original.length + 24);
      bytes.setRange(0, 44, original);
      bytes.setRange(68, bytes.length, original, 44);
      final data = ByteData.sublistView(bytes);
      data.setUint32(4, bytes.length - 8, Endian.little);
      data.setUint32(16, 40, Endian.little);
      data.setUint16(20, 0xfffe, Endian.little);
      data.setUint16(36, 22, Endian.little);
      data.setUint16(38, 16, Endian.little);
      bytes.setRange(44, 60, [
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
      ]);
      bytes.setRange(60, 64, 'data'.codeUnits);
      data.setUint32(64, original.length - 44, Endian.little);
      final file = File('${dir.path}/test.wav');
      await file.writeAsBytes(bytes);
      await normalizeRecordedWav(file);
      expect(
        ByteData.sublistView(await file.readAsBytes())
            .getUint16(20, Endian.little),
        1,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('accepts the negotiated 48 kHz stereo PCM format', () async {
    final dir = await Directory.systemTemp.createTemp('audio_test_');
    try {
      final bytes = Uint8List(44 + 48000 * 4);
      final data = ByteData.sublistView(bytes);
      bytes.setRange(0, 4, 'RIFF'.codeUnits);
      data.setUint32(4, bytes.length - 8, Endian.little);
      bytes.setRange(8, 16, 'WAVEfmt '.codeUnits);
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 1, Endian.little);
      data.setUint16(22, 2, Endian.little);
      data.setUint32(24, 48000, Endian.little);
      data.setUint32(28, 192000, Endian.little);
      data.setUint16(32, 4, Endian.little);
      data.setUint16(34, 16, Endian.little);
      bytes.setRange(36, 40, 'data'.codeUnits);
      data.setUint32(40, bytes.length - 44, Endian.little);
      for (var frame = 20000; frame < 28000; frame++) {
        data.setInt16(44 + frame * 4, 1000, Endian.little);
      }
      final file = File('${dir.path}/test.wav');
      await file.writeAsBytes(bytes);
      await normalizeRecordedWav(file);
      final result = ByteData.sublistView(await file.readAsBytes());
      expect(result.getUint16(22, Endian.little), 2);
      expect(result.getUint32(24, Endian.little), 48000);
      expect(result.getInt16(44 + 20000 * 4, Endian.little), 4000);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('preserves quiet edges and applies bounded gain', () async {
    final dir = await Directory.systemTemp.createTemp('audio_test_');
    try {
      final file = File('${dir.path}/test.wav');
      final original = wav();
      ByteData.sublistView(original).setInt16(44 + 10 * 2, 100, Endian.little);
      await file.writeAsBytes(original);
      await normalizeRecordedWav(file);
      final output = await file.readAsBytes();
      expect(output.length, 32044);
      expect(
        ByteData.sublistView(output).getInt16(44 + 10 * 2, Endian.little),
        400,
      );
      expect(
        ByteData.sublistView(output).getInt16(44 + 6000 * 2, Endian.little),
        4000,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('rejects silence', () async {
    final dir = await Directory.systemTemp.createTemp('audio_test_');
    try {
      final file = File('${dir.path}/test.wav');
      await file.writeAsBytes(wav(silent: true));
      await expectLater(
        normalizeRecordedWav(file),
        throwsA(isA<DictationException>()),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
