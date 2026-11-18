// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:velora/velora.dart';
import 'package:window_manager/legacy.dart';

import 'dictation_controller.dart';
import 'services/audio_service.dart';
import 'services/desktop_service.dart';
import 'settings/settings_store.dart';
import 'settings/settings_view.dart';
import 'ui/floating_hud.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Velora.boot(
    config: const VeloraConfig(
      appName: 'AI Voice Dictator',
      apiBaseUrl: 'https://generativelanguage.googleapis.com',
    ),
  );
  final settings = SettingsStore();
  await settings.initialize();
  late final DictationController controller;
  var exiting = false;
  final desktop = DesktopService(
    onHotkey: () => unawaited(controller.toggle()),
    onTranslate: () => unawaited(controller.toggle(translate: true)),
    onSettings: () => unawaited(controller.showSettings()),
    onSettingsClosed: () => controller.settingsVisible.value = false,
    onPause: () => controller.paused = !controller.paused,
    onExit: () async {
      if (exiting) return;
      exiting = true;
      try {
        await controller.close();
      } finally {
        await windowManager.destroy();
      }
    },
  );
  controller = DictationController(settings, AudioService(), desktop);
  await desktop.initialize();
  String? startupError;
  try {
    await desktop.registerShortcuts(
      settings.shortcut(),
      settings.translationShortcut(),
    );
  } catch (_) {
    startupError =
        'Could not register the saved shortcuts. Choose available shortcuts below.';
  }
  runApp(DictatorApp(controller: controller, startupError: startupError));
  if (startupError != null || (await settings.apiKey()).isEmpty) {
    await controller.showSettings();
  }
}

class DictatorApp extends StatelessWidget {
  const DictatorApp({super.key, required this.controller, this.startupError});
  final DictationController controller;
  final String? startupError;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI Voice Dictator',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: Obx(
      () => controller.settingsVisible.value
          ? SettingsView(
              store: controller.settings,
              onShortcutChanged: controller.desktop.registerShortcuts,
              initialError: startupError,
            )
          : FloatingHudOverlay(
              state: controller.hud.value,
              message: controller.message.value,
              durationSeconds: controller.seconds.value,
            ),
    ),
  );
}
