// The legacy bridge retains the established desktop plugin interfaces.
// ignore_for_file: deprecated_member_use
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/legacy.dart';

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

class DesktopService with TrayListener, WindowListener {
  DesktopService({
    required this.onHotkey,
    required this.onTranslate,
    required this.onSettings,
    required this.onSettingsClosed,
    required this.onPause,
    required this.onExit,
  });
  final VoidCallback onHotkey;
  final VoidCallback onTranslate;
  final VoidCallback onSettings;
  final VoidCallback onSettingsClosed;
  final VoidCallback onPause;
  final VoidCallback onExit;
  final _user32 = DynamicLibrary.open('user32.dll');
  final List<HotKey> _shortcuts = [];
  String? _primary;
  String? _translation;
  bool _settingsVisible = false;

  Future<void> initialize() async {
    if (!Platform.isWindows) throw UnsupportedError('Windows is required.');
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
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
  }

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

  Future<void> paste(String text, int target) async {
    if (text.isEmpty) throw StateError('No text to paste.');
    if (target == 0 || captureTarget() != target) {
      throw StateError(
        'The target window changed. Copy the transcript from history.',
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

  Future<void> showHud() async {
    if (_settingsVisible) return;
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setSize(const Size(340, 76));
    await windowManager.setAlignment(Alignment.bottomCenter);
    await windowManager.show(inactive: true);
  }

  Future<void> hideHud() async {
    if (!_settingsVisible) await windowManager.hide();
  }

  Future<void> showSettings() async {
    _settingsVisible = true;
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setBackgroundColor(Colors.white);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setSize(const Size(800, 600));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    _settingsVisible = false;
    onSettingsClosed();
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() => onSettings();
  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();
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
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
  }
}
