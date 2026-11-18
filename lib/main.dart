import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:velora/velora.dart';
import 'package:velora_ui/velora_ui.dart' as ui;

import 'app_module.dart';
import 'settings/settings_view.dart';
import 'ui/floating_hud.dart';

const _voiceTheme = ui.VeloraThemePreset(
  name: 'AI Voice Dictator',
  seed: Color(0xFF3454B5),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Velora.boot(
    config: const VeloraConfig(
      appName: 'AI Voice Dictator',
      apiBaseUrl: 'https://generativelanguage.googleapis.com',
    ),
  );
  final module = await AppModule.create();
  runApp(DictatorApp(module: module));
  if (kDebugMode ||
      module.startupError != null ||
      (await module.settings.apiKey()).isEmpty) {
    await module.controller.showSettings();
  }
}

class DictatorApp extends StatelessWidget {
  const DictatorApp({super.key, required this.module});
  final AppModule module;

  @override
  Widget build(BuildContext context) {
    final controller = module.controller;
    return MaterialApp(
      title: 'AI Voice Dictator',
      debugShowCheckedModeBanner: false,
      theme: ui.buildVeloraTheme(preset: _voiceTheme),
      darkTheme: ui.buildVeloraTheme(
        preset: _voiceTheme,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: Obx(
        () => controller.settingsVisible.value
            ? SettingsView(
                controller: module.settingsController(),
                onClose: controller.desktop.onWindowClose,
                dictation: controller,
              )
            : FloatingHudOverlay(
                state: controller.hud.value,
                message: controller.message.value,
                durationSeconds: controller.seconds.value,
              ),
      ),
    );
  }
}
