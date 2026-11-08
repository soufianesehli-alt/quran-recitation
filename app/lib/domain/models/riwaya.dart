/// A supported riwaya. Text, ayah numbering, phonetizer and rules all depend on it.
enum Riwaya {
  /// Hafs ʿan ʿĀṣim. Kufan ayah count.
  hafs(id: 'hafs', nameAr: 'حفص عن عاصم', numbering: AyahNumbering.kufan),

  /// Warsh ʿan Nāfiʿ, Azraq route. Madani ayah count
  /// (TODO-VERIFY: Madani I vs Madani II, against the chosen Warsh text source in Phase 2).
  warsh(id: 'warsh', nameAr: 'ورش عن نافع', numbering: AyahNumbering.madani);

  const Riwaya({
    required this.id,
    required this.nameAr,
    required this.numbering,
  });

  /// Stable identifier, also used by the backend `/check` endpoint (`riwaya` field).
  final String id;
  final String nameAr;
  final AyahNumbering numbering;

  static Riwaya fromId(String id) => values.firstWhere(
    (r) => r.id == id,
    orElse: () => throw ArgumentError.value(id, 'id'),
  );
}

/// Ayah counting system. The same `surah:ayah` key can point at different text under
/// different systems, so an [AyahRef] always carries its riwaya.
enum AyahNumbering { kufan, madani }
