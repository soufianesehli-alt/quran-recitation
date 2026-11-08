import 'dart:async';
import 'dart:typed_data';

import '../../data/quran_repository.dart';
import '../../domain/models/finding.dart';
import '../../domain/models/quran.dart';
import '../../domain/models/riwaya.dart';
import '../engine_capabilities.dart';
import '../live_event.dart';
import '../recitation_engine.dart';
import 'asr_backend.dart';
import 'audio_stream.dart';
import 'ring_buffer.dart';
import 'vad.dart';
import 'word_aligner.dart';
import 'word_findings.dart';

/// Tunables of the offline pipeline. Defaults are starting points, tuned in Phase 5.
class OfflineEngineConfig {
  const OfflineEngineConfig({
    this.liveTickMs = 1500,
    this.maxSegmentMs = 25000,
    this.pauseMs = 500,
    this.longPauseMs = 1500,
    this.highConfidence = 0.9,
    this.devTreatWordRulesAsBlocking = false,
    this.liveHighlighting = true,
  });

  /// Re-recognise the current segment every this many ms of audio (live highlighting).
  final int liveTickMs;

  /// Segments longer than this are cut (Whisper windows are at most 30 s).
  final int maxSegmentMs;
  final int pauseMs;
  final int longPauseMs;
  final double highConfidence;
  final bool devTreatWordRulesAsBlocking;

  /// False on low-tier phones: results appear after each pause instead of live.
  final bool liveHighlighting;
}

/// Timing metrics for the debug screen. Numbers only, never audio or text.
typedef MetricSink = void Function(String name, num value);

/// V1 engine (docs/SPEC.md §5): mic → ring buffer → VAD → on-device ASR biased with the
/// expected text → word alignment → findings. Word-level checks only in Phase 3; madd and
/// ghunnah checks arrive in Phase 4.
class OfflineEngine implements RecitationEngine {
  OfflineEngine({
    required this.audio,
    required this.asr,
    required this.modelPath,
    required this.openQuran,
    this.config = const OfflineEngineConfig(),
    this.onMetric,
  });

  final AudioSource audio;
  final AsrBackend asr;
  final String modelPath;
  final OfflineEngineConfig config;
  final MetricSink? onMetric;
  final Future<QuranRepository> Function(Riwaya) openQuran;

  static const _sr = MicAudioSource.sampleRate;

  QuranRepository? _quran;
  Riwaya? _riwaya;
  _Run? _run;

  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    families: {RuleFamily.words},
    usesNetwork: false,
    // Empty until a model is validated per riwaya: every acoustic finding is needsReview.
    acousticallyValidated: {},
  );

  @override
  Future<void> init(Riwaya riwaya) async {
    final sw = Stopwatch()..start();
    _riwaya = riwaya;
    _quran = await openQuran(riwaya);
    await asr.load(modelPath);
    onMetric?.call('init_ms', sw.elapsedMilliseconds);
  }

  @override
  Stream<LiveEvent> start(AyahRef ayah, {int fromWordIndex = 0}) {
    if (_quran == null || _riwaya != ayah.riwaya) {
      throw StateError('init(${ayah.riwaya.id}) must be called first');
    }
    final controller = StreamController<LiveEvent>();
    final run = _Run(this, ayah, controller, fromWordIndex);
    _run = run;
    controller.onListen = run.begin;
    controller.onCancel = () => run.finish(complete: false);
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await _run?.finish(complete: false);
    _run = null;
  }
}

/// One listening attempt on one ayah (or from a word inside it).
class _Run {
  _Run(this.e, this.ref, this.out, this.fromWord);

  final OfflineEngine e;
  final AyahRef ref;
  final StreamController<LiveEvent> out;
  final int fromWord;

  late final Ayah ayah;
  Ayah? nextAyah;
  late final List<Word> expected; // words from [fromWord]
  final buffer = PcmRingBuffer(capacitySamples: OfflineEngine._sr * 30);
  late final EnergyVad vad = EnergyVad(
    pauseMs: e.config.pauseMs,
    longPauseMs: e.config.longPauseMs,
  );
  StreamSubscription<Int16List>? _sub;

  /// Final hypothesis of each closed segment, in order.
  final List<HypWord> _closed = [];
  int?
  _segStart; // absolute sample index where the current segment's speech started
  int _lastTick = 0;
  bool _busy = false;
  bool _done = false;
  final Map<int, WordStatus> _sent = {};
  int _current = -1;
  Future<void> _work = Future.value();

  WordFindingBuilder get _builder => WordFindingBuilder(
    highConfidence: e.config.highConfidence,
    devTreatWordRulesAsBlocking: e.config.devTreatWordRulesAsBlocking,
  );

  Future<void> begin() async {
    try {
      ayah = await e._quran!.ayah(ref.surah, ref.ayah);
      final surahs = await e._quran!.surahs();
      if (ref.ayah < surahs[ref.surah - 1].ayahCount) {
        nextAyah = await e._quran!.ayah(ref.surah, ref.ayah + 1);
      }
      expected = ayah.words.sublist(fromWord.clamp(0, ayah.words.length - 1));
      _emitCurrent(expected.first.index);
      final stream = await e.audio.start();
      _sub = stream.listen(
        _onAudio,
        onError: (Object _) => _fail('تعذّر الوصول إلى الميكروفون.'),
      );
    } catch (_) {
      _fail('تعذّر بدء الاستماع.');
    }
  }

  void _onAudio(Int16List chunk) {
    if (_done) return;
    buffer.write(chunk);
    for (final ev in vad.process(chunk)) {
      switch (ev.type) {
        case VadEventType.speechStart:
          _segStart ??= (ev.atMs * OfflineEngine._sr ~/ 1000).clamp(
            0,
            buffer.totalWritten,
          );
          _lastTick = buffer.totalWritten;
        case VadEventType.pause:
          _closeSegment();
        case VadEventType.longPause:
          _closeSegment();
          _enqueue(_complete);
      }
    }
    final seg = _segStart;
    if (seg == null) return;
    final segMs = (buffer.totalWritten - seg) * 1000 ~/ OfflineEngine._sr;
    if (segMs >= e.config.maxSegmentMs) {
      _closeSegment();
    } else if (e.config.liveHighlighting &&
        !_busy &&
        (buffer.totalWritten - _lastTick) * 1000 ~/ OfflineEngine._sr >=
            e.config.liveTickMs) {
      _lastTick = buffer.totalWritten;
      final from = seg, to = buffer.totalWritten;
      _busy = true;
      _recognise(from, to).then((partial) {
        _busy = false;
        if (!_done) _updateLive([..._closed, ...partial], partial: true);
      });
    }
  }

  /// Ends the current speech segment (at a pause) and recognises it in full.
  void _closeSegment() {
    final from = _segStart;
    if (from == null) return;
    final to = buffer.totalWritten;
    _segStart = null;
    _enqueue(() async {
      final words = await _recognise(from, to);
      _closed.addAll(words);
      if (!_done) _updateLive(_closed, partial: false);
    });
  }

  void _enqueue(Future<void> Function() job) =>
      _work = _work.then((_) => _done ? null : job());

  Future<List<HypWord>> _recognise(int fromSample, int toSample) async {
    final sw = Stopwatch()..start();
    final audio = buffer.range(fromSample, toSample);
    final prompt = expected.map((w) => w.uthmani).join(' ');
    try {
      final words = await e.asr.transcribe(audio, prompt: prompt);
      final offsetMs = fromSample * 1000 ~/ OfflineEngine._sr;
      e.onMetric?.call('asr_ms', sw.elapsedMilliseconds);
      e.onMetric?.call(
        'asr_audio_ms',
        audio.length * 1000 ~/ OfflineEngine._sr,
      );
      return [
        for (final w in words)
          HypWord(
            w.text,
            confidence: w.confidence,
            startMs: w.startMs == null ? null : w.startMs! + offsetMs,
            endMs: w.endMs == null ? null : w.endMs! + offsetMs,
          ),
      ];
    } finally {
      audio.fillRange(0, audio.length, 0);
    }
  }

  /// Emits word colours for everything up to the furthest word matched so far.
  void _updateLive(List<HypWord> hyp, {required bool partial}) {
    final keys = [for (final w in expected) w.normalized];
    final alignment = const WordAligner().align(keys, hyp);
    var furthest = -1;
    for (final aw in alignment.words) {
      if (aw.status == AlignStatus.correct ||
          aw.status == AlignStatus.variant) {
        furthest = aw.expectedIndex;
      }
    }
    final findings = _builder.build(expected, alignment);
    for (final aw in alignment.words) {
      if (aw.expectedIndex > furthest) break;
      final word = expected[aw.expectedIndex];
      _emitWord(word.index, _statusFor(word.index, aw.status, findings));
    }
    final next = furthest + 1;
    if (next < expected.length) _emitCurrent(expected[next].index);
    if (!partial && furthest == expected.length - 1) {
      // Every word heard and the reciter paused: the attempt can end without a long pause.
      _enqueue(_complete);
    }
  }

  WordStatus _statusFor(int wordIndex, AlignStatus s, List<Finding> findings) {
    if (s == AlignStatus.correct) return WordStatus.correct;
    final f = findings.where((x) => x.wordIndex == wordIndex);
    if (f.any((x) => x.severity == Severity.error)) return WordStatus.error;
    return WordStatus.needsReview;
  }

  Future<void> _complete() async {
    if (_done) return;
    final sw = Stopwatch()..start();
    final keys = [for (final w in expected) w.normalized];
    final alignment = const WordAligner().align(keys, _closed);
    var findings = _builder.build(expected, alignment);

    // Skipped ayah: nothing of this ayah matched but the next ayah's words did.
    final matched = alignment.words
        .where((w) => w.status == AlignStatus.correct)
        .length;
    final next = nextAyah;
    if (matched == 0 && next != null && _closed.isNotEmpty) {
      final nk = [for (final w in next.words) w.normalized];
      final na = const WordAligner().align(nk, _closed);
      final nm = na.words.where((w) => w.status == AlignStatus.correct).length;
      if (nm * 2 >= nk.length) {
        final conf =
            _closed.map((w) => w.confidence).reduce((a, b) => a + b) /
            _closed.length;
        findings = [_builder.skippedAyah(ayah, conf)];
      }
    }

    for (final aw in alignment.words) {
      final word = expected[aw.expectedIndex];
      _emitWord(word.index, _statusFor(word.index, aw.status, findings));
    }
    for (final f in findings) {
      if (!out.isClosed) out.add(FindingEvent(ref, f));
    }
    e.onMetric?.call('end_of_ayah_ms', sw.elapsedMilliseconds);
    if (!out.isClosed) out.add(AyahCompleteEvent(ref, findings));
    await finish(complete: true);
  }

  void _emitWord(int index, WordStatus s) {
    if (_sent[index] == s || out.isClosed) return;
    _sent[index] = s;
    out.add(WordResultEvent(ref, index, s));
  }

  void _emitCurrent(int index) {
    if (_current == index || out.isClosed) return;
    _current = index;
    out.add(CurrentWordEvent(ref, index));
  }

  void _fail(String messageAr) {
    if (!out.isClosed) out.add(EngineErrorEvent(ref, messageAr));
    finish(complete: false);
  }

  Future<void> finish({required bool complete}) async {
    if (_done) return;
    _done = true;
    await _sub?.cancel();
    _sub = null;
    await e.audio.stop();
    buffer.clear(); // zero all audio
    vad.reset();
    _closed.clear();
    if (!out.isClosed) await out.close();
  }
}
