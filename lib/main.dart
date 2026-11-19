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

ThemeData buildVoiceTheme(Brightness brightness) {
  final theme = ui.buildVeloraTheme(
    preset: _voiceTheme,
    brightness: brightness,
  );
  final dark = brightness == Brightness.dark;
  final colors = theme.colorScheme.copyWith(
    primary: dark ? const Color(0xFFA8C8FF) : const Color(0xFF155DB4),
    onPrimary: dark ? const Color(0xFF082B58) : Colors.white,
    secondary: dark ? const Color(0xFFD8BCEB) : const Color(0xFF654C80),
    onSecondary: dark ? const Color(0xFF392247) : Colors.white,
    tertiary: dark ? const Color(0xFF79D8CF) : const Color(0xFF00766F),
    onTertiary: dark ? const Color(0xFF003731) : Colors.white,
    error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
    onError: dark ? const Color(0xFF690005) : Colors.white,
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
  final tokens = theme.extension<ui.VeloraTokens>()!.copyWith(
    radiusMd: 6,
    radiusLg: 12,
    success: dark ? const Color(0xFF79DBA1) : const Color(0xFF187145),
    onSuccess: dark ? const Color(0xFF00391E) : Colors.white,
    warning: dark ? const Color(0xFFFFC56B) : const Color(0xFF805000),
    onWarning: dark ? const Color(0xFF452B00) : Colors.white,
    info: dark ? const Color(0xFF9EC9FF) : const Color(0xFF145DA6),
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
