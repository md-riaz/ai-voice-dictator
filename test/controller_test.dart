import 'dart:async';

import 'package:ai_voice_dictator/dictation_controller.dart';
import 'package:ai_voice_dictator/guardrails.dart';
import 'package:ai_voice_dictator/ui/floating_hud.dart';
import 'package:ai_voice_dictator/services/audio_service.dart';
import 'package:ai_voice_dictator/services/desktop_service.dart';
import 'package:ai_voice_dictator/services/dictation_service.dart';
import 'package:ai_voice_dictator/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

class TestSettings extends SettingsStore {
  @override
  bool streamPreview() => false;
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

class ProcessingDictation extends DictationService {
  ProcessingDictation(super.settings, super.audio, super.desktop);
  final started = Completer<void>();
  final done = Completer<void>();
  bool cancelled = false;
  @override
  Future<void> start({bool translate = false}) async {}
  @override
  Future<void> finish({void Function(String)? onChunk}) {
    started.complete();
    return done.future;
  }

  @override
  void cancelProcessing() {
    cancelled = true;
    if (!done.isCompleted) done.complete();
  }
}

class FallbackDictation extends DictationService {
  FallbackDictation(super.settings, super.audio, super.desktop);
  @override
  Future<void> start({bool translate = false}) async {}
  @override
  Future<void> finish({void Function(String)? onChunk}) async {
    throw const DictationException(
      'clipboard_fallback',
      'Transcript copied to clipboard.',
    );
  }
}

void main() {
  test('clipboard fallback displays a success notice', () async {
    final settings = TestSettings();
    final desktop = TestDesktop();
    final controller = DictationController(
      FallbackDictation(settings, TestAudio(), desktop),
      settings,
      desktop,
    );
    await controller.toggle();
    await controller.toggle();
    expect(controller.hud.value, HudState.success);
    expect(controller.message.value, contains('clipboard'));
    await controller.close();
  });

  test('escape cancels processing and leaves controller ready', () async {
    final settings = TestSettings();
    final audio = TestAudio();
    final desktop = TestDesktop();
    final service = ProcessingDictation(settings, audio, desktop);
    final controller = DictationController(service, settings, desktop);
    await controller.toggle();
    final finishing = controller.toggle();
    await service.started.future;
    await controller.handleShortcut('cancel');
    await finishing;
    expect(service.cancelled, isTrue);
    expect(controller.processing, isFalse);
    expect(controller.recording.value, isFalse);
  });

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
