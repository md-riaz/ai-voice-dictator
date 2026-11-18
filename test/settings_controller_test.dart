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

class FakeSettings implements SettingsStore {
  String? savedKey;
  @override
  Future<void> saveApiKey(String key) async {
    savedKey = key;
  }

  @override
  Future<String> apiKey() async => 'saved-key';
  @override
  String targetLanguage() => 'English';
  @override
  String language() => 'auto';
  @override
  String shortcut() => 'Ctrl+Space';
  @override
  String translationShortcut() => 'Ctrl+Alt+Space';
  @override
  String? deviceId() => 'device';
  @override
  Future<List<HistoryEntry>> history() async => [
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
  @override
  Future<int> validateKey(String key) {
    testedKey = key;
    return validation.future;
  }
  String? testedKey;
  bool closed = false;
  @override
  Future<List<InputDevice>> listDevices() async => [
    const InputDevice(id: 'device', label: 'Mic'),
  ];
  @override
  Future<bool> hasPermission() => permission.future;
  @override
  Future<void> dispose() async {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
    expect(find.text('Gemini connection'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    final field = find.byType(TextField).first;
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
    expect(find.text('Not checked'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Recent dictations'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Recent dictations'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);
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
  test('saving a key starts validation automatically', () async {
    final store = FakeSettings();
    final service = FakeSettingsService();
    final controller = SettingsController(store: store, service: service, onShortcutChanged: (_, _) async {});
    controller.key.text = 'new-key';
    final pending = controller.saveKey();
    await Future<void>.delayed(Duration.zero);
    expect(store.savedKey, 'new-key');
    expect(service.testedKey, 'new-key');
    expect(controller.keyStatus, 'Checking…');
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
    expect(controller.keyStatus, 'Not checked');
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
