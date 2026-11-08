import 'dart:convert';
import 'dart:typed_data';

import 'word_aligner.dart';

/// One decoded sub-word token from the recogniser.
class AsrToken {
  const AsrToken(this.bytes, this.p, this.t0Ms, this.t1Ms);

  /// Raw UTF-8 bytes (a token may hold only part of an Arabic letter's encoding).
  final Uint8List bytes;
  final double p;
  final int t0Ms;
  final int t1Ms;
}

/// Speech recogniser contract used by the offline engine (docs/ARCHITECTURE.md §4.1).
/// Implementations must keep audio in memory only.
abstract class AsrBackend {
  Future<void> load(String modelPath);

  /// Transcribes 16 kHz mono PCM16 [samples], biased towards [prompt] (the expected text).
  /// Returned word times are relative to the start of [samples].
  Future<List<HypWord>> transcribe(Int16List samples, {String? prompt});

  Future<void> dispose();
}

/// Groups BPE tokens into words: a token whose bytes start with a space opens a new word.
/// Word confidence = mean token probability; times = first t0 .. last t1.
List<HypWord> groupTokensIntoWords(List<AsrToken> tokens, {int offsetMs = 0}) {
  final words = <HypWord>[];
  var buf = <int>[];
  var probs = <double>[];
  int? t0;
  var t1 = 0;

  void flush() {
    if (buf.isEmpty) return;
    final text = utf8.decode(buf, allowMalformed: true).trim();
    final keys = WordAligner.wordsFromText(text);
    if (keys.isNotEmpty) {
      final conf = probs.reduce((a, b) => a + b) / probs.length;
      for (final k in keys) {
        words.add(
          HypWord(
            k.text,
            confidence: conf.clamp(0.0, 1.0),
            startMs: offsetMs + (t0 ?? 0),
            endMs: offsetMs + t1,
          ),
        );
      }
    }
    buf = [];
    probs = [];
    t0 = null;
  }

  for (final t in tokens) {
    if (t.bytes.isNotEmpty && t.bytes.first == 0x20) flush();
    buf.addAll(t.bytes);
    probs.add(t.p);
    t0 ??= t.t0Ms;
    t1 = t.t1Ms;
  }
  flush();
  return words;
}
