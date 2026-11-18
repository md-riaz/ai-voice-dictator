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
  test('trims quiet edges and applies bounded gain', () async {
    final dir = await Directory.systemTemp.createTemp('audio_test_');
    try {
      final file = File('${dir.path}/test.wav');
      await file.writeAsBytes(wav());
      await normalizeRecordedWav(file);
      final output = await file.readAsBytes();
      expect(output.length, lessThan(32044));
      expect(
        ByteData.sublistView(output).getInt16(44 + 1600 * 2, Endian.little),
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
