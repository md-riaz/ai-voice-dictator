import 'package:ai_voice_dictator/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
      expect(rows.first.wordCount, 2);
      await store.close();
    },
  );
}
