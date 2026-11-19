// ignore_for_file: deprecated_member_use
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nativeapi/nativeapi.dart' as nativeapi;
import 'package:nativeapi_flutter/nativeapi_flutter.dart' show ImageAsset;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/legacy.dart';
import 'package:velora_desktop/velora_desktop.dart';

@visibleForTesting
bool isTrayActivation(nativeapi.TrayIconEvent event) =>
    event is nativeapi.TrayIconClickedEvent ||
    event is nativeapi.TrayIconDoubleClickedEvent;

class _TrayPort implements VeloraDesktopTrayPort {
  _TrayPort(this.owner);
  final DesktopService owner;
  nativeapi.TrayIcon? _icon;
  nativeapi.Menu? _menu;
  nativeapi.ListenerId? _listener;
  final _items = <nativeapi.MenuItem>[];
  final _itemListeners = <nativeapi.ListenerId?>[];

  @override
  Future<bool> setup({
    required VeloraTrayConfig config,
    required void Function() onActivate,
    required void Function() onShow,
    required void Function() onQuit,
  }) async {
    _icon = nativeapi.TrayIcon.create();
    if (_icon == null) return false;
    try {
      await setIcon(config.iconAsset);
      await setTooltip(config.tooltip ?? 'AI Voice Dictator');
      _icon!.setContextMenuTrigger(nativeapi.ContextMenuTrigger.rightClicked);
      _listener = _icon!.addListener((event) {
        if (isTrayActivation(event)) owner.onSettings();
      });
      await updatePaused(false);
      if (!_icon!.setVisible(true)) {
        await dispose();
        return false;
      }
      return true;
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  Future<void> updatePaused(bool paused) => setMenuItems(
    showLabel: 'Settings',
    quitLabel: 'Exit',
    items: [
      VeloraTrayMenuItem(
        id: 'pause',
        label: paused ? 'Resume dictation' : 'Pause dictation',
        onTap: () {
          final paused = owner.onPause();
          unawaited(
            Future<void>(() => updatePaused(paused)).catchError((Object error) {
              debugPrint('Could not update the tray menu: $error');
            }),
          );
        },
      ),
    ],
    onShow: owner.onSettings,
    onQuit: owner.onExit,
  );

  @override
  Future<void> dispose() async {
    final icon = _icon;
    if (icon != null) {
      if (_listener != null) icon.removeListener(_listener!);
      icon.setContextMenu(null);
      icon.dispose();
    }
    _icon = null;
    _listener = null;
    _disposeMenu();
  }

  @override
  Future<void> setIcon(String assetPath) async {
    _icon?.icon = ImageAsset.fromAsset(assetPath);
  }

  @override
  Future<void> setTooltip(String? tooltip) async => _icon?.setTooltip(tooltip);

  @override
  Future<void> setMenuItems({
    required String showLabel,
    required String quitLabel,
    required List<VeloraTrayMenuItem> items,
    required void Function() onShow,
    required void Function() onQuit,
  }) async {
    final icon = _icon;
    if (icon == null) return;
    final menu = nativeapi.Menu.create();
    if (menu == null) throw StateError('Could not create tray menu.');
    final newItems = <nativeapi.MenuItem>[];
    final listeners = <nativeapi.ListenerId?>[];
    try {
      void add(
        String label,
        VoidCallback? callback, {
        bool enabled = true,
        bool? checked,
      }) {
        final item = nativeapi.MenuItem.createWithLabelAndType(
          label,
          checked == null
              ? nativeapi.MenuItemType.normal
              : nativeapi.MenuItemType.checkbox,
        );
        if (item == null) throw StateError('Could not create tray menu item.');
        newItems.add(item);
        item.isEnabled = enabled;
        if (checked != null) {
          item.state = checked
              ? nativeapi.MenuItemState.checked
              : nativeapi.MenuItemState.unchecked;
        }
        listeners.add(
          callback == null
              ? null
              : item.addListener((event) {
                  if (event is nativeapi.MenuItemClickedEvent) callback();
                }),
        );
        menu.addItem(item);
      }

      add(showLabel, owner.onSettings);
      for (final item in items) {
        add(
          item.label,
          item.onTap,
          enabled: item.enabled,
          checked: item.checked,
        );
      }
      add(quitLabel, owner.onExit);
      icon.setContextMenu(menu);
      _disposeMenu();
      _menu = menu;
      _items.addAll(newItems);
      _itemListeners.addAll(listeners);
    } catch (_) {
      for (var i = 0; i < newItems.length; i++) {
        if (i < listeners.length && listeners[i] != null) {
          newItems[i].removeListener(listeners[i]!);
        }
        newItems[i].dispose();
      }
      menu.dispose();
      rethrow;
    }
  }

  void _disposeMenu() {
    for (var i = 0; i < _items.length; i++) {
      if (_itemListeners[i] != null) {
        _items[i].removeListener(_itemListeners[i]!);
      }
    }
    _menu?.dispose();
    for (final item in _items) {
      item.dispose();
    }
    _menu = null;
    _items.clear();
    _itemListeners.clear();
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

class DesktopService {
  DesktopService({
    required this.onHotkey,
    required this.onTranslate,
    required this.onSettings,
    required this.onSettingsClosed,
    required this.onPause,
    required this.onSuspend,
    required this.onResume,
    required this.onExit,
    this.onKeyEvent,
  });
  final VoidCallback onHotkey;
  final VoidCallback onTranslate;
  final VoidCallback onSettings;
  final VoidCallback onSettingsClosed;
  final bool Function() onPause;
  final VoidCallback onSuspend;
  final VoidCallback onResume;
  final VoidCallback onExit;
  final void Function(String)? onKeyEvent;
  static const _keyChannel = MethodChannel('ai_voice_dictator/keys');
  final _user32 = DynamicLibrary.open('user32.dll');
  bool hotkeysAvailable = false;
  late final VeloraDesktopCoordinator _desktop;
  final _window = WindowManagerAdapter();
  late final SharedPreferencesStorageAdapter _storage;
  StreamSubscription<VeloraDesktopEvent>? _desktopEvents;

  Future<void> initialize({List<String> launchArguments = const []}) async {
    if (!Platform.isWindows) throw UnsupportedError('Windows is required.');
    await windowManager.ensureInitialized();
    _storage = SharedPreferencesStorageAdapter(
      await SharedPreferences.getInstance(),
    );
    _desktop = VeloraDesktopCoordinator(
      config: VeloraDesktopConfig(
        appId: 'com.mdriaz.aivoicedictator',
        appName: 'AI Voice Dictator',
        launchArguments: launchArguments,
        tray: const VeloraTrayConfig(iconAsset: 'assets/tray_icon.ico'),
        closeToTray: true,
        singleInstance: true,
      ),
      window: _window,
      tray: _TrayPort(this),
      singleInstance: WindowsSingleInstanceAdapter(),
      autoStart: NativeApiAutoStartAdapter(),
      power: PowerStateMonitorAdapter(),
      storage: _storage,
    );
    await _desktop.initialize();
    if (!_desktop.capabilities.window || !_desktop.capabilities.tray) {
      throw StateError('Desktop window or tray could not be initialized.');
    }
    _keyChannel.setMethodCallHandler((call) async {
      onKeyEvent?.call(call.method);
    });
    hotkeysAvailable =
        await _keyChannel.invokeMethod<bool>('available') == true;
    debugPrint(
      'Global shortcuts: ${hotkeysAvailable ? 'ready' : 'unavailable'}',
    );
    _desktopEvents = _desktop.events.listen((event) {
      if (event.type == VeloraDesktopEventType.closeRequested &&
          event.data['hidden'] == true) {
        unawaited(_saveBounds());
        onSettingsClosed();
      }
      if (event.type == VeloraDesktopEventType.secondaryLaunch) onSettings();
      if (event.type == VeloraDesktopEventType.suspending) onSuspend();
      if (event.type == VeloraDesktopEventType.resumed) onResume();
    });
  }

  bool get singleInstanceAvailable => _desktop.capabilities.singleInstance;
  bool get autoStartAvailable => _desktop.capabilities.autoStart;
  Future<bool> isAutoStartEnabled() => _desktop.isAutoStartEnabled();
  Future<void> setAutoStart(bool enabled) => _desktop.setAutoStart(enabled);

  Future<void> _saveBounds() async {
    try {
      final bounds = await _window.getBounds();
      if (bounds != null) {
        await _storage.set(
          VeloraDesktopCoordinator.boundsKey,
          jsonEncode(bounds.toJson()),
        );
      }
    } catch (_) {
      // Window closing must not depend on saving its bounds.
    }
  }

  Future<void> setRecording(bool active) =>
      _keyChannel.invokeMethod<void>('setRecording', active);

  Future<void> registerShortcuts(
    String primary,
    String translation,
    String handsFreeKey,
  ) async {
    if (!hotkeysAvailable) {
      throw StateError('Global shortcuts are unavailable.');
    }
    final accepted = await _keyChannel.invokeMethod<bool>(
      'configureShortcuts',
      {
        'hold': primary,
        'translation': translation,
        'handsFree': '$primary+$handsFreeKey',
      },
    );
    if (accepted != true) {
      throw StateError('Could not configure shortcuts.');
    }
  }

  int captureTarget() =>
      _user32.lookupFunction<IntPtr Function(), int Function()>(
        'GetForegroundWindow',
      )();

  bool isAppForeground() {
    final target = captureTarget();
    if (target == 0) return false;
    final processId = calloc<Uint32>();
    try {
      _user32.lookupFunction<
        Uint32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetWindowThreadProcessId')(target, processId);
      return processId.value == pid;
    } finally {
      calloc.free(processId);
    }
  }

  Future<void> copyTranscript(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<void> typeText(String text, int target) async {
    if (text.isEmpty) throw StateError('No text to type.');
    final keyState = _user32
        .lookupFunction<Int16 Function(Int32), int Function(int)>(
          'GetAsyncKeyState',
        );
    bool modifiersHeld() => [
      0x10,
      0x11,
      0x12,
      0x5b,
      0x5c,
    ].any((key) => (keyState(key) & 0x8000) != 0);
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (modifiersHeld() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (modifiersHeld()) {
      throw StateError(
        'Release the shortcut keys. The transcript is on the clipboard.',
      );
    }
    final send = _user32
        .lookupFunction<
          Uint32 Function(Uint32, Pointer<_Input>, Int32),
          int Function(int, Pointer<_Input>, int)
        >('SendInput');
    final units = text.codeUnits;
    // shortcut: SendInput cannot confirm field acceptance; use UI Automation when reliable.
    for (var offset = 0; offset < units.length;) {
      if (target == 0 || captureTarget() != target) {
        throw StateError(
          'The target window changed. Text may be partially typed; the full transcript is on the clipboard.',
        );
      }
      var count = (units.length - offset).clamp(0, 128);
      if (offset + count < units.length &&
          units[offset + count - 1] >= 0xd800 &&
          units[offset + count - 1] <= 0xdbff) {
        count--;
      }
      final inputs = calloc<_Input>(count * 2);
      try {
        for (var i = 0; i < count; i++) {
          inputs[2 * i].type = 1;
          inputs[2 * i].data.keyboard.scan = units[offset + i];
          inputs[2 * i].data.keyboard.flags = 4;
          inputs[2 * i + 1].type = 1;
          inputs[2 * i + 1].data.keyboard.scan = units[offset + i];
          inputs[2 * i + 1].data.keyboard.flags = 6;
        }
        if (send(count * 2, inputs, sizeOf<_Input>()) != count * 2) {
          throw StateError(
            'Windows could not type everything. Text may be partial; the full transcript is on the clipboard.',
          );
        }
      } finally {
        calloc.free(inputs);
      }
      offset += count;
    }
  }

  Future<void> paste(String text, int target) async {
    if (text.isEmpty) throw StateError('No text to paste.');
    final keyState = _user32
        .lookupFunction<Int16 Function(Int32), int Function(int)>(
          'GetAsyncKeyState',
        );
    bool modifiersHeld() => [
      0x10,
      0x11,
      0x12,
      0x5b,
      0x5c,
    ].any((key) => (keyState(key) & 0x8000) != 0);
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
    await _keyChannel.invokeMethod<void>('ensureWindowVisible');
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> dispose() async {
    await _saveBounds();
    await _desktopEvents?.cancel();
    await _desktop.dispose();
  }
}
