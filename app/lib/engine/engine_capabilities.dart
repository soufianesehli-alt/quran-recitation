import '../domain/models/riwaya.dart';

/// Families of checks an engine can run. The UI only shows results for supported families.
enum RuleFamily {
  words, // omission, addition, substitution, repetition, skipped ayah
  madd,
  ghunnah,
  qalqalah,
  waqf,
  makharij, // V2 online only
  sifat, // V2 online only (tafkhim/tarqiq, taqlil/imala, ...)
}

class EngineCapabilities {
  const EngineCapabilities({
    required this.families,
    required this.usesNetwork,
    required this.acousticallyValidated,
  });

  final Set<RuleFamily> families;

  /// Must be false for every engine that ships in V1.
  final bool usesNetwork;

  /// Riwayat whose acoustic results come from a model trained on that riwaya.
  /// Acoustic findings for any other riwaya are downgraded to needsReview (docs/SPEC.md §2).
  final Set<Riwaya> acousticallyValidated;

  bool supports(RuleFamily f) => families.contains(f);
}
