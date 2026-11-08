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

  /// Waqf sign that follows this word, if any (segments re-recitation, docs/SPEC.md §7).
  final String? waqfMark;
}

class Ayah {
  const Ayah({
    required this.ref,
    required this.textUthmani,
    required this.words,
  });

  final AyahRef ref;
  final String textUthmani;
  final List<Word> words;
}
