import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../guardrails.dart';
import '../settings/settings_store.dart';

enum DictationLanguageMode { auto, codeSwitching, translate }

const String kDictationSystemInstruction = '''
Transcribe the audio as clean dictation, not a reply. Remove meaningless fillers
and false starts; retain meaningful affirmations. Preserve meaning, word order,
names, numbers, and technical terms. Punctuate naturally; convert spoken
punctuation and new line commands. Write Bengali in Bengali script and spoken
English words in English; preserve code-switching. Never translate unless
requested. Return only the transcript.
''';

class LanguagePromptBuilder {
  static String buildSystemPrompt({
    required DictationLanguageMode mode,
    String targetLanguage = 'English',
  }) {
    final directive = switch (mode) {
      DictationLanguageMode.auto => 'Automatically identify the spoken language and transcribe in that language. Preserve transitions between languages.',
      DictationLanguageMode.codeSwitching => 'Write colloquial Bengali in natural Bengali script and all spoken English words and phrases in English. Preserve the original languages and do not translate.',
      DictationLanguageMode.translate =>
        'Translate the spoken audio into fluent, natural $targetLanguage. Return only the translated text.',
    };
    return '$kDictationSystemInstruction\nLANGUAGE DIRECTIVE: $directive';
  }
}

class GeminiDictationService {
  // The public injection parameter remains named client.
  // ignore: prefer_initializing_formals
  GeminiDictationService(
    this.apiKey, {
    this.model = SettingsStore.defaultModel,
    this._client,
  });
  final String apiKey;
  final String model;
  final http.Client? _client;
  static const maxAudioBytes = 12 * 1024 * 1024;
  static const models = ['gemini-3.1-flash-lite', 'gemini-3.5-flash-lite'];

  Future<String> transcribe(
    File audioFile,
    int durationSec, {
    DictationLanguageMode mode = DictationLanguageMode.auto,
    String targetLanguage = 'English',
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const DictationException(
        'key_missing',
        'Please set your Gemini API key in Settings.',
      );
    }
    if (!SettingsStore.validModel(model)) {
      throw const DictationException(
        'invalid_model',
        'Enter a valid Gemini model ID in Setup.',
      );
    }
    if (targetLanguage.length > 50 ||
        !RegExp(r'^[a-zA-Z -]+$').hasMatch(targetLanguage)) {
      throw const DictationException(
        'invalid_language',
        'Invalid translation language.',
      );
    }
    final length = await audioFile.length();
    if (length > maxAudioBytes) {
      throw const DictationException(
        'audio_too_large',
        'Recording is too long.',
      );
    }
    final bytes = await audioFile.readAsBytes();
    if (bytes.length > maxAudioBytes) {
      throw const DictationException(
        'audio_too_large',
        'Recording is too long.',
      );
    }
    final payload = {
      'system_instruction': {
        'parts': [
          {
            'text': LanguagePromptBuilder.buildSystemPrompt(
              mode: mode,
              targetLanguage: targetLanguage,
            ),
          },
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'inline_data': {
                'mime_type': 'audio/wav',
                'data': base64Encode(bytes),
              },
            },
            {
              'text':
                  'Transcribe accurately according to the system instructions.',
            },
          ],
        },
      ],
    };
    final client = _client ?? http.Client();
    try {
      String? failure;
      for (final model in this.model == models.first ? models : [this.model]) {
        final body = jsonEncode({
          ...payload,
          'generationConfig': {
            'temperature': 0.0,
            'topP': 0.95,
            if (models.contains(model) || model == 'gemini-3-flash-preview')
              'thinkingConfig': {'thinkingLevel': 'minimal'},
          },
        });
        for (var attempt = 0; attempt < 2; attempt++) {
          http.Response response;
          try {
            response = await client
                .post(
                  Uri.https(
                    'generativelanguage.googleapis.com',
                    '/v1beta/models/$model:generateContent',
                  ),
                  headers: {
                    'Content-Type': 'application/json',
                    'x-goog-api-key': apiKey,
                  },
                  body: body,
                )
                .timeout(const Duration(seconds: 25));
          } on TimeoutException {
            debugPrint('Gemini request timed out for $model');
            failure ??=
                'Gemini timed out. Check your internet connection and retry.';
            break;
          } on http.ClientException {
            debugPrint('Gemini network connection failed for $model');
            failure ??=
                'Could not reach Gemini. Check your internet connection.';
            break;
          }
          debugPrint('Gemini $model HTTP ${response.statusCode}');
          if (response.statusCode == 200) {
            try {
              final json = jsonDecode(response.body) as Map<String, dynamic>;
              final candidates = json['candidates'] as List<dynamic>?;
              final content =
                  candidates?.firstOrNull?['content'] as Map<String, dynamic>?;
              final parts = content?['parts'] as List<dynamic>?;
              final text =
                  parts?.map((part) => part['text'] as String? ?? '').join() ??
                  '';
              return DictationGuardrails.sanitizeResponse(text, durationSec);
            } on FormatException {
              throw const DictationException(
                'invalid_response',
                'Gemini returned an invalid response.',
              );
            } on TypeError {
              throw const DictationException(
                'invalid_response',
                'Gemini returned an invalid response.',
              );
            }
          }
          if (response.statusCode == 429) {
            failure = 'Gemini quota or rate limit reached (HTTP 429). Check your API quota.';
            break;
          }
          if (response.statusCode == 404) {
            failure ??=
                'The configured Gemini model is unavailable (HTTP 404).';
            break;
          }
          if (response.statusCode == 503 || response.statusCode == 500) {
            failure ??=
                'Gemini is temporarily unavailable (HTTP ${response.statusCode}).';
            if (attempt == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 600));
            }
            continue;
          }
          if (response.statusCode == 400 ||
              response.statusCode == 401 ||
              response.statusCode == 403) {
            throw const DictationException(
              'api_rejected',
              'Gemini rejected the request. Check your API key and access.',
            );
          }
          throw DictationException(
            'api_error',
            'Gemini request failed (HTTP ${response.statusCode}).',
          );
        }
      }
      throw DictationException(
        'api_unavailable',
        failure ?? 'Gemini is unavailable. Try again later.',
      );
    } finally {
      if (_client == null) client.close();
    }
  }
}
