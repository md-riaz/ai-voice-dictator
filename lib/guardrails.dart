import 'dart:io';

class DictationException implements Exception {
  const DictationException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '[$code] $message';
}

class DictationGuardrails {
  static void validateAudio(File file, int durationMs) {
    if (durationMs < 500) {
      throw const DictationException(
        'audio_too_short',
        'Hold the key longer while speaking.',
      );
    }
    if (file.lengthSync() < 8192) {
      throw const DictationException(
        'audio_silent',
        'No speech detected. Check your microphone.',
      );
    }
  }

  static String sanitizeResponse(String rawText, [int? durationSeconds]) {
    var text = rawText.trim();
    for (final prefix in [
      'here is the transcription:',
      'here is what was said:',
      'transcription:',
    ]) {
      if (text.toLowerCase().startsWith(prefix)) {
        text = text.substring(prefix.length).trim();
        break;
      }
    }
    if (text.isEmpty ||
        text.toLowerCase().startsWith('as an ai') ||
        text.toLowerCase().startsWith('sure, here is')) {
      throw const DictationException(
        'no_speech',
        'Could not transcribe audio.',
      );
    }
    if (durationSeconds != null &&
        durationSeconds > 1 &&
        text.split(RegExp(r'\s+')).length > (durationSeconds + 1) * 5) {
      throw const DictationException(
        'length_anomaly',
        'The transcription was unusually long for this recording. Please try again.',
      );
    }
    return text;
  }
}
