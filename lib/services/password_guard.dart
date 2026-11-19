import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win;

enum PasswordFieldStatus { password, other, unknown }

// One in-flight query prevents unbounded isolates when an accessibility provider hangs.
class PasswordGuard {
  PasswordGuard({
    int Function()? foreground,
    Future<PasswordFieldStatus> Function(int)? query,
    this.timeout = const Duration(seconds: 2),
  }) : _foreground = foreground ?? _currentForeground,
       _query = query ?? _queryPassword;

  final int Function() _foreground;
  final Future<PasswordFieldStatus> Function(int) _query;
  final Duration timeout;
  Future<PasswordFieldStatus>? _pending;

  Future<PasswordFieldStatus> check() async {
    final foreground = _foreground();
    if (foreground == 0 || _pending != null) {
      return PasswordFieldStatus.unknown;
    }
    final work = _query(foreground)
        .catchError((Object _) => PasswordFieldStatus.unknown);
    _pending = work;
    unawaited(work.whenComplete(() => _pending = null));
    try {
      final result = await work.timeout(timeout);
      if (_foreground() != foreground) {
        return PasswordFieldStatus.unknown;
      }
      return result;
    } catch (_) {
      return PasswordFieldStatus.unknown;
    }
  }
}

int _currentForeground() => win.GetForegroundWindow().address;

Future<PasswordFieldStatus> _queryPassword(int target) =>
    Isolate.run(() => _checkPassword(target));

PasswordFieldStatus _checkPassword(int foreground) {
  final user32 = DynamicLibrary.open('user32.dll');
  final thread = user32
      .lookupFunction<
        Uint32 Function(IntPtr, Pointer<Uint32>),
        int Function(int, Pointer<Uint32>)
      >('GetWindowThreadProcessId')(foreground, nullptr);
  if (thread == 0) return PasswordFieldStatus.unknown;
  final info = calloc<win.GUITHREADINFO>();
  try {
    info.ref.cbSize = sizeOf<win.GUITHREADINFO>();
    if (win.GetGUIThreadInfo(thread, info).value) {
      final focus = info.ref.hwndFocus;
      if (!focus.isNull) {
        final name = calloc<Uint16>(256);
        try {
          final length = user32
              .lookupFunction<
                Int32 Function(IntPtr, Pointer<Uint16>, Int32),
                int Function(int, Pointer<Uint16>, int)
              >('GetClassNameW')(focus.address, name, 256);
          if (length > 0 &&
              String.fromCharCodes(name.asTypedList(length)).toLowerCase() ==
                  'edit') {
            if ((win.GetWindowLongPtr(focus, win.GWL_STYLE).value & 0x20) !=
                0) {
              return PasswordFieldStatus.password;
            }
          }
        } finally {
          calloc.free(name);
        }
      }
    }
  } finally {
    calloc.free(info);
  }
  try {
    final init = win.CoInitializeEx(win.COINIT_MULTITHREADED);
    if (init.isError) return PasswordFieldStatus.unknown;
    try {
      final clsid = win.GUID.fromComponents(
        0xff48dba4,
        0x60ef,
        0x4201,
        .fromList(const [0xaa, 0x87, 0x54, 0x10, 0x3e, 0xef, 0x59, 0x4e]),
      );
      final automation = win.createInstance<win.IUIAutomation>(clsid);
      try {
        final element = automation.getFocusedElement();
        if (element == null) return PasswordFieldStatus.unknown;
        try {
          return element.currentIsPassword
              ? PasswordFieldStatus.password
              : PasswordFieldStatus.other;
        } finally {
          element.release();
        }
      } finally {
        automation.release();
      }
    } finally {
      win.CoUninitialize();
    }
  } catch (_) {
    return PasswordFieldStatus.unknown;
  }
}
