import 'dart:io';

import 'package:ai_voice_dictator/services/audio_service.dart';
import 'package:ai_voice_dictator/guardrails.dart';
import 'package:ai_voice_dictator/services/desktop_service.dart';
import 'package:ai_voice_dictator/services/dictation_service.dart';
import 'package:ai_voice_dictator/services/gemini_service.dart';
import 'package:ai_voice_dictator/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSettings implements SettingsStore {
  final events = <String>[];
  @override
  Future<String> apiKey() async => 'test';
  @override
  String? deviceId() => null;
  @override
  String language() => 'auto';
  @override
  String targetLanguage() => 'English';
  @override
  Future<void> addHistory(String text, Duration duration) async {
    events.add('history:$text');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAudio implements AudioService {
  FakeAudio(this.file);
  final File file;
  @override
  Future<void> start({String? deviceId}) async {}
  @override
  Future<RecordedAudioResult?> stop() async =>
      RecordedAudioResult(file: file, durationMs: 1000);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EmptyAudio extends FakeAudio {
  EmptyAudio(super.file);
  @override
  Future<RecordedAudioResult?> stop() async => null;
}

class FakeDesktop implements DesktopService {
  FakeDesktop(this.events);
  final List<String> events;
  @override
  int captureTarget() => 42;
  @override
  Future<void> copyTranscript(String text) async => events.add('copy:$text');
  @override
  Future<void> paste(String text, int target) async {
    events.add('paste:$text:$target');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('explains when no audio was captured', () async {
    final dir = await Directory.systemTemp.createTemp('dictation_test');
    addTearDown(() => dir.delete(recursive: true));
    final settings = FakeSettings();
    final service = DictationService(
      settings,
      EmptyAudio(File('${dir.path}/audio.wav')),
      FakeDesktop(settings.events),
    );
    await service.start();
    await expectLater(
      service.finish(),
      throwsA(
        isA<DictationException>().having((e) => e.code, 'code', 'audio_empty'),
      ),
    );
  });
  test('keeps transcript in history when playground focus is lost', () async {
    final dir = await Directory.systemTemp.createTemp('dictation_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/audio.wav');
    await file.writeAsBytes(List.filled(9000, 1));
    final settings = FakeSettings();
    final service = DictationService(
      settings,
      FakeAudio(file),
      FakeDesktop(settings.events),
      canPaste: () => false,
      transcribe: (file, seconds, key, mode, target) async => 'Hello',
    );
    await service.start();
    await expectLater(service.finish(), throwsStateError);
    expect(settings.events, ['copy:Hello', 'history:Hello']);
    expect(await file.exists(), false);
  });
  test('saves transcript before paste and deletes temporary audio', () async {
    final dir = await Directory.systemTemp.createTemp('dictation_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/audio.wav');
    await file.writeAsBytes(List.filled(9000, 1));
    final settings = FakeSettings();
    final service = DictationService(
      settings,
      FakeAudio(file),
      FakeDesktop(settings.events),
      transcribe: (file, seconds, key, mode, target) async {
        expect(mode, DictationLanguageMode.translate);
        return 'Hello';
      },
    );
    await service.start(translate: true);
    await service.finish();
    expect(settings.events, ['copy:Hello', 'history:Hello', 'paste:Hello:42']);
    expect(await file.exists(), false);
  });
  test('deletes temporary audio when transcription fails', () async {
    final dir = await Directory.systemTemp.createTemp('dictation_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/audio.wav');
    await file.writeAsBytes(List.filled(9000, 1));
    final settings = FakeSettings();
    final service = DictationService(
      settings,
      FakeAudio(file),
      FakeDesktop(settings.events),
      transcribe: (file, seconds, key, mode, target) async =>
          throw StateError('failed'),
    );
    await service.start();
    await expectLater(service.finish(), throwsStateError);
    expect(settings.events, isEmpty);
    expect(await file.exists(), false);
  });
}
