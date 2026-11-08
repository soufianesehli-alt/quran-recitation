import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa/engine/offline/audio_stream.dart';
import 'package:tilawa/engine/offline/ring_buffer.dart';
import 'package:tilawa/engine/offline/vad.dart';

const sr = 16000;

/// Synthetic test signals only (no recorded audio anywhere in the repo).
Int16List tone(int ms, {double amp = 0.3, double hz = 220}) =>
    Int16List.fromList([
      for (var i = 0; i < sr * ms ~/ 1000; i++)
        (amp * 32767 * math.sin(2 * math.pi * hz * i / sr)).round(),
    ]);
Int16List noise(int ms, {double amp = 0.003, int seed = 1}) {
  final r = math.Random(seed);
  return Int16List.fromList([
    for (var i = 0; i < sr * ms ~/ 1000; i++)
      ((r.nextDouble() * 2 - 1) * amp * 32767).round(),
  ]);
}

void main() {
  group('PcmRingBuffer', () {
    test('keeps the most recent samples and wraps', () {
      final b = PcmRingBuffer(capacitySamples: 5);
      b.write(Int16List.fromList([1, 2, 3]));
      b.write(Int16List.fromList([4, 5, 6, 7]));
      expect(b.totalWritten, 7);
      expect(b.last(5), [3, 4, 5, 6, 7]);
      expect(b.range(0, 7), [3, 4, 5, 6, 7]); // overwritten samples are clipped
      expect(b.range(4, 6), [5, 6]);
    });

    test('clear zeroes memory', () {
      final b = PcmRingBuffer(capacitySamples: 4)
        ..write(Int16List.fromList([9, 9, 9, 9]));
      b.clear();
      expect(b.length, 0);
      b.write(Int16List.fromList([1]));
      expect(b.range(0, 1), [1]);
      expect(b.last(4), [1]);
    });
  });

  test('pcm16FromBytes decodes little-endian samples', () {
    final bytes = Uint8List.fromList([0x01, 0x00, 0xFF, 0xFF, 0x00, 0x80]);
    expect(pcm16FromBytes(bytes), [1, -1, -32768]);
  });

  group('EnergyVad', () {
    test('speech, short pause, then long pause', () {
      final vad = EnergyVad();
      final events = <VadEvent>[
        ...vad.process(noise(300)),
        ...vad.process(tone(800)),
        ...vad.process(noise(600, seed: 2)),
        ...vad.process(tone(500)),
        ...vad.process(noise(1700, seed: 3)),
      ];
      expect(events.map((e) => e.type), [
        VadEventType.speechStart,
        VadEventType.pause, // short pause: a waqf candidate
        VadEventType.speechStart, // speech resumes: new segment
        VadEventType.pause,
        VadEventType.longPause, // end of the attempt
      ]);
      expect(events[1].atMs, closeTo(300 + 800 + 500, 40));
      expect(events[2].atMs, closeTo(300 + 800 + 600, 60));
    });

    test('background noise alone triggers nothing', () {
      final vad = EnergyVad();
      expect(vad.process(noise(3000)), isEmpty);
    });

    test('very short clicks are not speech', () {
      final vad = EnergyVad();
      final ev = [
        ...vad.process(noise(300)),
        ...vad.process(tone(60)),
        ...vad.process(noise(2000, seed: 4)),
      ];
      expect(ev, isEmpty);
    });
  });
}
