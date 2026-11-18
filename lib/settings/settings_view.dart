import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:velora_ui/velora_ui.dart';
import 'package:velora/velora.dart' as vx;

import '../dictation_controller.dart';
import '../ui/floating_hud.dart';
import 'settings_controller.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.controller,
    this.onClose,
    this.dictation,
  });
  final SettingsController controller;
  final VoidCallback? onClose;
  final DictationController? dictation;
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _playground = TextEditingController();
  int _page = 0;
  bool _setupPageChosen = false;
  bool _wasSetupRequired = false;
  SettingsController get controller => widget.controller;
  Future<void> _saveTarget(String value) async {
    final language = value.trim();
    if (language.isEmpty ||
        language.length > 50 ||
        !RegExp(r'^[a-zA-Z -]+$').hasMatch(language)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use letters, spaces or hyphens, up to 50 characters.'),
        ),
      );
      return;
    }
    try {
      await controller.setTarget(language);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Target language saved.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save target language.')),
        );
      }
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {
        if (!controller.pageLoading && !_setupPageChosen) {
          _page = controller.needsSetup ? 1 : 0;
          _wasSetupRequired = controller.needsSetup;
          _setupPageChosen = true;
        } else if (_wasSetupRequired && !controller.needsSetup) {
          _page = 0;
          _wasSetupRequired = false;
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    widget.dictation?.insertPlayground = (text) {
      if (!mounted || widget.dictation?.playgroundFocused != true) return false;
      final value = _playground.value;
      final selection = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      final next = value.text.replaceRange(
        selection.start,
        selection.end,
        text,
      );
      _playground.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(
          offset: selection.start + text.length,
        ),
      );
      return true;
    };
    controller.initialize();
  }

  @override
  void dispose() {
    if (widget.dictation != null) {
      widget.dictation!.playgroundFocused = false;
      widget.dictation!.insertPlayground = null;
    }
    _playground.dispose();
    controller.removeListener(_refresh);
    controller.onClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final decoration = InputDecorationTheme.of(context);
    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: controller.pageLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Row(
                children: [
                  VeloraNavRail(
                    destinations: const [
                      VeloraNavDestination(
                        icon: Icons.mic_none_rounded,
                        label: 'Home',
                      ),
                      VeloraNavDestination(
                        icon: Icons.tune_rounded,
                        label: 'Setup',
                      ),
                      VeloraNavDestination(
                        icon: Icons.history_rounded,
                        label: 'History',
                      ),
                    ],
                    selectedIndex: _page,
                    onDestinationSelected: (value) {
                      if (controller.needsSetup && value != 1) return;
                      if (value == 2) controller.refreshHistory();
                      FocusScope.of(context).unfocus();
                      setState(() => _page = value);
                    },
                  ),
                  Expanded(
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
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.asset(
                                    'assets/app_icon.png',
                                    width: 52,
                                    height: 52,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'AI Voice Dictator',
                                        style: theme.textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        ['Home', 'Setup', 'History'][_page],
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
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
                            if (_page == 1)
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
                                    if (controller.needsSetup) ...[
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Save and validate your Gemini API key to continue.',
                                      ),
                                    ],
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
                                        prefixIcon: const Icon(
                                          Icons.vpn_key_outlined,
                                        ),
                                        border: const OutlineInputBorder(),
                                      ).applyDefaults(decoration),
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 10,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
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
                                        if (!controller.needsSetup)
                                          VeloraButton(
                                            label: 'Continue to Home',
                                            variant: VeloraButtonVariant.ghost,
                                            onPressed: () =>
                                                setState(() => _page = 0),
                                          ),
                                        Semantics(
                                          liveRegion: true,
                                          child: VeloraBadge(
                                            label: controller.keyStatus,
                                            status:
                                                controller.keyStatus ==
                                                    'Connected'
                                                ? VeloraStatus.success
                                                : VeloraStatus.info,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Audio is sent to Google Gemini for transcription. Transcripts are saved on this device.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_page == 1) const SizedBox(height: 16),
                            if (_page == 0)
                              VeloraCard(
                                elevated: false,
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Try dictation',
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Click in the box, hold Ctrl + Win, wait for Listening, speak, then release.',
                                    ),
                                    const SizedBox(height: 8),
                                    Focus(
                                      onFocusChange: (focused) {
                                        if (widget.dictation != null) {
                                          widget.dictation!.playgroundFocused =
                                              focused;
                                        }
                                      },
                                      child: TextField(
                                        controller: _playground,
                                        maxLines: 3,
                                        decoration: const InputDecoration(
                                          labelText: 'Dictation playground',
                                          hintText: 'Your words appear here',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                    if (widget.dictation != null)
                                      vx.Obx(() {
                                        final dictation = widget.dictation!;
                                        final status = switch (dictation
                                            .hud
                                            .value) {
                                          HudState.preparing =>
                                            'Preparing microphone… Please wait',
                                          HudState.listening => 'Listening…',
                                          HudState.writing => 'Writing…',
                                          HudState.success => 'Inserted',
                                          HudState.error =>
                                            dictation.message.value,
                                        };
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
                                          child: Text(
                                            dictation.recording.value ||
                                                    dictation.hud.value ==
                                                        HudState.preparing ||
                                                    dictation.hud.value ==
                                                        HudState.writing ||
                                                    dictation.hud.value ==
                                                        HudState.error ||
                                                    dictation.hud.value ==
                                                        HudState.success
                                                ? status
                                                : 'Ready',
                                          ),
                                        );
                                      }),
                                  ],
                                ),
                              ),
                            if (_page == 0) const SizedBox(height: 16),
                            if (_page == 0)
                              VeloraCard(
                                elevated: false,
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _heading(
                                      context,
                                      Icons.keyboard_rounded,
                                      'Keyboard shortcuts',
                                      'Dictate wherever you are working.',
                                    ),
                                    const SizedBox(height: 20),
                                    const Text(
                                      'Ctrl + Win  ·  Hold to dictate; release to finish',
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Ctrl + Win + Alt  ·  Hold to translate; release to finish',
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Ctrl + Win + Space  ·  Press to start or finish hands-free',
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('Esc  ·  Cancel recording'),
                                  ],
                                ),
                              ),
                            if (_page == 0) const SizedBox(height: 16),
                            if (_page == 0)
                              VeloraCard(
                                elevated: false,
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _heading(
                                      context,
                                      Icons.translate_rounded,
                                      'Language',
                                      'Choose how your speech is transcribed.',
                                    ),
                                    const SizedBox(height: 20),
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
                                      onSubmitted: _saveTarget,
                                    ),
                                    const SizedBox(height: 10),
                                    VeloraButton(
                                      label: 'Save target language',
                                      icon: Icons.check_rounded,
                                      variant: VeloraButtonVariant.secondary,
                                      onPressed: () =>
                                          _saveTarget(controller.target.text),
                                    ),
                                  ],
                                ),
                              ),
                            if (_page == 0) const SizedBox(height: 16),
                            if (_page == 1)
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
                                        prefixIcon: Icon(
                                          Icons.mic_none_rounded,
                                        ),
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
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
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
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            if (_page == 1) const SizedBox(height: 16),
                            if (_page == 2)
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
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
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
                ],
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
}
