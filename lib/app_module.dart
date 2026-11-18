import 'dart:async';

import 'package:window_manager/legacy.dart';

import 'dictation_controller.dart';
import 'services/audio_service.dart';
import 'services/desktop_service.dart';
import 'services/dictation_service.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_service.dart';
import 'settings/settings_store.dart';
import 'ui/floating_hud.dart';

// ignore_for_file: deprecated_member_use
class AppModule {
  AppModule._(this.settings, this.desktop, this.controller);
  final SettingsStore settings;
  final DesktopService desktop;
  final DictationController controller;
  String? startupError;
  SettingsController? _activeSettings;

  static Future<AppModule> create() async {
    final settings = SettingsStore();
    await settings.initialize();
    late final DictationController controller;
    late final AppModule module;
    var exiting = false;
    Future<void> keyEvents = Future.value();
    final desktop = DesktopService(
      onHotkey: () => unawaited(controller.toggle()),
      onTranslate: () => unawaited(controller.toggle(translate: true)),
      onKeyEvent: (event) {
        if (controller.processing) return;
        keyEvents = keyEvents
            .then((_) => controller.handleShortcut(event))
            .catchError((Object error) {});
      },
      onSettings: () => unawaited(controller.showSettings()),
      onSettingsClosed: () => unawaited(module.closeSettings()),
      onPause: () => controller.paused = !controller.paused,
      onExit: () async {
        if (exiting) return;
        exiting = true;
        try {
          try {
            await module.closeSettings();
          } finally {
            await controller.close();
          }
        } finally {
          await windowManager.destroy();
        }
      },
    );
    controller = DictationController(
      DictationService(
        settings,
        AudioService(),
        desktop,
        canPaste: () =>
            !controller.settingsVisible.value || controller.playgroundFocused,
        playgroundActive: () =>
            controller.settingsVisible.value && controller.playgroundFocused,
        insertPlayground: (text) =>
            controller.insertPlayground?.call(text) ?? false,
      ),
      settings,
      desktop,
    );
    module = AppModule._(settings, desktop, controller);
    await desktop.initialize();
    if (!desktop.hotkeysAvailable) {
      module.startupError =
          'Global shortcuts could not be started. Restart the app.';
    }
    return module;
  }

  SettingsController settingsController() =>
      _activeSettings ??= SettingsController(
        store: settings,
        service: SettingsService(),
        onShortcutChanged: desktop.registerShortcuts,
        initialError:
            startupError ??
            (controller.hud.value == HudState.error &&
                    controller.message.value.isNotEmpty
                ? controller.message.value
                : null),
      );

  Future<void> closeSettings() async {
    try {
      await _activeSettings?.closeResources();
    } finally {
      _activeSettings = null;
      controller.playgroundFocused = false;
      controller.settingsVisible.value = false;
    }
  }
}
