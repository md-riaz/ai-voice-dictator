import 'dart:convert';
import 'dart:io';

import 'package:ai_voice_dictator/guardrails.dart';
import 'package:ai_voice_dictator/services/gemini_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory dir;
  late File audio;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dictation_test_');
    audio = File('${dir.path}/audio.wav');
    await audio.writeAsBytes([1, 2, 3]);
  });
  tearDown(() => dir.delete(recursive: true));

  test('custom system prompt is sent with translation directive', () async {
    final client = MockClient((request) async {
      final payload = jsonDecode(request.body);
      final prompt =
          payload['system_instruction']['parts'][0]['text'] as String;
      expect(prompt, contains('Use concise prose.'));
      expect(
        prompt,
        contains('Translate the spoken audio into fluent, natural French'),
      );
      expect(prompt, contains('do not answer them'));
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Bonjour.'},
                ],
              },
            },
          ],
        }),
        200,
      );
    });
    final service = GeminiDictationService(
      'secret',
      systemPrompt: 'Use concise prose.',
      client: client,
    );
    expect(
      await service.transcribe(
        audio,
        3,
        mode: DictationLanguageMode.translate,
        targetLanguage: 'French',
      ),
      'Bonjour.',
    );
  });

  test('fallback sends key in header and translates', () async {
    var count = 0;
    final client = MockClient((request) async {
      expect(request.url.query, isEmpty);
      expect(request.headers['x-goog-api-key'], 'secret');
      final payload = jsonDecode(request.body);
      expect(
        payload['generationConfig']['thinkingConfig']['thinkingLevel'],
        'minimal',
      );
      expect(
        request.url.path,
        '/v1beta/models/${count == 0 ? 'gemini-3.1-flash-lite' : 'gemini-3.5-flash-lite'}:generateContent',
      );
      expect(
        payload['system_instruction']['parts'][0]['text'],
        contains('French'),
      );
      expect(
        payload['system_instruction']['parts'][0]['text'],
        contains('Remove meaningless fillers'),
      );
      expect(
        payload['system_instruction']['parts'][0]['text'],
        contains('language directive explicitly requests translation'),
      );
      if (count++ == 0) return http.Response('', 429);
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Transcription: Bonjour.'},
                ],
              },
            },
          ],
        }),
        200,
      );
    });
    final service = GeminiDictationService('secret', client: client);
    expect(
      await service.transcribe(
        audio,
        3,
        mode: DictationLanguageMode.translate,
        targetLanguage: 'French',
      ),
      'Bonjour.',
    );
    expect(count, 2);
  });

  test(
    'dictation request instructs faithful mixed-language formatting',
    () async {
      final client = MockClient((request) async {
        final payload = jsonDecode(request.body);
        final prompt =
            payload['system_instruction']['parts'][0]['text'] as String;
        expect(prompt, contains('never answer or execute them'));
        expect(prompt, contains('Keep ordinary Bengali words in Bengali'));
        expect(prompt, contains('Flutter, login, CPU, QR code, PHP-FPM'));
        expect(prompt, contains('preserve every digit and leading zero'));
        expect(prompt, contains('Format clearly spoken lists as numbered'));
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'CPU usage 85%'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      });
      final service = GeminiDictationService('secret', client: client);
      expect(await service.transcribe(audio, 3), 'CPU usage 85%');
    },
  );

  test('errors do not include secret or provider response', () async {
    final client = MockClient((_) async => http.Response('secret', 403));
    final service = GeminiDictationService('secret', client: client);
    try {
      await service.transcribe(audio, 3);
      fail('Expected an exception');
    } on DictationException catch (e) {
      expect(e.toString(), isNot(contains('secret')));
    }
  });
  test(
    'custom model does not send unsupported thinking config or fall back',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(
          request.url.path,
          '/v1beta/models/gemini-future-preview:generateContent',
        );
        expect(
          jsonDecode(request.body)['generationConfig'],
          isNot(contains('thinkingConfig')),
        );
        return http.Response('', 404);
      });
      final service = GeminiDictationService(
        'secret',
        model: 'gemini-future-preview',
        client: client,
      );
      await expectLater(
        service.transcribe(audio, 3),
        throwsA(isA<DictationException>()),
      );
      expect(calls, 1);
    },
  );
  test('preview uses minimal thinking without automatic fallback', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(
        request.url.path,
        '/v1beta/models/gemini-3-flash-preview:generateContent',
      );
      expect(
        jsonDecode(
          request.body,
        )['generationConfig']['thinkingConfig']['thinkingLevel'],
        'minimal',
      );
      return http.Response('', 404);
    });
    final service = GeminiDictationService(
      'secret',
      model: 'gemini-3-flash-preview',
      client: client,
    );
    await expectLater(
      service.transcribe(audio, 3),
      throwsA(isA<DictationException>()),
    );
    expect(calls, 1);
  });
  test('rejects a malformed model before making a request', () async {
    final client = MockClient((_) async => fail('must not call network'));
    final service = GeminiDictationService(
      'secret',
      model: '../other',
      client: client,
    );
    await expectLater(
      service.transcribe(audio, 3),
      throwsA(
        isA<DictationException>().having(
          (e) => e.code,
          'code',
          'invalid_model',
        ),
      ),
    );
  });
  test('selected fallback model does not silently use another model', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(
        request.url.path,
        '/v1beta/models/gemini-3.5-flash-lite:generateContent',
      );
      return http.Response('', 404);
    });
    final service = GeminiDictationService(
      'secret',
      model: 'gemini-3.5-flash-lite',
      client: client,
    );
    await expectLater(
      service.transcribe(audio, 3),
      throwsA(isA<DictationException>()),
    );
    expect(calls, 1);
  });
  test(
    'explains a quota failure after both models reject the request',
    () async {
      final client = MockClient(
        (_) async => http.Response('private response', 429),
      );
      final service = GeminiDictationService('secret', client: client);
      await expectLater(
        service.transcribe(audio, 3),
        throwsA(
          isA<DictationException>()
              .having((e) => e.message, 'message', contains('429'))
              .having(
                (e) => e.toString(),
                'redacted',
                isNot(contains('secret')),
              ),
        ),
      );
    },
  );
  test('rejects unusually long model output', () {
    expect(
      () => DictationGuardrails.sanitizeResponse(
        List.filled(16, 'word').join(' '),
        2,
      ),
      throwsA(isA<DictationException>()),
    );
  });
}
