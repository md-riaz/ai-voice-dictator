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
  }) : _transcribe = transcribe; // ignore: prefer_initializing_formals
  final SettingsStore settings;
  final AudioService audio;
  final DesktopService desktop;
  final Transcribe? _transcribe;
  final bool Function()? canPaste;
  final bool Function()? playgroundActive;
  final bool Function(String)? insertPlayground;
  bool _translate = false;

  static Future<String> _transcribeWithGemini(
    File file,
    int duration,
    String key,
    DictationLanguageMode mode,
    String target,
    String model,
    String? systemPrompt,
  ) => GeminiDictationService(
    key,
    model: model,
    systemPrompt: systemPrompt,
  ).transcribe(file, duration, mode: mode, targetLanguage: target);

  Future<void> start({bool translate = false}) async {
    if ((await settings.apiKey()).isEmpty) {
      throw const DictationException(
        'key_missing',
        'Please set your Gemini API key in Settings.',
      );
    }
    _translate = translate;
    await audio.start(deviceId: settings.deviceId());
  }

  Future<void> finish() async {
    final recording = await audio.stop();
    if (recording == null) {
      throw const DictationException(
        'audio_empty',
        'No audio captured. Wait for “Speak now”, then try again.',
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
      final transcribe =
          _transcribe ??
          (file, duration, key, mode, target, model) => _transcribeWithGemini(
            file,
            duration,
            key,
            mode,
            target,
            model,
            settings.systemPrompt(),
          );
      final text = await transcribe(
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
          'Focus a text field. The transcript is on the clipboard.',
        );
      }
      if (playgroundActive?.call() == true) {
        if (insertPlayground?.call(text) != true) {
          throw StateError(
            'The playground lost focus. The transcript is on the clipboard.',
          );
        }
      } else {
        final target = desktop.captureTarget();
        if (target == 0) {
          throw StateError(
            'No active window. The transcript is on the clipboard.',
          );
        }
        await desktop.paste(text, target);
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
