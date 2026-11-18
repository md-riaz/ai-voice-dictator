import 'package:ai_voice_dictator/guardrails.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes a transcription preamble', () {
    expect(
      DictationGuardrails.sanitizeResponse('Transcription: Hello.'),
      'Hello.',
    );
  });
  test('rejects empty and conversational output', () {
    for (final value in ['', 'Transcription:', 'As an AI, I cannot help.']) {
      expect(
        () => DictationGuardrails.sanitizeResponse(value),
        throwsA(isA<DictationException>()),
      );
    }
  });
}
