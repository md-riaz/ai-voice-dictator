import 'package:flutter/material.dart';

enum HudState { preparing, listening, writing, success, error }

class FloatingHudOverlay extends StatelessWidget {
  const FloatingHudOverlay({
    super.key,
    required this.state,
    this.message = '',
    this.durationSeconds = 0,
  });
  final HudState state;
  final String message;
  final int durationSeconds;

  @override
  Widget build(BuildContext context) {
    final (color, icon, title) = switch (state) {
      HudState.preparing => (
        Colors.amberAccent,
        Icons.mic_none,
        'Please wait before speaking…',
      ),
      HudState.listening => (Colors.redAccent, Icons.mic, 'Speak now'),
      HudState.writing => (
        Colors.cyanAccent,
        Icons.hourglass_top_rounded,
        message.isNotEmpty ? message : 'Turning speech into text…',
      ),
      HudState.success => (
        Colors.greenAccent,
        Icons.check_circle_rounded,
        'Done',
      ),
      HudState.error => (
        Colors.amberAccent,
        Icons.warning_amber_rounded,
        message.isEmpty ? 'Error occurred' : message,
      ),
    };
    final minutes = durationSeconds ~/ 60;
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return Material(
      color: const Color(0xFF171513),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: color, width: 4),
              top: const BorderSide(color: Color(0xFF4A443C)),
              right: const BorderSide(color: Color(0xFF4A443C)),
              bottom: const BorderSide(color: Color(0xFF4A443C)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 19),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFFFFBF4),
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: state == HudState.error ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (state == HudState.listening) ...[
                const SizedBox(width: 16),
                Text(
                  '$minutes:$seconds',
                  style: const TextStyle(
                    color: Color(0xFFD9CFC0),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
