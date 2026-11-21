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
  List<HistoryEntry>? testHistory;
  List<HistoryEntry> olderHistory = [];
  @override
  Future<List<HistoryEntry>> historyPage({int? beforeId}) async => olderHistory;
  int retention = 0;
  @override
  int historyRetention() => retention;
  @override
  Future<void> setHistoryRetention(int days) async => retention = days;
  @override
  bool typeText() => false;
  bool savedStreamPreview = false;
  @override
  bool streamPreview() => savedStreamPreview;
  @override
  Future<void> setStreamPreview(bool value) async => savedStreamPreview = value;
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
  String shortcut() => savedShortcut;
  @override
  String translationShortcut() => savedTranslationShortcut;
  String savedShortcut = 'Ctrl+Win';
  String savedTranslationShortcut = 'Ctrl+Win+Alt';
  String savedHandsFreeKey = 'Space';
  @override
  String handsFreeKey() => savedHandsFreeKey;
  @override
  Future<void> setShortcuts(String hold, String translation, String key) async {
    savedShortcut = hold;
    savedTranslationShortcut = translation;
    savedHandsFreeKey = key;
  }

  @override
  String? deviceId() => savedDevice;
  String? savedDevice = 'device';
  @override
  Future<void> clearHistory() async {
    if (failClearHistory) throw StateError('delete failed');
    historyCleared = true;
  }

  @override
  Future<List<HistoryEntry>> history() async => historyCleared
      ? []
      : testHistory ??
            [
              HistoryEntry(
                text: 'Hello',
                createdAt: DateTime(2026),
                duration: const Duration(seconds: 1),
              ),
            ];
  DictationStats? testStats;
  @override
  Future<DictationStats> stats({int daysCount = 7}) async {
    if (testStats != null) return testStats!;
    final entries = await history();
    var words = 0;
    var duration = Duration.zero;
    for (final e in entries) {
      words += e.wordCount;
      duration += e.duration;
    }
    return DictationStats(
      totalWords: words,
      totalDuration: duration,
      totalSessions: entries.length,
      days: List.generate(
        daysCount,
        (i) => DayStat(
          date: DateTime.now().subtract(Duration(days: daysCount - 1 - i)),
          words: i == daysCount - 1 ? words : 0,
          duration: i == daysCount - 1 ? duration : Duration.zero,
        ),
      ),
    );
  }

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
  bool isAppForeground() => true;
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
  test('shortcut changes configure and persist matching chords', () async {
    final store = FakeSettings();
    final calls = <String>[];
    final controller = SettingsController(
      store: store,
      service: FakeSettingsService(),
      onShortcutChanged: (hold, translation, key) async =>
          calls.add('$hold|$translation|$key'),
    );
    await controller.changeShortcuts('Ctrl+Alt', 'Ctrl+Alt+Shift', key: 'F8');
    expect(calls, ['Ctrl+Alt|Ctrl+Alt+Shift|F8']);
    expect(store.handsFreeKey(), 'F8');
    expect(store.shortcut(), 'Ctrl+Alt');
    expect(controller.translationShortcut, 'Ctrl+Alt+Shift');
    await controller.changeShortcuts('Ctrl+Alt', 'Ctrl+Alt');
    expect(calls, hasLength(1));
    expect(store.shortcut(), 'Ctrl+Alt');
    expect(controller.pageError, isNotNull);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'launch at sign-in reflects system state and handles failed changes',
    () async {
      var enabled = true;
      var fail = false;
      final controller = SettingsController(
        store: FakeSettings(),
        service: FakeSettingsService(),
        onShortcutChanged: (_, _, _) async {},
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
        onShortcutChanged: (_, _, _) async {},
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
      onShortcutChanged: (_, _, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Language mode'), findsNothing);
    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle();
    expect(find.text('Language mode'), findsNothing);
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
      onShortcutChanged: (_, _, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gemini connection'), findsOneWidget);
    expect(find.text('Open Google AI Studio API keys'), findsOneWidget);
    expect(find.textContaining('not the project ID'), findsOneWidget);
    expect(find.text('Your workspace'), findsNothing);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Gemini connection'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'new-key');
    await tester.tap(find.text('Save key'));
    await tester.pump();
    service.validation.complete(200);
    await tester.pumpAndSettle();
    expect(find.text('Your workspace'), findsOneWidget);
  });
  testWidgets('settings opens when device enumeration stalls', (tester) async {
    final service = FakeSettingsService()
      ..devicesPending = Completer<List<InputDevice>>();
    final controller = SettingsController(
      store: FakeSettings(),
      service: service,
      onShortcutChanged: (_, _, _) async {},
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
      onShortcutChanged: (_, _, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller, dictation: dictation),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('dictation-playground'));
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
      onShortcutChanged: (_, _, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.dark(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('history and setup have no extra close button', (tester) async {
    final controller = SettingsController(
      store: FakeSettings(),
      service: FakeSettingsService(),
      onShortcutChanged: (_, _, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    for (final page in ['Stats', 'History', 'Setup']) {
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
      onShortcutChanged: (_, _, _) async {},
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
      onShortcutChanged: (_, _, _) async {},
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
    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('Dictation statistics'), findsOneWidget);
    expect(find.text('Words dictated'), findsOneWidget);
    expect(find.text('Time saved'), findsOneWidget);
    expect(find.text('Speaking pace'), findsOneWidget);
    expect(find.text('Words per week'), findsOneWidget);
    expect(find.text('Productivity insights'), findsOneWidget);
  });
  testWidgets('stats view displays empty state when no history exists', (
    tester,
  ) async {
    final store = FakeSettings()..testHistory = [];
    final controller = SettingsController(
      store: store,
      service: FakeSettingsService(),
      onShortcutChanged: (_, _, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ui.VeloraTheme.light(),
        home: SettingsView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('No dictation stats yet'), findsOneWidget);
  });
  testWidgets('stream preview toggle can be changed in setup', (tester) async {
    final store = FakeSettings();
    final controller = SettingsController(
      store: store,
      service: FakeSettingsService(),
      onShortcutChanged: (_, _, _) async {},
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
    final toggle = find.text('Live HUD streaming preview');
    await tester.scrollUntilVisible(
      toggle,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.savedStreamPreview, true);
  });
  testWidgets('clear history requires confirmation', (tester) async {
    final store = FakeSettings();
    final controller = SettingsController(
      store: store,
      service: FakeSettingsService(),
      onShortcutChanged: (_, _, _) async {},
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
  testWidgets('retention is changed only after confirmation', (tester) async {
    final store = FakeSettings();
    final controller = SettingsController(
      store: store,
      service: FakeSettingsService(),
      onShortcutChanged: (_, _, _) async {},
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
    await tester.tap(find.text('Keep all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 days').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('permanently deleted'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.retention, 0);
    expect(find.text('Keep all'), findsOneWidget);
    await tester.tap(find.text('Keep all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 days').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(store.retention, 30);
    expect(find.text('30 days'), findsOneWidget);
  });
  testWidgets('older history can be loaded', (tester) async {
    final store = FakeSettings()
      ..testHistory = List.generate(
        50,
        (i) => HistoryEntry(
          id: 100 - i,
          text: 'Entry $i',
          createdAt: DateTime(2026),
          duration: Duration.zero,
        ),
      )
      ..olderHistory = [
        HistoryEntry(
          id: 50,
          text: 'Older entry',
          createdAt: DateTime(2026),
          duration: Duration.zero,
        ),
      ];
    final controller = SettingsController(
      store: store,
      service: FakeSettingsService(),
      onShortcutChanged: (_, _, _) async {},
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
    await tester.ensureVisible(find.text('Load older dictations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load older dictations'));
    await tester.pumpAndSettle();
    expect(find.text('Older entry'), findsOneWidget);
    expect(find.text('Load older dictations'), findsNothing);
  });
  test('failed history deletion retains entries and reports error', () async {
    final store = FakeSettings()..failClearHistory = true;
    final controller = SettingsController(
      store: store,
      service: FakeSettingsService(),
      onShortcutChanged: (_, _, _) async {},
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
        onShortcutChanged: (_, _, _) async {},
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
  test('retains an unavailable microphone selection', () async {
    final controller = SettingsController(
      store: FakeSettings()..savedDevice = 'disconnected',
      service: FakeSettingsService(),
      onShortcutChanged: (_, _, _) async {},
    );
    await controller.load();
    expect(controller.device, 'disconnected');
    expect(controller.devices.any((d) => d.id == controller.device), isFalse);
    await controller.closeResources();
    controller.onClose();
  });
  test(
    'checks a saved key in the background without blocking settings',
    () async {
      final service = FakeSettingsService();
      final controller = SettingsController(
        store: FakeSettings(),
        service: service,
        onShortcutChanged: (_, _, _) async {},
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
        onShortcutChanged: (_, _, _) async {},
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
      onShortcutChanged: (_, _, _) async {},
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
      onShortcutChanged: (_, _, _) async {},
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
      onShortcutChanged: (_, _, _) async {},
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
