import 'dart:io';

import '../guardrails.dart';
import '../settings/settings_store.dart';
import 'audio_service.dart';
import 'desktop_service.dart';
import 'gemini_service.dart';

typedef Transcribe =
    Future<String> Function(
      File file,
      int durationSeconds,
      String apiKey,
      DictationLanguageMode mode,
      String targetLanguage,
    );

class DictationService {
  DictationService(
    this.settings,
    this.audio,
    this.desktop, {
    Transcribe? transcribe,
  }) : _transcribe = transcribe ?? _transcribeWithGemini;
  final SettingsStore settings;
  final AudioService audio;
  final DesktopService desktop;
  final Transcribe _transcribe;
  int _target = 0;
  bool _translate = false;

  static Future<String> _transcribeWithGemini(
    File file,
    int duration,
    String key,
    DictationLanguageMode mode,
    String target,
  ) => GeminiDictationService(
    key,
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
    _translate = translate;
    await audio.start(deviceId: settings.deviceId());
  }

  Future<void> finish() async {
    final recording = await audio.stop();
    if (recording == null) throw StateError('Recording failed.');
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
      );
      await settings.addHistory(
        text,
        Duration(milliseconds: recording.durationMs),
      );
      await desktop.paste(text, _target);
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
