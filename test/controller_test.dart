import 'dart:async';

import 'package:ai_voice_dictator/dictation_controller.dart';
import 'package:ai_voice_dictator/services/audio_service.dart';
import 'package:ai_voice_dictator/services/desktop_service.dart';
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
        onPause: () {},
        onExit: () {},
      );
  @override
  Future<void> showHud() async {}
  @override
  Future<void> hideHud() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'exit waits for an active operation before disposing services',
    () async {
      final settings = TestSettings();
      final audio = TestAudio();
      final controller = DictationController(settings, audio, TestDesktop());
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
