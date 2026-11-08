import 'models/quran.dart';

/// Waqf segments of an ayah (docs/SPEC.md §7): a segment ends after a word that carries a
/// pause sign. Used to restart re-recitation at the segment containing an error.
abstract final class WaqfSegments {
  /// Index of the first word of the segment that contains [wordIndex].
  static int startOf(List<Word> words, int wordIndex) {
    var start = 0;
    for (final w in words) {
      if (w.index >= wordIndex) break;
      if (w.waqfMark != null && w.waqfMark!.isNotEmpty) start = w.index + 1;
    }
    return start;
  }
}
