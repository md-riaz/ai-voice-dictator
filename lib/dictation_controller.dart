import 'dart:async';

import 'package:velora/velora.dart';

import 'guardrails.dart';
import 'services/audio_service.dart';
import 'services/desktop_service.dart';
import 'services/gemini_service.dart';
import 'settings/settings_store.dart';
import 'ui/floating_hud.dart';

class DictationController extends VeloraController {
  DictationController(this.settings, this.audio, this.desktop);
  final SettingsStore settings;
  final AudioService audio;
  final DesktopService desktop;
  final hud = HudState.listening.obs;
  final message = ''.obs;
  final seconds = 0.obs;
  final settingsVisible = false.obs;
  bool paused = false;
  bool _busy = false;
  bool _listening = false;
  bool _translate = false;
  int _target = 0;
  Timer? _timer;

  Future<void> toggle({bool translate = false}) async {
    if ((paused && !_listening) || _busy || settingsVisible.value) return;
    _busy = true;
    try {
      if (!_listening) {
        if ((await settings.apiKey()).isEmpty) {
          throw const DictationException(
            'key_missing',
            'Please set your Gemini API key in Settings.',
          );
        }
        _target = desktop.captureTarget();
        if (_target == 0) throw StateError('No active window found.');
        _translate = translate;
        await audio.start(deviceId: settings.deviceId());
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
        final recording = await audio.stop();
        if (recording == null) throw StateError('Recording failed.');
        try {
          DictationGuardrails.validateAudio(
            recording.file,
            recording.durationMs,
          );
          final mode = _translate
              ? DictationLanguageMode.translate
              : DictationLanguageMode.values.firstWhere(
                  (m) => m.name == settings.language(),
                  orElse: () => DictationLanguageMode.auto,
                );
          final text = await GeminiDictationService(await settings.apiKey())
              .transcribe(
                recording.file,
                recording.durationSec,
                mode: mode,
                targetLanguage: settings.targetLanguage(),
              );
          await settings.addHistory(
            text,
            Duration(milliseconds: recording.durationMs),
          );
          await desktop.paste(text, _target);
          hud.value = HudState.success;
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await desktop.hideHud();
        } finally {
          if (await recording.file.exists()) await recording.file.delete();
        }
      }
    } catch (e) {
      _timer?.cancel();
      if (_listening) {
        _listening = false;
        try {
          final recording = await audio.stop();
          if (recording != null && await recording.file.exists()) {
            await recording.file.delete();
          }
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
    }
  }

  Future<void> showSettings() async {
    if (_busy || _listening) return;
    settingsVisible.value = true;
    await desktop.showSettings();
  }

  Future<void> close() async {
    _timer?.cancel();
    await audio.dispose();
    await settings.close();
    await desktop.dispose();
  }
}
