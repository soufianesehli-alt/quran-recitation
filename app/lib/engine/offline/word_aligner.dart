import 'dart:math' as math;

import '../../core/arabic/normalizer.dart';

/// One recognised word from the ASR (already normalised with [ArabicNormalizer]).
class HypWord {
  const HypWord(this.text, {this.confidence = 1.0, this.startMs, this.endMs})
    : assert(confidence >= 0 && confidence <= 1);

  final String text;

  /// Recogniser confidence in [0, 1] (e.g. mean token probability).
  final double confidence;
  final int? startMs;
  final int? endMs;
}

/// How an expected word was recited.
enum AlignStatus {
  /// Same normalised key.
  correct,

  /// Same consonant skeleton, different long-vowel letters (ا و ي ء). Text alone cannot tell a
  /// recognition spelling variant from a real reading difference, so this is never an error.
  variant,

  /// A different word was read in its place.
  substituted,

  /// Not heard.
  omitted,
}

/// What happened to an extra recognised word that matches no expected word.
enum ExtraKind {
  /// Equal to an expected word just read (reciter going back): informational only.
  repeated,

  /// Anything else.
  added,
}

class AlignedWord {
  const AlignedWord(this.expectedIndex, this.status, {this.hyp});

  final int expectedIndex;
  final AlignStatus status;

  /// The recognised word aligned to it (null when omitted).
  final HypWord? hyp;
}

class ExtraWord {
  const ExtraWord(this.hyp, this.kind, {required this.afterExpectedIndex});

  final HypWord hyp;
  final ExtraKind kind;

  /// Index of the expected word this extra word follows (-1 = before the first word).
  final int afterExpectedIndex;
}

class Alignment {
  const Alignment(this.words, this.extras);

  /// One entry per expected word, in order.
  final List<AlignedWord> words;
  final List<ExtraWord> extras;
}

/// Global word alignment (Needleman-Wunsch) of a recognised hypothesis against the expected
/// words of an ayah or segment (docs/SPEC.md §5 step 4).
class WordAligner {
  const WordAligner({this.gapCost = 1.0});

  final double gapCost;

  static const _longVowels = {'ا', 'و', 'ي', 'ء'};

  /// Normalised key with long-vowel letters and hamza removed.
  static String skeleton(String key) =>
      key.split('').where((c) => !_longVowels.contains(c)).join();

  /// Cost of aligning [expected] with [heard], in [0, 1]. Keys are already normalised.
  static double substitutionCost(String expected, String heard) {
    if (expected == heard) return 0;
    if (skeleton(expected) == skeleton(heard) &&
        skeleton(expected).isNotEmpty) {
      return 0.3;
    }
    final d =
        _levenshtein(expected, heard) / math.max(expected.length, heard.length);
    return 0.5 + 0.5 * d;
  }

  static AlignStatus _statusFor(String expected, String heard) {
    if (expected == heard) return AlignStatus.correct;
    if (skeleton(expected) == skeleton(heard) &&
        skeleton(expected).isNotEmpty) {
      return AlignStatus.variant;
    }
    return AlignStatus.substituted;
  }

  Alignment align(List<String> expected, List<HypWord> hyp) {
    final n = expected.length, m = hyp.length;
    // dp[i][j] = cost of aligning expected[0..i) with hyp[0..j).
    final dp = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
    for (var i = 1; i <= n; i++) {
      dp[i][0] = i * gapCost;
    }
    for (var j = 1; j <= m; j++) {
      dp[0][j] = j * gapCost;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        // Substitutions costlier than an omission + insertion pair are never chosen.
        final sub =
            dp[i - 1][j - 1] +
            substitutionCost(expected[i - 1], hyp[j - 1].text);
        final del = dp[i - 1][j] + gapCost;
        final ins = dp[i][j - 1] + gapCost;
        dp[i][j] = math.min(sub, math.min(del, ins));
      }
    }

    // Trace back. Ties prefer diagonal, then omission, then insertion (deterministic).
    final words = <AlignedWord>[];
    final extrasRev = <(int, HypWord)>[];
    var i = n, j = m;
    while (i > 0 || j > 0) {
      if (i > 0 &&
          j > 0 &&
          _eq(
            dp[i][j],
            dp[i - 1][j - 1] +
                substitutionCost(expected[i - 1], hyp[j - 1].text),
          )) {
        words.add(
          AlignedWord(
            i - 1,
            _statusFor(expected[i - 1], hyp[j - 1].text),
            hyp: hyp[j - 1],
          ),
        );
        i--;
        j--;
      } else if (i > 0 && _eq(dp[i][j], dp[i - 1][j] + gapCost)) {
        words.add(AlignedWord(i - 1, AlignStatus.omitted));
        i--;
      } else {
        extrasRev.add((i - 1, hyp[j - 1]));
        j--;
      }
    }
    final ordered = words.reversed.toList();

    final extras = <ExtraWord>[];
    for (final (after, h) in extrasRev.reversed) {
      // A repeat equals one of the (up to 3) expected words just before this point.
      final recent = [
        for (var k = after; k >= 0 && k > after - 3; k--) expected[k],
        if (after + 1 < n)
          expected[after + 1], // re-reading the next word twice
      ];
      final kind = recent.contains(h.text)
          ? ExtraKind.repeated
          : ExtraKind.added;
      extras.add(ExtraWord(h, kind, afterExpectedIndex: after));
    }
    return Alignment(ordered, extras);
  }

  /// Convenience: normalises raw recogniser text and splits it into words.
  static List<HypWord> wordsFromText(String text, {double confidence = 1.0}) =>
      [
        for (final w in text.split(RegExp(r'\s+')))
          if (ArabicNormalizer.normalize(w).isNotEmpty)
            HypWord(ArabicNormalizer.normalize(w), confidence: confidence),
      ];

  static bool _eq(double a, double b) => (a - b).abs() < 1e-9;

  static int _levenshtein(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (k) => k);
    for (var x = 1; x <= a.length; x++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = x;
      for (var y = 1; y <= b.length; y++) {
        final c = a[x - 1] == b[y - 1] ? 0 : 1;
        cur[y] = math.min(
          math.min(cur[y - 1] + 1, prev[y] + 1),
          prev[y - 1] + c,
        );
      }
      prev = cur;
    }
    return prev[b.length];
  }
}
