import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:velora/velora.dart';
import 'package:velora_ui/velora_ui.dart' as ui;

import 'app_module.dart';
import 'settings/settings_view.dart';
import 'ui/floating_hud.dart';

const _voiceTheme = ui.VeloraThemePreset(
  name: 'AI Voice Dictator',
  seed: Color(0xFF8B2018),
);

ThemeData buildVoiceTheme(Brightness brightness) {
  final theme = ui.buildVeloraTheme(
    preset: _voiceTheme,
    brightness: brightness,
  );
  final dark = brightness == Brightness.dark;
  final colors = theme.colorScheme.copyWith(
    primary: dark ? const Color(0xFFFFB4A7) : const Color(0xFF8B2018),
    onPrimary: dark ? const Color(0xFF5D0000) : Colors.white,
    secondary: dark ? const Color(0xFFFFDCA8) : const Color(0xFF795A19),
    onSecondary: dark ? const Color(0xFF422C00) : Colors.white,
    tertiary: dark ? const Color(0xFFB9D7C1) : const Color(0xFF356A4B),
    onTertiary: dark ? const Color(0xFF003820) : Colors.white,
    error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
    onError: dark ? const Color(0xFF690005) : Colors.white,
    surface: dark ? const Color(0xFF171513) : const Color(0xFFF4F0E8),
    surfaceContainerLowest: dark
        ? const Color(0xFF100E0D)
        : const Color(0xFFFFFBF4),
    surfaceContainerLow: dark
        ? const Color(0xFF211E1B)
        : const Color(0xFFECE6DB),
    surfaceContainer: dark ? const Color(0xFF2B2723) : const Color(0xFFE7E0D4),
    surfaceContainerHigh: dark
        ? const Color(0xFF36312C)
        : const Color(0xFFE2D9CC),
    surfaceContainerHighest: dark
        ? const Color(0xFF403A34)
        : const Color(0xFFD9CFC0),
  );
  final tokens = theme.extension<ui.VeloraTokens>()!.copyWith(
    radiusMd: 6,
    radiusLg: 12,
    success: dark ? const Color(0xFF91E0AD) : const Color(0xFF1E6B3A),
    onSuccess: dark ? const Color(0xFF00391E) : Colors.white,
    warning: dark ? const Color(0xFFFFC56B) : const Color(0xFF805000),
    onWarning: dark ? const Color(0xFF452B00) : Colors.white,
    info: dark ? const Color(0xFFFFDCA8) : const Color(0xFF795A19),
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
