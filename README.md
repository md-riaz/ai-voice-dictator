# AI Voice Dictator

Windows 10/11 Flutter desktop dictation using a personal Gemini API key and Velora. Audio is sent to Google's Gemini API for processing. Transcripts are stored locally in SQLite; the API key is stored with Windows secure storage.

## Build

Install Flutter 3.47 or newer, Visual Studio with the Desktop development with C++ workload, and the Windows SDK. Run:

```powershell
flutter pub get
flutter test
flutter analyze
dart run custom_lint
flutter build windows
```

The application executable and required runtime files are in `build/windows/x64/runner/Release/`. Distribute the entire directory.

## Use

On first launch, open Setup, save a Gemini API key, and select and test a microphone. Home includes a playground: click its text box before dictating. Hold Ctrl+Win to dictate, or Ctrl+Win+Alt to translate, and release to finish. Press Ctrl+Win+Space to start hands-free and press it again to finish. Esc cancels recording. A separate non-activating overlay shows progress while the main window stays open. Use the close button or tray menu to keep the app in the system tray, reopen it, pause/resume, or exit.

Gemini can make mistakes. Review inserted text, especially numbers and technical terms. Transcripts remain in local history; recordings are temporary and deleted after processing. If the active window changes while processing, the app refuses to paste; copy the transcript from history.
