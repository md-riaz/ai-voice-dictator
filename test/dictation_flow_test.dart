import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  FlowAudio(this.file, {this.capturedAudio, this.submittedAudio});
  final File file;
  final Duration? capturedAudio;
  final Duration? submittedAudio;
  bool started = false;
  @override
  Future<void> start({String? deviceId}) async {
    started = true;
  }

  @override
  Future<RecordedAudioResult> stop() async => RecordedAudioResult(
    file: file,
    durationMs: 2000,
    capturedAudio: capturedAudio,
    submittedAudio: submittedAudio,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FlowDesktop implements DesktopService {
  int target = 123;
  String? pasted;
  String? typed;
  String? copied;
  bool copyFails = false;
  Object? pasteFailure;
  @override
  Future<void> copyTranscript(String text) async {
    if (copyFails) throw StateError('Clipboard unavailable');
    copied = text;
  }

  @override
  int captureTarget() => target;
  @override
  Future<void> paste(String text, int target) async {
    expect(target, this.target);
    if (pasteFailure != null) throw pasteFailure!;
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
  test('normalizes mixed Windows clipboard line endings idempotently', () {
    const expected = 'one\r\ntwo\r\nthree\r\n\r\nfour';
    expect(
      normalizeWindowsLineEndings('one\ntwo\r\nthree\r\n\nfour'),
      expected,
    );
    expect(normalizeWindowsLineEndings(expected), expected);
  });
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

  test('records request time and total time after recording stops', () async {
    final service = DictationService(
      settings,
      FlowAudio(file),
      FlowDesktop(),
      transcribe: (_, _, _, _, _, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return 'Hello';
      },
    );
    await service.start();
    await service.finish();
    final entry = (await settings.history()).single;
    expect(entry.geminiRequest!.inMilliseconds, greaterThanOrEqualTo(40));
    expect(entry.afterStop!, greaterThanOrEqualTo(entry.geminiRequest!));
  });

  Future<void> runFlow(
    FlowDesktop desktop, {
    int status = 200,
    bool Function()? canPaste,
    bool Function()? playgroundActive,
    bool Function(String)? insertPlayground,
    void Function()? onTranscribe,
    String transcript = 'Hello world.',
    Duration? capturedAudio,
    Duration? submittedAudio,
  }) async {
    final audio = FlowAudio(
      file,
      capturedAudio: capturedAudio,
      submittedAudio: submittedAudio,
    );
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
                        {'text': transcript},
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

  test(
    'automatically shortens pauses and stores the final submitted duration',
    () async {
      const rate = 16000;
      final bytes = Uint8List(44 + rate * 4 * 2);
      final data = ByteData.sublistView(bytes);
      void tag(int offset, String value) =>
          bytes.setRange(offset, offset + value.length, value.codeUnits);
      tag(0, 'RIFF');
      data.setUint32(4, bytes.length - 8, Endian.little);
      tag(8, 'WAVE');
      tag(12, 'fmt ');
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 1, Endian.little);
      data.setUint16(22, 1, Endian.little);
      data.setUint32(24, rate, Endian.little);
      data.setUint32(28, rate * 2, Endian.little);
      data.setUint16(32, 2, Endian.little);
      data.setUint16(34, 16, Endian.little);
      tag(36, 'data');
      data.setUint32(40, bytes.length - 44, Endian.little);
      for (var i = 0; i < rate; i++) {
        data.setInt16(44 + i * 2, 1000, Endian.little);
        data.setInt16(44 + (i + rate * 3) * 2, 1000, Endian.little);
      }
      await file.writeAsBytes(bytes);
      await runFlow(
        FlowDesktop(),
        capturedAudio: const Duration(seconds: 4),
        submittedAudio: const Duration(seconds: 4),
      );
      final entry = (await settings.history()).single;
      expect(entry.capturedAudio, const Duration(seconds: 4));
      expect(entry.submittedAudio, const Duration(milliseconds: 2650));
    },
  );

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
  test('preserves multiline text in clipboard, history, and paste', () async {
    final desktop = FlowDesktop();
    await runFlow(desktop, transcript: 'First line.\nSecond line.');
    expect(desktop.pasted, 'First line.\nSecond line.');
    expect(desktop.copied, desktop.pasted);
    expect((await settings.history()).single.text, desktop.pasted);
  });
  test('typing mode delivers multiline text', () async {
    await settings.setTypeText(true);
    final desktop = FlowDesktop();
    await runFlow(desktop, transcript: 'First line.\nSecond line.');
    expect(desktop.typed, 'First line.\nSecond line.');
    expect(desktop.copied, desktop.typed);
  });
  test('falls back to typing when paste was not dispatched', () async {
    final desktop = FlowDesktop()..pasteFailure = const PasteNotDispatched();
    await runFlow(desktop);
    expect(desktop.typed, 'Hello world.');
    expect(desktop.pasted, isNull);
  });
  test('does not retry an uncertain paste', () async {
    final desktop = FlowDesktop()
      ..pasteFailure = StateError('partial dispatch');
    await expectLater(runFlow(desktop), throwsStateError);
    expect(desktop.typed, isNull);
  });
  test('types when clipboard is unavailable but history is saved', () async {
    final desktop = FlowDesktop()..copyFails = true;
    await runFlow(desktop);
    expect(desktop.typed, 'Hello world.');
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
