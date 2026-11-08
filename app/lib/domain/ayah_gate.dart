import 'models/finding.dart';

/// Ayah gating policy (docs/SPEC.md §7): the next ayah unlocks only when there is no
/// high-confidence blocking error. `needsReview` findings never block.
class AyahGate {
  const AyahGate({
    this.highConfidenceThreshold = 0.9,
    this.maxAttemptsPerWord = 3,
  }) : assert(maxAttemptsPerWord >= 1);

  final double highConfidenceThreshold;

  /// After this many failed attempts on the same word, the user may continue anyway.
  final int maxAttemptsPerWord;

  bool canAdvance(Iterable<Finding> findings) =>
      !findings.any((f) => f.blocksAt(highConfidenceThreshold));

  bool offerContinueAnyway(int failedAttemptsOnWord) =>
      failedAttemptsOnWord >= maxAttemptsPerWord;
}
