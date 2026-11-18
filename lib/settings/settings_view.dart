import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings_controller.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.controller});
  final SettingsController controller;
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  SettingsController get controller => widget.controller;
  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    controller.initialize();
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    controller.onClose();
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
      body: controller.pageLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (controller.pageError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      controller.pageError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const Text(
                  'Audio is sent to Google Gemini for transcription. Transcripts are saved on this device.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Gemini API key',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextField(
                  controller: controller.key,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: controller.keyChanged,
                  decoration: const InputDecoration(labelText: 'API key'),
                ),
                Row(
                  children: [
                    FilledButton(
                      onPressed: controller.saveKey,
                      child: const Text('Save key'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: controller.testKey,
                      child: const Text('Test connection'),
                    ),
                    const SizedBox(width: 12),
                    Flexible(child: Text(controller.keyStatus)),
                  ],
                ),
                const SizedBox(height: 20),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Dictation shortcut',
                  ),
                  child: DropdownButton<String>(
                    value: controller.shortcut,
                    isExpanded: true,
                    items: shortcuts
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (s) {
                      if (s != null) {
                        controller.changeShortcuts(
                          s,
                          controller.translationShortcut,
                        );
                      }
                    },
                  ),
                ),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Translation shortcut',
                  ),
                  child: DropdownButton<String>(
                    value: controller.translationShortcut,
                    isExpanded: true,
                    items: shortcuts
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (s) {
                      if (s != null) {
                        controller.changeShortcuts(controller.shortcut, s);
                      }
                    },
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: controller.language,
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
                      await controller.setLanguage(s);
                    }
                  },
                ),
                TextField(
                  controller: controller.target,
                  decoration: const InputDecoration(
                    labelText: 'Translation target language',
                  ),
                  onSubmitted: (s) async {
                    if (s.trim().isNotEmpty) {
                      await controller.setTarget(s);
                    }
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () async {
                      final target = controller.target.text.trim();
                      if (target.isNotEmpty) {
                        await controller.setTarget(target);
                      }
                    },
                    child: const Text('Save target language'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: controller.device,
                  decoration: const InputDecoration(labelText: 'Microphone'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('System default'),
                    ),
                    ...controller.devices.map(
                      (d) =>
                          DropdownMenuItem(value: d.id, child: Text(d.label)),
                    ),
                  ],
                  onChanged: controller.testingMic
                      ? null
                      : (s) async {
                          await controller.setDevice(s);
                        },
                ),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: controller.toggleMic,
                      child: Text(
                        controller.testingMic
                            ? 'Stop microphone test'
                            : 'Test microphone',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Semantics(
                        label: 'Microphone level',
                        value: '${(controller.level * 100).round()} percent',
                        child: LinearProgressIndicator(value: controller.level),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Recent dictations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (controller.history.isEmpty)
                  const Text('No dictations yet.'),
                for (final entry in controller.history)
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
