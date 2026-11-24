# AI Voice Dictator

Windows 10/11 Flutter desktop dictation using a personal Gemini API key and Velora. Audio is sent to Google's Gemini API for processing. Transcripts are stored locally in SQLite; the API key is stored with Windows secure storage.

[Explore the landing page](https://md-riaz.github.io/ai-voice-dictator/)

## Preview

The workspace includes a playground for dictation and shortcut settings.

![Workspace with the dictation playground and shortcut settings.](docs/images/workspace.png)

The statistics screen shows dictation activity and audio duration coverage.

![Dictation statistics with activity and productivity insights.](docs/images/stats.png)

Setup manages the Gemini connection, model, and microphone.

![Setup screen showing the Gemini connection and model settings.](docs/images/setup.png)

You can also dictate in other applications with the global shortcuts while a small floating overlay shows recording and processing progress. The completed transcript is copied to the clipboard and saved in local history.

### Floating HUD in action

**Listening:** The HUD shows the recording time and microphone activity.

![Floating HUD listening while recording audio.](docs/images/hud-listening.png)

**Processing:** The spinner shows that speech is being converted to text.

![Floating HUD processing the recording.](docs/images/hud-processing.png)

**Done:** The HUD confirms that processing has finished.

![Floating HUD showing the completed state.](docs/images/hud-complete.png)

## Download

Get the Windows x64 setup executable from [Releases](https://github.com/md-riaz/ai-voice-dictator/releases).

## Build

On Windows, install Flutter 3.47.9 (the version used by the release workflow), Visual Studio with the **Desktop development with C++** workload, and the Windows SDK. From the repository root, run:

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
dart run custom_lint
flutter run -d windows --no-pub
```

To make a release build, run `flutter build windows --release`. The application executable and required runtime files are in `build/windows/x64/runner/Release/`. Distribute the entire directory. To build the installer, use the release workflow described below.

Automated tests use test doubles for Gemini and do not need an API key. A live dictation test needs a Gemini API key configured in the app, a microphone, network access, and permission for desktop apps to use the microphone. Avoid sharing keys, private transcripts, or recordings in logs, issues, or screenshots.

Debug builds keep a copy of stopped recordings, including cancelled recordings, before audio normalization in the `ai_voice_dictator_debug_audio` folder inside the system temporary directory (`%TEMP%` on Windows). These files can contain private speech; delete them when they are no longer needed. Release builds do not create these debug copies.

The app's Dart entry point is `lib/main.dart`; `lib/dictation_controller.dart` coordinates dictation, `lib/services/` contains audio, Gemini, and desktop integrations, and `lib/settings/` contains the setup and playground UI. The Windows shortcut hook and overlay live in `windows/runner/flutter_window.cpp`. See [AGENTS.md](AGENTS.md) for implementation and verification guidance.

To publish a new Windows release, update `version` in `pubspec.yaml`, push the change, and run **Windows release** from the repository's Actions tab. The workflow uses the version before the `+` build number as the Git tag and creates an installer; existing tags are rejected.

## Use

On first launch, open Setup, save a Gemini API key, and select and test a microphone. Home includes a playground: click its text box before dictating. Hold Ctrl+Win to dictate, or Ctrl+Win+Alt to translate, and release to finish. Press Ctrl+Win+Space to start hands-free and press it again to finish. Esc cancels recording. A separate non-activating overlay shows progress while the main window stays open. Use the close button or tray menu to keep the app in the system tray, reopen it, pause/resume, or exit.

Audio processing automatically shortens detected low-energy pauses over 1.5 seconds while retaining 400 ms after and 250 ms before speech. Low-contrast audio is left unchanged. Energy detection cannot reliably distinguish quiet speech from noise and may remove quiet speech. Processing happens locally; the resulting audio is sent to Gemini through the existing transcription flow.

Setup offers experimental live dictation streaming. It sends short audio chunks to Gemini while you speak and types each completed chunk. Translation always processes the complete recording after you stop. Chunking can affect punctuation and formatting, and the extra requests use more API quota. In other applications use the hands-free shortcut (Ctrl+Win+Space) so modifier keys are released while typing. If a chunk fails or appears repeatedly generated, the full recording is transcribed; if typing has already begun, the recovery transcript is copied to the clipboard instead of being typed a second time. Repeated speech can also trigger recovery. Audio already sent to Gemini cannot be recalled when cancelling.

### Recording and request limits

Audio is sent inline to Gemini. Each recording is limited to **12 MiB before encoding**—approximately **6.5 minutes** at 16 kHz, mono, 16-bit PCM. Actual duration depends on the recorded sample rate and channel count. The limit is checked after recording stops; oversized recordings are rejected and their temporary audio is deleted, so keep longer dictations in shorter sections. Gemini's **20 MB total request limit** also includes the encoded audio and prompt; a very long prompt can reduce the usable audio length.

Connecting to Gemini has a 25-second timeout. The initial response and non-streaming requests use a duration-based timeout of 30–300 seconds; a streaming response times out after 20 seconds without data. Retries and fallback models can make the total wait longer.

History shows the time from stopping the recording until the transcript is ready, including local preparation and any live chunk wait. For a complete-recording request it also shows the time before that request and the request time, including request preparation, upload, network, response, and retries. It is not a measurement of Gemini's server processing alone. These timings exclude clipboard, history storage, and paste. Live chunk processing overlaps recording, so it has no single full-request duration. Older entries do not have these timings.

Gemini can make mistakes. Review inserted text, especially numbers and technical terms. Transcripts remain in local history; recordings are temporary and deleted after processing. The transcript is also copied to the clipboard, including when the active window changes before insertion.
