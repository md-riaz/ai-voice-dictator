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

ThemeData _buildVoiceTheme(Brightness brightness) {
  final theme = ui.buildVeloraTheme(
    preset: _voiceTheme,
    brightness: brightness,
  );
  final dark = brightness == Brightness.dark;
  final colors = theme.colorScheme.copyWith(
    surface: dark ? const Color(0xFF111827) : const Color(0xFFE9EEF7),
    surfaceContainerLowest: dark
        ? const Color(0xFF0D1422)
        : const Color(0xFFF8FAFE),
    surfaceContainerLow: dark
        ? const Color(0xFF182235)
        : const Color(0xFFF0F4FB),
    surfaceContainer: dark ? const Color(0xFF1D293D) : const Color(0xFFE4EBF6),
    surfaceContainerHigh: dark
        ? const Color(0xFF253149)
        : const Color(0xFFDAE3F1),
    surfaceContainerHighest: dark
        ? const Color(0xFF303D56)
        : const Color(0xFFD2DDEE),
  );
  return theme.copyWith(
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.55),
    ),
  );
}

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
      theme: _buildVoiceTheme(Brightness.light),
      darkTheme: _buildVoiceTheme(Brightness.dark),
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
