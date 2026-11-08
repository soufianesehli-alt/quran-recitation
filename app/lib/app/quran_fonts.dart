import '../domain/models/riwaya.dart';

/// Font used to display each riwaya's Quran text (docs/DATA_SOURCES.md §2, §6.3).
abstract final class QuranFonts {
  /// Amiri Quran (SIL OFL 1.1): approved fallback for the Tanzil Hafs text.
  static const amiriQuran = 'AmiriQuran';

  /// Returns the font family for [riwaya], or null when no font is bundled yet.
  ///
  /// Warsh text is in the KFGQPC font encoding and must only be shown with the KFGQPC Warsh
  /// font. Rendering it with any other font can misplace or drop marks, so there is no
  /// fallback for Warsh.
  static String? familyFor(Riwaya riwaya) => switch (riwaya) {
    Riwaya.hafs => amiriQuran,
    Riwaya.warsh => null,
  };
}
