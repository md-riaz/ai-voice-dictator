import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:velora_ui/velora_ui.dart';

import 'settings_controller.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.controller, this.onClose});
  final SettingsController controller;
  final VoidCallback? onClose;
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
    final decoration = InputDecorationTheme.of(context);
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: controller.pageLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 28,
                    ),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              Icons.graphic_eq_rounded,
                              color: colors.onPrimaryContainer,
                              size: 27,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI Voice Dictator',
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Settings',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.onClose != null)
                            IconButton(
                              onPressed: widget.onClose,
                              tooltip: 'Close to system tray',
                              icon: const Icon(Icons.close_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (controller.pageError != null) ...[
                        VeloraAlert(
                          message: controller.pageError!,
                          status: VeloraStatus.error,
                        ),
                        const SizedBox(height: 16),
                      ],
                      VeloraCard(
                        elevated: false,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _heading(
                              context,
                              Icons.key_rounded,
                              'Gemini connection',
                              'Connect your API key to start dictating.',
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: controller.key,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              onChanged: controller.keyChanged,
                              decoration: InputDecoration(
                                labelText: 'Gemini API key',
                                hintText: 'Enter your API key',
                                prefixIcon: const Icon(Icons.vpn_key_outlined),
                                border: const OutlineInputBorder(),
                              ).applyDefaults(decoration),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                VeloraButton(
                                  label: 'Save key',
                                  onPressed: controller.saveKey,
                                ),
                                VeloraButton(
                                  label: 'Test connection',
                                  variant: VeloraButtonVariant.outline,
                                  onPressed: controller.testKey,
                                ),
                                Semantics(
                                  liveRegion: true,
                                  child: VeloraBadge(
                                    label: controller.keyStatus,
                                    status: controller.keyStatus == 'Connected'
                                        ? VeloraStatus.success
                                        : VeloraStatus.info,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Audio is sent to Google Gemini for transcription. Transcripts are saved on this device.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      VeloraCard(
                        elevated: false,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _heading(
                              context,
                              Icons.keyboard_rounded,
                              'Shortcuts & language',
                              'Choose how you start dictation and translation.',
                            ),
                            const SizedBox(height: 20),
                            _shortcut(
                              'Dictation shortcut',
                              controller.shortcut,
                              shortcuts,
                              (value) => controller.changeShortcuts(
                                value,
                                controller.translationShortcut,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _shortcut(
                              'Translation shortcut',
                              controller.translationShortcut,
                              shortcuts,
                              (value) => controller.changeShortcuts(
                                controller.shortcut,
                                value,
                              ),
                            ),
                            const SizedBox(height: 14),
                            VeloraSelect<String>(
                              label: 'Language mode',
                              value: controller.language,
                              options: const [
                                VeloraSelectOption(
                                  value: 'auto',
                                  label: 'Auto detect',
                                ),
                                VeloraSelectOption(
                                  value: 'codeSwitching',
                                  label: 'Code switching',
                                ),
                                VeloraSelectOption(
                                  value: 'translate',
                                  label: 'Translate',
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  controller.setLanguage(value);
                                }
                              },
                            ),
                            const SizedBox(height: 14),
                            VeloraTextField(
                              label: 'Translation target language',
                              controller: controller.target,
                              onSubmitted: controller.setTarget,
                            ),
                            const SizedBox(height: 10),
                            VeloraButton(
                              label: 'Save target language',
                              variant: VeloraButtonVariant.ghost,
                              onPressed: () =>
                                  controller.setTarget(controller.target.text),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      VeloraCard(
                        elevated: false,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _heading(
                              context,
                              Icons.mic_none_rounded,
                              'Microphone',
                              'Select an input and check your audio level.',
                            ),
                            const SizedBox(height: 20),
                            DropdownButtonFormField<String>(
                              initialValue: controller.device,
                              decoration: const InputDecoration(
                                labelText: 'Microphone',
                                prefixIcon: Icon(Icons.mic_none_rounded),
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('System default'),
                                ),
                                ...controller.devices.map(
                                  (d) => DropdownMenuItem(
                                    value: d.id,
                                    child: Text(
                                      d.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: controller.testingMic
                                  ? null
                                  : controller.setDevice,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 16,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                VeloraButton(
                                  label: controller.testingMic
                                      ? 'Stop microphone test'
                                      : 'Test microphone',
                                  variant: VeloraButtonVariant.outline,
                                  onPressed: controller.toggleMic,
                                ),
                                SizedBox(
                                  width: 180,
                                  child: Semantics(
                                    label: 'Microphone level',
                                    value:
                                        '${(controller.level * 100).round()} percent',
                                    child: LinearProgressIndicator(
                                      value: controller.level,
                                      minHeight: 6,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      VeloraCard(
                        elevated: false,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _heading(
                              context,
                              Icons.history_rounded,
                              'Recent dictations',
                              'Your latest transcripts are stored locally.',
                            ),
                            const SizedBox(height: 12),
                            if (controller.history.isEmpty)
                              Text(
                                'No dictations yet.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
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
                                  onPressed: () => Clipboard.setData(
                                    ClipboardData(text: entry.text),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _heading(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _shortcut(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        items: options
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: (s) {
          if (s != null) onChanged(s);
        },
      ),
    ),
  );
}
