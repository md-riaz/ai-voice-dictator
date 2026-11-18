import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import 'settings_store.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.store,
    required this.onShortcutChanged,
    this.initialError,
  });
  final String? initialError;
  final SettingsStore store;
  final Future<void> Function(String primary, String translation)
  onShortcutChanged;
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _key = TextEditingController();
  final _target = TextEditingController();
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _samples;
  StreamSubscription<Amplitude>? _amplitude;
  List<InputDevice> _devices = [];
  List<HistoryEntry> _history = [];
  String? _device;
  String _language = 'auto';
  String _shortcut = 'Ctrl+Space';
  String _translationShortcut = 'Ctrl+Alt+Space';
  String _keyStatus = 'Key missing';
  String? _error;
  bool _loading = true;
  bool _testingMic = false;
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
    _load();
  }

  Future<void> _load() async {
    try {
      final key = await widget.store.apiKey();
      List<InputDevice> devices;
      try {
        devices = await _recorder.listInputDevices();
      } catch (_) {
        devices = [];
      }
      final history = await widget.store.history();
      if (!mounted) return;
      setState(() {
        _key.text = key;
        _target.text = widget.store.targetLanguage();
        _language = widget.store.language();
        _shortcut = widget.store.shortcut();
        _translationShortcut = widget.store.translationShortcut();
        _devices = devices;
        final savedDevice = widget.store.deviceId();
        _device = devices.any((d) => d.id == savedDevice) ? savedDevice : null;
        _history = history;
        _keyStatus = key.isEmpty ? 'Key missing' : 'Not checked';
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load settings or microphone devices.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveKey() async {
    try {
      await widget.store.saveApiKey(_key.text);
      if (mounted) {
        setState(() {
          _keyStatus = _key.text.trim().isEmpty ? 'Key missing' : 'Not checked';
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the API key securely.');
      }
    }
  }

  Future<void> _testKey() async {
    final key = _key.text.trim();
    if (key.isEmpty) {
      setState(() => _keyStatus = 'Key missing');
      return;
    }
    setState(() {
      _keyStatus = 'Checking…';
      _error = null;
    });
    try {
      final response = await http
          .get(
            Uri.https('generativelanguage.googleapis.com', '/v1beta/models'),
            headers: {'x-goog-api-key': key},
          )
          .timeout(const Duration(seconds: 15));
      if (mounted) {
        setState(
          () => _keyStatus = response.statusCode == 200
              ? 'Connected'
              : 'Validation failed (HTTP ${response.statusCode})',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _keyStatus = 'Unable to validate key');
    }
  }

  Future<void> _changeShortcuts(String primary, String translation) async {
    try {
      if (primary == translation) {
        throw StateError('Choose different shortcuts.');
      }
      await widget.onShortcutChanged(primary, translation);
      await widget.store.setShortcut(primary);
      await widget.store.setTranslationShortcut(translation);
      if (mounted) {
        setState(() {
          _shortcut = primary;
          _translationShortcut = translation;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Shortcut could not be registered: $e');
      }
    }
  }

  Future<void> _toggleMic() async {
    if (_testingMic) {
      await _stopMic();
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        throw StateError('Microphone permission denied.');
      }
      final selected = _devices.where((d) => d.id == _device).firstOrNull;
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: 1,
          sampleRate: 16000,
          device: selected,
        ),
      );
      _samples = stream.listen(
        (_) {},
        onError: (_) {
          if (mounted) setState(() => _error = 'Microphone test failed.');
        },
      );
      _amplitude = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((a) {
            if (mounted) {
              setState(() => _level = ((a.current + 60) / 60).clamp(0, 1));
            }
          });
      if (mounted) {
        setState(() {
          _testingMic = true;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start microphone test.');
    }
  }

  Future<void> _stopMic() async {
    await _amplitude?.cancel();
    await _recorder.stop();
    await _samples?.cancel();
    if (mounted) {
      setState(() {
        _testingMic = false;
        _level = 0;
      });
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _target.dispose();
    unawaited(_amplitude?.cancel());
    unawaited(_samples?.cancel());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const shortcuts = [
      'Ctrl+Space',
      'Ctrl+Alt+Space',
      'Ctrl+Shift+Space',
      'Ctrl+Win+Space',
      'Ctrl+Alt+Shift+Space',
      'Ctrl+Alt+Win+Space',
      'Ctrl+Shift+Win+Space',
      'Ctrl+Alt+Shift+Win+Space',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('AI Voice Dictator settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Text(
                  'Gemini API key',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextField(
                  controller: _key,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'API key'),
                ),
                Row(
                  children: [
                    FilledButton(
                      onPressed: _saveKey,
                      child: const Text('Save key'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _testKey,
                      child: const Text('Test connection'),
                    ),
                    const SizedBox(width: 12),
                    Flexible(child: Text(_keyStatus)),
                  ],
                ),
                const SizedBox(height: 20),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Dictation shortcut',
                  ),
                  child: DropdownButton<String>(
                    value: _shortcut,
                    isExpanded: true,
                    items: shortcuts
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (s) {
                      if (s != null) _changeShortcuts(s, _translationShortcut);
                    },
                  ),
                ),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Translation shortcut',
                  ),
                  child: DropdownButton<String>(
                    value: _translationShortcut,
                    isExpanded: true,
                    items: shortcuts
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (s) {
                      if (s != null) _changeShortcuts(_shortcut, s);
                    },
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _language,
                  decoration: const InputDecoration(labelText: 'Language mode'),
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto detect')),
                    DropdownMenuItem(
                      value: 'codeSwitching',
                      child: Text('Code switching'),
                    ),
                    DropdownMenuItem(
                      value: 'translate',
                      child: Text('Translate'),
                    ),
                  ],
                  onChanged: (s) async {
                    if (s != null) {
                      await widget.store.setLanguage(s);
                      if (mounted) setState(() => _language = s);
                    }
                  },
                ),
                TextField(
                  controller: _target,
                  decoration: const InputDecoration(
                    labelText: 'Translation target language',
                  ),
                  onSubmitted: (s) async {
                    if (s.trim().isNotEmpty) {
                      await widget.store.setTargetLanguage(s.trim());
                    }
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () async {
                      final target = _target.text.trim();
                      if (target.isNotEmpty) {
                        await widget.store.setTargetLanguage(target);
                      }
                    },
                    child: const Text('Save target language'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _device,
                  decoration: const InputDecoration(labelText: 'Microphone'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('System default'),
                    ),
                    ..._devices.map(
                      (d) =>
                          DropdownMenuItem(value: d.id, child: Text(d.label)),
                    ),
                  ],
                  onChanged: _testingMic
                      ? null
                      : (s) async {
                          await widget.store.setDeviceId(s);
                          if (mounted) setState(() => _device = s);
                        },
                ),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _toggleMic,
                      child: Text(
                        _testingMic
                            ? 'Stop microphone test'
                            : 'Test microphone',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Semantics(
                        label: 'Microphone level',
                        value: '${(_level * 100).round()} percent',
                        child: LinearProgressIndicator(value: _level),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Recent dictations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_history.isEmpty) const Text('No dictations yet.'),
                for (final entry in _history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      entry.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${entry.createdAt.toLocal()} · ${entry.duration.inSeconds}s · ${entry.wordCount} words',
                    ),
                    trailing: IconButton(
                      tooltip: 'Copy',
                      icon: const Icon(Icons.copy),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: entry.text)),
                    ),
                  ),
              ],
            ),
    );
  }
}
