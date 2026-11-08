/// What kind of deviation a [Finding] reports.
enum ErrorType {
  // Word level (V1, may block once validated).
  omission,
  addition,
  substitution,
  repetition,
  skippedAyah,
  // Tajweed (V1: warning-only until precision >= 90%, docs/SPEC.md §8).
  madd,
  ghunnah,
  qalqalah,
  waqf,
}

/// How a finding is presented. Only [error] can ever block the next ayah.
enum Severity {
  /// Confident error. Red. Blocks only if the rule is validated as blocking.
  error,

  /// Uncertain. Orange, "مراجعة". NEVER blocks (docs/SPEC.md §0.5, §7).
  needsReview,

  /// Informational note.
  info,
}

/// A single correction shown to the user (docs/SPEC.md §5, step 6).
class Finding {
  const Finding({
    required this.wordIndex,
    required this.word,
    required this.errorType,
    required this.ruleId,
    required this.ruleNameAr,
    required this.severity,
    required this.confidence,
    required this.messageAr,
    required this.ruleIsBlocking,
    this.expected,
    this.observed,
    this.startMs,
    this.endMs,
  }) : assert(confidence >= 0 && confidence <= 1);

  final int wordIndex;
  final String word;
  final ErrorType errorType;
  final String ruleId;
  final String ruleNameAr;
  final String? expected;
  final String? observed;
  final Severity severity;

  /// Engine confidence in [0, 1].
  final double confidence;
  final int? startMs;
  final int? endMs;
  final String messageAr;

  /// Copied from the rule definition: `blocking: true` only after the rule passed the
  /// precision gate for this riwaya (docs/SPEC.md §8).
  final bool ruleIsBlocking;

  /// True when this finding must prevent moving to the next ayah.
  bool blocksAt(double highConfidenceThreshold) =>
      severity == Severity.error &&
      ruleIsBlocking &&
      confidence >= highConfidenceThreshold;
}
