import 'dart:async';

import 'package:ai_voice_dictator/dictation_controller.dart';
import 'package:ai_voice_dictator/services/audio_service.dart';
import 'package:ai_voice_dictator/services/desktop_service.dart';
import 'package:ai_voice_dictator/services/dictation_service.dart';
import 'package:ai_voice_dictator/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

class TestSettings extends SettingsStore {
  final keyResult = Completer<String>();
  bool closed = false;
  @override
  Future<String> apiKey() => keyResult.future;
  @override
  Future<void> close() async {
    closed = true;
  }
}

class TestAudio implements AudioService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  bool closed = false;
  @override
  Future<void> dispose() async {
    closed = true;
  }
}

class TestDesktop extends DesktopService {
  TestDesktop()
    : super(
        onHotkey: () {},
        onTranslate: () {},
        onSettings: () {},
        onSettingsClosed: () {},
        onPause: () => false,
        onSuspend: () {},
        onResume: () {},
        onExit: () {},
      );
  @override
  int captureTarget() => 123;
  @override
  Future<void> showHud() async {}
  @override
  Future<void> hideHud() async {}
  @override
  Future<void> setRecording(bool active) async {}
  @override
  Future<void> updateHud(String state, String message, int seconds) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'exit waits for an active operation before disposing services',
    () async {
      final settings = TestSettings();
      final audio = TestAudio();
      final desktop = TestDesktop();
      final controller = DictationController(
        DictationService(settings, audio, desktop),
        settings,
        desktop,
      );
      final operation = controller.toggle();
      final closing = controller.close();
      await Future<void>.delayed(Duration.zero);
      expect(settings.closed, false);
      expect(audio.closed, false);
      settings.keyResult.complete('');
      await operation;
      await closing;
      expect(settings.closed, true);
      expect(audio.closed, true);
    },
  );
}
