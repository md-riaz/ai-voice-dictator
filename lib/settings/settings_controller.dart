import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:velora/velora.dart';

import 'settings_service.dart';
import 'settings_store.dart';

class SettingsController extends VeloraController {
  SettingsController({
    required this.store,
    required this.service,
    required this.onShortcutChanged,
    this.initialError,
  });
  final SettingsStore store;
  final SettingsService service;
  final Future<void> Function(String, String) onShortcutChanged;
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
  StreamSubscription<Uint8List>? samples;
  StreamSubscription<Amplitude>? amplitude;
  List<InputDevice> devices = [];
  List<HistoryEntry> history = [];
  String? device;
  String language = 'auto';
  String shortcut = 'Ctrl+Space';
  String translationShortcut = 'Ctrl+Alt+Space';
  String keyStatus = 'Key missing';
  String? pageError;
  bool pageLoading = true;
  bool testingMic = false;
  double level = 0;

  void initialize() {
    pageError = initialError;
    load();
  }

  Future<void> load() async {
    try {
      final key = await store.apiKey();
      List<InputDevice> devices;
      try {
        devices = await service.listDevices();
      } catch (_) {
        devices = [];
      }
      final history = await store.history();
      if (_closed) return;
      _updateState(() {
        this.key.text = key;
        target.text = store.targetLanguage();
        language = store.language();
        shortcut = store.shortcut();
        translationShortcut = store.translationShortcut();
        this.devices = devices;
        final savedDevice = store.deviceId();
        device = devices.any((d) => d.id == savedDevice) ? savedDevice : null;
        this.history = history;
        keyStatus = key.isEmpty ? 'Key missing' : 'Not checked';
        pageLoading = false;
      });
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
    _updateState(
      () => keyStatus = value.trim().isEmpty ? 'Key missing' : 'Not checked',
    );
  }

  Future<void> saveKey() async {
    try {
      await store.saveApiKey(key.text);
      if (!_closed) {
        _updateState(() {
          keyStatus = key.text.trim().isEmpty ? 'Key missing' : 'Not checked';
          pageError = null;
        });
      }
    } catch (_) {
      if (!_closed) {
        _updateState(() => pageError = 'Could not save the API key securely.');
      }
    }
  }

  Future<void> testKey() async {
    final key = this.key.text.trim();
    if (key.isEmpty) {
      _updateState(() => keyStatus = 'Key missing');
      return;
    }
    _updateState(() {
      keyStatus = 'Checking…';
      pageError = null;
    });
    try {
      final statusCode = await service.validateKey(key);
      if (!_closed && this.key.text.trim() == key) {
        _updateState(
          () => keyStatus = statusCode == 200
              ? 'Connected'
              : 'Validation failed (HTTP $statusCode)',
        );
      }
    } catch (_) {
      if (!_closed && this.key.text.trim() == key) {
        _updateState(() => keyStatus = 'Unable to validate key');
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

  Future<void> setTarget(String value) async {
    if (value.trim().isNotEmpty) await store.setTargetLanguage(value.trim());
  }

  Future<void> setDevice(String? value) async {
    await store.setDeviceId(value);
    _updateState(() => device = value);
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
    super.onClose();
  }
}
