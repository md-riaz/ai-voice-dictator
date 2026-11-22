import 'package:ai_voice_dictator/services/desktop_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:velora_desktop/velora_desktop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('rejects collapsed and minimized bounds but keeps valid bounds', () {
    expect(
      isUsableWindowBounds(
        const WindowBounds(x: 20, y: 30, width: 900, height: 700),
      ),
      isTrue,
    );
    expect(
      isUsableWindowBounds(
        const WindowBounds(x: 20, y: 30, width: 180, height: 39),
      ),
      isFalse,
    );
    expect(
      isUsableWindowBounds(
        const WindowBounds(x: -32000, y: -32000, width: 900, height: 700),
      ),
      isFalse,
    );
  });
  test('only left and double tray clicks activate the window', () {
    expect(
      isTrayActivation(const nativeapi.TrayIconClickedEvent(trayIconId: 1)),
      isTrue,
    );
    expect(
      isTrayActivation(
        const nativeapi.TrayIconDoubleClickedEvent(trayIconId: 1),
      ),
      isTrue,
    );
    expect(
      isTrayActivation(
        const nativeapi.TrayIconRightClickedEvent(trayIconId: 1),
      ),
      isFalse,
    );
  });
  test('overlay updates, shows and hides through the native channel', () async {
    const channel = MethodChannel('ai_voice_dictator/keys');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final desktop = DesktopService(
      onHotkey: () {},
      onTranslate: () {},
      onSettings: () {},
      onSettingsClosed: () {},
      onPause: () => false,
      onSuspend: () {},
      onResume: () {},
      onExit: () {},
    );
    await desktop.updateHud('writing', '', 3);
    await desktop.updateHudLevel(0.7);
    await desktop.showHud();
    await desktop.hideHud();
    expect(calls.map((call) => call.method), [
      'updateHud',
      'updateHudLevel',
      'showHud',
      'hideHud',
    ]);
    expect(calls.first.arguments['state'], 'writing');
    expect(calls[1].arguments['level'], 0.7);
  });
}
