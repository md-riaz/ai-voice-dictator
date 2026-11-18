import 'package:flutter/material.dart';
import 'package:velora/velora.dart';

import 'app_module.dart';
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
  final module = await AppModule.create();
  runApp(DictatorApp(module: module));
  if (module.startupError != null || (await module.settings.apiKey()).isEmpty) {
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
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: Obx(
        () => controller.settingsVisible.value
            ? SettingsView(controller: module.settingsController())
            : FloatingHudOverlay(
                state: controller.hud.value,
                message: controller.message.value,
                durationSeconds: controller.seconds.value,
              ),
      ),
    );
  }
}
