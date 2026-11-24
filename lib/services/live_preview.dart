import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'audio_service.dart';

class LivePreview {
  LivePreview({
    required this.transcribe,
    required this.deliver,
    this.onStatus,
    this.onAudit,
  });
  final Future<String> Function(File, int, String, void Function(String))
  transcribe;
  final Future<void> Function(String, String) deliver;
  final void Function(String)? onStatus;
  final void Function(String)? onAudit;
  final _pending = <int>[];
  final _chunk = BytesBuilder(copy: false);
  Future<void> _queue = Future.value();
  int _frames = 0;
  int _silentFrames = 0;
  int _queued = 0;
  int _nextChunkId = 0;
  bool _speech = false;
  bool _active = true;
  bool get active => _active;
  bool failed = false;
  bool deliveryAttempted = false;
  String text = '';
  String _lastChunk = '';
  int _sameChunks = 0;

  void add(Uint8List data) {
    if (!_active || failed) return;
    _pending.addAll(data);
    var offset = 0;
    while (_pending.length - offset >= 640) {
      final frame = Uint8List.fromList(_pending.sublist(offset, offset + 640));
      offset += 640;
      final samples = ByteData.sublistView(frame);
      var energy = 0.0;
      for (var i = 0; i < 640; i += 2) {
        final sample = samples.getInt16(i, Endian.little);
        energy += sample * sample;
      }
      final voiced = energy / 320 > 2500;
      _speech |= voiced;
      _silentFrames = voiced ? 0 : _silentFrames + 1;
      _frames++;
      _chunk.add(frame);
      if (_frames >= 200 || (_frames >= 150 && _silentFrames >= 5)) {
        _emit();
      }
    }
    if (offset > 0) _pending.removeRange(0, offset);
  }

  void _emit() {
    var bytes = _chunk.takeBytes();
    var frames = _frames;
    final shouldSend = _speech;
    _frames = 0;
    _silentFrames = 0;
    _speech = false;
    if (!shouldSend) return;
    if (frames < 150) {
      bytes = Uint8List(150 * 640)..setRange(0, bytes.length, bytes);
      frames = 150;
    }
    if (_queued >= 128) {
      _fail();
      return;
    }
    if (_queued == 0 && text.isEmpty) onStatus?.call('Connecting live...');
    _queued++;
    final previous = _queue;
    _queue = _process(
      bytes,
      frames,
      previous,
      ++_nextChunkId,
    ).whenComplete(() => _queued--);
  }

  Future<void> _process(
    Uint8List bytes,
    int frames,
    Future<void> previous,
    int chunkId,
  ) async {
    Directory? dir;
    final clock = Stopwatch()..start();
    void timing(String stage) {
      final message =
          'Chunk #$chunkId (${frames * 20}ms): $stage ${clock.elapsedMilliseconds}ms';
      onAudit?.call(message);
      if (kDebugMode) debugPrint(message);
    }

    try {
      await previous;
      timing('queue wait complete');
      if (!_active || failed) return;
      dir = await Directory.systemTemp.createTemp('dictation_live_');
      final file = File('${dir.path}/chunk.wav');
      await file.writeAsBytes(pcmToWav(bytes));
      if (!_active || failed) return;
      timing('request start');
      final result = await runZoned(
        () => transcribe(file, (frames / 50).ceil(), text, (_) {}),
        zoneValues: {'auditChunkId': chunkId},
      );
      timing('request complete');
      if (!_active || failed) return;
      final chunk = result
          .replaceAll(
            RegExp(
              r'^\s*\d{1,2}:\d{2}:\d{2}[.,]\d{3}\s*(?:-->|→)\s*\d{1,2}:\d{2}:\d{2}[.,]\d{3}\s*$',
              multiLine: true,
            ),
            '',
          )
          .trim();
      if (chunk.isEmpty) throw StateError('Empty transcription');
      final normalized = _normalize(chunk);
      _sameChunks = normalized == _lastChunk ? _sameChunks + 1 : 1;
      _lastChunk = normalized;
      if (_sameChunks >= 3 || _repeatsPhrase(normalized)) {
        throw StateError('Repeated transcription');
      }
      final delta = text.isEmpty ? chunk : ' $chunk';
      final next = '$text$delta';
      deliveryAttempted = true;
      await deliver(delta, next);
      timing('delivered');
      text = next;
    } catch (error) {
      final message =
          'Chunk #$chunkId failed: ${error.runtimeType} at ${clock.elapsedMilliseconds}ms';
      onAudit?.call(message);
      if (kDebugMode) debugPrint(message);
      _fail();
    } finally {
      try {
        await dir?.delete(recursive: true);
      } catch (_) {}
    }
  }

  void _fail() {
    if (failed) return;
    failed = true;
    if (_active) onStatus?.call('Live unavailable; finish to recover');
  }

  Future<void> finish() async {
    if (_active && !failed) _emit();
    await _queue;
    _active = false;
  }

  void stop() => _active = false;
}

String _normalize(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[.,!?;:।]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _repeatsPhrase(String text) {
  final words = text.split(' ');
  for (var size = 2; size <= 12 && size * 3 <= words.length; size++) {
    for (var start = 0; start + size * 3 <= words.length; start++) {
      final phrase = words.sublist(start, start + size).join(' ');
      if (phrase == words.sublist(start + size, start + size * 2).join(' ') &&
          phrase ==
              words.sublist(start + size * 2, start + size * 3).join(' ')) {
        return true;
      }
    }
  }
  return false;
}
