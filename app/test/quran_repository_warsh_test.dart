import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tilawa/core/arabic/normalizer.dart';
import 'package:tilawa/data/quran_repository.dart';
import 'package:tilawa/domain/models/riwaya.dart';

/// Integrity tests on the committed Warsh DB (KFGQPC Uthmanic Warsh data v2.1).
final _warshDb = File('assets/quran/warsh.sqlite').absolute.path;
final _hafsDb = File('assets/quran/hafs.sqlite').absolute.path;

void main() {
  late QuranRepository warsh;

  setUpAll(() async {
    sqfliteFfiInit();
    warsh = await QuranRepository.open(
      Riwaya.warsh,
      _warshDb,
      databaseFactoryFfi,
    );
  });
  tearDownAll(() => warsh.close());

  test('114 surahs, Madani count from the source', () async {
    final surahs = await warsh.surahs();
    final info = await warsh.sourceInfo();
    expect(surahs.map((s) => s.number), List.generate(114, (i) => i + 1));
    expect(surahs.fold<int>(0, (n, s) => n + s.ayahCount), info.ayahCount);
    expect(info.ayahCount, 6214);
    expect(info.source, contains('KFGQPC'));
  });

  test('every ayah loads with words and no basmala prefix', () async {
    for (final s in await warsh.surahs()) {
      for (var a = 1; a <= s.ayahCount; a++) {
        final ayah = await warsh.ayah(s.number, a);
        expect(ayah.words, isNotEmpty, reason: '${s.number}:$a');
        expect(ayah.basmalaPrefixChars, 0);
      }
    }
  });

  test('Hafs and Warsh number ayahs differently', () async {
    final hafs = await QuranRepository.open(
      Riwaya.hafs,
      _hafsDb,
      databaseFactoryFfi,
    );
    addTearDown(hafs.close);
    final h = await hafs.surahs();
    final w = await warsh.surahs();
    expect(h[0].ayahCount, w[0].ayahCount); // Al-Fatiha: 7 in both counts
    expect(h[1].ayahCount, isNot(w[1].ayahCount)); // Al-Baqarah differs
    // Ayah 1:1 is the basmala in Hafs but not in Warsh.
    expect((await hafs.ayah(1, 1)).words.first.normalized, 'بسم');
    expect((await warsh.ayah(1, 1)).words.first.normalized, 'الحمد');
  });

  test('Dart normalizer agrees with the build on every Warsh word', () async {
    final keys = await warsh.allWordKeys();
    expect(keys.length, greaterThan(70000));
    final mismatches = [
      for (final (u, n) in keys)
        if (ArabicNormalizer.normalize(u) != n) u,
    ];
    expect(mismatches, isEmpty);
  });
}
