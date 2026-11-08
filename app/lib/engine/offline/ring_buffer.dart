import 'dart:typed_data';

/// Fixed-size in-memory PCM16 buffer (docs/SPEC.md §5 step 1). Never persisted.
/// [clear] overwrites every sample with zeros so no audio lingers in memory after a session.
class PcmRingBuffer {
  PcmRingBuffer({required this.capacitySamples})
    : _data = Int16List(capacitySamples);

  final int capacitySamples;
  final Int16List _data;
  int _write = 0; // next write position
  int _total = 0; // samples written since the last clear

  /// Samples written since the last [clear] (keeps counting past capacity).
  int get totalWritten => _total;

  /// Samples currently held (at most [capacitySamples]).
  int get length => _total < capacitySamples ? _total : capacitySamples;

  void write(Int16List samples) {
    for (final s in samples) {
      _data[_write] = s;
      _write = (_write + 1) % capacitySamples;
    }
    _total += samples.length;
  }

  /// Copies the samples written in [fromTotal, toTotal) (absolute positions, see
  /// [totalWritten]). Positions already overwritten are clipped away.
  Int16List range(int fromTotal, int toTotal) {
    final oldest = _total - length;
    final from = fromTotal < oldest ? oldest : fromTotal;
    final to = toTotal > _total ? _total : toTotal;
    if (to <= from) return Int16List(0);
    final out = Int16List(to - from);
    for (var i = 0; i < out.length; i++) {
      final abs = from + i;
      final idx = (_write - (_total - abs)) % capacitySamples;
      out[i] = _data[idx < 0 ? idx + capacitySamples : idx];
    }
    return out;
  }

  /// The most recent [n] samples (fewer if not yet available).
  Int16List last(int n) => range(_total - n, _total);

  void clear() {
    _data.fillRange(0, capacitySamples, 0);
    _write = 0;
    _total = 0;
  }
}
