import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa/domain/ayah_gate.dart';
import 'package:tilawa/domain/models/finding.dart';
import 'package:tilawa/domain/models/quran.dart';
import 'package:tilawa/engine/offline/word_aligner.dart';
import 'package:tilawa/engine/offline/word_findings.dart';

// Placeholder words (not Quran text): the builder only cares about structure.
const words = [
  Word(index: 0, uthmani: 'ab', normalized: 'ab'),
  Word(index: 1, uthmani: 'cd', normalized: 'cd'),
  Word(index: 2, uthmani: 'ef', normalized: 'ef'),
];
List<String> get keys => [for (final w in words) w.normalized];
List<HypWord> h(List<String> ws, double c) => [
  for (final w in ws) HypWord(w, confidence: c),
];

void main() {
  const aligner = WordAligner();
  const gate = AyahGate();

  test(
    'confident substitution is an error but does not block before Phase 5',
    () {
      final f = const WordFindingBuilder().build(
        words,
        aligner.align(keys, h(['ab', 'xy', 'ef'], 0.97)),
      );
      expect(f.single.ruleId, 'word.substitution');
      expect(f.single.severity, Severity.error);
      expect(f.single.ruleIsBlocking, isFalse);
      expect(gate.canAdvance(f), isTrue);
    },
  );

  test('low-confidence substitution is needsReview', () {
    final f = const WordFindingBuilder().build(
      words,
      aligner.align(keys, h(['ab', 'xy', 'ef'], 0.6)),
    );
    expect(f.single.severity, Severity.needsReview);
  });

  test('dev blocking switch makes a confident error block the gate', () {
    const b = WordFindingBuilder(devTreatWordRulesAsBlocking: true);
    final f = b.build(words, aligner.align(keys, h(['ab', 'xy', 'ef'], 0.97)));
    expect(gate.canAdvance(f), isFalse);
  });

  test('even with the dev switch, needsReview and repetitions never block', () {
    const b = WordFindingBuilder(devTreatWordRulesAsBlocking: true);
    final low = b.build(words, aligner.align(keys, h(['ab', 'xy', 'ef'], 0.5)));
    final rep = b.build(
      words,
      aligner.align(keys, h(['ab', 'cd', 'cd', 'ef'], 0.99)),
    );
    expect(rep.single.ruleId, 'word.repetition');
    expect(rep.single.severity, Severity.info);
    expect(gate.canAdvance([...low, ...rep]), isTrue);
  });

  test('omission confidence comes from the surrounding words', () {
    final f = const WordFindingBuilder().build(
      words,
      aligner.align(keys, h(['ab', 'ef'], 0.95)),
    );
    expect(f.single.ruleId, 'word.omission');
    expect(f.single.confidence, 0.95);
    final none = const WordFindingBuilder().build(
      words,
      aligner.align(keys, []),
    );
    expect(none.every((x) => x.severity == Severity.needsReview), isTrue);
  });

  test('every user-facing message is Arabic', () {
    final f = const WordFindingBuilder().build(
      words,
      aligner.align(keys, h(['zz', 'cd', 'ef', 'yy'], 0.99)),
    );
    for (final x in f) {
      expect(RegExp(r'[؀-ۿ]').hasMatch(x.messageAr), isTrue);
      expect(RegExp(r'[؀-ۿ]').hasMatch(x.ruleNameAr), isTrue);
    }
  });
}
