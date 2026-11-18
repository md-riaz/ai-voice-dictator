// The legacy bridge retains the established desktop plugin interfaces.
// ignore_for_file: deprecated_member_use
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:async';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';
import 'package:velora_desktop/velora_desktop.dart';

class _TrayPort implements VeloraDesktopTrayPort {
  _TrayPort(this.owner);
  final DesktopService owner;
  @override
  Future<bool> setup({
    required VeloraTrayConfig config,
    required void Function() onActivate,
    required void Function() onShow,
    required void Function() onQuit,
  }) => owner._setupTray();
  @override
  Future<void> dispose() async {
    trayManager.removeListener(owner);
    await trayManager.destroy();
  }
}

final class _MouseInput extends Struct {
  @Int32()
  external int dx;
  @Int32()
  external int dy;
  @Uint32()
  external int mouseData;
  @Uint32()
  external int flags;
  @Uint32()
  external int time;
  @UintPtr()
  external int extraInfo;
}

final class _KeyboardInput extends Struct {
  @Uint16()
  external int key;
  @Uint16()
  external int scan;
  @Uint32()
  external int flags;
  @Uint32()
  external int time;
  @UintPtr()
  external int extraInfo;
}

final class _InputUnion extends Union {
  external _MouseInput mouse;
  external _KeyboardInput keyboard;
}

final class _Input extends Struct {
  @Uint32()
  external int type;
  external _InputUnion data;
}

class DesktopService with TrayListener {
  DesktopService({
    required this.onHotkey,
    required this.onTranslate,
    required this.onSettings,
    required this.onSettingsClosed,
    required this.onPause,
    required this.onExit,
    this.onKeyEvent,
  });
  final VoidCallback onHotkey;
  final VoidCallback onTranslate;
  final VoidCallback onSettings;
  final VoidCallback onSettingsClosed;
  final VoidCallback onPause;
  final VoidCallback onExit;
  final void Function(String)? onKeyEvent;
  static const _keyChannel = MethodChannel('ai_voice_dictator/keys');
  final _user32 = DynamicLibrary.open('user32.dll');
  final List<HotKey> _shortcuts = [];
  String? _primary;
  String? _translation;
  bool hotkeysAvailable = false;
  late final VeloraDesktopCoordinator _desktop;
  StreamSubscription<VeloraDesktopEvent>? _desktopEvents;

  Future<void> initialize() async {
    if (!Platform.isWindows) throw UnsupportedError('Windows is required.');
    await windowManager.ensureInitialized();
    _keyChannel.setMethodCallHandler((call) async {
      onKeyEvent?.call(call.method);
    });
    hotkeysAvailable =
        await _keyChannel.invokeMethod<bool>('available') == true;
    debugPrint(
      'Global shortcuts: ${hotkeysAvailable ? 'ready' : 'unavailable'}',
    );
    _desktop = VeloraDesktopCoordinator(
      config: const VeloraDesktopConfig(
        appId: 'com.mdriaz.aivoicedictator',
        appName: 'AI Voice Dictator',
        tray: VeloraTrayConfig(iconAsset: 'assets/tray_icon.ico'),
        closeToTray: true,
        singleInstance: false,
      ),
      window: WindowManagerAdapter(),
      tray: _TrayPort(this),
    );
    await _desktop.initialize();
    if (!_desktop.capabilities.window || !_desktop.capabilities.tray) {
      throw StateError('Desktop window or tray could not be initialized.');
    }
    _desktopEvents = _desktop.events.listen((event) {
      if (event.type == VeloraDesktopEventType.closeRequested &&
          event.data['hidden'] == true) {
        onSettingsClosed();
      }
    });
  }

  Future<bool> _setupTray() async {
    trayManager.addListener(this);
    await trayManager.setIcon('assets/tray_icon.ico');
    await trayManager.setToolTip('AI Voice Dictator');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'settings', label: 'Settings'),
          MenuItem(key: 'pause', label: 'Pause / Resume'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Exit'),
        ],
      ),
    );
    trayManager.trayIcon?.setContextMenuTrigger(
      nativeapi.ContextMenuTrigger.rightClicked,
    );
    return trayManager.trayIcon != null;
  }

  Future<void> setRecording(bool active) =>
      _keyChannel.invokeMethod<void>('setRecording', active);

  HotKey _parseShortcut(String value) {
    final parts = value.toLowerCase().split('+').map((e) => e.trim()).toSet();
    if (!parts.remove('space') || !parts.remove('ctrl')) {
      throw const FormatException('Shortcut must include Ctrl and Space.');
    }
    final modifiers = <HotKeyModifier>[HotKeyModifier.control];
    if (parts.remove('alt')) modifiers.add(HotKeyModifier.alt);
    if (parts.remove('shift')) modifiers.add(HotKeyModifier.shift);
    if (parts.remove('win')) modifiers.add(HotKeyModifier.meta);
    if (parts.isNotEmpty) throw const FormatException('Unsupported shortcut.');
    return HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: modifiers,
      scope: HotKeyScope.system,
    );
  }

  Future<void> _install(String primary, String translation) async {
    final first = _parseShortcut(primary);
    final second = _parseShortcut(translation);
    if (first.modifiers!.toSet().containsAll(second.modifiers!) &&
        first.modifiers!.length == second.modifiers!.length) {
      throw const FormatException(
        'Dictation and translation shortcuts must differ.',
      );
    }
    await hotKeyManager.register(first, keyDownHandler: (_) => onHotkey());
    _shortcuts.add(first);
    await hotKeyManager.register(second, keyDownHandler: (_) => onTranslate());
    _shortcuts.add(second);
  }

  Future<void> _clearShortcuts() async {
    for (final key in List<HotKey>.of(_shortcuts)) {
      await hotKeyManager.unregister(key);
      _shortcuts.remove(key);
    }
  }

  Future<void> registerShortcuts(String primary, String translation) async {
    _parseShortcut(primary);
    _parseShortcut(translation);
    final oldPrimary = _primary;
    final oldTranslation = _translation;
    await _clearShortcuts();
    try {
      await _install(primary, translation);
      _primary = primary;
      _translation = translation;
    } catch (_) {
      await _clearShortcuts();
      if (oldPrimary != null && oldTranslation != null) {
        await _install(oldPrimary, oldTranslation);
      }
      rethrow;
    }
  }

  int captureTarget() =>
      _user32.lookupFunction<IntPtr Function(), int Function()>(
        'GetForegroundWindow',
      )();

  Future<void> copyTranscript(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<void> paste(String text, int target) async {
    if (text.isEmpty) throw StateError('No text to paste.');
    final keyState = _user32
        .lookupFunction<Int16 Function(Int32), int Function(int)>(
          'GetAsyncKeyState',
        );
    bool modifiersHeld() =>
        [0x11, 0x12, 0x5b, 0x5c].any((key) => (keyState(key) & 0x8000) != 0);
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (modifiersHeld() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (modifiersHeld()) {
      throw StateError(
        'Release the shortcut keys. The transcript is on the clipboard.',
      );
    }
    if (target == 0 || captureTarget() != target) {
      throw StateError(
        'The target window changed. The transcript is on the clipboard.',
      );
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (captureTarget() != target) {
      throw StateError(
        'The target window changed. The transcript is on the clipboard.',
      );
    }
    final inputs = calloc<_Input>(4);
    try {
      for (var i = 0; i < 4; i++) {
        inputs[i].type = 1;
        inputs[i].data.keyboard.key = (i == 0 || i == 3) ? 0x11 : 0x56;
        inputs[i].data.keyboard.flags = i >= 2 ? 2 : 0;
      }
      final send = _user32
          .lookupFunction<
            Uint32 Function(Uint32, Pointer<_Input>, Int32),
            int Function(int, Pointer<_Input>, int)
          >('SendInput');
      if (send(4, inputs, sizeOf<_Input>()) != 4) {
        throw StateError(
          'Windows could not paste the transcript. It is on the clipboard.',
        );
      }
    } finally {
      calloc.free(inputs);
    }
  }

  Future<void> updateHud(String state, String message, int seconds) =>
      _keyChannel.invokeMethod<void>('updateHud', {
        'state': state,
        'message': message,
        'seconds': seconds,
      });

  Future<void> showHud() => _keyChannel.invokeMethod<void>('showHud');

  Future<void> hideHud() => _keyChannel.invokeMethod<void>('hideHud');

  Future<void> showSettings() async {
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setBackgroundColor(Colors.white);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setSize(const Size(800, 600));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  void onWindowClose() {
    onSettingsClosed();
    _desktop.hide();
  }

  @override
  void onTrayIconMouseDown() => onSettings();
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'settings':
        onSettings();
      case 'pause':
        onPause();
      case 'exit':
        onExit();
    }
  }

  Future<void> dispose() async {
    await _clearShortcuts();
    await _desktopEvents?.cancel();
    await _desktop.dispose();
  }
}
