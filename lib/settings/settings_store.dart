import 'dart:io';
import 'dart:convert';

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
    this.capturedAudio,
    this.submittedAudio,
    this.afterStop,
    this.geminiRequest,
    this.technicalDetails = const [],
  });
  final int? id;
  final String text;
  final DateTime createdAt;
  final Duration duration;
  final Duration? capturedAudio;
  final Duration? submittedAudio;
  final Duration? afterStop;
  final Duration? geminiRequest;
  final List<String> technicalDetails;
  int get wordCount =>
      text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
}

class DayStat {
  const DayStat({
    required this.date,
    required this.words,
    required this.duration,
    this.sessions = 0,
    this.dictationWords = 0,
    this.translationWords = 0,
  });
  final int sessions;
  final int dictationWords;
  final int translationWords;
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
    this.measuredSessions = 0,
    this.capturedAudio = Duration.zero,
    this.submittedAudio = Duration.zero,
    this.activity = const [],
    this.dictationWords = 0,
    this.translationWords = 0,
    this.unknownWords = 0,
    this.activeDays = 0,
    this.streak = 0,
  });

  const DictationStats.empty()
    : totalWords = 0,
      totalDuration = Duration.zero,
      totalSessions = 0,
      days = const [],
      measuredSessions = 0,
      capturedAudio = Duration.zero,
      submittedAudio = Duration.zero,
      activity = const [],
      dictationWords = 0,
      translationWords = 0,
      unknownWords = 0,
      activeDays = 0,
      streak = 0;

  final int totalWords;
  final Duration totalDuration;
  final int totalSessions;
  final List<DayStat> days;
  final int measuredSessions;
  final Duration capturedAudio;
  final Duration submittedAudio;
  final List<DayStat> activity;
  final int dictationWords, translationWords, unknownWords, activeDays, streak;

  static const typingWpm = 40.0;

  /// Time saved compared to typing at 40 WPM.
  Duration get timeSaved {
    if (totalWords <= 0) return Duration.zero;
    final typingSeconds = (totalWords / typingWpm) * 60.0;
    final speakingSeconds = totalDuration.inSeconds.toDouble();
    final savedSeconds = (typingSeconds - speakingSeconds).clamp(
      0.0,
      double.infinity,
    );
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
          version: 5,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE history (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL, created_at INTEGER NOT NULL, duration_ms INTEGER NOT NULL, captured_us INTEGER, submitted_us INTEGER, after_stop_ms INTEGER, gemini_request_ms INTEGER, technical_details TEXT, mode TEXT)',
            );
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) {
              await db.execute(
                'ALTER TABLE history ADD COLUMN captured_us INTEGER',
              );
              await db.execute(
                'ALTER TABLE history ADD COLUMN submitted_us INTEGER',
              );
            }
            if (oldVersion < 3) {
              await db.execute(
                'ALTER TABLE history ADD COLUMN after_stop_ms INTEGER',
              );
              await db.execute(
                'ALTER TABLE history ADD COLUMN gemini_request_ms INTEGER',
              );
            }
            if (oldVersion < 5) {
              await db.execute('ALTER TABLE history ADD COLUMN mode TEXT');
            }
            if (oldVersion < 4) {
              await db.execute(
                'ALTER TABLE history ADD COLUMN technical_details TEXT',
              );
            }
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

  Future<void> enableAutoStartByDefault(
    Future<void> Function(bool) setEnabled,
  ) async {
    if (_prefs.getBool('auto_start_initialized') == true) return;
    await setEnabled(true);
    await _prefs.setBool('auto_start_initialized', true);
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

  Future<int> addHistory(
    String text,
    Duration duration, {
    Duration? capturedAudio,
    Duration? submittedAudio,
    Duration? afterStop,
    Duration? geminiRequest,
    List<String> technicalDetails = const [],
    String? mode,
  }) async {
    final now = DateTime.now();
    return _historyDatabase.transaction((txn) async {
      final id = await txn.insert('history', {
        'text': text,
        'mode': mode,
        'created_at': now.millisecondsSinceEpoch,
        'duration_ms': duration.inMilliseconds,
        'captured_us': capturedAudio?.inMicroseconds,
        'submitted_us': submittedAudio?.inMicroseconds,
        'after_stop_ms': afterStop?.inMilliseconds,
        'gemini_request_ms': geminiRequest?.inMilliseconds,
        'technical_details': technicalDetails.isEmpty
            ? null
            : jsonEncode(technicalDetails),
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
      return id;
    });
  }

  Future<void> updateTechnicalDetails(int id, List<String> details) async {
    await _historyDatabase.update(
      'history',
      {'technical_details': jsonEncode(details)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearHistory() async => _historyDatabase.delete('history');

  Future<List<HistoryEntry>> history() => historyPage();

  Future<DictationStats> stats({
    int daysCount = 7,
    String period = 'all',
  }) async {
    if (_database == null) {
      return const DictationStats.empty();
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(Duration(days: daysCount - 1));
    final startMs = startDate.millisecondsSinceEpoch;

    final rows = await _historyDatabase.query(
      'history',
      columns: [
        'created_at',
        'duration_ms',
        'text',
        'captured_us',
        'submitted_us',
        'mode',
      ],
      orderBy: 'created_at ASC',
    );

    final periodStart = switch (period) {
      'week' => DateTime(
        today.year,
        today.month,
        today.day - today.weekday + 1,
      ),
      'month' => DateTime(today.year, today.month),
      _ => null,
    };
    var totalWords = 0, totalSessions = 0;
    var dictationWords = 0, translationWords = 0, unknownWords = 0;
    var totalMs = 0;
    var capturedUs = 0, submittedUs = 0, measured = 0;
    final dayWordsMap = <int, int>{};
    final dayDurationMap = <int, int>{};
    final allActivity = <int, int>{};
    final daySessions = <int, int>{};
    final dayDictation = <int, int>{}, dayTranslation = <int, int>{};

    for (final row in rows) {
      final text = row['text'] as String;
      final createdAtMs = row['created_at'] as int;
      final durationMs = row['duration_ms'] as int;
      final words = text.trim().isEmpty
          ? 0
          : text.trim().split(RegExp(r'\s+')).length;

      final entryDate = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
      final entryKey = DateTime(
        entryDate.year,
        entryDate.month,
        entryDate.day,
      ).millisecondsSinceEpoch;
      allActivity[entryKey] = (allActivity[entryKey] ?? 0) + 1;
      if (periodStart != null &&
          createdAtMs < periodStart.millisecondsSinceEpoch) {
        continue;
      }
      totalSessions++;
      final mode = row['mode'];
      if (mode == 'dictate') {
        dictationWords += words;
      } else if (mode == 'translate') {
        translationWords += words;
      } else {
        unknownWords += words;
      }
      totalWords += words;
      totalMs += durationMs;
      final captured = row['captured_us'] as int?;
      final submitted = row['submitted_us'] as int?;
      if (captured != null && submitted != null) {
        capturedUs += captured;
        submittedUs += submitted;
        measured++;
      }

      if (createdAtMs >= startMs) {
        final entryDate = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
        final dayKey = DateTime(
          entryDate.year,
          entryDate.month,
          entryDate.day,
        ).millisecondsSinceEpoch;
        daySessions[dayKey] = (daySessions[dayKey] ?? 0) + 1;
        if (mode == 'dictate') {
          dayDictation[dayKey] = (dayDictation[dayKey] ?? 0) + words;
        }
        if (mode == 'translate') {
          dayTranslation[dayKey] = (dayTranslation[dayKey] ?? 0) + words;
        }
        dayWordsMap[dayKey] = (dayWordsMap[dayKey] ?? 0) + words;
        dayDurationMap[dayKey] = (dayDurationMap[dayKey] ?? 0) + durationMs;
      }
    }

    final days = List.generate(daysCount, (i) {
      final d = DateTime(
        today.year,
        today.month,
        today.day - daysCount + 1 + i,
      );
      final key = d.millisecondsSinceEpoch;
      return DayStat(
        date: d,
        words: dayWordsMap[key] ?? 0,
        sessions: daySessions[key] ?? 0,
        dictationWords: dayDictation[key] ?? 0,
        translationWords: dayTranslation[key] ?? 0,
        duration: Duration(milliseconds: dayDurationMap[key] ?? 0),
      );
    });

    final activity = List.generate(181, (i) {
      final d = DateTime(today.year, today.month, today.day - 180 + i);
      return DayStat(
        date: d,
        words: 0,
        duration: Duration.zero,
        sessions: allActivity[d.millisecondsSinceEpoch] ?? 0,
      );
    });
    var streak = 0;
    var d = today;
    if (!allActivity.containsKey(d.millisecondsSinceEpoch)) {
      d = DateTime(d.year, d.month, d.day - 1);
    }
    while (allActivity.containsKey(d.millisecondsSinceEpoch)) {
      streak++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return DictationStats(
      activity: activity,
      streak: streak,
      activeDays: periodStart == null
          ? allActivity.length
          : allActivity.keys
                .where((key) => key >= periodStart.millisecondsSinceEpoch)
                .length,
      dictationWords: dictationWords,
      translationWords: translationWords,
      unknownWords: unknownWords,
      totalWords: totalWords,
      totalDuration: Duration(milliseconds: totalMs),
      totalSessions: totalSessions,
      days: days,
      measuredSessions: measured,
      capturedAudio: Duration(microseconds: capturedUs),
      submittedAudio: Duration(microseconds: submittedUs),
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
            capturedAudio: row['captured_us'] == null
                ? null
                : Duration(microseconds: row['captured_us'] as int),
            submittedAudio: row['submitted_us'] == null
                ? null
                : Duration(microseconds: row['submitted_us'] as int),
            afterStop: row['after_stop_ms'] == null
                ? null
                : Duration(milliseconds: row['after_stop_ms'] as int),
            technicalDetails: _decodeTechnicalDetails(row['technical_details']),
            geminiRequest: row['gemini_request_ms'] == null
                ? null
                : Duration(milliseconds: row['gemini_request_ms'] as int),
          ),
        )
        .toList();
  }

  Future<void> close() async {
    await _database?.close();
  }
}

List<String> _decodeTechnicalDetails(Object? value) {
  if (value is! String) return const [];
  try {
    return (jsonDecode(value) as List).whereType<String>().toList();
  } catch (_) {
    return const [];
  }
}
