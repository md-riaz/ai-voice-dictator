import 'dart:io';

import 'package:ai_voice_dictator/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('shortcut configuration is validated and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    await store.initialize(databasePath: inMemoryDatabasePath);
    expect(store.shortcut(), 'Ctrl+Win');
    await store.setShortcuts('Win+Shift', 'Win+Shift+Alt', 'F8');
    final reopened = SettingsStore();
    await reopened.initialize(databasePath: inMemoryDatabasePath);
    expect(reopened.shortcut(), 'Win+Shift');
    expect(reopened.translationShortcut(), 'Win+Shift+Alt');
    expect(reopened.handsFreeKey(), 'F8');
    await expectLater(
      store.setShortcuts('Ctrl', 'Ctrl+Alt', 'Space'),
      throwsFormatException,
    );
    await store.close();
    await reopened.close();
  });
  test('custom prompt persists and reset returns to default', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    await store.initialize(databasePath: inMemoryDatabasePath);
    expect(store.systemPrompt(), isNull);
    await store.setSystemPrompt('Write technical words in English.');
    final reopened = SettingsStore();
    await reopened.initialize(databasePath: inMemoryDatabasePath);
    expect(reopened.systemPrompt(), 'Write technical words in English.');
    await expectLater(store.setSystemPrompt('x' * 5001), throwsFormatException);
    await store.setSystemPrompt(null);
    expect(store.systemPrompt(), isNull);
    await store.close();
    await reopened.close();
  });
  test('persists a validated model choice', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SettingsStore();
    await store.initialize(databasePath: inMemoryDatabasePath);
    expect(store.model(), SettingsStore.defaultModel);
    await store.setModel('gemini-future-preview');
    final reopened = SettingsStore();
    await reopened.initialize(databasePath: inMemoryDatabasePath);
    expect(reopened.model(), 'gemini-future-preview');
    await expectLater(
      store.setModel('models/gemini-invalid'),
      throwsFormatException,
    );
    await store.close();
    await reopened.close();
  });
  test('invalid persisted model falls back to default', () async {
    SharedPreferences.setMockInitialValues({'gemini_model': '../invalid'});
    final store = SettingsStore();
    await store.initialize(databasePath: inMemoryDatabasePath);
    expect(store.model(), SettingsStore.defaultModel);
    await store.close();
  });
  test(
    'history returns the newest 50 entries and preserves durations',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore();
      await store.initialize(databasePath: inMemoryDatabasePath);
      for (var i = 0; i < 52; i++) {
        await store.addHistory('entry $i', Duration(seconds: i));
      }
      final rows = await store.history();
      expect(rows.length, 50);
      expect(rows.first.text, 'entry 51');
      expect(rows.first.duration, const Duration(seconds: 51));
      expect(rows.last.text, 'entry 2');
      final older = await store.historyPage(beforeId: rows.last.id);
      expect(older.map((entry) => entry.text), ['entry 1', 'entry 0']);
      expect(rows.first.wordCount, 2);
      await store.clearHistory();
      expect(await store.history(), isEmpty);
      await store.addHistory('after clearing', const Duration(seconds: 1));
      expect((await store.history()).single.text, 'after clearing');
      await store.close();
    },
  );
  test(
    'retention is opt-in and deletes expired entries on next save',
    () async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('history_retention_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/history.sqlite';
      final store = SettingsStore();
      await store.initialize(databasePath: path);
      expect(store.historyRetention(), 0);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.insert('history', {
        'text': 'old',
        'created_at': DateTime.now()
            .subtract(const Duration(days: 31))
            .millisecondsSinceEpoch,
        'duration_ms': 1000,
      });
      await store.addHistory('keep all', const Duration(seconds: 1));
      expect((await store.history()).length, 2);
      await store.setHistoryRetention(30);
      await expectLater(store.setHistoryRetention(-1), throwsFormatException);
      await store.addHistory('new', const Duration(seconds: 1));
      expect((await store.history()).map((entry) => entry.text), [
        'new',
        'keep all',
      ]);
      await db.close();
      await store.close();
    },
  );
  test('corrupt history does not prevent loading other settings', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('history_bad_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/history.sqlite');
    await file.writeAsString('not a database');
    final store = SettingsStore();
    await store.initialize(databasePath: file.path);
    expect(store.model(), SettingsStore.defaultModel);
    await expectLater(store.history(), throwsStateError);
    expect(await file.readAsString(), 'not a database');
    await store.close();
  });
  test(
    'pages and prunes a 1200-entry history without losing newer rows',
    () async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('history_large_');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/history.sqlite';
      final store = SettingsStore();
      await store.initialize(databasePath: path);
      final db = await databaseFactoryFfi.openDatabase(path);
      final now = DateTime.now();
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (var i = 0; i < 1200; i++) {
          batch.insert('history', {
            'text': 'entry $i',
            'created_at': now
                .subtract(Duration(days: i < 600 ? 60 : 1))
                .millisecondsSinceEpoch,
            'duration_ms': 1000,
          });
        }
        await batch.commit(noResult: true);
      });
      var page = await store.history();
      final texts = <String>[];
      while (page.isNotEmpty) {
        texts.addAll(page.map((entry) => entry.text));
        page = await store.historyPage(beforeId: page.last.id);
      }
      expect(texts.length, 1200);
      expect(texts.toSet().length, 1200);
      expect(texts.first, 'entry 1199');
      expect(texts.last, 'entry 0');
      await store.setHistoryRetention(30);
      await store.addHistory('new entry', const Duration(seconds: 1));
      final counts = await db.rawQuery('SELECT COUNT(*) AS n FROM history');
      expect(counts.single['n'], 601);
      expect((await store.history()).first.text, 'new entry');
      await db.close();
      await store.close();
    },
  );
  test('SQLite full error leaves existing history intact', () async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('history_full_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/history.sqlite';
    final store = SettingsStore();
    await store.initialize(databasePath: path);
    await store.addHistory('existing', const Duration(seconds: 1));
    final db = await databaseFactoryFfi.openDatabase(path);
    final pages =
        (await db.rawQuery('PRAGMA page_count')).first.values.first as int;
    await db.rawQuery('PRAGMA max_page_count = $pages');
    await expectLater(
      store.addHistory('x' * 1000000, const Duration(seconds: 1)),
      throwsA(anything),
    );
    expect((await store.history()).map((entry) => entry.text), ['existing']);
    await db.close();
    await store.close();
  });
}
