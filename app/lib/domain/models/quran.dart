import 'riwaya.dart';

/// Reference to one ayah *in a given riwaya's numbering*.
class AyahRef {
  const AyahRef({required this.riwaya, required this.surah, required this.ayah})
    : assert(surah >= 1 && surah <= 114),
      assert(ayah >= 1);

  final Riwaya riwaya;
  final int surah;
  final int ayah;

  @override
  bool operator ==(Object other) =>
      other is AyahRef &&
      other.riwaya == riwaya &&
      other.surah == surah &&
      other.ayah == ayah;

  @override
  int get hashCode => Object.hash(riwaya, surah, ayah);

  @override
  String toString() => '${riwaya.id}:$surah:$ayah';
}

class Surah {
  const Surah({
    required this.number,
    required this.nameAr,
    required this.ayahCount,
  });

  final int number;
  final String nameAr;

  /// Ayah count in the riwaya this object was loaded for.
  final int ayahCount;
}

/// One word of the expected text, as stored in the per-riwaya SQLite DB (docs/SPEC.md §3).
class Word {
  const Word({
    required this.index,
    required this.uthmani,
    required this.normalized,
    this.waqfMark,
  });

  /// 0-based position in the ayah.
  final int index;

  /// Display text, exactly as in the source (never modified).
  final String uthmani;

  /// Matching key produced by the Arabic normalizer. Never shown to the user.
  final String normalized;

  /// Pause sign(s) after this word, in source order (may hold several, e.g. sakta + pause
  /// at Hafs 36:52). Segments re-recitation (docs/SPEC.md §7).
  final String? waqfMark;
}

class Ayah {
  const Ayah({
    required this.ref,
    required this.textUthmani,
    required this.words,
    this.basmalaPrefixChars = 0,
  });

  final AyahRef ref;

  /// Verbatim source text. For Tanzil this includes the basmala prefix of ayah 1.
  final String textUthmani;

  /// The ayah's own words (the basmala prefix is excluded).
  final List<Word> words;

  /// Length of the basmala prefix in [textUthmani], 0 if none.
  final int basmalaPrefixChars;
}
