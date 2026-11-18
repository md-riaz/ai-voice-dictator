import 'package:ai_voice_dictator/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:velora_ui/velora_ui.dart';

double contrast(Color a, Color b) {
  final values = [a.computeLuminance(), b.computeLuminance()]..sort();
  return (values.last + 0.05) / (values.first + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    test('$brightness semantic colors remain readable', () {
      final theme = buildVoiceTheme(brightness);
      final colors = theme.colorScheme;
      final tokens = theme.extension<VeloraTokens>()!;
      for (final pair in [
        (colors.primary, colors.onPrimary),
        (colors.secondary, colors.onSecondary),
        (colors.tertiary, colors.onTertiary),
        (colors.error, colors.onError),
        (tokens.success, tokens.onSuccess),
        (tokens.warning, tokens.onWarning),
        (tokens.info, tokens.onInfo),
        (colors.surface, colors.onSurface),
      ]) {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
    });
  }
}
