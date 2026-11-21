import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:velora/velora.dart';
import 'package:velora_ui/velora_ui.dart' as ui;

import 'app_module.dart';
import 'settings/settings_view.dart';
import 'ui/floating_hud.dart';

const _voiceTheme = ui.VeloraThemePreset(
  name: 'AI Voice Dictator',
  seed: Color(0xFF4F46E5),
);

ThemeData buildVoiceTheme(Brightness brightness) {
  final theme = ui.buildVeloraTheme(
    preset: _voiceTheme,
    brightness: brightness,
  );
  final dark = brightness == Brightness.dark;
  final colors = theme.colorScheme.copyWith(
    primary: dark ? const Color(0xFFC4B5FD) : const Color(0xFF4F46E5),
    onPrimary: dark ? const Color(0xFF312E81) : Colors.white,
    primaryContainer: dark ? const Color(0xFF3730A3) : const Color(0xFFEEF2FF),
    onPrimaryContainer: dark
        ? const Color(0xFFEEF2FF)
        : const Color(0xFF3730A3),
    onSurface: dark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
    onSurfaceVariant: dark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
    outlineVariant: dark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
    secondary: dark ? const Color(0xFFC7D2FE) : const Color(0xFF3730A3),
    onSecondary: dark ? const Color(0xFF1E1B4B) : Colors.white,
    tertiary: dark ? const Color(0xFFB9D7C1) : const Color(0xFF356A4B),
    onTertiary: dark ? const Color(0xFF003820) : Colors.white,
    error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
    onError: dark ? const Color(0xFF690005) : Colors.white,
    surface: dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    surfaceContainerLowest: dark
        ? const Color(0xFF0B1120)
        : const Color(0xFFFFFFFF),
    surfaceContainerLow: dark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF1F5F9),
    surfaceContainer: dark ? const Color(0xFF273449) : const Color(0xFFEEF2FF),
    surfaceContainerHigh: dark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0),
    surfaceContainerHighest: dark
        ? const Color(0xFF475569)
        : const Color(0xFFCBD5E1),
  );
  final tokens = theme.extension<ui.VeloraTokens>()!.copyWith(
    radiusMd: 6,
    radiusLg: 12,
    success: dark ? const Color(0xFF91E0AD) : const Color(0xFF10B981),
    onSuccess: dark ? const Color(0xFF00391E) : const Color(0xFF052E16),
    warning: dark ? const Color(0xFFFFC56B) : const Color(0xFF805000),
    onWarning: dark ? const Color(0xFF452B00) : Colors.white,
    info: dark ? const Color(0xFFC7D2FE) : const Color(0xFF3730A3),
    onInfo: dark ? const Color(0xFF00315F) : Colors.white,
  );
  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color, width: width),
      );
  return theme.copyWith(
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    extensions: [tokens],
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      fillColor: colors.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: inputBorder(colors.outlineVariant),
      focusedBorder: inputBorder(colors.primary, 2),
      errorBorder: inputBorder(colors.error),
      focusedErrorBorder: inputBorder(colors.error, 2),
    ),
  );
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Velora.boot(
    config: const VeloraConfig(
      appName: 'AI Voice Dictator',
      apiBaseUrl: 'https://generativelanguage.googleapis.com',
    ),
  );
  final module = await AppModule.create(launchArguments: args);
  runApp(DictatorApp(module: module));
  if (kDebugMode ||
      !args.contains('--autostart') ||
      module.startupError != null ||
      !module.desktop.trayAvailable ||
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
      theme: buildVoiceTheme(Brightness.light),
      darkTheme: buildVoiceTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: Obx(
        () => controller.settingsVisible.value
            ? SettingsView(
                controller: module.settingsController(),
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
