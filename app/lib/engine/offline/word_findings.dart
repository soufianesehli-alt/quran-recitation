import '../../domain/models/finding.dart';
import '../../domain/models/quran.dart';
import 'word_aligner.dart';

/// Word-level rules (docs/SPEC.md §2). `blocking` stays false for every rule until its
/// precision is measured >= 90% on the eval set (docs/SPEC.md §8, Phase 5).
class WordRule {
  const WordRule(this.id, this.nameAr, this.type, {this.blocking = false});

  final String id;
  final String nameAr;
  final ErrorType type;
  final bool blocking;
}

abstract final class WordRules {
  static const omission = WordRule(
    'word.omission',
    'إسقاط كلمة',
    ErrorType.omission,
  );
  static const substitution = WordRule(
    'word.substitution',
    'إبدال كلمة',
    ErrorType.substitution,
  );
  static const addition = WordRule(
    'word.addition',
    'زيادة كلمة',
    ErrorType.addition,
  );
  static const repetition = WordRule(
    'word.repetition',
    'تكرار كلمة',
    ErrorType.repetition,
  );
  static const variant = WordRule(
    'word.variant',
    'اختلاف محتمل في الكلمة',
    ErrorType.substitution,
  );
  static const skippedAyah = WordRule(
    'word.skipped_ayah',
    'تجاوز آية',
    ErrorType.skippedAyah,
  );
}

/// Turns an [Alignment] into user-facing [Finding]s.
///
/// Policy (docs/SPEC.md §0.5): low confidence => needsReview; a long-vowel/hamza-only
/// difference => needsReview; a repetition => info. Nothing here is ever more assertive.
class WordFindingBuilder {
  const WordFindingBuilder({
    this.highConfidence = 0.9,
    this.devTreatWordRulesAsBlocking = false,
  });

  final double highConfidence;

  /// DEV BUILDS ONLY: lets testers see gating before the Phase 5 precision gate.
  final bool devTreatWordRulesAsBlocking;

  List<Finding> build(List<Word> expected, Alignment alignment) {
    final out = <Finding>[];
    for (final aw in alignment.words) {
      final word = expected[aw.expectedIndex];
      switch (aw.status) {
        case AlignStatus.correct:
          break;
        case AlignStatus.variant:
          out.add(
            _finding(
              WordRules.variant,
              word,
              confidence: aw.hyp!.confidence,
              forceSeverity: Severity.needsReview,
              observed: aw.hyp!.text,
              hyp: aw.hyp,
              messageAr:
                  'قد تكون الكلمة قُرئت بلفظ مختلف. استمع إلى نفسك وراجعها.',
            ),
          );
        case AlignStatus.substituted:
          // Recogniser mistakes are typically near-misses (a letter or two) that still get
          // high token probability, so only a clearly different word may be an error.
          final near = isNearMiss(word.normalized, aw.hyp!.text);
          out.add(
            _finding(
              WordRules.substitution,
              word,
              confidence: aw.hyp!.confidence,
              forceSeverity: near ? Severity.needsReview : null,
              observed: aw.hyp!.text,
              hyp: aw.hyp,
              messageAr: near
                  ? 'قد تكون «${word.uthmani}» قُرئت بشكل غير دقيق. راجعها.'
                  : 'قُرئت كلمة أخرى مكان «${word.uthmani}».',
            ),
          );
        case AlignStatus.omitted:
          out.add(
            _finding(
              WordRules.omission,
              word,
              confidence: _contextConfidence(alignment, aw.expectedIndex),
              messageAr: 'لم تُسمع كلمة «${word.uthmani}».',
            ),
          );
      }
    }
    for (final ex in alignment.extras) {
      final anchor = ex.afterExpectedIndex.clamp(0, expected.length - 1);
      final word = expected[anchor];
      if (ex.kind == ExtraKind.repeated) {
        out.add(
          _finding(
            WordRules.repetition,
            word,
            confidence: ex.hyp.confidence,
            forceSeverity: Severity.info,
            observed: ex.hyp.text,
            hyp: ex.hyp,
            messageAr: 'كُرّرت كلمة. لا بأس إن كان ذلك لتصحيح القراءة.',
          ),
        );
      } else {
        out.add(
          _finding(
            WordRules.addition,
            word,
            confidence: ex.hyp.confidence,
            observed: ex.hyp.text,
            hyp: ex.hyp,
            messageAr: 'سُمعت كلمة زائدة بعد «${word.uthmani}».',
          ),
        );
      }
    }
    return out;
  }

  /// Finding for "the reciter read the following ayah instead of this one".
  Finding skippedAyah(Ayah expected, double confidence) => _finding(
    WordRules.skippedAyah,
    expected.words.first,
    confidence: confidence,
    messageAr: 'يبدو أنك انتقلت إلى الآية التالية قبل قراءة هذه الآية.',
  );

  Finding _finding(
    WordRule rule,
    Word word, {
    required double confidence,
    required String messageAr,
    Severity? forceSeverity,
    String? observed,
    HypWord? hyp,
  }) {
    final severity =
        forceSeverity ??
        (confidence >= highConfidence ? Severity.error : Severity.needsReview);
    return Finding(
      wordIndex: word.index,
      word: word.uthmani,
      errorType: rule.type,
      ruleId: rule.id,
      ruleNameAr: rule.nameAr,
      expected: word.uthmani,
      observed: observed,
      severity: severity,
      confidence: confidence,
      startMs: hyp?.startMs,
      endMs: hyp?.endMs,
      messageAr: messageAr,
      ruleIsBlocking: rule.blocking || devTreatWordRulesAsBlocking,
    );
  }

  /// True when [heard] differs from [expected] in at most half of the letters (normalised
  /// edit distance <= 0.5): such a difference may be the recogniser's, not the reciter's.
  static bool isNearMiss(String expected, String heard) =>
      WordAligner.substitutionCost(expected, heard) <= 0.75;

  /// Confidence that a word was really skipped: the recogniser must be confident about the
  /// words around the gap; with no neighbours we stay uncertain.
  static double _contextConfidence(Alignment a, int index) {
    final around = [
      for (final w in a.words)
        if ((w.expectedIndex - index).abs() <= 2 && w.hyp != null)
          w.hyp!.confidence,
    ];
    if (around.isEmpty) return 0.5;
    return around.reduce((x, y) => x < y ? x : y);
  }
}
