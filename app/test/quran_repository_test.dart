import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tilawa/core/arabic/normalizer.dart';
import 'package:tilawa/data/quran_repository.dart';
import 'package:tilawa/domain/models/riwaya.dart';

/// Integrity tests on the committed Hafs DB (docs/SPEC.md §3, §10 Phase 2).
// sqflite resolves relative paths against its own DB directory, so use an absolute one.
final _hafsDb = File('assets/quran/hafs.sqlite').absolute.path;

void main() {
  late QuranRepository hafs;

  setUpAll(() async {
    sqfliteFfiInit();
    hafs = await QuranRepository.open(Riwaya.hafs, _hafsDb, databaseFactoryFfi);
  });
  tearDownAll(() => hafs.close());

  test('114 surahs whose ayah counts add up to the source total', () async {
    final surahs = await hafs.surahs();
    final info = await hafs.sourceInfo();
    expect(surahs.map((s) => s.number), List.generate(114, (i) => i + 1));
    expect(surahs.fold<int>(0, (n, s) => n + s.ayahCount), info.ayahCount);
    expect(info.ayahCount, 6236); // Kufan count, from Tanzil's own metadata
  });

  test('every ayah of every surah loads with words', () async {
    for (final s in await hafs.surahs()) {
      for (var a = 1; a <= s.ayahCount; a++) {
        final ayah = await hafs.ayah(s.number, a);
        expect(ayah.words, isNotEmpty, reason: '${s.number}:$a');
      }
    }
  });

  test('attribution required by the Tanzil terms is present', () async {
    final info = await hafs.sourceInfo();
    expect(info.source, 'Tanzil Project');
    expect(info.copyrightNotice, contains('CHANGING IT IS NOT ALLOWED'));
    expect(info.copyrightNotice, contains('tanzil.net'));
  });

  test('basmala: ayah in Al-Fatiha, prefix (not words) elsewhere', () async {
    final f1 = await hafs.ayah(1, 1);
    expect(f1.basmalaPrefixChars, 0);
    expect(f1.words.length, 4);
    final n1 = await hafs.ayah(114, 1);
    expect(n1.basmalaPrefixChars, greaterThan(0));
    expect(n1.words.first.normalized, 'قل');
    expect((await hafs.ayah(9, 1)).basmalaPrefixChars, 0);
  });

  test('words are verbatim substrings, in order', () async {
    for (final ref in [(1, 7), (2, 255), (36, 52), (114, 6)]) {
      final a = await hafs.ayah(ref.$1, ref.$2);
      var from = a.basmalaPrefixChars;
      for (final w in a.words) {
        final at = a.textUthmani.indexOf(w.uthmani, from);
        expect(at, greaterThanOrEqualTo(from), reason: '$ref ${w.uthmani}');
        from = at + w.uthmani.length;
      }
    }
  });

  test('Dart normalizer agrees with the build on all 77k words', () async {
    final keys = await hafs.allWordKeys();
    expect(keys.length, greaterThan(70000));
    final mismatches = [
      for (final (u, n) in keys)
        if (ArabicNormalizer.normalize(u) != n) u,
    ];
    expect(mismatches, isEmpty);
  });

  test('opening a DB as the wrong riwaya fails', () async {
    expect(
      () => QuranRepository.open(Riwaya.warsh, _hafsDb, databaseFactoryFfi),
      throwsStateError,
    );
  });
}
