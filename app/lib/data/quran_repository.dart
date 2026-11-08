import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models/quran.dart';
import '../domain/models/riwaya.dart';

/// Provenance of a bundled Quran DB, shown on the attribution screen.
class QuranSourceInfo {
  const QuranSourceInfo({
    required this.source,
    required this.sourceUrl,
    required this.version,
    required this.license,
    required this.copyrightNotice,
    required this.ayahCount,
  });

  final String source;
  final String sourceUrl;
  final String version;
  final String license;
  final String copyrightNotice;
  final int ayahCount;
}

/// Read-only access to one riwaya's Quran DB (built by tools/build_quran_db.py).
class QuranRepository {
  QuranRepository(this._db, this.riwaya);

  static const supportedSchemaVersion = 1;

  final Database _db;
  final Riwaya riwaya;

  static String assetPath(Riwaya r) => 'assets/quran/${r.id}.sqlite';

  /// Copies the bundled asset to the app's database directory (sqflite cannot open assets
  /// in place) and opens it read-only. This is Quran text only, never audio.
  static Future<QuranRepository> openBundled(Riwaya riwaya) async {
    final ByteData data;
    try {
      data = await rootBundle.load(assetPath(riwaya));
    } on FlutterError {
      throw StateError(
        'Quran DB for ${riwaya.id} is not bundled yet (docs/DATA_SOURCES.md)',
      );
    }
    final target = File(
      p.join(await getDatabasesPath(), '${riwaya.id}.sqlite'),
    );
    if (!await target.exists() || await target.length() != data.lengthInBytes) {
      await target.parent.create(recursive: true);
      await target.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return open(riwaya, target.path, databaseFactory);
  }

  /// Opens a DB file directly (tests, tools).
  static Future<QuranRepository> open(
    Riwaya riwaya,
    String path,
    DatabaseFactory factory,
  ) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    final repo = QuranRepository(db, riwaya);
    final meta = await repo._meta();
    if (meta['riwaya'] != riwaya.id) {
      await db.close();
      throw StateError(
        'DB at $path is for ${meta['riwaya']}, expected ${riwaya.id}',
      );
    }
    if (int.parse(meta['schema_version']!) != supportedSchemaVersion) {
      await db.close();
      throw StateError('Unsupported Quran DB schema ${meta['schema_version']}');
    }
    return repo;
  }

  Future<Map<String, String>> _meta() async {
    final rows = await _db.query('meta');
    return {for (final r in rows) r['key']! as String: r['value']! as String};
  }

  Future<QuranSourceInfo> sourceInfo() async {
    final m = await _meta();
    return QuranSourceInfo(
      source: m['source']!,
      sourceUrl: m['source_url']!,
      version: m['version']!,
      license: m['license']!,
      copyrightNotice: m['copyright_notice']!,
      ayahCount: int.parse(m['count_ayahs']!),
    );
  }

  Future<List<Surah>> surahs() async {
    final rows = await _db.query('surahs', orderBy: 'surah');
    return [
      for (final r in rows)
        Surah(
          number: r['surah']! as int,
          nameAr: r['name_ar']! as String,
          ayahCount: r['ayah_count']! as int,
        ),
    ];
  }

  Future<Ayah> ayah(int surah, int ayah) async {
    final a = await _db.query(
      'ayahs',
      where: 'surah = ? AND ayah = ?',
      whereArgs: [surah, ayah],
    );
    if (a.isEmpty) throw RangeError('No ayah $surah:$ayah in ${riwaya.id}');
    final w = await _db.query(
      'words',
      where: 'surah = ? AND ayah = ?',
      whereArgs: [surah, ayah],
      orderBy: 'word_index',
    );
    return Ayah(
      ref: AyahRef(riwaya: riwaya, surah: surah, ayah: ayah),
      textUthmani: a.first['text_uthmani']! as String,
      basmalaPrefixChars: a.first['basmala_prefix_chars']! as int,
      words: [
        for (final r in w)
          Word(
            index: r['word_index']! as int,
            uthmani: r['uthmani']! as String,
            normalized: r['normalized']! as String,
            waqfMark: r['waqf_mark'] as String?,
          ),
      ],
    );
  }

  /// All (uthmani, normalized) pairs: used by tests to check normalizer parity.
  Future<List<(String, String)>> allWordKeys() async {
    final rows = await _db.query('words', columns: ['uthmani', 'normalized']);
    return [
      for (final r in rows)
        (r['uthmani']! as String, r['normalized']! as String),
    ];
  }

  Future<void> close() => _db.close();
}
