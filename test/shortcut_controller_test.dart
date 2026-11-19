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
  bool get historySaveFailed => false;
  @override
  Future<void> start({bool translate = false}) async =>
      events.add(translate ? 'translate' : 'start');
  @override
  Future<void> finish({void Function(String)? onChunk}) async =>
      events.add('finish');
  @override
  Future<void> cancel() async => events.add('cancel');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDesktop implements DesktopService {
  int hidden = 0;
  bool foreground = true;
  @override
  bool isAppForeground() => foreground;
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
  bool streamPreview() => false;
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
  test('suspend cancels recording and blocks starts until resume', () async {
    final service = FakeDictation();
    final controller = DictationController(
      service,
      FakeSettings(),
      FakeDesktop(),
    );
    await controller.handleShortcut('holdStart');
    await controller.handleSuspend();
    await controller.handleShortcut('holdStart');
    expect(service.events, ['start', 'cancel']);
    expect(controller.recording.value, false);
    controller.handleResume();
    await controller.handleShortcut('holdStart');
    expect(service.events, ['start', 'cancel', 'start']);
    await controller.cancel();
  });
  test('suspend during microphone startup cancels when ready', () async {
    final service = SlowDictation();
    final controller = DictationController(
      service,
      FakeSettings(),
      FakeDesktop(),
    );
    final start = controller.handleShortcut('holdStart');
    await Future<void>.delayed(Duration.zero);
    final suspend = controller.handleSuspend();
    service.ready.complete();
    await start;
    await suspend;
    expect(service.events, ['cancel']);
    expect(controller.recording.value, false);
  });
  test('release during microphone startup finishes once ready', () async {
    final service = SlowDictation();
    final controller = DictationController(
      service,
      FakeSettings(),
      FakeDesktop(),
    );
    final start = controller.handleShortcut('holdStart');
    await Future<void>.delayed(Duration.zero);
    final stop = controller.handleShortcut('holdStop');
    service.ready.complete();
    await Future.wait([start, stop]);
    expect(service.events, ['finish']);
    expect(controller.recording.value, false);
  });
  test('hands-free promotion during startup survives hold release', () async {
    final service = SlowDictation();
    final controller = DictationController(
      service,
      FakeSettings(),
      FakeDesktop(),
    );
    final start = controller.handleShortcut('holdStart');
    await Future<void>.delayed(Duration.zero);
    await controller.handleShortcut('handsFree');
    await controller.handleShortcut('holdStop');
    service.ready.complete();
    await start;
    expect(controller.recording.value, true);
    await controller.handleShortcut('handsFree');
    expect(service.events, ['finish']);
  });
  test(
    'cancel during microphone startup discards recording once ready',
    () async {
      final service = SlowDictation();
      final controller = DictationController(
        service,
        FakeSettings(),
        FakeDesktop(),
      );
      final start = controller.handleShortcut('holdStart');
      await Future<void>.delayed(Duration.zero);
      final cancel = controller.handleShortcut('cancel');
      service.ready.complete();
      await Future.wait([start, cancel]);
      expect(service.events, ['cancel']);
      expect(controller.recording.value, false);
    },
  );
  test(
    'resume waits for suspended startup cleanup before another start',
    () async {
      final service = SlowDictation();
      final controller = DictationController(
        service,
        FakeSettings(),
        FakeDesktop(),
      );
      final firstStart = controller.handleShortcut('holdStart');
      await Future<void>.delayed(Duration.zero);
      final suspend = controller.handleSuspend();
      controller.handleResume();
      await controller.handleShortcut('holdStart');
      service.ready.complete();
      await firstStart;
      await suspend;
      expect(service.events, ['cancel']);
      await controller.handleShortcut('holdStart');
      expect(controller.recording.value, true);
      expect(service.events, ['cancel']);
      await controller.cancel();
    },
  );
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
  test('shortcuts work in another app while settings stays visible', () async {
    final service = FakeDictation();
    final desktop = FakeDesktop()..foreground = false;
    final controller = DictationController(service, FakeSettings(), desktop);
    controller.settingsVisible.value = true;
    controller.playgroundFocused = true;
    expect(controller.playgroundActive, false);
    expect(controller.canPaste, true);
    await controller.handleShortcut('holdStart');
    await controller.handleShortcut('cancel');
    expect(service.events, ['start', 'cancel']);
    desktop.foreground = true;
    expect(controller.playgroundActive, true);
    controller.playgroundFocused = false;
    expect(controller.canPaste, false);
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
