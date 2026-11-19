import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class HistoryEntry {
  const HistoryEntry({
    this.id,
    required this.text,
    required this.createdAt,
    required this.duration,
  });
  final int? id;
  final String text;
  final DateTime createdAt;
  final Duration duration;
  int get wordCount =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
}

class SettingsStore {
  static const defaultModel = 'gemini-3.1-flash-lite';
  static bool validModel(String value) =>
      RegExp(r'^[a-z0-9][a-z0-9.-]{0,99}$').hasMatch(value);
  SettingsStore({FlutterSecureStorage? secureStorage})
    : _secure = secureStorage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _secure;
  late SharedPreferences _prefs;
  Database? _database;
  Database get _historyDatabase =>
      _database ?? (throw StateError('History storage is unavailable.'));

  Future<void> initialize({String? databasePath}) async {
    _prefs = await SharedPreferences.getInstance();
    sqfliteFfiInit();
    final path =
        databasePath ??
        p.join((await getApplicationSupportDirectory()).path, 'history.sqlite');
    try {
      if (path != inMemoryDatabasePath) {
        await Directory(p.dirname(path)).create(recursive: true);
      }
      _database = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE history (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL, created_at INTEGER NOT NULL, duration_ms INTEGER NOT NULL)',
            );
          },
        ),
      );
    } catch (_) {
      // Preserve an inaccessible database; dictation can continue without history.
      _database = null;
    }
  }

  Future<String> apiKey() async =>
      await _secure.read(key: 'gemini_api_key') ?? '';
  Future<void> saveApiKey(String key) async {
    if (key.trim().isEmpty) {
      await _secure.delete(key: 'gemini_api_key');
    } else {
      await _secure.write(key: 'gemini_api_key', value: key.trim());
    }
  }

  String language() => _prefs.getString('language') ?? 'auto';
  bool typeText() => _prefs.getBool('type_text') ?? false;
  Future<void> setTypeText(bool value) async =>
      _prefs.setBool('type_text', value);
  int historyRetention() {
    final days = _prefs.getInt('history_retention_days') ?? 0;
    return [0, 30, 90, 365].contains(days) ? days : 0;
  }

  Future<void> setHistoryRetention(int days) async {
    if (![0, 30, 90, 365].contains(days)) {
      throw const FormatException('Invalid history retention.');
    }
    await _prefs.setInt('history_retention_days', days);
  }

  String? systemPrompt() => _prefs.getString('system_prompt');
  Future<void> setSystemPrompt(String? value) async {
    if (value == null || value.trim().isEmpty) {
      await _prefs.remove('system_prompt');
    } else if (value.length > 5000) {
      throw const FormatException('Prompt must be 5000 characters or fewer.');
    } else {
      await _prefs.setString('system_prompt', value.trim());
    }
  }

  String model() {
    final value = _prefs.getString('gemini_model');
    return value != null && validModel(value) ? value : defaultModel;
  }

  Future<void> setModel(String value) async {
    if (!validModel(value)) {
      throw const FormatException('Invalid Gemini model ID.');
    }
    await _prefs.setString('gemini_model', value);
  }

  Future<void> setLanguage(String value) async {
    await _prefs.setString('language', value);
  }

  String targetLanguage() => _prefs.getString('target_language') ?? 'English';
  Future<void> setTargetLanguage(String value) async {
    await _prefs.setString('target_language', value);
  }

  String? deviceId() => _prefs.getString('device_id');
  Future<void> setDeviceId(String? value) async {
    if (value == null) {
      await _prefs.remove('device_id');
    } else {
      await _prefs.setString('device_id', value);
    }
  }

  static const shortcutModifiers = ['Ctrl', 'Win', 'Alt', 'Shift'];
  static const shortcutBases = [
    'Ctrl+Win',
    'Ctrl+Alt',
    'Ctrl+Shift',
    'Win+Alt',
    'Win+Shift',
    'Alt+Shift',
  ];
  static bool validShortcuts(String hold, String translation) {
    if (!shortcutBases.contains(hold)) return false;
    final additions = shortcutModifiers.where(
      (m) => !hold.split('+').contains(m),
    );
    return additions.any((m) => translation == '$hold+$m');
  }

  List<String> _shortcutConfiguration() {
    final parts = (_prefs.getString('shortcut_config') ?? '').split('|');
    if (parts.length == 2 && validShortcuts(parts[0], parts[1])) return parts;
    return ['Ctrl+Win', 'Ctrl+Win+Alt'];
  }

  String shortcut() => _shortcutConfiguration()[0];
  String translationShortcut() => _shortcutConfiguration()[1];
  Future<void> setShortcuts(String hold, String translation) async {
    if (!validShortcuts(hold, translation)) {
      throw const FormatException('Choose a valid shortcut combination.');
    }
    await _prefs.setString('shortcut_config', '$hold|$translation');
  }

  Future<void> addHistory(String text, Duration duration) async {
    final now = DateTime.now();
    await _historyDatabase.transaction((txn) async {
      await txn.insert('history', {
        'text': text,
        'created_at': now.millisecondsSinceEpoch,
        'duration_ms': duration.inMilliseconds,
      });
      final days = historyRetention();
      if (days > 0) {
        await txn.delete(
          'history',
          where: 'created_at < ?',
          whereArgs: [
            now.subtract(Duration(days: days)).millisecondsSinceEpoch,
          ],
        );
      }
    });
  }

  Future<void> clearHistory() async => _historyDatabase.delete('history');

  Future<List<HistoryEntry>> history() => historyPage();

  Future<List<HistoryEntry>> historyPage({int? beforeId}) async {
    final rows = await _historyDatabase.query(
      'history',
      where: beforeId == null ? null : 'id < ?',
      whereArgs: beforeId == null ? null : [beforeId],
      orderBy: 'id DESC',
      limit: 50,
    );
    return rows
        .map(
          (row) => HistoryEntry(
            id: row['id'] as int,
            text: row['text'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
            ),
            duration: Duration(milliseconds: row['duration_ms'] as int),
          ),
        )
        .toList();
  }

  Future<void> close() async {
    await _database?.close();
  }
}
