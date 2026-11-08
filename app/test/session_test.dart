import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tilawa/app/providers.dart';
import 'package:tilawa/data/app_store.dart';
import 'package:tilawa/data/quran_repository.dart';
import 'package:tilawa/domain/models/finding.dart';
import 'package:tilawa/domain/models/quran.dart';
import 'package:tilawa/domain/models/riwaya.dart';
import 'package:tilawa/domain/segments.dart';
import 'package:tilawa/domain/settings.dart';
import 'package:tilawa/engine/engine_capabilities.dart';
import 'package:tilawa/engine/live_event.dart';
import 'package:tilawa/engine/recitation_engine.dart';

/// Engine that replays scripted findings for each attempt.
class ScriptedEngine implements RecitationEngine {
  ScriptedEngine(this.attempts);
  final List<List<Finding>> attempts;
  final starts = <int>[]; // fromWordIndex of each start
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    families: {},
    usesNetwork: false,
    acousticallyValidated: {},
  );
  @override
  Future<void> init(Riwaya riwaya) async {}
  @override
  Future<void> stop() async {}
  @override
  Stream<LiveEvent> start(AyahRef ayah, {int fromWordIndex = 0}) {
    starts.add(fromWordIndex);
    final f = attempts[(starts.length - 1).clamp(0, attempts.length - 1)];
    return Stream.fromIterable([AyahCompleteEvent(ayah, f)]);
  }
}

Finding finding(
  int word, {
  Severity sev = Severity.error,
  bool blocking = true,
  double conf = 0.95,
}) => Finding(
  wordIndex: word,
  word: '-',
  errorType: ErrorType.substitution,
  ruleId: 'word.substitution',
  ruleNameAr: 'إبدال كلمة',
  severity: sev,
  confidence: conf,
  messageAr: '-',
  ruleIsBlocking: blocking,
);

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

  Future<(ProviderContainer, ScriptedEngine, AppStore)> setup(
    List<List<Finding>> script, {
    ReReciteMode mode = ReReciteMode.segment,
  }) async {
    final store = await AppStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await store.saveSettings(AppSettings(reReciteMode: mode));
    final engine = ScriptedEngine(script);
    final c = ProviderContainer(
      overrides: [
        appStoreProvider.overrideWith((ref) async => store),
        quranRepoProvider.overrideWith((ref, r) async => hafs),
        engineProvider.overrideWith((ref, r) async => engine),
      ],
    );
    addTearDown(c.dispose);
    return (c, engine, store);
  }

  Future<void> attempt(ProviderContainer c) async {
    await c.read(sessionProvider.notifier).start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test(
    'a clean attempt passes, saves progress and unlocks the next ayah',
    () async {
      final (c, _, store) = await setup([[]]);
      await c.read(sessionProvider.notifier).open(Riwaya.hafs, 1, 2);
      await attempt(c);
      expect(c.read(sessionProvider).phase, SessionPhase.passed);
      expect(await store.lastUnlocked(Riwaya.hafs, 1), 2);
      await c.read(sessionProvider.notifier).next();
      expect(c.read(sessionProvider).ayahNumber, 3);
    },
  );

  test('needsReview findings never block', () async {
    final (c, _, _) = await setup([
      [finding(1, sev: Severity.needsReview, conf: 1)],
    ]);
    await c.read(sessionProvider.notifier).open(Riwaya.hafs, 1, 2);
    await attempt(c);
    expect(c.read(sessionProvider).phase, SessionPhase.passed);
  });

  test(
    'a blocking error fails the attempt and restarts from its waqf segment',
    () async {
      final ayah = await hafs.ayah(2, 2);
      final last = ayah.words.last.index;
      final segStart = WaqfSegments.startOf(ayah.words, last);
      expect(segStart, greaterThan(0)); // 2:2 has pause signs inside the ayah
      final (c, engine, store) = await setup([
        [finding(last)],
        [],
      ]);
      final s = c.read(sessionProvider.notifier);
      await s.open(Riwaya.hafs, 2, 2);
      await attempt(c);
      var st = c.read(sessionProvider);
      expect(st.phase, SessionPhase.failed);
      expect(st.fromWord, segStart);
      expect(st.offerContinue, isFalse);
      expect(await store.lastUnlocked(Riwaya.hafs, 2), 0);
      await s.retry();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      st = c.read(sessionProvider);
      expect(engine.starts, [0, segStart]);
      expect(st.phase, SessionPhase.passed);
    },
  );

  test('full-ayah mode restarts from the first word', () async {
    final ayah = await hafs.ayah(2, 2);
    final (c, _, _) = await setup([
      [finding(ayah.words.last.index)],
    ], mode: ReReciteMode.fullAyah);
    await c.read(sessionProvider.notifier).open(Riwaya.hafs, 2, 2);
    await attempt(c);
    expect(c.read(sessionProvider).fromWord, 0);
  });

  test(
    'after 3 failures on the same word, "continue anyway" is offered and works',
    () async {
      final (c, _, store) = await setup([
        [finding(1)],
      ]);
      final s = c.read(sessionProvider.notifier);
      await s.open(Riwaya.hafs, 1, 2);
      for (var i = 0; i < 3; i++) {
        expect(c.read(sessionProvider).offerContinue, isFalse);
        i == 0 ? await attempt(c) : await s.retry();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(c.read(sessionProvider).attempts[1], 3);
      expect(c.read(sessionProvider).offerContinue, isTrue);
      await s.continueAnyway();
      expect(c.read(sessionProvider).ayahNumber, 3);
      expect(await store.lastUnlocked(Riwaya.hafs, 1), 2);
    },
  );

  test('next() is refused until the ayah has passed', () async {
    final (c, _, _) = await setup([
      [finding(1)],
    ]);
    final s = c.read(sessionProvider.notifier);
    await s.open(Riwaya.hafs, 1, 2);
    await attempt(c);
    await s.next();
    expect(c.read(sessionProvider).ayahNumber, 2);
  });
}
