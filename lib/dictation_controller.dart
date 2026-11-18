import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:velora/velora.dart';

import 'guardrails.dart';
import 'services/desktop_service.dart';
import 'services/dictation_service.dart';
import 'settings/settings_store.dart';
import 'ui/floating_hud.dart';

class DictationController extends VeloraController {
  DictationController(this.dictation, this.settings, this.desktop);
  final DictationService dictation;
  final SettingsStore settings;
  final DesktopService desktop;
  final hud = HudState.listening.obs;
  final message = ''.obs;
  final seconds = 0.obs;
  final settingsVisible = false.obs;
  final recording = false.obs;
  bool playgroundFocused = false;
  bool Function(String)? insertPlayground;
  bool paused = false;
  bool _busy = false;
  bool _closing = false;
  Completer<void>? _operationDone;
  bool _listening = false;
  bool processing = false;
  String? _mode;
  Timer? _timer;
  Timer? _hudTimer;

  Future<void> handleShortcut(String event) async {
    if (_closing) return;
    switch (event) {
      case 'holdStart':
      case 'translationStart':
        if (_mode != null ||
            paused ||
            (settingsVisible.value && !playgroundFocused)) {
          return;
        }
        await toggle(translate: event == 'translationStart');
        if (_listening) _mode = 'hold';
      case 'switchTranslation':
        if (_mode != 'hold') return;
        await cancel();
        await toggle(translate: true);
        if (_listening) _mode = 'hold';
      case 'holdStop':
        if (_mode != 'hold') return;
        _mode = null;
        await toggle();
      case 'handsFree':
        if (_mode == 'hold') {
          _mode = 'handsFree';
        } else if (_mode == 'handsFree') {
          _mode = null;
          await toggle();
        } else if (!paused && (!settingsVisible.value || playgroundFocused)) {
          await toggle();
          if (_listening) _mode = 'handsFree';
        }
      case 'cancel':
        await cancel();
    }
  }

  Future<void> cancel() async {
    if (!_listening) return;
    _listening = false;
    recording.value = false;
    _mode = null;
    _timer?.cancel();
    try {
      await dictation.cancel();
    } catch (_) {
      // A cancelled recording can be too short to normalize.
    } finally {
      await desktop.setRecording(false);
      await desktop.hideHud();
    }
  }

  Future<void> toggle({bool translate = false}) async {
    if (_closing ||
        (paused && !_listening) ||
        _busy ||
        (settingsVisible.value && !playgroundFocused && !_listening)) {
      return;
    }
    _busy = true;
    _operationDone = Completer<void>();
    _hudTimer?.cancel();
    try {
      if (!_listening) {
        seconds.value = 0;
        message.value = '';
        hud.value = HudState.preparing;
        await desktop.updateHud(hud.value.name, message.value, seconds.value);
        await desktop.showHud();
        await dictation.start(translate: translate);
        _listening = true;
        recording.value = true;
        await desktop.setRecording(true);
        hud.value = HudState.listening;
        await desktop.updateHud(hud.value.name, message.value, seconds.value);
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          seconds.value++;
          unawaited(
            desktop.updateHud(hud.value.name, message.value, seconds.value),
          );
        });
      } else {
        _timer?.cancel();
        _listening = false;
        recording.value = false;
        processing = true;
        await desktop.setRecording(false);
        hud.value = HudState.writing;
        await desktop.updateHud(hud.value.name, message.value, seconds.value);
        await dictation.finish();
        hud.value = HudState.success;
        await desktop.updateHud(hud.value.name, message.value, seconds.value);
        _scheduleHudHide(const Duration(milliseconds: 1200));
      }
    } catch (e) {
      debugPrint(
        'Dictation failed: ${e is DictationException ? e.code : e.runtimeType}',
      );
      _mode = null;
      recording.value = false;
      _timer?.cancel();
      if (_listening) {
        _listening = false;
        try {
          await dictation.cancel();
        } catch (_) {}
      }
      await desktop.setRecording(false);
      hud.value = HudState.error;
      message.value = e is DictationException
          ? e.message
          : e
                .toString()
                .replaceFirst('Bad state: ', '')
                .replaceFirst('Exception: ', '');
      await desktop.updateHud(hud.value.name, message.value, seconds.value);
      await desktop.showHud();
      _scheduleHudHide(const Duration(seconds: 5));
    } finally {
      processing = false;
      _busy = false;
      _operationDone?.complete();
      _operationDone = null;
    }
  }

  void _scheduleHudHide(Duration duration) {
    _hudTimer?.cancel();
    _hudTimer = Timer(duration, () => unawaited(desktop.hideHud()));
  }

  Future<void> showSettings() async {
    if (_closing || _busy || _listening) return;
    settingsVisible.value = true;
    await desktop.showSettings();
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    await _operationDone?.future;
    _timer?.cancel();
    _hudTimer?.cancel();
    await dictation.dispose();
    await settings.close();
    await desktop.dispose();
  }
}
