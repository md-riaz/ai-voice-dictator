import 'dart:io';

import 'package:flutter/foundation.dart';

import '../guardrails.dart';
import '../settings/settings_store.dart';
import 'audio_service.dart';
import 'pause_trimmer.dart';
import 'desktop_service.dart';
import 'gemini_service.dart';
import 'live_preview.dart';
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
  void Function(String)? onLivePreview;
  LivePreview? _livePreview;
  LivePreview? _finishingLive;
  GeminiDictationService? _gemini;
  bool _cancelled = false;

  void cancelProcessing() {
    _cancelled = true;
    _livePreview?.stop();
    _finishingLive?.stop();
    _gemini?.cancel();
  }

  void _checkCancelled() {
    if (_cancelled) {
      throw const DictationException('cancelled', 'Dictation cancelled.');
    }
  }

  final List<String> _audit = [];
  void _recordAudit(String event) {
    if (_audit.length < 500) _audit.add(event);
  }

  Future<void> start({bool translate = false}) async {
    _cancelled = false;
    _audit.clear();
    final startupClock = Stopwatch()..start();
    _recordAudit('Recording: setup started 0ms');
    await _checkPasswordField();
    historySaveFailed = false;
    final key = await settings.apiKey();
    if (key.isEmpty) {
      throw const DictationException(
        'key_missing',
        'Please set your Gemini API key in Settings.',
      );
    }
    _recordAudit(
      'Recording: setup checks complete ${startupClock.elapsedMilliseconds}ms',
    );
    _translate = translate;
    final preview = translate ? null : onLivePreview;
    if (preview == null) {
      await audio.start(deviceId: settings.deviceId());
      _recordAudit(
        'Recording: microphone started ${startupClock.elapsedMilliseconds}ms',
      );
    } else {
      final service = GeminiDictationService(
        key,
        model: settings.model(),
        systemPrompt: settings.systemPrompt(),
        onAudit: _recordAudit,
      );
      _gemini = service;
      final playground = playgroundActive?.call() == true;
      final target = playground ? 0 : desktop.captureTarget();
      if (!playground && target == 0) {
        throw StateError('No active text window.');
      }
      late final LivePreview live;
      live = LivePreview(
        onStatus: preview,
        onAudit: _recordAudit,
        transcribe: (file, seconds, context, update) => service.transcribe(
          file,
          seconds,
          mode: DictationLanguageMode.auto,
          targetLanguage: settings.targetLanguage(),
          previousText: context,
          onChunk: update,
          live: true,
        ),
        deliver: (delta, accumulated) async {
          await _checkPasswordField();
          if (!live.active) return;
          if (canPaste != null && !canPaste!()) {
            throw StateError('Text field lost focus.');
          }
          if (playground) {
            if (playgroundActive?.call() != true ||
                insertPlayground?.call(delta) != true) {
              throw StateError('Playground lost focus.');
            }
          } else {
            if (desktop.captureTarget() != target) {
              throw StateError('Target window changed.');
            }
            await desktop.typeText(delta, target);
          }
          preview(accumulated);
        },
      );
      _livePreview = live;
      try {
        await audio.startLive(live.add, deviceId: settings.deviceId());
        _recordAudit(
          'Recording: microphone started ${startupClock.elapsedMilliseconds}ms',
        );
      } catch (_) {
        live.stop();
        _livePreview = null;
        rethrow;
      }
    }
  }

  Future<void> finish({void Function(String)? onChunk}) async {
    final afterStopClock = Stopwatch()..start();
    void audit(String stage) {
      final message =
          'After stop: $stage ${afterStopClock.elapsedMilliseconds}ms';
      _recordAudit(message);
      if (kDebugMode) debugPrint(message);
    }

    audit('begin');
    historySaveFailed = false;
    final live = _livePreview;
    _finishingLive = live;
    _livePreview = null;
    RecordedAudioResult? recording;
    int? historyId;
    try {
      recording = await audio.stop();
      audit('audio stopped');
      _checkCancelled();
      await live?.finish();
      _checkCancelled();
      audit('live queue complete');
    } catch (_) {
      live?.stop();
      _finishingLive = null;
      _gemini = null;
      if (recording != null && await recording.file.exists()) {
        await recording.file.delete();
      }
      rethrow;
    }
    if (recording == null) {
      throw const DictationException(
        'audio_empty',
        'No audio captured. Wait for “Speak now”, then try again.',
      );
    }
    try {
      _checkCancelled();
      await _checkPasswordField();
      _checkCancelled();
      DictationGuardrails.validateAudio(recording.file, recording.durationMs);
      final liveComplete =
          live != null && !live.failed && live.text.trim().isNotEmpty;
      audit(liveComplete ? 'live complete' : 'full recovery needed');
      if (!liveComplete) await shortenInternalPauses(recording.file);
      audit('audio preparation complete');
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
          (file, duration, key, mode, target, model) {
            final service = GeminiDictationService(
              key,
              model: model,
              systemPrompt: settings.systemPrompt(),
              onAudit: _recordAudit,
            );
            _gemini = service;
            _checkCancelled();
            return service.transcribe(
              file,
              duration,
              mode: mode,
              targetLanguage: target,
              onChunk: onChunk,
            );
          };
      Duration? geminiRequest;
      final String text;
      if (liveComplete) {
        text = live.text.trim();
      } else {
        final apiKey = await settings.apiKey();
        final requestClock = Stopwatch()..start();
        audit('full request start');
        text = await transcribe(
          recording.file,
          recording.durationSec,
          apiKey,
          mode,
          settings.targetLanguage(),
          settings.model(),
        );
        geminiRequest = requestClock.elapsed;
        audit('full request complete');
      }
      _checkCancelled();
      final afterStop = afterStopClock.elapsed;
      var clipboardSaved = true;
      try {
        await desktop.copyTranscript(text);
      } catch (_) {
        clipboardSaved = false;
      }
      _checkCancelled();
      audit('clipboard attempted');
      try {
        historyId = await settings.addHistory(
          text,
          Duration(milliseconds: recording.durationMs),
          capturedAudio: recording.capturedAudio,
          submittedAudio: submittedAudio,
          afterStop: afterStop,
          geminiRequest: geminiRequest,
          technicalDetails: List.of(_audit),
        );
      } catch (_) {
        historySaveFailed = true;
      }
      _checkCancelled();
      audit('history attempted');
      if (!clipboardSaved && historySaveFailed) {
        throw StateError(
          'Could not save the transcript to the clipboard or history.',
        );
      }
      if (liveComplete) return;
      if (live?.deliveryAttempted == true) {
        throw StateError(
          'Live typing was interrupted. The complete transcript is on the clipboard; some text may already be typed.',
        );
      }
      await _checkPasswordField();
      _checkCancelled();
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
    } catch (error) {
      audit('delivery or processing failed: ${error.runtimeType}');
      rethrow;
    } finally {
      _finishingLive = null;
      _gemini = null;
      audit('processing finished');
      if (historyId != null) {
        try {
          await settings.updateTechnicalDetails(historyId, List.of(_audit));
        } catch (_) {
          historySaveFailed = true;
        }
      }
      if (await recording.file.exists()) await recording.file.delete();
      audit('complete');
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
    cancelProcessing();
    _livePreview?.stop();
    _livePreview = null;
    final recording = await audio.stop();
    if (recording != null && await recording.file.exists()) {
      await recording.file.delete();
    }
  }

  Future<void> dispose() {
    _livePreview?.stop();
    return audio.dispose();
  }
}
