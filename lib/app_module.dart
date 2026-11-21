import 'dart:async';

import 'package:window_manager/legacy.dart';

import 'dictation_controller.dart';
import 'services/audio_service.dart';
import 'services/desktop_service.dart';
import 'services/dictation_service.dart';
import 'services/password_guard.dart';
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

  static Future<AppModule> create({
    List<String> launchArguments = const [],
  }) async {
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
      onSuspend: () => unawaited(controller.handleSuspend()),
      onResume: () => controller.handleResume(),
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
    final passwordGuard = PasswordGuard();
    controller = DictationController(
      DictationService(
        settings,
        AudioService(),
        desktop,
        passwordCheck: passwordGuard.check,
        canPaste: () => controller.canPaste,
        playgroundActive: () => controller.playgroundActive,
        insertPlayground: (text) =>
            controller.insertPlayground?.call(text) ?? false,
      ),
      settings,
      desktop,
    );
    module = AppModule._(settings, desktop, controller);
    await desktop.initialize(launchArguments: launchArguments);
    final errors = <String>[];
    if (desktop.autoStartAvailable) {
      try {
        await settings.enableAutoStartByDefault(desktop.setAutoStart);
      } catch (_) {
        errors.add('Could not enable launch at sign-in. Check Setup.');
      }
    }
    if (desktop.hotkeysAvailable) {
      try {
        await desktop.registerShortcuts(
          settings.shortcut(),
          settings.translationShortcut(),
          settings.handsFreeKey(),
        );
      } catch (_) {
        desktop.hotkeysAvailable = false;
      }
    }
    if (!desktop.hotkeysAvailable) {
      errors.add('Global shortcuts could not be started. Restart the app.');
    }
    if (!desktop.singleInstanceAvailable) {
      errors.add(
        'Single-instance protection is unavailable. Avoid opening another copy.',
      );
    }
    if (errors.isNotEmpty) module.startupError = errors.join('\n');
    return module;
  }

  SettingsController settingsController() =>
      _activeSettings ??= SettingsController(
        store: settings,
        service: SettingsService(),
        onShortcutChanged: desktop.registerShortcuts,
        getAutoStart: desktop.autoStartAvailable
            ? desktop.isAutoStartEnabled
            : null,
        onAutoStartChanged: desktop.autoStartAvailable
            ? desktop.setAutoStart
            : null,
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
