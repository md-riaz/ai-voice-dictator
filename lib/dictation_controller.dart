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
  bool _suspended = false;
  bool _resumePending = false;
  Future<void>? _suspendCleanup;
  Completer<void>? _operationDone;
  bool _listening = false;
  bool processing = false;
  bool _cancelRequested = false;
  String? _mode;
  Timer? _timer;
  Timer? _hudTimer;
  Timer? _levelTimer;
  bool _readingLevel = false;

  bool get playgroundActive =>
      settingsVisible.value && desktop.isAppForeground() && playgroundFocused;

  bool get canPaste =>
      !settingsVisible.value || !desktop.isAppForeground() || playgroundFocused;

  bool get _settingsBlocksShortcut =>
      settingsVisible.value && desktop.isAppForeground() && !playgroundFocused;

  Future<void> handleShortcut(String event) async {
    if (_closing || _suspended) return;
    switch (event) {
      case 'holdStart':
      case 'translationStart':
        if (_mode != null || _busy || paused || _settingsBlocksShortcut) {
          return;
        }
        _mode = 'hold';
        await toggle(translate: event == 'translationStart');
        if (!_listening && _mode == 'hold') _mode = null;
      case 'switchTranslation':
        if (_mode != 'hold') return;
        if (_busy && !processing) await _operationDone?.future;
        if (_mode != 'hold' || !_listening) return;
        await cancel();
        await toggle(translate: true);
        if (_listening) _mode = 'hold';
      case 'holdStop':
        if (_mode != 'hold') return;
        _mode = null;
        if (_busy && !processing) await _operationDone?.future;
        if (_listening) await toggle();
      case 'handsFree':
        if (_mode == 'hold') {
          _mode = 'handsFree';
        } else if (_mode == 'handsFree') {
          _mode = null;
          if (_busy && !processing) await _operationDone?.future;
          if (_listening) await toggle();
        } else if (!_busy && !paused && !_settingsBlocksShortcut) {
          _mode = 'handsFree';
          await toggle();
          if (!_listening && _mode == 'handsFree') _mode = null;
        }
      case 'cancel':
        _mode = null;
        if (_busy && !processing) {
          _cancelRequested = true;
          await _operationDone?.future;
        }
        await cancel();
    }
  }

  Future<void> handleSuspend() async {
    _suspended = true;
    _resumePending = false;
    final existing = _suspendCleanup;
    if (existing != null) return existing;
    final cleanup = _cancelForSuspend();
    _suspendCleanup = cleanup;
    try {
      await cleanup;
    } finally {
      _suspendCleanup = null;
      if (_resumePending) _suspended = false;
    }
  }

  Future<void> _cancelForSuspend() async {
    if (_busy && !processing) await _operationDone?.future;
    await cancel();
  }

  void handleResume() {
    if (_suspendCleanup != null) {
      _resumePending = true;
    } else {
      _suspended = false;
    }
  }

  Future<void> cancel() async {
    if (processing) {
      _cancelRequested = true;
      dictation.cancelProcessing();
      await desktop.hideHud();
      await _operationDone?.future;
      await desktop.setRecording(false);
      return;
    }
    if (!_listening) {
      _hudTimer?.cancel();
      await desktop.hideHud();
      return;
    }
    _listening = false;
    recording.value = false;
    _mode = null;
    _timer?.cancel();
    _levelTimer?.cancel();
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
        _suspended ||
        (paused && !_listening) ||
        _busy ||
        (_settingsBlocksShortcut && !_listening)) {
      return;
    }
    _busy = true;
    _cancelRequested = false;
    _operationDone = Completer<void>();
    _hudTimer?.cancel();
    try {
      if (!_listening) {
        seconds.value = 0;
        message.value = '';
        hud.value = HudState.preparing;
        await desktop.updateHud(hud.value.name, message.value, seconds.value);
        await desktop.showHud();
        final liveEnabled = !translate && settings.streamPreview();
        dictation.onLivePreview = liveEnabled
            ? (text) {
                if (!_listening) return;
                final display = text.trim().replaceAll(RegExp(r'\s+'), ' ');
                message.value = display.length > 38
                    ? '…${display.substring(display.length - 35)}'
                    : display;
                unawaited(
                  desktop.updateHud(
                    hud.value.name,
                    message.value,
                    seconds.value,
                  ),
                );
              }
            : null;
        await dictation.start(translate: translate);
        if (_cancelRequested) {
          await dictation.cancel();
          await desktop.setRecording(false);
          await desktop.hideHud();
          return;
        }
        _listening = true;
        recording.value = true;
        await desktop.setRecording(true);
        hud.value = HudState.listening;
        if (liveEnabled) message.value = 'Live: waiting for speech';
        await desktop.updateHud(hud.value.name, message.value, seconds.value);
        _levelTimer = Timer.periodic(const Duration(milliseconds: 120), (
          _,
        ) async {
          if (_readingLevel || !_listening) return;
          _readingLevel = true;
          try {
            final amplitude = await dictation.audio.amplitude();
            if (_listening) {
              await desktop.updateHudLevel(
                ((amplitude.current + 60) / 60).clamp(0.0, 1.0),
              );
            }
          } catch (_) {
            // Audio level is optional; recording must continue if unavailable.
          } finally {
            _readingLevel = false;
          }
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          seconds.value++;
          unawaited(
            desktop.updateHud(hud.value.name, message.value, seconds.value),
          );
        });
      } else {
        _timer?.cancel();
        _levelTimer?.cancel();
        _listening = false;
        recording.value = false;
        processing = true;
        hud.value = HudState.writing;
        message.value = dictation.onLivePreview != null
            ? 'Finishing transcription…'
            : '';
        await desktop.updateHud(hud.value.name, message.value, seconds.value);
        await dictation.finish();
        if (_cancelRequested) return;
        await desktop.setRecording(false);
        if (dictation.historySaveFailed) {
          hud.value = HudState.error;
          message.value = 'Text sent, but history could not be saved.';
        } else {
          hud.value = HudState.success;
          message.value = '';
        }
        await desktop.updateHud(hud.value.name, message.value, seconds.value);
        _scheduleHudHide(
          dictation.historySaveFailed
              ? const Duration(seconds: 5)
              : const Duration(milliseconds: 1200),
        );
      }
    } catch (e) {
      if (_cancelRequested) {
        await desktop.setRecording(false);
        await desktop.hideHud();
        return;
      }
      debugPrint(
        'Dictation failed: ${e is DictationException ? e.code : e.runtimeType}',
      );
      _mode = null;
      recording.value = false;
      _timer?.cancel();
      _levelTimer?.cancel();
      if (_listening) {
        _listening = false;
        try {
          await dictation.cancel();
        } catch (_) {}
      }
      await desktop.setRecording(false);
      final clipboardFallback =
          e is DictationException && e.code == 'clipboard_fallback';
      hud.value = clipboardFallback ? HudState.success : HudState.error;
      message.value = e is DictationException
          ? e.message
          : e
                .toString()
                .replaceFirst('Bad state: ', '')
                .replaceFirst('Exception: ', '');
      if (dictation.historySaveFailed) {
        message.value += ' History could not be saved.';
      }
      await desktop.updateHud(hud.value.name, message.value, seconds.value);
      await desktop.showHud();
      _scheduleHudHide(Duration(milliseconds: clipboardFallback ? 4000 : 5000));
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
    _levelTimer?.cancel();
    _hudTimer?.cancel();
    await dictation.dispose();
    await settings.close();
    await desktop.dispose();
  }
}
