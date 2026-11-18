import 'dart:async';

import 'package:ai_voice_dictator/dictation_controller.dart';
import 'package:ai_voice_dictator/services/desktop_service.dart';
import 'package:ai_voice_dictator/services/dictation_service.dart';
import 'package:ai_voice_dictator/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_voice_dictator/ui/floating_hud.dart';

class SlowDictation extends FakeDictation {
  final ready = Completer<void>();
  @override
  Future<void> start({bool translate = false}) => ready.future;
}

class FakeDictation implements DictationService {
  final events = <String>[];
  @override
  Future<void> start({bool translate = false}) async =>
      events.add(translate ? 'translate' : 'start');
  @override
  Future<void> finish() async => events.add('finish');
  @override
  Future<void> cancel() async => events.add('cancel');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDesktop implements DesktopService {
  int hidden = 0;
  @override
  Future<void> updateHud(String state, String message, int seconds) async {}
  @override
  Future<void> showHud() async {}
  @override
  Future<void> hideHud() async {
    hidden++;
  }

  @override
  Future<void> setRecording(bool active) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettings implements SettingsStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a new recording can start while the success overlay is shown', (
    tester,
  ) async {
    final service = FakeDictation();
    final desktop = FakeDesktop();
    final controller = DictationController(service, FakeSettings(), desktop);
    await controller.handleShortcut('holdStart');
    await controller.handleShortcut('holdStop');
    await controller.handleShortcut('holdStart');
    expect(service.events, ['start', 'finish', 'start']);
    await tester.pump(const Duration(seconds: 2));
    expect(desktop.hidden, 0);
    await controller.cancel();
  });
  test('shows preparing until the microphone is ready', () async {
    final service = SlowDictation();
    final controller = DictationController(
      service,
      FakeSettings(),
      FakeDesktop(),
    );
    final pending = controller.toggle();
    await Future<void>.delayed(Duration.zero);
    expect(controller.hud.value, HudState.preparing);
    expect(controller.recording.value, false);
    service.ready.complete();
    await pending;
    expect(controller.hud.value, HudState.listening);
    await controller.cancel();
  });
  test('settings allows shortcuts only while playground has focus', () async {
    final service = FakeDictation();
    final controller = DictationController(
      service,
      FakeSettings(),
      FakeDesktop(),
    );
    controller.settingsVisible.value = true;
    await controller.handleShortcut('holdStart');
    expect(service.events, isEmpty);
    controller.playgroundFocused = true;
    await controller.handleShortcut('holdStart');
    await controller.handleShortcut('cancel');
    expect(service.events, ['start', 'cancel']);
  });
  test('hold starts and release finishes', () async {
    final service = FakeDictation();
    final controller = DictationController(
      service,
      FakeSettings(),
      FakeDesktop(),
    );
    await controller.handleShortcut('holdStart');
    await controller.handleShortcut('holdStop');
    expect(service.events, ['start', 'finish']);
  });
  test('translation and escape cancel without sending', () async {
    final service = FakeDictation();
    final controller = DictationController(
      service,
      FakeSettings(),
      FakeDesktop(),
    );
    await controller.handleShortcut('translationStart');
    await controller.handleShortcut('cancel');
    await controller.handleShortcut('holdStop');
    expect(service.events, ['translate', 'cancel']);
  });
  test(
    'hands-free promotion ignores release and stops on next shortcut',
    () async {
      final service = FakeDictation();
      final controller = DictationController(
        service,
        FakeSettings(),
        FakeDesktop(),
      );
      await controller.handleShortcut('holdStart');
      await controller.handleShortcut('handsFree');
      await controller.handleShortcut('holdStop');
      expect(service.events, ['start']);
      await controller.handleShortcut('handsFree');
      expect(service.events, ['start', 'finish']);
    },
  );
}
