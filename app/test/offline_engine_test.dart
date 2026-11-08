import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tilawa/data/quran_repository.dart';
import 'package:tilawa/domain/models/finding.dart';
import 'package:tilawa/domain/models/quran.dart';
import 'package:tilawa/domain/models/riwaya.dart';
import 'package:tilawa/engine/live_event.dart';
import 'package:tilawa/engine/offline/asr_backend.dart';
import 'package:tilawa/engine/offline/audio_stream.dart';
import 'package:tilawa/engine/offline/offline_engine.dart';
import 'package:tilawa/engine/offline/word_aligner.dart';

const sr = 16000;

class FakeAudio implements AudioSource {
  final controller = StreamController<Int16List>();
  bool stopped = false;
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<Stream<Int16List>> start() async => controller.stream;
  @override
  Future<void> stop() async => stopped = true;
}

/// Segment k of speech is a tone of amplitude 0.2 + 0.1k. The fake recogniser reads the
/// amplitude to know which scripted segment it is hearing, and returns a prefix of that
/// segment's words proportional to how much of the segment it has heard (live windows).
class FakeAsr implements AsrBackend {
  FakeAsr(this.segments, this.segmentMs);
  final List<List<String>> segments;
  final int segmentMs;
  int calls = 0;
  @override
  Future<void> load(String modelPath) async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<List<HypWord>> transcribe(Int16List s, {String? prompt}) async {
    calls++;
    var peak = 0;
    for (final x in s) {
      peak = math.max(peak, x.abs());
    }
    final k = ((peak / 32767 - 0.2) / 0.1).round().clamp(
      0,
      segments.length - 1,
    );
    final words = segments[k];
    final heardMs = s.length * 1000 ~/ sr;
    final n = (words.length * heardMs / segmentMs).ceil().clamp(
      0,
      words.length,
    );
    return [for (final w in words.take(n)) HypWord(w, confidence: 0.97)];
  }
}

Int16List tone(int ms, double amp) => Int16List.fromList([
  for (var i = 0; i < sr * ms ~/ 1000; i++)
    (amp * 32767 * math.sin(2 * math.pi * 220 * i / sr)).round(),
]);
Int16List quiet(int ms) => Int16List(sr * ms ~/ 1000);

/// Feeds audio in 100 ms chunks, letting the engine's async work run in between.
Future<void> feed(FakeAudio a, Int16List samples) async {
  for (var i = 0; i < samples.length; i += 1600) {
    a.controller.add(
      Int16List.sublistView(samples, i, math.min(i + 1600, samples.length)),
    );
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late QuranRepository hafs;
  setUpAll(() async {
    sqfliteFfiInit();
    hafs = await QuranRepository.open(
      Riwaya.hafs,
      File('assets/quran/hafs.sqlite').absolute.path,
      databaseFactoryFfi,
    );
  });
  tearDownAll(() => hafs.close());

  Future<(List<LiveEvent>, FakeAudio)> recite(
    AyahRef ref,
    List<List<String>> segments, {
    int segMs = 2000,
  }) async {
    final audio = FakeAudio();
    final engine = OfflineEngine(
      audio: audio,
      asr: FakeAsr(segments, segMs),
      modelPath: 'x',
      openQuran: (_) async => hafs,
    );
    await engine.init(Riwaya.hafs);
    final events = <LiveEvent>[];
    final done = Completer<void>();
    engine.start(ref).listen(events.add, onDone: done.complete);
    await Future<void>.delayed(Duration.zero);
    await feed(audio, quiet(300));
    for (var k = 0; k < segments.length; k++) {
      await feed(audio, tone(segMs, 0.2 + 0.1 * k));
      await feed(audio, quiet(k == segments.length - 1 ? 1800 : 700));
    }
    await done.future.timeout(const Duration(seconds: 5));
    return (events, audio);
  }

  Future<List<String>> keys(int s, int a) async => [
    for (final w in (await hafs.ayah(s, a)).words) w.normalized,
  ];

  test(
    'correct recitation in two waqf segments: all green, no findings',
    () async {
      final k = await keys(2, 255);
      final cut = k.length ~/ 2;
      final (events, audio) = await recite(
        const AyahRef(riwaya: Riwaya.hafs, surah: 2, ayah: 255),
        [k.sublist(0, cut), k.sublist(cut)],
      );
      final complete = events.whereType<AyahCompleteEvent>().single;
      expect(complete.findings, isEmpty);
      final finalStatus = <int, WordStatus>{
        for (final e in events.whereType<WordResultEvent>())
          e.wordIndex: e.status,
      };
      expect(finalStatus.length, k.length);
      expect(finalStatus.values, everyElement(WordStatus.correct));
      expect(audio.stopped, isTrue);
    },
  );

  test(
    'live highlighting advances the current word before the ayah ends',
    () async {
      final k = await keys(2, 255);
      final (events, _) = await recite(
        const AyahRef(riwaya: Riwaya.hafs, surah: 2, ayah: 255),
        [k],
        segMs: 6000,
      );
      final firstComplete = events.indexWhere((e) => e is AyahCompleteEvent);
      final liveCurrents = events
          .take(firstComplete)
          .whereType<CurrentWordEvent>()
          .map((e) => e.wordIndex)
          .toSet();
      expect(liveCurrents.length, greaterThan(2));
    },
  );

  test(
    'a dropped word becomes an omission finding (not blocking before Phase 5)',
    () async {
      final k = await keys(1, 2);
      final heard = [...k]..removeAt(1);
      final (events, _) = await recite(
        const AyahRef(riwaya: Riwaya.hafs, surah: 1, ayah: 2),
        [heard],
      );
      final f = events.whereType<AyahCompleteEvent>().single.findings.single;
      expect(f.ruleId, 'word.omission');
      expect(f.wordIndex, 1);
      expect(f.severity, Severity.error);
      expect(f.ruleIsBlocking, isFalse);
    },
  );

  test(
    'reciting the next ayah instead is reported as a skipped ayah',
    () async {
      final next = await keys(1, 3);
      final (events, _) = await recite(
        const AyahRef(riwaya: Riwaya.hafs, surah: 1, ayah: 2),
        [next],
      );
      final f = events.whereType<AyahCompleteEvent>().single.findings;
      expect(f.single.ruleId, 'word.skipped_ayah');
    },
  );
}
