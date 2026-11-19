import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:velora/velora.dart';

import '../services/gemini_service.dart';
import 'settings_service.dart';
import 'settings_store.dart';

class SettingsController extends VeloraController {
  SettingsController({
    required this.store,
    required this.service,
    required this.onShortcutChanged,
    this.getAutoStart,
    this.onAutoStartChanged,
    this.initialError,
  });
  final SettingsStore store;
  final SettingsService service;
  final Future<void> Function(String, String) onShortcutChanged;
  final Future<bool> Function()? getAutoStart;
  final Future<void> Function(bool)? onAutoStartChanged;
  final String? initialError;
  bool _closed = false;
  Completer<void>? _micOperation;
  Future<void>? _cleanup;
  void _updateState(void Function() fn) {
    if (!_closed) {
      fn();
      update();
    }
  }

  final key = TextEditingController();
  final target = TextEditingController();
  final modelInput = TextEditingController();
  final systemPrompt = TextEditingController();
  String modelChoice = SettingsStore.defaultModel;
  static const knownModels = [
    SettingsStore.defaultModel,
    'gemini-3-flash-preview',
    'gemini-3.5-flash-lite',
  ];
  StreamSubscription<Uint8List>? samples;
  StreamSubscription<Amplitude>? amplitude;
  List<InputDevice> devices = [];
  List<HistoryEntry> history = [];
  String? device;
  String language = 'auto';
  bool typeText = false;
  String shortcut = 'Ctrl+Space';
  String translationShortcut = 'Ctrl+Alt+Space';
  String keyStatus = 'Key missing';
  String? pageError;
  bool pageLoading = true;
  bool needsSetup = true;
  bool _keySaved = false;
  int _keyCheckVersion = 0;
  bool testingMic = false;
  bool? autoStart;
  bool changingAutoStart = false;
  double level = 0;

  void initialize() {
    pageError = initialError;
    load();
  }

  Future<void> load() async {
    try {
      final key = await store.apiKey().timeout(const Duration(seconds: 8));
      List<InputDevice> devices;
      try {
        devices = await service.listDevices().timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {
        devices = [];
      }
      final history = await store.history().timeout(const Duration(seconds: 8));
      bool? autoStart;
      if (getAutoStart != null && onAutoStartChanged != null) {
        try {
          autoStart = await getAutoStart!();
        } catch (_) {
          autoStart = null;
        }
      }
      if (_closed) return;
      _updateState(() {
        this.key.text = key;
        target.text = store.targetLanguage();
        final savedModel = store.model();
        modelChoice = knownModels.contains(savedModel) ? savedModel : 'custom';
        modelInput.text = savedModel;
        systemPrompt.text =
            store.systemPrompt() ?? kDictationSystemInstruction.trim();
        language = store.language();
        typeText = store.typeText();
        shortcut = store.shortcut();
        translationShortcut = store.translationShortcut();
        this.devices = devices;
        final savedDevice = store.deviceId();
        device = devices.any((d) => d.id == savedDevice) ? savedDevice : null;
        this.history = history;
        this.autoStart = autoStart;
        keyStatus = key.isEmpty ? 'Key missing' : 'Checking saved key…';
        needsSetup = key.isEmpty;
        _keySaved = key.isNotEmpty;
        pageLoading = false;
      });
      if (key.isNotEmpty) unawaited(testKey());
    } catch (_) {
      if (!_closed) {
        _updateState(() {
          pageError = 'Could not load settings or microphone devices.';
          pageLoading = false;
        });
      }
    }
  }

  void keyChanged(String value) {
    _updateState(() {
      _keyCheckVersion++;
      _keySaved = false;
      keyStatus = value.trim().isEmpty ? 'Key missing' : 'Unsaved key';
    });
  }

  Future<void> refreshHistory() async {
    try {
      final entries = await store.history();
      _updateState(() => history = entries);
    } catch (_) {
      _updateState(() => pageError = 'Could not load dictation history.');
    }
  }

  Future<void> clearHistory() async {
    try {
      await store.clearHistory();
      await refreshHistory();
    } catch (_) {
      _updateState(() => pageError = 'Could not clear dictation history.');
    }
  }

  Future<void> saveKey() async {
    try {
      final savedKey = key.text.trim();
      await store.saveApiKey(savedKey);
      if (!_closed && key.text.trim() == savedKey) {
        _updateState(() {
          pageError = null;
          _keySaved = savedKey.isNotEmpty;
          if (savedKey.isEmpty) needsSetup = true;
        });
        if (savedKey.isEmpty) {
          _updateState(() => keyStatus = 'Key missing');
        } else {
          await testKey();
        }
      }
    } catch (_) {
      if (!_closed) {
        _updateState(() => pageError = 'Could not save the API key securely.');
      }
    }
  }

  Future<void> testKey() async {
    final key = this.key.text.trim();
    final version = ++_keyCheckVersion;
    if (key.isEmpty) {
      _updateState(() => keyStatus = 'Key missing');
      return;
    }
    _updateState(() {
      keyStatus = _keySaved ? 'Checking saved key…' : 'Checking key…';
    });
    try {
      final statusCode = await service.validateKey(key);
      if (!_closed &&
          version == _keyCheckVersion &&
          this.key.text.trim() == key) {
        _updateState(() {
          keyStatus = statusCode == 200
              ? (_keySaved ? 'Connected' : 'Valid — save key')
              : 'Validation failed (HTTP $statusCode)';
          if (statusCode == 200 && _keySaved) needsSetup = false;
        });
      }
    } catch (_) {
      if (!_closed &&
          version == _keyCheckVersion &&
          this.key.text.trim() == key) {
        _updateState(() => keyStatus = 'Could not check connection');
      }
    }
  }

  Future<void> changeShortcuts(String primary, String translation) async {
    try {
      if (primary == translation) {
        throw StateError('Choose different shortcuts.');
      }
      await onShortcutChanged(primary, translation);
      await store.setShortcut(primary);
      await store.setTranslationShortcut(translation);
      if (!_closed) {
        _updateState(() {
          shortcut = primary;
          translationShortcut = translation;
          pageError = null;
        });
      }
    } catch (e) {
      if (!_closed) {
        _updateState(() => pageError = 'Shortcut could not be registered: $e');
      }
    }
  }

  Future<void> toggleMic() async {
    if (_closed || _micOperation != null) return;
    _micOperation = Completer<void>();
    try {
      if (testingMic) {
        await stopMic();
        return;
      }
      try {
        if (!await service.hasPermission()) {
          throw StateError('Microphone permission denied.');
        }
        final selected = devices.where((d) => d.id == device).firstOrNull;
        final stream = await service.startMic(selected);
        samples = stream.listen(
          (_) {},
          onError: (_) {
            if (!_closed) {
              _updateState(() => pageError = 'Microphone test failed.');
            }
          },
        );
        amplitude = service.levels().listen((a) {
          if (!_closed) {
            _updateState(() => level = ((a.current + 60) / 60).clamp(0, 1));
          }
        });
        if (!_closed) {
          _updateState(() {
            testingMic = true;
            pageError = null;
          });
        }
      } catch (_) {
        if (!_closed) {
          _updateState(() => pageError = 'Could not start microphone test.');
        }
      }
    } finally {
      _micOperation?.complete();
      _micOperation = null;
    }
  }

  Future<void> stopMic() async {
    await amplitude?.cancel();
    await service.stopMic();
    await samples?.cancel();
    if (!_closed) {
      _updateState(() {
        testingMic = false;
        level = 0;
      });
    }
  }

  Future<void> setLanguage(String value) async {
    await store.setLanguage(value);
    _updateState(() => language = value);
  }

  void chooseModel(String value) {
    _updateState(() => modelChoice = value);
  }

  Future<void> saveModel() async {
    final model = modelChoice == 'custom'
        ? modelInput.text.trim()
        : modelChoice;
    if (!SettingsStore.validModel(model)) {
      throw const FormatException('Use a Gemini model ID, not a URL or path.');
    }
    await store.setModel(model);
    _updateState(() => modelInput.text = model);
  }

  Future<void> saveSystemPrompt() async {
    final value = systemPrompt.text.trim();
    await store.setSystemPrompt(
      value == kDictationSystemInstruction.trim() ? null : value,
    );
    _updateState(
      () => systemPrompt.text =
          store.systemPrompt() ?? kDictationSystemInstruction.trim(),
    );
  }

  Future<void> setTypeText(bool value) async {
    await store.setTypeText(value);
    _updateState(() => typeText = value);
  }

  Future<void> resetSystemPrompt() async {
    await store.setSystemPrompt(null);
    _updateState(() => systemPrompt.text = kDictationSystemInstruction.trim());
  }

  Future<void> setTarget(String value) async {
    if (value.trim().isNotEmpty) await store.setTargetLanguage(value.trim());
  }

  Future<void> setDevice(String? value) async {
    await store.setDeviceId(value);
    _updateState(() => device = value);
  }

  Future<void> setAutoStart(bool value) async {
    if (changingAutoStart || autoStart == null || onAutoStartChanged == null) {
      return;
    }
    _updateState(() => changingAutoStart = true);
    try {
      await onAutoStartChanged!(value);
      _updateState(() {
        autoStart = value;
        pageError = null;
      });
    } catch (_) {
      _updateState(() => pageError = 'Could not update launch at sign-in.');
    } finally {
      _updateState(() => changingAutoStart = false);
    }
  }

  Future<void> closeResources() => _cleanup ??= _closeResources();
  Future<void> _closeResources() async {
    _closed = true;
    await _micOperation?.future;
    await amplitude?.cancel();
    await samples?.cancel();
    await service.dispose();
  }

  @override
  void onClose() {
    unawaited(closeResources());
    key.dispose();
    target.dispose();
    modelInput.dispose();
    systemPrompt.dispose();
    super.onClose();
  }
}
