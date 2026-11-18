import 'package:ai_voice_dictator/ui/floating_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows listening duration across minutes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FloatingHudOverlay(
          state: HudState.listening,
          durationSeconds: 65,
        ),
      ),
    );
    expect(find.text('Listening...'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
  });
  testWidgets('shows the supplied error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FloatingHudOverlay(
          state: HudState.error,
          message: 'Microphone unavailable',
        ),
      ),
    );
    expect(find.text('Microphone unavailable'), findsOneWidget);
  });
}
