import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:record/record.dart';

class SettingsService {
  SettingsService({AudioRecorder? recorder, http.Client? client})
    : _recorder = recorder ?? AudioRecorder(),
      _client = client ?? http.Client();
  final AudioRecorder _recorder;
  final http.Client _client;
  Future<List<InputDevice>> listDevices() => _recorder.listInputDevices();
  Future<bool> hasPermission() => _recorder.hasPermission();
  Future<Stream<Uint8List>> startMic(InputDevice? device) =>
      _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: 1,
          sampleRate: 16000,
          device: device,
        ),
      );
  Stream<Amplitude> levels() =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));
  Future<String?> stopMic() => _recorder.stop();
  Future<int> validateKey(String key) async =>
      (await _client
              .get(
                Uri.https(
                  'generativelanguage.googleapis.com',
                  '/v1beta/models',
                ),
                headers: {'x-goog-api-key': key},
              )
              .timeout(const Duration(seconds: 15)))
          .statusCode;
  Future<void> dispose() async {
    _client.close();
    await _recorder.dispose();
  }
}
