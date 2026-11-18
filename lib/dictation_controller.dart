import 'dart:async';

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
  bool paused = false;
  bool _busy = false;
  bool _closing = false;
  Completer<void>? _operationDone;
  bool _listening = false;
  Timer? _timer;

  Future<void> toggle({bool translate = false}) async {
    if (_closing || (paused && !_listening) || _busy || settingsVisible.value) {
      return;
    }
    _busy = true;
    _operationDone = Completer<void>();
    try {
      if (!_listening) {
        await dictation.start(translate: translate);
        _listening = true;
        seconds.value = 0;
        hud.value = HudState.listening;
        message.value = '';
        await desktop.showHud();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          seconds.value++;
        });
      } else {
        _timer?.cancel();
        _listening = false;
        hud.value = HudState.writing;
        await dictation.finish();
        hud.value = HudState.success;
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await desktop.hideHud();
      }
    } catch (e) {
      _timer?.cancel();
      if (_listening) {
        _listening = false;
        try {
          await dictation.cancel();
        } catch (_) {}
      }
      hud.value = HudState.error;
      message.value = e is DictationException
          ? e.message
          : e
                .toString()
                .replaceFirst('Bad state: ', '')
                .replaceFirst('Exception: ', '');
      await desktop.showHud();
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await desktop.hideHud();
    } finally {
      _busy = false;
      _operationDone?.complete();
      _operationDone = null;
    }
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
    await dictation.dispose();
    await settings.close();
    await desktop.dispose();
  }
}
