import 'dart:convert';
import 'dart:io';

import 'package:ai_voice_dictator/services/audio_service.dart';
import 'package:ai_voice_dictator/services/desktop_service.dart';
import 'package:ai_voice_dictator/services/dictation_service.dart';
import 'package:ai_voice_dictator/services/gemini_service.dart';
import 'package:ai_voice_dictator/settings/settings_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FlowAudio implements AudioService {
  FlowAudio(this.file);
  final File file;
  bool started = false;
  @override
  Future<void> start({String? deviceId}) async {
    started = true;
  }

  @override
  Future<RecordedAudioResult> stop() async =>
      RecordedAudioResult(file: file, durationMs: 2000);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FlowDesktop implements DesktopService {
  int target = 123;
  String? pasted;
  String? typed;
  String? copied;
  @override
  Future<void> copyTranscript(String text) async => copied = text;
  @override
  int captureTarget() => target;
  @override
  Future<void> paste(String text, int target) async {
    expect(target, this.target);
    pasted = text;
  }

  @override
  Future<void> typeText(String text, int target) async {
    expect(target, this.target);
    typed = text;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File file;
  late SettingsStore settings;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('flow_test');
    file = File('${dir.path}/recording.wav');
    await file.writeAsBytes(List.filled(9000, 1));
    settings = SettingsStore();
    await settings.initialize(databasePath: inMemoryDatabasePath);
    await settings.saveApiKey('test-key');
  });
  tearDown(() async {
    await settings.close();
    await dir.delete(recursive: true);
  });

  Future<void> runFlow(
    FlowDesktop desktop, {
    int status = 200,
    bool Function()? canPaste,
    bool Function()? playgroundActive,
    bool Function(String)? insertPlayground,
    void Function()? onTranscribe,
  }) async {
    final audio = FlowAudio(file);
    final client = MockClient((request) async {
      onTranscribe?.call();
      expect(request.headers['x-goog-api-key'], 'test-key');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['contents'], isNotEmpty);
      return http.Response(
        status == 200
            ? jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Hello world.'},
                      ],
                    },
                  },
                ],
              })
            : '{}',
        status,
      );
    });
    final service = DictationService(
      settings,
      audio,
      desktop,
      canPaste: canPaste,
      playgroundActive: playgroundActive,
      insertPlayground: insertPlayground,
      transcribe: (file, duration, key, mode, target, model) =>
          GeminiDictationService(
            key,
            model: model,
            client: client,
          ).transcribe(file, duration, mode: mode, targetLanguage: target),
    );
    await service.start();
    expect(audio.started, true);
    try {
      await service.finish();
    } finally {
      client.close();
    }
  }

  test('records, sends Gemini request, stores and pastes transcript', () async {
    final desktop = FlowDesktop();
    await runFlow(desktop);
    expect(desktop.pasted, 'Hello world.');
    expect(desktop.copied, 'Hello world.');
    expect((await settings.history()).single.text, 'Hello world.');
    expect(await file.exists(), false);
  });
  test('typing mode preserves clipboard and history without pasting', () async {
    await settings.setTypeText(true);
    final desktop = FlowDesktop();
    await runFlow(desktop);
    expect(desktop.typed, 'Hello world.');
    expect(desktop.pasted, isNull);
    expect(desktop.copied, 'Hello world.');
    expect((await settings.history()).single.text, 'Hello world.');
  });
  test('pastes into the current window when target changes', () async {
    final desktop = FlowDesktop();
    await runFlow(desktop, onTranscribe: () => desktop.target = 456);
    expect(desktop.pasted, 'Hello world.');
    expect(desktop.copied, 'Hello world.');
    expect((await settings.history()).single.text, 'Hello world.');
    expect(await file.exists(), false);
  });
  test(
    'routes to playground when it gains focus during transcription',
    () async {
      final desktop = FlowDesktop();
      var focused = false;
      String? inserted;
      await runFlow(
        desktop,
        playgroundActive: () => focused,
        onTranscribe: () => focused = true,
        insertPlayground: (text) {
          inserted = text;
          return true;
        },
      );
      expect(inserted, 'Hello world.');
      expect(desktop.pasted, isNull);
    },
  );
  test(
    'pastes externally when playground loses focus during transcription',
    () async {
      final desktop = FlowDesktop();
      var focused = true;
      await runFlow(
        desktop,
        playgroundActive: () => focused,
        onTranscribe: () => focused = false,
        insertPlayground: (_) => fail('Playground is not focused'),
      );
      expect(desktop.pasted, 'Hello world.');
    },
  );
  test('keeps clipboard and history when no window is active', () async {
    final desktop = FlowDesktop();
    await expectLater(
      runFlow(desktop, onTranscribe: () => desktop.target = 0),
      throwsStateError,
    );
    expect(desktop.copied, 'Hello world.');
    expect((await settings.history()).single.text, 'Hello world.');
  });
  test(
    'inserts into the playground without simulating a system paste',
    () async {
      final desktop = FlowDesktop();
      String? inserted;
      await runFlow(
        desktop,
        playgroundActive: () => true,
        insertPlayground: (text) {
          inserted = text;
          return true;
        },
      );
      expect(inserted, 'Hello world.');
      expect(desktop.pasted, isNull);
      expect(desktop.copied, 'Hello world.');
      expect((await settings.history()).single.text, 'Hello world.');
    },
  );
  test('copies the transcript even if input focus changes', () async {
    final desktop = FlowDesktop();
    await expectLater(
      runFlow(desktop, canPaste: () => false),
      throwsStateError,
    );
    expect(desktop.copied, 'Hello world.');
    expect(desktop.pasted, isNull);
    expect((await settings.history()).single.text, 'Hello world.');
  });
  test(
    'cleans recording without storing or pasting on API rejection',
    () async {
      final desktop = FlowDesktop();
      await expectLater(runFlow(desktop, status: 403), throwsException);
      expect(await settings.history(), isEmpty);
      expect(desktop.pasted, isNull);
      expect(await file.exists(), false);
    },
  );
}
