import 'dart:ui';

import 'package:flutter/material.dart';

enum HudState { listening, writing, success, error }

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
      HudState.listening => (Colors.redAccent, Icons.mic, 'Listening...'),
      HudState.writing => (
        Colors.cyanAccent,
        Icons.hourglass_top_rounded,
        'Writing...',
      ),
      HudState.success => (
        Colors.greenAccent,
        Icons.check_circle_rounded,
        'Inserted!',
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
      color: Colors.transparent,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xe6181825),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: color),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: state == HudState.error ? 3 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (state == HudState.listening) ...[
                    const SizedBox(width: 10),
                    Text(
                      '$minutes:$seconds',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
