import 'dart:async';
import 'dart:typed_data';

import 'package:ai_voice_dictator/services/live_preview.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List audio(int milliseconds, int sample) {
  final bytes = Uint8List(milliseconds * 32);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < bytes.length; i += 2) {
    data.setInt16(i, sample, Endian.little);
  }
  return bytes;
}

void main() {
  test('waits for three seconds and pads the final speech chunk', () async {
    final lengths = <int>[];
    final preview = LivePreview(
      transcribe: (file, _, _, _) async {
        lengths.add((await file.length()) - 44);
        return 'word${lengths.length}';
      },
      deliver: (_, _) async {},
    );
    preview.add(audio(1200, 1200));
    preview.add(audio(400, 0));
    await Future<void>.delayed(Duration.zero);
    expect(lengths, isEmpty);
    preview.add(audio(1400, 1200));
    preview.add(audio(100, 0));
    await preview.finish();
    expect(lengths, [3100 * 32]);

    final short = LivePreview(
      transcribe: (file, _, _, _) async {
        final data = await file.readAsBytes();
        expect(data.length - 44, 3000 * 32);
        expect(ByteData.sublistView(data).getInt16(44, Endian.little), 1200);
        expect(data.last, 0);
        return 'final';
      },
      deliver: (_, _) async {},
    );
    short.add(audio(1000, 1200));
    await short.finish();
    expect(short.failed, isFalse);
  });

  test('removes subtitle timestamp lines before delivery', () async {
    final delivered = <String>[];
    final preview = LivePreview(
      transcribe: (_, _, _, _) async =>
          '00:00:00.000 → 00:00:01.000\nHello there.',
      deliver: (delta, _) async => delivered.add(delta),
    );
    preview.add(audio(4000, 1200));
    await preview.finish();
    expect(delivered, ['Hello there.']);
  });

  test(
    'stops on a third identical chunk without dropping the first two',
    () async {
      final delivered = <String>[];
      final preview = LivePreview(
        transcribe: (_, _, _, _) async => 'আমার কথা',
        deliver: (delta, _) async => delivered.add(delta),
      );
      preview.add(audio(12000, 1200));
      await preview.finish();
      expect(delivered, ['আমার কথা', ' আমার কথা']);
      expect(preview.failed, isTrue);
      expect(preview.deliveryAttempted, isTrue);
    },
  );
  test('requests wait for previous chunk delivery', () async {
    final first = Completer<String>();
    final started = Completer<void>();
    final delivered = <String>[];
    var calls = 0;
    final preview = LivePreview(
      transcribe: (_, _, _, _) {
        calls++;
        if (calls == 1) {
          started.complete();
          return first.future;
        }
        return Future.value('second');
      },
      deliver: (delta, _) async => delivered.add(delta),
    );
    preview.add(audio(8000, 1200));
    await started.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(calls, 1);
    first.complete('first');
    await preview.finish();
    expect(calls, 2);
    expect(delivered, ['first', ' second']);
  });

  test(
    'slow first request still delivers after several chunks arrive',
    () async {
      final started = Completer<void>();
      final first = Completer<String>();
      final deltas = <String>[];
      var calls = 0;
      final preview = LivePreview(
        transcribe: (_, _, _, _) {
          calls++;
          if (calls == 1) {
            started.complete();
            return first.future;
          }
          return Future.value('next$calls');
        },
        deliver: (delta, _) async => deltas.add(delta),
      );
      preview.add(audio(4000, 1200));
      await started.future;
      preview.add(audio(16000, 1200));
      first.complete('first');
      await preview.finish();
      expect(preview.failed, isFalse);
      expect(calls, 5);
      expect(deltas.first, 'first');
    },
  );

  test('streams deltas in order and flushes the final chunk', () async {
    final contexts = <String>[];
    final deltas = <String>[];
    final firstDelivered = Completer<void>();
    final preview = LivePreview(
      transcribe: (file, seconds, context, update) async {
        contexts.add(context);
        if (contexts.length == 1) {
          update('Hel');
          update('Hello');
          return 'Hello';
        }
        update('world');
        return 'world';
      },
      deliver: (delta, text) async {
        deltas.add(delta);
        if (text == 'Hello') firstDelivered.complete();
      },
    );
    preview.add(audio(4000, 1200));
    await firstDelivered.future.timeout(const Duration(seconds: 5));
    preview.add(audio(1000, 1200));
    await preview.finish();
    expect(contexts, ['', 'Hello']);
    expect(deltas, ['Hello', ' world']);
    expect(preview.text, 'Hello world');
    expect(preview.failed, isFalse);
  });

  test('failure stops later delivery for safe full-file recovery', () async {
    var calls = 0;
    final statuses = <String>[];
    final preview = LivePreview(
      transcribe: (_, _, _, _) async {
        calls++;
        throw StateError('offline');
      },
      deliver: (_, _) async => fail('must not type'),
      onStatus: statuses.add,
    );
    preview.add(audio(8000, 1200));
    await preview.finish();
    expect(calls, inInclusiveRange(1, 2));
    expect(preview.failed, isTrue);
    expect(statuses.last, 'Live unavailable; finish to recover');
    expect(preview.deliveryAttempted, isFalse);
  });

  test('cancel suppresses an in-flight result', () async {
    final started = Completer<void>();
    final result = Completer<String>();
    final preview = LivePreview(
      transcribe: (_, _, _, _) {
        started.complete();
        return result.future;
      },
      deliver: (_, _) async => fail('must not type'),
    );
    preview.add(audio(4000, 1200));
    await started.future.timeout(const Duration(seconds: 5));
    preview.stop();
    result.complete('Cancelled');
    await preview.finish();
    expect(preview.text, isEmpty);
  });

  test(
    'waits for an in-flight insertion before reporting stream failure',
    () async {
      final inserted = Completer<void>();
      final proceed = Completer<void>();
      final preview = LivePreview(
        transcribe: (_, _, _, _) async => 'Hello',
        deliver: (_, _) async {
          inserted.complete();
          await proceed.future;
          throw StateError('typing failed');
        },
      );
      preview.add(audio(4000, 1200));
      await inserted.future.timeout(const Duration(seconds: 5));
      var finished = false;
      final finish = preview.finish().then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      proceed.complete();
      await finish;
      expect(preview.failed, isTrue);
      expect(preview.deliveryAttempted, isTrue);
    },
  );

  test(
    'rejects a repeated phrase before typing and requests recovery',
    () async {
      final delivered = <String>[];
      final preview = LivePreview(
        transcribe: (_, _, _, _) async => 'আমার কথা আমার কথা আমার কথা',
        deliver: (delta, _) async => delivered.add(delta),
      );
      preview.add(audio(4000, 1200));
      await preview.finish();
      expect(delivered, isEmpty);
      expect(preview.failed, isTrue);
    },
  );
}
