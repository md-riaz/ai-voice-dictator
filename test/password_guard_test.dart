import 'dart:async';

import 'package:ai_voice_dictator/services/password_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a changed foreground rejects an otherwise safe result', () async {
    var foreground = 1;
    final result = Completer<PasswordFieldStatus>();
    final guard = PasswordGuard(
      foreground: () => foreground,
      query: (_) => result.future,
    );
    final check = guard.check();
    foreground = 2;
    result.complete(PasswordFieldStatus.other);
    expect(await check, PasswordFieldStatus.unknown);
  });

  test('a timed-out query does not spawn repeated background workers', () async {
    var calls = 0;
    final result = Completer<PasswordFieldStatus>();
    final guard = PasswordGuard(
      foreground: () => 1,
      timeout: const Duration(milliseconds: 10),
      query: (_) {
        calls++;
        return result.future;
      },
    );
    expect(await guard.check(), PasswordFieldStatus.unknown);
    expect(await guard.check(), PasswordFieldStatus.unknown);
    expect(calls, 1);
    result.complete(PasswordFieldStatus.other);
    await result.future;
    await Future<void>.delayed(Duration.zero);
    expect(await guard.check(), PasswordFieldStatus.other);
    expect(calls, 2);
  });
}
