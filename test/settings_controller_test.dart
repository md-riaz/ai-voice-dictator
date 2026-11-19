import 'dart:async';

import 'package:ai_voice_dictator/settings/settings_controller.dart';
import 'package:ai_voice_dictator/settings/settings_service.dart';
import 'package:ai_voice_dictator/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:velora_ui/velora_ui.dart' as ui;
import 'package:ai_voice_dictator/settings/settings_view.dart';
import 'package:record/record.dart';
import 'package:ai_voice_dictator/dictation_controller.dart';
import 'package:ai_voice_dictator/services/desktop_service.dart';
import 'package:ai_voice_dictator/services/dictation_service.dart';

class FakeSettings implements SettingsStore {
  String? savedPrompt;
  @override
  String? systemPrompt() => savedPrompt;
  @override
  Future<void> setSystemPrompt(String? value) async => savedPrompt = value;
  bool historyCleared = false;
  bool failClearHistory = false;
  String savedModel = SettingsStore.defaultModel;
  @override
  String model() => savedModel;
  @override
  Future<void> setModel(String value) async => savedModel = value;
  String? savedKey;
  String? savedTarget;
  String initialKey = 'saved-key';
  @override
  Future<void> saveApiKey(String key) async {
    savedKey = key;
  }

  @override
  Future<String> apiKey() async => initialKey;
  @override
  String targetLanguage() => 'English';
  @override
  Future<void> setTargetLanguage(String value) async => savedTarget = value;
  @override
  String language() => 'auto';
  @override
  String shortcut() => 'Ctrl+Space';
  @override
  String translationShortcut() => 'Ctrl+Alt+Space';
  @override
  String? deviceId() => 'device';
  @override
  Future<void> clearHistory() async {
    if (failClearHistory) throw StateError('delete failed');
    historyCleared = true;
  }

  @override
  Future<List<HistoryEntry>> history() async => historyCleared
      ? []
      : [
          HistoryEntry(
            text: 'Hello',
            createdAt: DateTime(2026),
            duration: const Duration(seconds: 1),
          ),
        ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsService implements SettingsService {
  final permission = Completer<bool>();
  final validation = Completer<int>();
  Completer<List<InputDevice>>? devicesPending;
  @override
  Future<int> validateKey(String key) {
    testedKey = key;
    return validation.future;
  }

  String? testedKey;
  bool closed = false;
  @override
  Future<List<InputDevice>> listDevices() =>
      devicesPending?.future ??
      Future.value([const InputDevice(id: 'device', label: 'Mic')]);
  @override
  Future<bool> hasPermission() => permission.future;
  @override
  Future<void> dispose() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PlaygroundDictation implements DictationService {
  bool started = false;
  @override
  Future<void> start({bool translate = false}) async {
    started = true;
  }

  @override
  Future<void> cancel() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PlaygroundDesktop implements DesktopService {
  @override
  Future<void> updateHud(String state, String message, int seconds) async {}
  @override
  Future<void> showHud() async {}
  @override
  Future<void> hideHud() async {}
  @override
  Future<void> setRecording(bool active) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'launch at sign-in reflects system state and handles failed changes',
    () async {
      var enabled = true;
      var fail = false;
      final controller = SettingsController(
        store: FakeSettings(),
        service: FakeSettingsService(),
        onShortcutChanged: (_, _) async {},
        getAutoStart: () async => enabled,
        onAutoStartChanged: (value) async {
          if (fail) throw StateError('failed');
          enabled = value;
        },
      );
      await controller.load();
      expect(controller.autoStart, isTrue);
      await controller.setAutoStart(false);
      expect(enabled, isFalse);
      expect(controller.autoStart, isFalse);
      fail = true;
      await controller.setAutoStart(true);
      expect(controller.autoStart, isFalse);
      expect(controller.pageError, 'Could not update launch at sign-in.');
      await controller.closeResources();
      controller.onClose();
    },
  );
  test(
    'persists selected and custom Gemini model IDs and rejects URLs',
    () async {
      final store = FakeSettings();
      final controller = SettingsController(
        store: store,
        service: FakeSettingsService(),
        onShortcutChanged: (_, _) async {},
      );
      controller.chooseModel('gemini-3.5-flash-lite');
      await controller.saveModel();
      expect(store.savedModel, 'gemini-3.5-flash-lite');
      await controller.load();
      expect(controller.modelChoice, 'gemini-3.5-flash-lite');
      controller.chooseModel('gemini-3-flash-preview');
      await controller.saveModel();
      await controller.load();
      expect(controller.modelChoice, 'gemini-3-flash-preview');
      controller.chooseModel('custom');
      controller.modelInput.text = 'gemini-future-preview';
      await controller.saveModel();
      expect(store.savedModel, 'gemini-future-preview');
      controller.modelInput.text = 'https://example.com/model';
      await expectLater(controller.saveModel(), throwsFormatException);
      expect(store.savedModel, 'gemini-future-preview');
      await controller.closeResources();
      controller.onClose();
    },
  );
  testWidgets('saving the target language confirms the change', (tester) async {
    final store = FakeSettings();
    final controller = SettingsController(
      store: store,
      service: FakeSettingsService(),
      onShortcutChanged: (_, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    controller.target.text = 'French';
    final button = find.text('Save target language');
    await tester.scrollUntilVisible(
      button,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    expect(store.savedTarget, 'French');
    expect(find.text('Target language saved.'), findsOneWidget);
  });
  testWidgets('first launch requires a validated saved key before home', (
    tester,
  ) async {
    final service = FakeSettingsService();
    final controller = SettingsController(
      store: FakeSettings()..initialKey = '',
      service: service,
      onShortcutChanged: (_, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gemini connection'), findsOneWidget);
    expect(find.text('Try dictation'), findsNothing);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Gemini connection'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'new-key');
    await tester.tap(find.text('Save key'));
    await tester.pump();
    service.validation.complete(200);
    await tester.pumpAndSettle();
    expect(find.text('Try dictation'), findsOneWidget);
  });
  testWidgets('settings opens when device enumeration stalls', (tester) async {
    final service = FakeSettingsService()
      ..devicesPending = Completer<List<InputDevice>>();
    final controller = SettingsController(
      store: FakeSettings(),
      service: service,
      onShortcutChanged: (_, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pump();
    expect(controller.pageLoading, true);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(controller.pageLoading, false);
    expect(controller.devices, isEmpty);
  });
  testWidgets('playground focus allows a dictation shortcut', (tester) async {
    final settings = FakeSettings();
    final service = PlaygroundDictation();
    final dictation = DictationController(
      service,
      settings,
      PlaygroundDesktop(),
    );
    dictation.settingsVisible.value = true;
    final controller = SettingsController(
      store: settings,
      service: FakeSettingsService(),
      onShortcutChanged: (_, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller, dictation: dictation),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('dictation-playground'));
    final statusSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.text('Ready'),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.liveRegion == true,
            ),
          )
          .first,
    );
    expect(statusSemantics.properties.liveRegion, true);
    await tester.scrollUntilVisible(
      field,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pump();
    expect(dictation.playgroundFocused, true);
    await tester.enterText(field, 'Draft');
    expect(dictation.insertPlayground?.call(' transcript'), true);
    await tester.pump();
    expect(find.text('Draft transcript'), findsOneWidget);
    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    expect(find.text('Draft transcript'), findsOneWidget);
    await tester.tap(field);
    await tester.pump();
    await dictation.handleShortcut('holdStart');
    expect(service.started, true);
    await dictation.handleShortcut('cancel');
  });
  testWidgets('settings renders at narrow width with the dark Velora theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = SettingsController(
      store: FakeSettings(),
      service: FakeSettingsService(),
      onShortcutChanged: (_, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.dark(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Try dictation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('history and setup have no extra close button', (tester) async {
    final controller = SettingsController(
      store: FakeSettings(),
      service: FakeSettingsService(),
      onShortcutChanged: (_, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    for (final page in ['History', 'Setup']) {
      await tester.tap(find.text(page));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    }
  });
  testWidgets('keyboard can focus the API key and save it', (tester) async {
    final store = FakeSettings();
    final controller = SettingsController(
      store: store,
      service: FakeSettingsService(),
      onShortcutChanged: (_, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle();
    final field = find.byType(TextField).first;
    final keyField = tester.widget<TextField>(field);
    expect(keyField.obscureText, true);
    expect(keyField.enableSuggestions, false);
    expect(keyField.autocorrect, false);
    expect(keyField.decoration?.labelText, isNull);
    expect(find.text('Gemini API key'), findsOneWidget);
    final save = find.widgetWithText(TextButton, 'Save key');
    Future<void> tabTo(Finder target) async {
      for (var i = 0; i < 20; i++) {
        final focus = FocusManager.instance.primaryFocus;
        if (focus != null &&
            focus is! FocusScopeNode &&
            focus.context != null &&
            focus.rect.contains(tester.getCenter(target))) {
          return;
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      fail('Could not focus $target');
    }

    await tabTo(field);
    await tester.enterText(field, 'new-key');
    await tabTo(save);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(store.savedKey, 'new-key');
  });
  testWidgets('settings view displays loaded controller state', (tester) async {
    final controller = SettingsController(
      store: FakeSettings(),
      service: FakeSettingsService(),
      onShortcutChanged: (_, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle();
    expect(find.text('Checking saved key…'), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Recent dictations'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
  });
  testWidgets('clear history requires confirmation', (tester) async {
    final store = FakeSettings();
    final controller = SettingsController(
      store: store,
      service: FakeSettingsService(),
      onShortcutChanged: (_, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.historyCleared, false);
    expect(find.text('Hello'), findsOneWidget);
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history').last);
    await tester.pumpAndSettle();
    expect(store.historyCleared, true);
    expect(find.text('No dictations yet.'), findsOneWidget);
  });
  test('failed history deletion retains entries and reports error', () async {
    final store = FakeSettings()..failClearHistory = true;
    final controller = SettingsController(
      store: store,
      service: FakeSettingsService(),
      onShortcutChanged: (_, _) async {},
    );
    await controller.load();
    await controller.clearHistory();
    expect(controller.history.single.text, 'Hello');
    expect(controller.pageError, 'Could not clear dictation history.');
    await controller.closeResources();
    controller.onClose();
  });
  test(
    'loads persisted settings, devices and history into controller state',
    () async {
      final service = FakeSettingsService();
      final controller = SettingsController(
        store: FakeSettings(),
        service: service,
        onShortcutChanged: (_, _) async {},
      );
      await controller.load();
      expect(controller.key.text, 'saved-key');
      expect(controller.devices.single.label, 'Mic');
      expect(controller.device, 'device');
      expect(controller.history.single.text, 'Hello');
      expect(controller.pageLoading, false);
      await controller.closeResources();
      controller.onClose();
    },
  );
  test(
    'checks a saved key in the background without blocking settings',
    () async {
      final service = FakeSettingsService();
      final controller = SettingsController(
        store: FakeSettings(),
        service: service,
        onShortcutChanged: (_, _) async {},
      );
      await controller.load();
      expect(controller.pageLoading, false);
      expect(controller.needsSetup, false);
      expect(controller.keyStatus, 'Checking saved key…');
      expect(service.testedKey, 'saved-key');
      service.validation.complete(200);
      await Future<void>.delayed(Duration.zero);
      expect(controller.keyStatus, 'Connected');
      await controller.closeResources();
      controller.onClose();
    },
  );
  test(
    'old validation cannot override edits even if text changes back',
    () async {
      final service = FakeSettingsService();
      final controller = SettingsController(
        store: FakeSettings(),
        service: service,
        onShortcutChanged: (_, _) async {},
      );
      await controller.load();
      controller.key.text = 'other-key';
      controller.keyChanged('other-key');
      controller.key.text = 'saved-key';
      controller.keyChanged('saved-key');
      service.validation.complete(200);
      await Future<void>.delayed(Duration.zero);
      expect(controller.keyStatus, 'Unsaved key');
      await controller.closeResources();
      controller.onClose();
    },
  );
  test('saving a key starts validation automatically', () async {
    final store = FakeSettings();
    final service = FakeSettingsService();
    final controller = SettingsController(
      store: store,
      service: service,
      onShortcutChanged: (_, _) async {},
    );
    controller.key.text = 'new-key';
    final pending = controller.saveKey();
    await Future<void>.delayed(Duration.zero);
    expect(store.savedKey, 'new-key');
    expect(service.testedKey, 'new-key');
    expect(controller.keyStatus, 'Checking saved key…');
    service.validation.complete(200);
    await pending;
    expect(controller.keyStatus, 'Connected');
    await controller.closeResources();
    controller.onClose();
  });
  test('old validation cannot mark a newly edited key connected', () async {
    final service = FakeSettingsService();
    final controller = SettingsController(
      store: FakeSettings(),
      service: service,
      onShortcutChanged: (_, _) async {},
    );
    controller.key.text = 'old-key';
    final pending = controller.testKey();
    controller.key.text = 'new-key';
    controller.keyChanged('new-key');
    service.validation.complete(200);
    await pending;
    expect(controller.keyStatus, 'Unsaved key');
    await controller.closeResources();
    controller.onClose();
  });
  test('waits for microphone startup before disposing its service', () async {
    final service = FakeSettingsService();
    final controller = SettingsController(
      store: FakeSettings(),
      service: service,
      onShortcutChanged: (_, _) async {},
    );
    final operation = controller.toggleMic();
    final closing = controller.closeResources();
    await Future<void>.delayed(Duration.zero);
    expect(service.closed, false);
    service.permission.complete(false);
    await operation;
    await closing;
    expect(service.closed, true);
    controller.onClose();
  });
}
