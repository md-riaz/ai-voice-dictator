import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class HistoryEntry {
  const HistoryEntry({
    required this.text,
    required this.createdAt,
    required this.duration,
  });
  final String text;
  final DateTime createdAt;
  final Duration duration;
  int get wordCount =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
}

class SettingsStore {
  static const defaultModel = 'gemini-3.5-flash-lite';
  static bool validModel(String value) =>
      RegExp(r'^[a-z0-9][a-z0-9.-]{0,99}$').hasMatch(value);
  SettingsStore({FlutterSecureStorage? secureStorage})
    : _secure = secureStorage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _secure;
  late SharedPreferences _prefs;
  late Database _database;

  Future<void> initialize({String? databasePath}) async {
    _prefs = await SharedPreferences.getInstance();
    sqfliteFfiInit();
    final path =
        databasePath ??
        p.join((await getApplicationSupportDirectory()).path, 'history.sqlite');
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

  String shortcut() => _prefs.getString('shortcut') ?? 'Ctrl+Space';
  Future<void> setShortcut(String value) async {
    await _prefs.setString('shortcut', value);
  }

  String translationShortcut() =>
      _prefs.getString('translation_shortcut') ?? 'Ctrl+Alt+Space';
  Future<void> setTranslationShortcut(String value) async {
    await _prefs.setString('translation_shortcut', value);
  }

  Future<void> addHistory(String text, Duration duration) async {
    await _database.insert('history', {
      'text': text,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'duration_ms': duration.inMilliseconds,
    });
  }

  Future<List<HistoryEntry>> history() async {
    final rows = await _database.query(
      'history',
      orderBy: 'id DESC',
      limit: 50,
    );
    return rows
        .map(
          (row) => HistoryEntry(
            text: row['text'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
            ),
            duration: Duration(milliseconds: row['duration_ms'] as int),
          ),
        )
        .toList();
  }

  Future<void> close() => _database.close();
}
