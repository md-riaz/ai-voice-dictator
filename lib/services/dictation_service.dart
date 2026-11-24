import 'dart:io';

import '../guardrails.dart';
import '../settings/settings_store.dart';
import 'audio_service.dart';
import 'pause_trimmer.dart';
import 'desktop_service.dart';
import 'gemini_service.dart';
import 'password_guard.dart';

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
    this.passwordCheck,
  }) : _transcribe = transcribe; // ignore: prefer_initializing_formals
  final SettingsStore settings;
  final AudioService audio;
  final DesktopService desktop;
  final Transcribe? _transcribe;
  final bool Function()? canPaste;
  final bool Function()? playgroundActive;
  final bool Function(String)? insertPlayground;
  final Future<PasswordFieldStatus> Function()? passwordCheck;
  bool _translate = false;
  bool historySaveFailed = false;

  static Future<String> _transcribeWithGemini(
    File file,
    int duration,
    String key,
    DictationLanguageMode mode,
    String target,
    String model,
    String? systemPrompt, {
    void Function(String)? onChunk,
  }) => GeminiDictationService(key, model: model, systemPrompt: systemPrompt)
      .transcribe(
        file,
        duration,
        mode: mode,
        targetLanguage: target,
        onChunk: onChunk,
      );

  Future<void> start({bool translate = false}) async {
    await _checkPasswordField();
    historySaveFailed = false;
    if ((await settings.apiKey()).isEmpty) {
      throw const DictationException(
        'key_missing',
        'Please set your Gemini API key in Settings.',
      );
    }
    _translate = translate;
    await audio.start(deviceId: settings.deviceId());
  }

  Future<void> finish({void Function(String)? onChunk}) async {
    historySaveFailed = false;
    final recording = await audio.stop();
    if (recording == null) {
      throw const DictationException(
        'audio_empty',
        'No audio captured. Wait for “Speak now”, then try again.',
      );
    }
    try {
      await _checkPasswordField();
      DictationGuardrails.validateAudio(recording.file, recording.durationMs);
      await shortenInternalPauses(recording.file);
      var submittedAudio = recording.submittedAudio;
      if (submittedAudio != null) {
        try {
          submittedAudio = await normalizedWavDuration(recording.file);
        } catch (_) {
          submittedAudio = null;
        }
      }
      final mode = _translate
          ? DictationLanguageMode.translate
          : DictationLanguageMode.auto;
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
            onChunk: onChunk,
          );
      final text = await transcribe(
        recording.file,
        recording.durationSec,
        await settings.apiKey(),
        mode,
        settings.targetLanguage(),
        settings.model(),
      );
      var clipboardSaved = true;
      try {
        await desktop.copyTranscript(text);
      } catch (_) {
        clipboardSaved = false;
      }
      try {
        await settings.addHistory(
          text,
          Duration(milliseconds: recording.durationMs),
          capturedAudio: recording.capturedAudio,
          submittedAudio: submittedAudio,
        );
      } catch (_) {
        historySaveFailed = true;
      }
      if (!clipboardSaved && historySaveFailed) {
        throw StateError(
          'Could not save the transcript to the clipboard or history.',
        );
      }
      await _checkPasswordField();
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
        if (settings.typeText() || !clipboardSaved) {
          await desktop.typeText(text, target);
        } else {
          try {
            await desktop.paste(text, target);
          } on PasteNotDispatched {
            await desktop.typeText(text, target);
          }
        }
      }
    } finally {
      if (await recording.file.exists()) await recording.file.delete();
    }
  }

  Future<void> _checkPasswordField() async {
    final status = await passwordCheck?.call();
    if (status == PasswordFieldStatus.password) {
      throw const DictationException(
        'password_field',
        'Voice input is unavailable in password fields.',
      );
    }
    if (status == PasswordFieldStatus.unknown) {
      throw const DictationException(
        'focus_check_unavailable',
        'Could not check the focused field. Try again.',
      );
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
