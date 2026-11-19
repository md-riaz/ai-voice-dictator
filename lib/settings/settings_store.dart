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

class DayStat {
  const DayStat({
    required this.date,
    required this.words,
    required this.duration,
  });
  final DateTime date;
  final int words;
  final Duration duration;

  String get dayLabel {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }
}

class DictationStats {
  const DictationStats({
    required this.totalWords,
    required this.totalDuration,
    required this.totalSessions,
    required this.days,
  });

  const DictationStats.empty()
      : totalWords = 0,
        totalDuration = Duration.zero,
        totalSessions = 0,
        days = const [];

  final int totalWords;
  final Duration totalDuration;
  final int totalSessions;
  final List<DayStat> days;

  static const typingWpm = 40.0;

  /// Time saved compared to typing at 40 WPM.
  Duration get timeSaved {
    if (totalWords <= 0) return Duration.zero;
    final typingSeconds = (totalWords / typingWpm) * 60.0;
    final speakingSeconds = totalDuration.inSeconds.toDouble();
    final savedSeconds =
        (typingSeconds - speakingSeconds).clamp(0.0, double.infinity);
    return Duration(seconds: savedSeconds.round());
  }

  /// Average speaking speed in words per minute.
  int get speakingWpm {
    final ms = totalDuration.inMilliseconds;
    if (ms <= 0 || totalWords <= 0) return 0;
    return (totalWords / (ms / 60000.0)).round();
  }

  /// Speed multiplier compared to typing (40 WPM).
  double get speedMultiplier {
    if (speakingWpm <= 0) return 1.0;
    return speakingWpm / typingWpm;
  }
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
  bool streamPreview() => _prefs.getBool('stream_preview') ?? false;
  Future<void> setStreamPreview(bool value) async =>
      _prefs.setBool('stream_preview', value);
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
  static final handsFreeKeys = [
    'Space',
    ...List.generate(26, (i) => String.fromCharCode(65 + i)),
    ...List.generate(10, (i) => '$i'),
    ...List.generate(12, (i) => 'F${i + 1}'),
  ];
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
    if ((parts.length == 2 || parts.length == 3) &&
        validShortcuts(parts[0], parts[1])) {
      return [
        parts[0],
        parts[1],
        if (parts.length == 3 && handsFreeKeys.contains(parts[2]))
          parts[2]
        else
          'Space',
      ];
    }
    return ['Ctrl+Win', 'Ctrl+Win+Alt', 'Space'];
  }

  String shortcut() => _shortcutConfiguration()[0];
  String translationShortcut() => _shortcutConfiguration()[1];
  String handsFreeKey() => _shortcutConfiguration()[2];
  Future<void> setShortcuts(String hold, String translation, String key) async {
    if (!validShortcuts(hold, translation) || !handsFreeKeys.contains(key)) {
      throw const FormatException('Choose a valid shortcut combination.');
    }
    await _prefs.setString('shortcut_config', '$hold|$translation|$key');
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

  Future<DictationStats> stats({int daysCount = 7}) async {
    if (_database == null) {
      return const DictationStats.empty();
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(Duration(days: daysCount - 1));
    final startMs = startDate.millisecondsSinceEpoch;

    final rows = await _historyDatabase.query(
      'history',
      columns: ['created_at', 'duration_ms', 'text'],
      orderBy: 'created_at ASC',
    );

    var totalWords = 0;
    var totalMs = 0;
    final dayWordsMap = <int, int>{};
    final dayDurationMap = <int, int>{};

    for (final row in rows) {
      final text = row['text'] as String;
      final createdAtMs = row['created_at'] as int;
      final durationMs = row['duration_ms'] as int;
      final words =
          text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

      totalWords += words;
      totalMs += durationMs;

      if (createdAtMs >= startMs) {
        final entryDate = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
        final dayKey =
            DateTime(entryDate.year, entryDate.month, entryDate.day)
                .millisecondsSinceEpoch;
        dayWordsMap[dayKey] = (dayWordsMap[dayKey] ?? 0) + words;
        dayDurationMap[dayKey] =
            (dayDurationMap[dayKey] ?? 0) + durationMs;
      }
    }

    final days = List.generate(daysCount, (i) {
      final d = startDate.add(Duration(days: i));
      final key = d.millisecondsSinceEpoch;
      return DayStat(
        date: d,
        words: dayWordsMap[key] ?? 0,
        duration: Duration(milliseconds: dayDurationMap[key] ?? 0),
      );
    });

    return DictationStats(
      totalWords: totalWords,
      totalDuration: Duration(milliseconds: totalMs),
      totalSessions: rows.length,
      days: days,
    );
  }

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
