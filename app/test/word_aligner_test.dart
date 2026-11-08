import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tilawa/data/quran_repository.dart';
import 'package:tilawa/domain/models/riwaya.dart';
import 'package:tilawa/engine/offline/word_aligner.dart';

List<HypWord> h(List<String> ws, {double c = 0.95}) => [
  for (final w in ws) HypWord(w, confidence: c),
];
List<AlignStatus> st(Alignment a) => [for (final w in a.words) w.status];

void main() {
  const aligner = WordAligner();

  group('algorithm (placeholder tokens)', () {
    test('perfect match', () {
      final a = aligner.align(['ab', 'cd', 'ef'], h(['ab', 'cd', 'ef']));
      expect(st(a), everyElement(AlignStatus.correct));
      expect(a.extras, isEmpty);
    });

    test('omission in the middle', () {
      final a = aligner.align(['ab', 'cd', 'ef'], h(['ab', 'ef']));
      expect(st(a), [
        AlignStatus.correct,
        AlignStatus.omitted,
        AlignStatus.correct,
      ]);
    });

    test('substitution by an unrelated word', () {
      final a = aligner.align(['ab', 'cd', 'ef'], h(['ab', 'xy', 'ef']));
      expect(st(a), [
        AlignStatus.correct,
        AlignStatus.substituted,
        AlignStatus.correct,
      ]);
      expect(a.words[1].hyp!.text, 'xy');
    });

    test('added word', () {
      final a = aligner.align(['ab', 'cd'], h(['ab', 'zz', 'cd']));
      expect(st(a), everyElement(AlignStatus.correct));
      expect(a.extras.single.kind, ExtraKind.added);
      expect(a.extras.single.afterExpectedIndex, 0);
    });

    test('repeated word is classified as a repeat, not an addition', () {
      final a = aligner.align(['ab', 'cd', 'ef'], h(['ab', 'cd', 'cd', 'ef']));
      expect(st(a), everyElement(AlignStatus.correct));
      expect(a.extras.single.kind, ExtraKind.repeated);
    });

    test('empty hypothesis: everything omitted', () {
      expect(
        st(aligner.align(['ab', 'cd'], [])),
        everyElement(AlignStatus.omitted),
      );
    });
  });

  group('Arabic keys', () {
    test(
      'long-vowel-only difference is a variant (never an assertive error)',
      () {
        // Same skeleton after removing ا/و/ي/ء: a spelling or reading variant.
        expect(WordAligner.skeleton('بالا'), 'بل');
        final a = aligner.align(['بل'], h(['بال']));
        expect(a.words.single.status, AlignStatus.variant);
      },
    );
  });

  group('real ayahs from the bundled Hafs DB', () {
    late QuranRepository hafs;
    setUpAll(() async {
      sqfliteFfiInit();
      hafs = await QuranRepository.open(
        Riwaya.hafs,
        File('assets/quran/hafs.sqlite').absolute.path,
        databaseFactoryFfi,
      );
    });
    tearDownAll(() => hafs.close());

    Future<List<String>> keys(int s, int a) async => [
      for (final w in (await hafs.ayah(s, a)).words) w.normalized,
    ];

    test('correct recitation of 2:255 aligns fully', () async {
      final k = await keys(2, 255);
      final a = aligner.align(k, h(k));
      expect(st(a), everyElement(AlignStatus.correct));
    });

    test('a dropped word is the only omission', () async {
      final k = await keys(2, 255);
      final heard = [...k]..removeAt(5);
      final a = aligner.align(k, h(heard));
      expect(
        [
          for (final w in a.words)
            if (w.status != AlignStatus.correct) w.expectedIndex,
        ],
        [5],
      );
      expect(a.words[5].status, AlignStatus.omitted);
    });

    test(
      'a word replaced by a word from another ayah is a substitution',
      () async {
        final k = await keys(1, 2);
        final other = (await keys(114, 1)).last; // a real word from elsewhere
        final heard = [...k]..[1] = other;
        final a = aligner.align(k, h(heard));
        expect(a.words[1].status, AlignStatus.substituted);
        expect(st(a).where((s) => s != AlignStatus.correct).length, 1);
      },
    );

    test(
      'reading the next ayah instead leaves the expected words unmatched',
      () async {
        final expected = await keys(1, 2);
        final next = await keys(1, 3);
        final a = aligner.align(expected, h(next));
        expect(st(a).where((s) => s == AlignStatus.correct), isEmpty);
      },
    );
  });
}
