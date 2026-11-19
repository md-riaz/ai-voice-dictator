# Working on AI Voice Dictator

This is a Windows Flutter desktop app. Run commands from the repository root; setup and release instructions are in [README.md](README.md). The release workflow uses Flutter 3.47.9.

- `lib/dictation_controller.dart` handles shortcut and dictation state. Audio capture, Gemini requests, desktop integration, and transcript delivery are under `lib/services/`.
- The setup, playground, and settings are under `lib/settings/`. The overlay has both Flutter (`lib/ui/floating_hud.dart`) and native Windows (`windows/runner/flutter_window.cpp`) parts. Keep user-facing status and behavior consistent across them.
- Windows global shortcuts, the native overlay, and method channels depend on `windows/runner/flutter_window.cpp`; check the matching Dart callers and tests when changing them.
- Run `flutter analyze --no-pub` and relevant `flutter test --no-pub` tests after `flutter pub get`. Build Windows when changing native code. Tests use fakes; live microphone, tray, system shortcut, and Gemini behavior need a Windows session and separate verification.
- API keys, private transcripts, audio, and research material do not belong in the repository, output, screenshots, or public issue reports. Do not read or disclose locally stored credentials for routine tests.
- Velora packages are pinned to the same Git revision in `pubspec.yaml`; update `pubspec.lock` with `flutter pub get` when changing pins.
