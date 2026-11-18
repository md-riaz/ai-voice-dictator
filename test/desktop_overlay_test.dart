import 'package:ai_voice_dictator/services/desktop_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('overlay updates, shows and hides through the native channel', () async {
    const channel = MethodChannel('ai_voice_dictator/keys');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async { calls.add(call); return null; });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final desktop = DesktopService(onHotkey: () {}, onTranslate: () {}, onSettings: () {}, onSettingsClosed: () {}, onPause: () {}, onExit: () {});
    await desktop.updateHud('writing', '', 3);
    await desktop.showHud();
    await desktop.hideHud();
    expect(calls.map((call) => call.method), ['updateHud', 'showHud', 'hideHud']);
    expect(calls.first.arguments['state'], 'writing');
  });
}
