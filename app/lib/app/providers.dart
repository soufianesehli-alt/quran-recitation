import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_store.dart';
import '../data/device_probe.dart';
import '../data/model_repository.dart';
import '../data/quran_repository.dart';
import '../domain/ayah_gate.dart';
import '../domain/device_tier.dart';
import '../domain/models/finding.dart';
import '../domain/models/quran.dart';
import '../domain/models/riwaya.dart';
import '../domain/segments.dart';
import '../domain/settings.dart';
import '../engine/live_event.dart';
import '../engine/offline/asr_native.dart';
import '../engine/offline/audio_stream.dart';
import '../engine/offline/offline_engine.dart';
import '../engine/recitation_engine.dart';

// ── Infrastructure providers (overridden in tests) ──────────────────────────────────────

final appStoreProvider = FutureProvider<AppStore>((ref) => AppStore.open());

final quranRepoProvider = FutureProvider.family<QuranRepository, Riwaya>(
  (ref, r) => QuranRepository.openBundled(r),
);

final deviceInfoProvider = FutureProvider<DeviceInfo>(
  (ref) => DeviceProbe.read(),
);

/// Timing metrics for the debug screen (numbers only; never audio or text).
final metricsProvider =
    NotifierProvider<MetricsNotifier, Map<String, List<num>>>(
      MetricsNotifier.new,
    );

class MetricsNotifier extends Notifier<Map<String, List<num>>> {
  @override
  Map<String, List<num>> build() => {};

  void add(String name, num value) {
    final list = [...?state[name], value];
    state = {
      ...state,
      name: list.length > 200 ? list.sublist(list.length - 200) : list,
    };
  }

  void clear() => state = {};
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async =>
      (await ref.watch(appStoreProvider.future)).loadSettings();

  Future<void> change(AppSettings Function(AppSettings) f) async {
    final next = f(await future);
    state = AsyncData(next);
    await (await ref.read(appStoreProvider.future)).saveSettings(next);
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Recogniser setup actually used: tier default, overridden by the user's settings.
final asrSetupProvider = FutureProvider<AsrSetup>((ref) async {
  final info = await ref.watch(deviceInfoProvider.future);
  final s = await ref.watch(settingsProvider.future);
  final tierSetup = AsrSetup.forTier(info.tier, info.cpuCores);
  return AsrSetup(
    modelAsset: switch (s.modelChoice) {
      ModelChoice.auto => tierSetup.modelAsset,
      ModelChoice.base => AsrSetup.baseModel,
      ModelChoice.tiny => AsrSetup.tinyModel,
    },
    beamSize: tierSetup.beamSize,
    liveHighlighting: s.liveHighlighting ?? tierSetup.liveHighlighting,
    threads: tierSetup.threads,
  );
});

/// A ready engine per riwaya (model installed and loaded).
final engineProvider = FutureProvider.family<RecitationEngine, Riwaya>((
  ref,
  riwaya,
) async {
  final setup = await ref.watch(asrSetupProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  final metrics = ref.read(metricsProvider.notifier);
  final modelPath = await ModelRepository.install(setup.modelAsset);
  final engine = OfflineEngine(
    audio: MicAudioSource(),
    asr: IsolateAsrBackend(
      threads: setup.threads,
      beamSize: setup.beamSize,
      backendDir: (await ref.read(deviceInfoProvider.future)).nativeLibDir,
    ),
    modelPath: modelPath,
    openQuran: (r) => ref.read(quranRepoProvider(r).future),
    config: OfflineEngineConfig(
      liveHighlighting: setup.liveHighlighting,
      highConfidence: settings.highConfidence,
      devTreatWordRulesAsBlocking:
          !kReleaseMode && settings.devBlockingWordRules,
    ),
    onMetric: metrics.add,
  );
  await engine.init(riwaya);
  ref.onDispose(engine.stop);
  return engine;
});

// ── Recitation session (docs/SPEC.md §7) ────────────────────────────────────────────────

enum SessionPhase {
  loading,
  ready,
  preparingEngine,
  listening,
  passed,
  failed,
  error,
}

@immutable
class SessionState {
  const SessionState({
    required this.riwaya,
    required this.surah,
    required this.ayahNumber,
    this.ayah,
    this.ayahCount = 0,
    this.statuses = const {},
    this.currentWord,
    this.findings = const [],
    this.phase = SessionPhase.loading,
    this.attempts = const {},
    this.offerContinue = false,
    this.fromWord = 0,
    this.messageAr,
    this.micLevel = 0,
    this.speaking = false,
  });

  final Riwaya riwaya;
  final int surah;
  final int ayahNumber;
  final Ayah? ayah;
  final int ayahCount;
  final Map<int, WordStatus> statuses;
  final int? currentWord;
  final List<Finding> findings;
  final SessionPhase phase;

  /// Failed attempts per word index (blocking findings only).
  final Map<int, int> attempts;
  final bool offerContinue;

  /// First word of the next attempt (segment restart).
  final int fromWord;
  final String? messageAr;

  /// Microphone level 0..1 and voice activity, for the on-screen meter.
  final double micLevel;
  final bool speaking;

  bool get hasNextAyah => ayahNumber < ayahCount;

  SessionState copyWith({
    Ayah? ayah,
    int? ayahCount,
    Map<int, WordStatus>? statuses,
    int? Function()? currentWord,
    List<Finding>? findings,
    SessionPhase? phase,
    Map<int, int>? attempts,
    bool? offerContinue,
    int? fromWord,
    String? Function()? messageAr,
    double? micLevel,
    bool? speaking,
  }) => SessionState(
    riwaya: riwaya,
    surah: surah,
    ayahNumber: ayahNumber,
    ayah: ayah ?? this.ayah,
    ayahCount: ayahCount ?? this.ayahCount,
    statuses: statuses ?? this.statuses,
    currentWord: currentWord == null ? this.currentWord : currentWord(),
    findings: findings ?? this.findings,
    phase: phase ?? this.phase,
    attempts: attempts ?? this.attempts,
    offerContinue: offerContinue ?? this.offerContinue,
    fromWord: fromWord ?? this.fromWord,
    messageAr: messageAr == null ? this.messageAr : messageAr(),
    micLevel: micLevel ?? this.micLevel,
    speaking: speaking ?? this.speaking,
  );
}

class SessionController extends Notifier<SessionState> {
  StreamSubscription<LiveEvent>? _sub;

  @override
  SessionState build() {
    ref.onDispose(() => _sub?.cancel());
    return const SessionState(riwaya: Riwaya.hafs, surah: 1, ayahNumber: 1);
  }

  Future<void> open(Riwaya riwaya, int surah, int ayahNumber) async {
    await _cancel();
    state = SessionState(riwaya: riwaya, surah: surah, ayahNumber: ayahNumber);
    try {
      final repo = await ref.read(quranRepoProvider(riwaya).future);
      final ayah = await repo.ayah(surah, ayahNumber);
      final count = (await repo.surahs())[surah - 1].ayahCount;
      state = state.copyWith(
        ayah: ayah,
        ayahCount: count,
        phase: SessionPhase.ready,
        currentWord: () => ayah.words.first.index,
      );
    } catch (_) {
      state = state.copyWith(
        phase: SessionPhase.error,
        messageAr: () => 'تعذّر تحميل الآية.',
      );
    }
  }

  Future<void> start() async {
    if (state.ayah == null || state.phase == SessionPhase.listening) return;
    state = state.copyWith(
      phase: SessionPhase.preparingEngine,
      messageAr: () => null,
    );
    try {
      final engine = await ref.read(engineProvider(state.riwaya).future);
      final ayahRef = AyahRef(
        riwaya: state.riwaya,
        surah: state.surah,
        ayah: state.ayahNumber,
      );
      state = state.copyWith(
        phase: SessionPhase.listening,
        findings: const [],
        statuses: {
          for (final e in state.statuses.entries)
            if (e.key < state.fromWord) e.key: e.value,
        },
        currentWord: () => state.fromWord,
      );
      _sub = engine
          .start(ayahRef, fromWordIndex: state.fromWord)
          .listen(_onEvent);
    } catch (_) {
      state = state.copyWith(
        phase: SessionPhase.error,
        messageAr: () => 'تعذّر تجهيز محرك التحليل.',
      );
    }
  }

  Future<void> stop() async {
    await _cancel();
    final engine = ref.read(engineProvider(state.riwaya)).value;
    await engine?.stop();
    if (state.phase == SessionPhase.listening) {
      state = state.copyWith(phase: SessionPhase.ready);
    }
  }

  void _onEvent(LiveEvent e) {
    switch (e) {
      case CurrentWordEvent(:final wordIndex):
        state = state.copyWith(currentWord: () => wordIndex);
      case WordResultEvent(:final wordIndex, :final status):
        state = state.copyWith(
          statuses: {...state.statuses, wordIndex: status},
        );
      case FindingEvent():
        break; // collected from AyahCompleteEvent (complete list for this attempt)
      case AyahCompleteEvent(:final findings):
        _evaluate(findings);
      case MicLevelEvent(:final level, :final speaking):
        state = state.copyWith(micLevel: level, speaking: speaking);
      case EngineErrorEvent(:final messageAr):
        state = state.copyWith(
          phase: SessionPhase.error,
          messageAr: () => messageAr,
        );
    }
  }

  Future<void> _evaluate(List<Finding> findings) async {
    final settings = await ref.read(settingsProvider.future);
    final gate = AyahGate(
      highConfidenceThreshold: settings.highConfidence,
      maxAttemptsPerWord: settings.maxAttempts,
    );
    if (gate.canAdvance(findings)) {
      state = state.copyWith(
        phase: SessionPhase.passed,
        findings: findings,
        currentWord: () => null,
        fromWord: 0,
        messageAr: () => findings.isEmpty
            ? 'أحسنت! تابع إلى الآية التالية.'
            : 'أحسنت. راجع الكلمات المعلَّمة إن شئت.',
      );
      await (await ref.read(appStoreProvider.future))
          .markUnlocked(state.riwaya, state.surah, state.ayahNumber);
      return;
    }
    final blocking =
        findings.where((f) => f.blocksAt(settings.highConfidence)).toList()
          ..sort((a, b) => a.wordIndex.compareTo(b.wordIndex));
    final attempts = {...state.attempts};
    for (final f in blocking) {
      attempts[f.wordIndex] = (attempts[f.wordIndex] ?? 0) + 1;
    }
    final first = blocking.first.wordIndex;
    final from = settings.reReciteMode == ReReciteMode.segment
        ? WaqfSegments.startOf(state.ayah!.words, first)
        : 0;
    state = state.copyWith(
      phase: SessionPhase.failed,
      findings: findings,
      attempts: attempts,
      fromWord: from,
      currentWord: () => from,
      offerContinue: blocking.any(
        (f) => gate.offerContinueAnyway(attempts[f.wordIndex] ?? 0),
      ),
      messageAr: () => from == 0
          ? 'أعد قراءة الآية من بدايتها.'
          : 'أعد القراءة من بداية المقطع المعلَّم.',
    );
  }

  /// Re-recite after a failed attempt (from the segment start computed above).
  Future<void> retry() async {
    if (state.phase != SessionPhase.failed) return;
    state = state.copyWith(phase: SessionPhase.ready);
    await start();
  }

  /// "متابعة على أي حال": only offered after N failed attempts on the same word.
  Future<void> continueAnyway() async {
    if (!state.offerContinue) return;
    await (await ref.read(appStoreProvider.future))
        .markUnlocked(state.riwaya, state.surah, state.ayahNumber);
    await next(force: true);
  }

  Future<void> next({bool force = false}) async {
    if (!force && state.phase != SessionPhase.passed) return;
    if (!state.hasNextAyah) return;
    await open(state.riwaya, state.surah, state.ayahNumber + 1);
  }

  Future<void> _cancel() async {
    await _sub?.cancel();
    _sub = null;
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);
