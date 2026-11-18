import 'dart:async';
import 'package:ai_voice_dictator/settings/settings_controller.dart';
import 'package:ai_voice_dictator/settings/settings_service.dart';
import 'package:ai_voice_dictator/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ai_voice_dictator/settings/settings_view.dart';
import 'package:record/record.dart';

class FakeSettings implements SettingsStore {
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
  testWidgets('settings view displays loaded controller state', (tester) async {
    final controller = SettingsController(
      store: FakeSettings(),
      service: FakeSettingsService(),
      onShortcutChanged: (_, _) async {},
    );
    await tester.pumpWidget(
      MaterialApp(home: SettingsView(controller: controller)),
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
