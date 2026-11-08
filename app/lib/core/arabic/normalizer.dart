/// Arabic matching normalizer: runtime twin of tools/quran_db/normalizer.py.
///
/// Produces a MATCHING KEY only. It is never displayed and never replaces source text.
/// Both implementations are tested against tools/normalizer_vectors.json, and the Dart one is
/// also checked against every `words.normalized` value in the bundled DB.
/// See the Python file for the rule list; any change must be made in both files.
abstract final class ArabicNormalizer {
  static const _removeRanges = <(int, int)>[
    (0x064B, 0x065F),
    (0x0670, 0x0670),
    (0x06D6, 0x06ED),
    (0x08D3, 0x08FF),
    (0x0640, 0x0640),
    (0x200B, 0x200F),
    (0xFEFF, 0xFEFF),
  ];

  static const _map = <int, int>{
    0x0622: 0x0627,
    0x0623: 0x0627,
    0x0625: 0x0627,
    0x0671: 0x0627,
    0x0672: 0x0627,
    0x0673: 0x0627, // alef forms -> ا
    0x0649: 0x064A, 0x06D2: 0x064A, 0x06CC: 0x064A, // ى ے ی -> ي
    0x0624: 0x0648, // ؤ -> و
    0x0626: 0x064A, // ئ -> ي
    0x0629: 0x0647, // ة -> ه
    0x06A9: 0x0643, // ک -> ك
  };

  static bool _removed(int cp) {
    for (final (lo, hi) in _removeRanges) {
      if (cp >= lo && cp <= hi) return true;
    }
    return false;
  }

  /// Arabic base letters ء..ي (U+0621..U+064A) minus tatweel and the letters folded by [_map].
  static bool _allowed(int cp) =>
      cp >= 0x0621 && cp <= 0x064A && cp != 0x0640 && !_map.containsKey(cp);

  static String normalize(String text) {
    final out = StringBuffer();
    for (final rune in text.runes) {
      if (_removed(rune)) continue;
      final cp = _map[rune] ?? rune;
      if (_allowed(cp)) out.writeCharCode(cp);
    }
    return out.toString();
  }
}
