import 'dart:io';

import '../guardrails.dart';
import '../settings/settings_store.dart';
import 'audio_service.dart';
import 'desktop_service.dart';
import 'gemini_service.dart';

typedef Transcribe = Future<String> Function(
  File file,
  int durationSeconds,
  String apiKey,
  DictationLanguageMode mode,
  String targetLanguage,
  String model,
);

class DictationService {
  DictationService(
    this.settings,
    this.audio,
    this.desktop, {
    Transcribe? transcribe,
    this.canPaste,
    this.playgroundActive,
    this.insertPlayground,
  }) : _transcribe = transcribe ?? _transcribeWithGemini;
  final SettingsStore settings;
  final AudioService audio;
  final DesktopService desktop;
  final Transcribe _transcribe;
  final bool Function()? canPaste;
  final bool Function()? playgroundActive;
  final bool Function(String)? insertPlayground;
  int _target = 0;
  bool _translate = false;
  bool _playgroundTarget = false;

  static Future<String> _transcribeWithGemini(
    File file,
    int duration,
    String key,
    DictationLanguageMode mode,
    String target,
    String model,
  ) => GeminiDictationService(
    key,
    model: model,
  ).transcribe(file, duration, mode: mode, targetLanguage: target);

  Future<void> start({bool translate = false}) async {
    if ((await settings.apiKey()).isEmpty) {
      throw const DictationException(
        'key_missing',
        'Please set your Gemini API key in Settings.',
      );
    }
    _target = desktop.captureTarget();
    if (_target == 0) throw StateError('No active window found.');
    _playgroundTarget = playgroundActive?.call() ?? false;
    _translate = translate;
    await audio.start(deviceId: settings.deviceId());
  }

  Future<void> finish() async {
    final recording = await audio.stop();
    if (recording == null) {
      throw const DictationException(
        'audio_empty',
        'No audio was captured. Wait for Listening, speak, then release. Check your microphone if it continues.',
      );
    }
    try {
      DictationGuardrails.validateAudio(recording.file, recording.durationMs);
      final mode = _translate
          ? DictationLanguageMode.translate
          : DictationLanguageMode.values.firstWhere(
              (m) => m.name == settings.language(),
              orElse: () => DictationLanguageMode.auto,
            );
      final text = await _transcribe(
        recording.file,
        recording.durationSec,
        await settings.apiKey(),
        mode,
        settings.targetLanguage(),
        settings.model(),
      );
      try {
        await desktop.copyTranscript(text);
      } catch (_) {
        throw StateError('Could not copy the transcript. Find it in history.');
      } finally {
        await settings.addHistory(
          text,
          Duration(milliseconds: recording.durationMs),
        );
      }
      if (canPaste != null && !canPaste!()) {
        throw StateError(
          'The input focus changed. The transcript is on the clipboard.',
        );
      }
      if (_playgroundTarget) {
        if (playgroundActive?.call() != true ||
            insertPlayground?.call(text) != true) {
          throw StateError(
            'The playground lost focus. The transcript is on the clipboard.',
          );
        }
      } else {
        await desktop.paste(text, _target);
      }
    } finally {
      if (await recording.file.exists()) await recording.file.delete();
    }
  }

  Future<void> cancel() async {
    final recording = await audio.stop();
    if (recording != null && await recording.file.exists()) {
      await recording.file.delete();
    }
  }

  Future<void> dispose() => audio.dispose();
}
