import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models/riwaya.dart';
import '../domain/settings.dart';

/// On-device storage for settings and progress per surah. Never audio, never transcripts.
class AppStore {
  AppStore(this._db);

  final Database _db;

  static Future<AppStore> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await getDatabasesPath(), 'app.sqlite');
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE progress (riwaya TEXT NOT NULL, surah INTEGER NOT NULL, '
            'last_unlocked_ayah INTEGER NOT NULL, PRIMARY KEY (riwaya, surah))',
          );
        },
      ),
    );
    return AppStore(db);
  }

  Future<AppSettings> loadSettings() async {
    final rows = await _db.query('settings');
    return AppSettings.fromMap({
      for (final r in rows) r['key']! as String: r['value']! as String,
    });
  }

  Future<void> saveSettings(AppSettings s) async {
    final batch = _db.batch();
    for (final e in s.toMap().entries) {
      batch.insert('settings', {
        'key': e.key,
        'value': e.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Highest ayah unlocked (recited successfully) in [surah], 0 if none.
  Future<int> lastUnlocked(Riwaya r, int surah) async {
    final rows = await _db.query(
      'progress',
      where: 'riwaya = ? AND surah = ?',
      whereArgs: [r.id, surah],
    );
    return rows.isEmpty ? 0 : rows.first['last_unlocked_ayah']! as int;
  }

  Future<void> markUnlocked(Riwaya r, int surah, int ayah) async {
    if (ayah <= await lastUnlocked(r, surah)) return;
    await _db.insert('progress', {
      'riwaya': r.id,
      'surah': surah,
      'last_unlocked_ayah': ayah,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> close() => _db.close();
}
