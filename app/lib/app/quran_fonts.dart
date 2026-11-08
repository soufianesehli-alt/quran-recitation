import '../domain/models/riwaya.dart';

/// Font used to display each riwaya's Quran text (docs/DATA_SOURCES.md §2, §6.3).
abstract final class QuranFonts {
  /// Amiri Quran (SIL OFL 1.1): approved fallback for the Tanzil Hafs text.
  static const amiriQuran = 'AmiriQuran';

  /// Official KFGQPC Uthmanic Warsh font v2.1. The KFGQPC Warsh text is encoded for this font
  /// (e.g. ayah-end markers are font-specific glyphs), so no other font may display it.
  static const kfgqpcWarsh = 'KfgqpcWarsh';

  /// Font family for [riwaya]. Warsh never falls back to another font.
  static String familyFor(Riwaya riwaya) => switch (riwaya) {
    Riwaya.hafs => amiriQuran,
    Riwaya.warsh => kfgqpcWarsh,
  };
}
