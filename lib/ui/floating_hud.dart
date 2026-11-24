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
        const Color(0xFFF59E0B),
        Icons.mic_none,
        'Please wait before speaking…',
      ),
      HudState.listening => (
        const Color(0xFF4F46E5),
        Icons.mic,
        message.isEmpty ? 'Speak now' : message,
      ),
      HudState.writing => (
        const Color(0xFF4F46E5),
        Icons.hourglass_top_rounded,
        message.isNotEmpty ? message : 'Turning speech into text…',
      ),
      HudState.success => (
        const Color(0xFF10B981),
        Icons.check_circle_rounded,
        'Done',
      ),
      HudState.error => (
        const Color(0xFFF59E0B),
        Icons.warning_amber_rounded,
        message.isEmpty ? 'Error occurred' : message,
      ),
    };
    final minutes = durationSeconds ~/ 60;
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(32),
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
                    color: Color(0xFF0F172A),
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
                    color: Color(0xFF64748B),
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
