import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:velora_ui/velora_ui.dart';
import 'package:velora/velora.dart' as vx;

import '../dictation_controller.dart';
import '../services/desktop_service.dart' show normalizeWindowsLineEndings;
import '../ui/floating_hud.dart';
import 'settings_controller.dart';
import 'settings_store.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.controller, this.dictation});
  final SettingsController controller;
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

  Future<void> _openApiKeys() async {
    try {
      if (await launchUrl(
        Uri.parse('https://aistudio.google.com/api-keys'),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open Google AI Studio. Visit aistudio.google.com/api-keys in your browser.',
          ),
        ),
      );
    }
  }

  Future<void> _updatePrompt({bool reset = false}) async {
    try {
      if (reset) {
        await controller.resetSystemPrompt();
      } else {
        await controller.saveSystemPrompt();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reset ? 'Default prompt restored.' : 'Prompt saved.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the prompt.')),
        );
      }
    }
  }

  Future<void> _saveModel() async {
    try {
      await controller.saveModel();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Gemini model saved.')));
      }
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enter a model ID using lowercase letters, numbers, dots or hyphens (up to 100 characters).',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the Gemini model.')),
        );
      }
    }
  }

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
          _page = controller.needsSetup ? 3 : 0;
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
    return Scaffold(
      backgroundColor: colors.surface,
      body: controller.pageLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Row(
                children: [
                  Theme(
                    data: theme.copyWith(
                      colorScheme: colors.copyWith(
                        surface: colors.surfaceContainerLow,
                      ),
                    ),
                    child: VeloraNavRail(
                      leading: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.asset(
                            'assets/app_icon.png',
                            width: 40,
                            height: 40,
                            excludeFromSemantics: true,
                          ),
                        ),
                      ),
                      destinations: const [
                        VeloraNavDestination(
                          icon: Icons.mic_none_rounded,
                          label: 'Home',
                        ),
                        VeloraNavDestination(
                          icon: Icons.insights_rounded,
                          label: 'Stats',
                        ),
                        VeloraNavDestination(
                          icon: Icons.history_rounded,
                          label: 'History',
                        ),
                        VeloraNavDestination(
                          icon: Icons.tune_rounded,
                          label: 'Setup',
                        ),
                      ],
                      selectedIndex: _page,
                      onDestinationSelected: (value) {
                        if (controller.needsSetup && value != 3) return;
                        if (value == 1) controller.refreshStats();
                        if (value == 2) controller.refreshHistory();
                        FocusScope.of(context).unfocus();
                        setState(() => _page = value);
                      },
                    ),
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
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        [
                                          'Your workspace',
                                          'Dictation statistics',
                                          'Dictation history',
                                          'Connection & audio',
                                        ][_page],
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                          'Speak naturally, wherever you work.',
                                          'See how much time voice dictation saves you.',
                                          'Your recent dictations, saved on this device.',
                                          'Manage your connection and microphone.',
                                        ][_page],
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            if (controller.pageError != null) ...[
                              Semantics(
                                liveRegion: true,
                                child: VeloraAlert(
                                  message: controller.pageError!,
                                  status: VeloraStatus.error,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (_page == 3)
                              VeloraCard(
                                elevated: false,
                                color: colors.surfaceContainerLowest,
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
                                    const SizedBox(height: 12),
                                    Semantics(
                                      liveRegion: true,
                                      child: VeloraBadge(
                                        label: controller.keyStatus,
                                        status:
                                            controller.keyStatus == 'Connected'
                                            ? VeloraStatus.success
                                            : controller.keyStatus.startsWith(
                                                    'Validation failed',
                                                  ) ||
                                                  controller.keyStatus == 'Could not check connection'
                                            ? VeloraStatus.error
                                            : VeloraStatus.info,
                                      ),
                                    ),
                                    if (controller.needsSetup) ...[
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Save and validate your Gemini API key to continue.',
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    const Text(
                                      '1. Open Google AI Studio and sign in.\n'
                                      '2. Use an existing Google Cloud project, or create one if needed. Import an existing project if it is not listed.\n'
                                      '3. Create or select an API key, copy only the key (not the project ID), then paste and save it below.',
                                    ),
                                    TextButton.icon(
                                      onPressed: _openApiKeys,
                                      icon: const Icon(Icons.open_in_new),
                                      label: const Text(
                                        'Open Google AI Studio API keys',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Gemini API key',
                                      style: theme.textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Semantics(
                                      label: 'Gemini API key',
                                      child: TextField(
                                        controller: controller.key,
                                        obscureText: true,
                                        enableSuggestions: false,
                                        autocorrect: false,
                                        onChanged: controller.keyChanged,
                                        decoration: InputDecoration(
                                          hintText: 'Enter your API key',
                                          prefixIcon: const Icon(
                                            Icons.vpn_key_outlined,
                                          ),
                                        ),
                                      ),
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
                                          size: VeloraButtonSize.small,
                                          onPressed: controller.saveKey,
                                        ),
                                        VeloraButton(
                                          label: 'Test connection',
                                          size: VeloraButtonSize.small,
                                          variant: VeloraButtonVariant.outline,
                                          onPressed: controller.testKey,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Your key is stored securely on this device. Audio is sent to Gemini, and transcripts are saved in local history.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_page == 3) const SizedBox(height: 16),
                            if (_page == 3)
                              VeloraCard(
                                elevated: false,
                                color: colors.surfaceContainerLowest,
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _heading(
                                      context,
                                      Icons.auto_awesome_outlined,
                                      'Gemini model',
                                      'Choose a model or enter a model ID supported by your API key.',
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      'Model',
                                      style: theme.textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Semantics(
                                      label: 'Gemini model',
                                      child: DropdownButtonFormField<String>(
                                        initialValue: controller.modelChoice,
                                        isExpanded: true,
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'gemini-3.1-flash-lite',
                                            child: Text(
                                              'Gemini 3.1 Flash-Lite',
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 'gemini-3-flash-preview',
                                            child: Text(
                                              'Gemini 3 Flash Preview',
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 'gemini-3.5-flash-lite',
                                            child: Text(
                                              'Gemini 3.5 Flash-Lite',
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 'custom',
                                            child: Text('Custom model ID'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value != null) {
                                            controller.chooseModel(value);
                                          }
                                        },
                                      ),
                                    ),
                                    if (controller.modelChoice == 'custom') ...[
                                      const SizedBox(height: 14),
                                      Text(
                                        'Custom model ID',
                                        style: theme.textTheme.labelLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Semantics(
                                        label: 'Custom model ID',
                                        child: TextField(
                                          controller: controller.modelInput,
                                          autocorrect: false,
                                          enableSuggestions: false,
                                          decoration: const InputDecoration(
                                            hintText:
                                                'e.g. gemini-3.5-flash-lite',
                                          ),
                                          onSubmitted: (_) => _saveModel(),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 14),
                                    VeloraButton(
                                      label: 'Save model',
                                      size: VeloraButtonSize.small,
                                      onPressed: _saveModel,
                                    ),
                                  ],
                                ),
                              ),
                            if (_page == 3) const SizedBox(height: 16),
                            if (_page == 3)
                              VeloraCard(
                                elevated: false,
                                color: colors.surfaceContainerLowest,
                                padding: const EdgeInsets.all(24),
                                child: Theme(
                                  data: theme.copyWith(
                                    dividerColor: Colors.transparent,
                                  ),
                                  child: ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    childrenPadding: const EdgeInsets.only(
                                      top: 12,
                                      bottom: 4,
                                    ),
                                    shape: const Border(),
                                    collapsedShape: const Border(),
                                    leading: const Icon(Icons.tune_rounded),
                                    title: const Text('Dictation prompt'),
                                    subtitle: const Text(
                                      'View or customize how Gemini formats your speech.',
                                    ),
                                    children: [
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Language mode still applies.',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      TextField(
                                        controller: controller.systemPrompt,
                                        minLines: 6,
                                        maxLines: 12,
                                        maxLength: 5000,
                                        decoration: const InputDecoration(
                                          labelText: 'System prompt',
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          VeloraButton(
                                            label: 'Save prompt',
                                            size: VeloraButtonSize.small,
                                            onPressed: _updatePrompt,
                                          ),
                                          const SizedBox(width: 12),
                                          VeloraButton(
                                            label: 'Restore default',
                                            size: VeloraButtonSize.small,
                                            variant:
                                                VeloraButtonVariant.outline,
                                            onPressed: () =>
                                                _updatePrompt(reset: true),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (_page == 3) const SizedBox(height: 16),
                            if (_page == 0)
                              VeloraCard(
                                elevated: false,
                                color: colors.surfaceContainerLowest,
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SIGNAL DESK  /  DICTATION',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: colors.secondary,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.2,
                                          ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Speak. Review. Deliver.',
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Hold your shortcut anywhere. Use this desk to practise and inspect the result.',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 24),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          'HOLD',
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1,
                                              ),
                                        ),
                                        for (final key
                                            in controller.shortcut.split('+'))
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: colors.outlineVariant,
                                              ),
                                              color: colors.surfaceContainerLow,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              key,
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                          ),
                                        Text(
                                          'RELEASE TO DELIVER',
                                          style: theme.textTheme.labelMedium
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 28),
                                    Text(
                                      'TRANSCRIPT',
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: colors.secondary,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.2,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Focus(
                                      onFocusChange: (focused) {
                                        if (widget.dictation != null) {
                                          widget.dictation!.playgroundFocused =
                                              focused;
                                        }
                                      },
                                      child: Semantics(
                                        label: 'Dictation playground',
                                        child: TextField(
                                          key: const ValueKey(
                                            'dictation-playground',
                                          ),
                                          controller: _playground,
                                          minLines: 5,
                                          maxLines: 8,
                                          decoration: const InputDecoration(
                                            hintText: 'Your words arrive here.',
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (widget.dictation != null)
                                      vx.Obx(() {
                                        final dictation = widget.dictation!;
                                        final status =
                                            switch (dictation.hud.value) {
                                              HudState.preparing =>
                                                'Please wait before speaking…',
                                              HudState.listening => 'Speak now',
                                              HudState.writing =>
                                                'Turning speech into text…',
                                              HudState.success => 'Done',
                                              HudState.error =>
                                                dictation.message.value,
                                            };
                                        final active =
                                            dictation.recording.value ||
                                            dictation.hud.value ==
                                                HudState.preparing ||
                                            dictation.hud.value ==
                                                HudState.writing ||
                                            dictation.hud.value ==
                                                HudState.error ||
                                            dictation.hud.value ==
                                                HudState.success;
                                        return Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(
                                            top: 12,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: active
                                                ? colors.primaryContainer
                                                : colors.surfaceContainerLow,
                                            border: Border(
                                              left: BorderSide(
                                                color: active
                                                    ? colors.primary
                                                    : colors.secondary,
                                                width: 3,
                                              ),
                                            ),
                                          ),
                                          child: Semantics(
                                            liveRegion: true,
                                            child: Text(
                                              active ? status : 'READY  •  Awaiting shortcut',
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: .4,
                                                  ),
                                            ),
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
                                color: colors.surfaceContainerLowest,
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
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                        'hold:${controller.shortcut}:${controller.pageError}',
                                      ),
                                      initialValue: controller.shortcut,
                                      decoration: const InputDecoration(
                                        labelText: 'Hold to dictate',
                                      ),
                                      items: [
                                        for (final base
                                            in SettingsStore.shortcutBases)
                                          DropdownMenuItem(
                                            value: base,
                                            child: Text(
                                              base.replaceAll('+', ' + '),
                                            ),
                                          ),
                                      ],
                                      onChanged: (base) {
                                        if (base == null) return;
                                        final available = SettingsStore
                                            .shortcutModifiers
                                            .where(
                                              (m) =>
                                                  !base.split('+').contains(m),
                                            );
                                        final current = controller
                                            .translationShortcut
                                            .split('+')
                                            .last;
                                        final extra =
                                            available.contains(current)
                                            ? current
                                            : available.first;
                                        controller.changeShortcuts(
                                          base,
                                          '$base+$extra',
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                        'translation:${controller.shortcut}:${controller.translationShortcut}:${controller.pageError}',
                                      ),
                                      initialValue: controller
                                          .translationShortcut
                                          .split('+')
                                          .last,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Additional key for translation',
                                      ),
                                      items: [
                                        for (final modifier
                                            in SettingsStore.shortcutModifiers
                                                .where(
                                                  (m) => !controller.shortcut
                                                      .split('+')
                                                      .contains(m),
                                                ))
                                          DropdownMenuItem(
                                            value: modifier,
                                            child: Text(modifier),
                                          ),
                                      ],
                                      onChanged: (modifier) {
                                        if (modifier != null) {
                                          controller.changeShortcuts(
                                            controller.shortcut,
                                            '${controller.shortcut}+$modifier',
                                          );
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey(
                                        'handsFree:${controller.handsFreeKey}:${controller.pageError}',
                                      ),
                                      initialValue: controller.handsFreeKey,
                                      decoration: const InputDecoration(
                                        labelText: 'Hands-free key',
                                      ),
                                      items: [
                                        for (final key
                                            in SettingsStore.handsFreeKeys)
                                          DropdownMenuItem(
                                            value: key,
                                            child: Text(key),
                                          ),
                                      ],
                                      onChanged: (key) {
                                        if (key != null) {
                                          controller.changeShortcuts(
                                            controller.shortcut,
                                            controller.translationShortcut,
                                            key: key,
                                          );
                                        }
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '${controller.shortcut.replaceAll('+', ' + ')}  ·  Hold to dictate; release to finish',
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${controller.translationShortcut.replaceAll('+', ' + ')}  ·  Hold to translate; release to finish',
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${controller.shortcut.replaceAll('+', ' + ')} + ${controller.handsFreeKey}  ·  Press to start or finish hands-free',
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('Esc  ·  Cancel dictation'),
                                  ],
                                ),
                              ),
                            if (_page == 0) const SizedBox(height: 16),
                            if (_page == 0)
                              VeloraCard(
                                elevated: false,
                                color: colors.surfaceContainerLowest,
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
                                    Text(
                                      'Language mode',
                                      style: theme.textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Semantics(
                                      label: 'Language mode',
                                      child: DropdownButtonFormField<String>(
                                        initialValue: controller.language,
                                        isExpanded: true,
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'auto',
                                            child: Text('Auto detect'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'codeSwitching',
                                            child: Text('Code switching'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'translate',
                                            child: Text('Translate'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value != null) {
                                            controller.setLanguage(value);
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Translation target language',
                                      style: theme.textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Semantics(
                                      label: 'Translation target language',
                                      child: TextField(
                                        controller: controller.target,
                                        onSubmitted: _saveTarget,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    VeloraButton(
                                      label: 'Save target language',
                                      size: VeloraButtonSize.small,
                                      icon: Icons.check_rounded,
                                      variant: VeloraButtonVariant.secondary,
                                      onPressed: () =>
                                          _saveTarget(controller.target.text),
                                    ),
                                  ],
                                ),
                              ),
                            if (_page == 0) const SizedBox(height: 16),
                            if (_page == 3)
                              VeloraCard(
                                elevated: false,
                                color: colors.surfaceContainerLowest,
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
                                    Text(
                                      'Microphone',
                                      style: theme.textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Semantics(
                                      label: 'Microphone',
                                      child: DropdownButtonFormField<String>(
                                        initialValue: controller.device,
                                        isExpanded: true,
                                        items: [
                                          const DropdownMenuItem(
                                            value: null,
                                            child: Text('System default'),
                                          ),
                                          if (controller.device != null &&
                                              !controller.devices.any(
                                                (d) =>
                                                    d.id == controller.device,
                                              ))
                                            DropdownMenuItem(
                                              value: controller.device,
                                              child: const Text(
                                                'Selected microphone unavailable',
                                              ),
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
                                    ),
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 16,
                                      runSpacing: 12,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        VeloraButton(
                                          size: VeloraButtonSize.small,
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
                            if (_page == 3) const SizedBox(height: 16),
                            if (_page == 3)
                              VeloraCard(
                                elevated: false,
                                color: colors.surfaceContainerLowest,
                                padding: const EdgeInsets.all(24),
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Type text instead of pasting',
                                  ),
                                  subtitle: const Text(
                                    'Try this for fields that block paste. Check the focused field; typing and paste cannot be verified in every app.',
                                  ),
                                  value: controller.typeText,
                                  onChanged: controller.setTypeText,
                                ),
                              ),
                            if (_page == 3) const SizedBox(height: 16),
                            if (_page == 3)
                              VeloraCard(
                                elevated: false,
                                color: colors.surfaceContainerLowest,
                                padding: const EdgeInsets.all(24),
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Launch at sign-in'),
                                  subtitle: Text(
                                    controller.autoStart == null
                                        ? 'Unavailable on this device.'
                                        : 'Start AI Voice Dictator when you sign in to Windows.',
                                  ),
                                  value: controller.autoStart ?? false,
                                  onChanged:
                                      controller.autoStart == null ||
                                          controller.changingAutoStart
                                      ? null
                                      : controller.setAutoStart,
                                ),
                              ),
                            if (_page == 3) const SizedBox(height: 16),
                            if (_page == 3)
                              VeloraCard(
                                elevated: false,
                                color: colors.surfaceContainerLowest,
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _heading(
                                      context,
                                      Icons.science_outlined,
                                      'Experimental features',
                                      'Optional advanced features for power users.',
                                    ),
                                    const SizedBox(height: 16),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Live HUD streaming preview',
                                      ),
                                      subtitle: Text(
                                        controller.streamPreview
                                            ? 'Streaming preview active. Words appear in the floating HUD in real-time as Gemini generates them.'
                                            : 'Stream words in real-time in the floating HUD as Gemini generates them before pasting.',
                                      ),
                                      value: controller.streamPreview,
                                      onChanged: controller.setStreamPreview,
                                    ),
                                  ],
                                ),
                              ),
                            if (_page == 3) const SizedBox(height: 16),
                            if (_page == 1)
                              _buildStatsSection(context, theme, colors),
                            if (_page == 1) const SizedBox(height: 16),
                            if (_page == 2)
                              VeloraCard(
                                elevated: false,
                                color: colors.surfaceContainerLowest,
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: _heading(
                                            context,
                                            Icons.history_rounded,
                                            'Recent dictations',
                                            'Your latest transcripts are stored locally.',
                                          ),
                                        ),
                                        if (controller.history.isNotEmpty)
                                          TextButton.icon(
                                            onPressed: () async {
                                              final confirmed =
                                                  await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) =>
                                                        AlertDialog(
                                                          title: const Text(
                                                            'Clear all history?',
                                                          ),
                                                          content: const Text(
                                                            'All saved transcripts will be permanently deleted from this device.',
                                                          ),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    false,
                                                                  ),
                                                              child: const Text(
                                                                'Cancel',
                                                              ),
                                                            ),
                                                            TextButton(
                                                              onPressed: () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    true,
                                                                  ),
                                                              child: const Text(
                                                                'Clear history',
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                  );
                                              if (confirmed == true) {
                                                await controller.clearHistory();
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            label: const Text('Clear history'),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('Keep history'),
                                    Semantics(
                                      label: 'History retention',
                                      child: DropdownButton<int>(
                                        value: controller.historyRetention,
                                        isExpanded: true,
                                        items: const [
                                          DropdownMenuItem(
                                            value: 0,
                                            child: Text('Keep all'),
                                          ),
                                          DropdownMenuItem(
                                            value: 30,
                                            child: Text('30 days'),
                                          ),
                                          DropdownMenuItem(
                                            value: 90,
                                            child: Text('90 days'),
                                          ),
                                          DropdownMenuItem(
                                            value: 365,
                                            child: Text('1 year'),
                                          ),
                                        ],
                                        onChanged: (days) async {
                                          if (days == null ||
                                              days ==
                                                  controller.historyRetention) {
                                            return;
                                          }
                                          if (days != 0) {
                                            final confirmed = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text(
                                                  'Change history retention?',
                                                ),
                                                content: Text(
                                                  'When your next dictation is saved, entries older than $days days will be permanently deleted.',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          false,
                                                        ),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          context,
                                                          true,
                                                        ),
                                                    child: const Text(
                                                      'Confirm',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirmed != true ||
                                                !context.mounted) {
                                              return;
                                            }
                                          }
                                          await controller.setHistoryRetention(
                                            days,
                                          );
                                        },
                                      ),
                                    ),
                                    Text(
                                      controller.historyRetention == 0
                                          ? 'History is kept until you clear it.'
                                          : 'Older entries are deleted when a new dictation is saved.',
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
                                          onPressed: () async {
                                            try {
                                              await Clipboard.setData(
                                                ClipboardData(
                                                  text:
                                                      normalizeWindowsLineEndings(
                                                        entry.text,
                                                      ),
                                                ),
                                              );
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Copied to clipboard.',
                                                      ),
                                                    ),
                                                  );
                                            } catch (_) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Could not copy to clipboard.',
                                                      ),
                                                    ),
                                                  );
                                            }
                                          },
                                        ),
                                      ),
                                    if (controller.historyHasMore)
                                      TextButton(
                                        onPressed: controller.historyLoadingMore
                                            ? null
                                            : controller.loadMoreHistory,
                                        child: Text(
                                          controller.historyLoadingMore
                                              ? 'Loading…'
                                              : 'Load older dictations',
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

  Widget _buildStatsSection(
    BuildContext context,
    ThemeData theme,
    ColorScheme colors,
  ) {
    final stats = controller.stats;
    if (stats.totalSessions == 0) {
      return VeloraCard(
        elevated: false,
        color: colors.surfaceContainerLowest,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insights_rounded, size: 48, color: colors.primary),
              const SizedBox(height: 16),
              Text(
                'No dictation stats yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Text(
                  'Your stats show up here as you dictate. Speak naturally in any app using your shortcut or test in the playground.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final maxWords = stats.days.fold<int>(
      1,
      (max, day) => day.words > max ? day.words : max,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 560;
        final cards = [
          _buildMetricCard(
            theme,
            colors,
            icon: Icons.chat_bubble_outline_rounded,
            value: _formatNumber(stats.totalWords),
            label: 'Words dictated',
            badge: '${stats.totalSessions} sessions',
          ),
          _buildMetricCard(
            theme,
            colors,
            icon: Icons.bolt_rounded,
            value: _formatDuration(stats.timeSaved),
            label: 'Time saved',
            badge: 'vs ~40 WPM typing',
          ),
          _buildMetricCard(
            theme,
            colors,
            icon: Icons.speed_rounded,
            value: '${stats.speakingWpm} WPM',
            label: 'Speaking pace',
            badge: '${stats.speedMultiplier.toStringAsFixed(1)}x faster',
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNarrow)
              Column(
                children: [
                  cards[0],
                  const SizedBox(height: 12),
                  cards[1],
                  const SizedBox(height: 12),
                  cards[2],
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[2]),
                ],
              ),
            const SizedBox(height: 16),
            VeloraCard(
              elevated: false,
              color: colors.surfaceContainerLowest,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading(
                    context,
                    Icons.bar_chart_rounded,
                    'Words per week',
                    'Your daily dictation volume over the last 7 days.',
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 160,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final day in stats.days) ...[
                          Expanded(
                            child: _buildBarColumn(
                              theme,
                              colors,
                              day: day,
                              maxWords: maxWords,
                            ),
                          ),
                          if (day != stats.days.last) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            VeloraCard(
              elevated: false,
              color: colors.surfaceContainerLowest,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading(
                    context,
                    Icons.lightbulb_outline_rounded,
                    'Productivity insights',
                    'How voice dictation compares with keyboard typing.',
                  ),
                  const SizedBox(height: 16),
                  _buildInsightRow(
                    theme,
                    colors,
                    icon: Icons.timer_outlined,
                    title: 'Total audio recorded',
                    detail: _formatAudioTime(stats.totalDuration),
                  ),
                  const Divider(height: 20),
                  _buildInsightRow(
                    theme,
                    colors,
                    icon: Icons.short_text_rounded,
                    title: 'Average dictation size',
                    detail:
                        '${(stats.totalWords / (stats.totalSessions == 0 ? 1 : stats.totalSessions)).round()} words / session',
                  ),
                  const Divider(height: 20),
                  _buildInsightRow(
                    theme,
                    colors,
                    icon: Icons.info_outline_rounded,
                    title: 'Time saved calculation',
                    detail:
                        'Compares speaking pace against average typing speed (~40 WPM). Dictating at ${stats.speakingWpm > 0 ? stats.speakingWpm : 140} WPM is roughly ${stats.speedMultiplier > 1 ? stats.speedMultiplier.toStringAsFixed(1) : '3.5'}x faster than typing.',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(
    ThemeData theme,
    ColorScheme colors, {
    required IconData icon,
    required String value,
    required String label,
    required String badge,
  }) {
    return VeloraCard(
      elevated: false,
      color: colors.surfaceContainerLowest,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  badge,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarColumn(
    ThemeData theme,
    ColorScheme colors, {
    required DayStat day,
    required int maxWords,
  }) {
    final heightRatio = maxWords > 0
        ? (day.words / maxWords).clamp(0.0, 1.0)
        : 0.0;
    final now = DateTime.now();
    final isToday =
        day.date.year == now.year &&
        day.date.month == now.month &&
        day.date.day == now.day;

    return Semantics(
      label: '${day.dayLabel}: ${day.words} words',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            day.words > 0 ? '${day.words}' : '0',
            style: theme.textTheme.labelSmall?.copyWith(
              color: day.words > 0 ? colors.onSurface : colors.onSurfaceVariant,
              fontWeight: day.words > 0 ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 110 * heightRatio > 6 ? 110 * heightRatio : 6,
                decoration: BoxDecoration(
                  color: day.words > 0
                      ? colors.primary
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            day.dayLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              color: isToday ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
          Text(
            '${day.date.month}/${day.date.day}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightRow(
    ThemeData theme,
    ColorScheme colors, {
    required IconData icon,
    required String title,
    required String detail,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: colors.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatNumber(int n) {
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds <= 0) return '0 min';
    if (d.inMinutes < 1) {
      return '${d.inSeconds} sec';
    } else if (d.inHours < 1) {
      return '${d.inMinutes} min';
    } else {
      final hours = d.inMinutes / 60.0;
      return '${hours.toStringAsFixed(1)} hrs';
    }
  }

  String _formatAudioTime(Duration d) {
    if (d.inSeconds < 60) {
      return '${d.inSeconds}s';
    }
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '${mins}m ${secs}s';
  }
}
