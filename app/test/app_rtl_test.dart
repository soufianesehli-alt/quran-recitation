import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tilawa/app/app.dart';
import 'package:tilawa/app/providers.dart';
import 'package:tilawa/core/l10n/strings_ar.dart';
import 'package:tilawa/data/app_store.dart';
import 'package:tilawa/data/quran_repository.dart';
import 'package:tilawa/domain/device_tier.dart';
import 'package:tilawa/domain/models/finding.dart';
import 'package:tilawa/domain/models/quran.dart';
import 'package:tilawa/domain/models/riwaya.dart';
import 'package:tilawa/domain/settings.dart';
import 'package:tilawa/engine/engine_capabilities.dart';
import 'package:tilawa/engine/live_event.dart';
import 'package:tilawa/engine/recitation_engine.dart';
import 'package:tilawa/features/first_launch/first_launch_screen.dart';
import 'package:tilawa/features/recitation/recitation_screen.dart';
import 'package:tilawa/features/selection/selection_screen.dart';

class OneShotEngine implements RecitationEngine {
  OneShotEngine(this.events);
  final List<LiveEvent> Function(AyahRef) events;
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
  Stream<LiveEvent> start(AyahRef ayah, {int fromWordIndex = 0}) =>
      Stream.fromIterable(events(ayah));
}

void main() {
  late QuranRepository hafs, warsh;
  late AppStore store;

  setUpAll(() async {
    sqfliteFfiInit();
    hafs = await QuranRepository.open(
      Riwaya.hafs,
      File('assets/quran/hafs.sqlite').absolute.path,
      databaseFactoryFfi,
    );
    warsh = await QuranRepository.open(
      Riwaya.warsh,
      File('assets/quran/warsh.sqlite').absolute.path,
      databaseFactoryFfi,
    );
  });

  Future<ProviderContainer> container(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(),
    RecitationEngine? engine,
  }) async {
    return (await tester.runAsync(() async {
      store = await AppStore.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      await store.saveSettings(settings);
      return ProviderContainer(
        overrides: [
          deviceInfoProvider.overrideWith(
            (ref) async => const DeviceInfo(
              totalRamMb: 8000,
              primaryAbi: 'arm64-v8a',
              cpuCores: 8,
              model: 'test',
              sdkInt: 35,
            ),
          ),
          appStoreProvider.overrideWith((ref) async => store),
          quranRepoProvider.overrideWith(
            (ref, r) async => r == Riwaya.hafs ? hafs : warsh,
          ),
          if (engine != null)
            engineProvider.overrideWith((ref, r) async => engine),
        ],
      );
    }))!;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
  }

  testWidgets(
    'first launch: Arabic RTL, privacy promise, permission leads to selection',
    (tester) async {
      final c = await container(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: TilawaApp(
            home: FirstLaunchScreen(requestPermission: () async => true),
          ),
        ),
      );
      await settle(tester);
      final ctx = tester.element(find.text(StringsAr.noAudioStored));
      expect(Directionality.of(ctx), TextDirection.rtl);
      await tester.tap(find.text(StringsAr.allowMic));
      await settle(tester);
      expect(find.byType(SelectionScreen), findsOneWidget);
      expect(find.text(StringsAr.offlineBanner), findsOneWidget);
      expect(
        (await tester.runAsync(store.loadSettings))!.firstLaunchDone,
        isTrue,
      );
    },
  );

  testWidgets('denied permission shows the explanation and stays', (
    tester,
  ) async {
    final c = await container(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: TilawaApp(
          home: FirstLaunchScreen(requestPermission: () async => false),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text(StringsAr.allowMic));
    await settle(tester);
    expect(find.text(StringsAr.micDenied), findsOneWidget);
  });

  testWidgets('selection offers both riwayat', (tester) async {
    final c = await container(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const TilawaApp(home: SelectionScreen()),
      ),
    );
    await settle(tester);
    expect(find.text(Riwaya.hafs.nameAr), findsOneWidget);
    expect(find.text(Riwaya.warsh.nameAr), findsOneWidget);
    expect(find.text(StringsAr.start), findsOneWidget);
  });

  testWidgets(
    'recitation: live colours, word sheet, failure and retry button',
    (tester) async {
      late Ayah ayah;
      await tester.runAsync(() async => ayah = await hafs.ayah(1, 2));
      final f = Finding(
        wordIndex: 1,
        word: ayah.words[1].uthmani,
        errorType: ErrorType.omission,
        ruleId: 'word.omission',
        ruleNameAr: 'إسقاط كلمة',
        expected: ayah.words[1].uthmani,
        severity: Severity.error,
        confidence: 0.95,
        messageAr: 'لم تُسمع الكلمة.',
        ruleIsBlocking: true,
      );
      final engine = OneShotEngine(
        (ref) => [
          CurrentWordEvent(ref, 0),
          WordResultEvent(ref, 0, WordStatus.correct),
          WordResultEvent(ref, 1, WordStatus.error),
          FindingEvent(ref, f),
          AyahCompleteEvent(ref, [f]),
        ],
      );
      final c = await container(tester, engine: engine);
      await tester.runAsync(
        () => c.read(sessionProvider.notifier).open(Riwaya.hafs, 1, 2),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const TilawaApp(home: RecitationScreen()),
        ),
      );
      await settle(tester);

      expect(find.text(StringsAr.listen), findsOneWidget);
      await tester.tap(find.text(StringsAr.listen));
      await settle(tester);

      Text wordText(int i) => tester.widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey('word-$i')),
          matching: find.byType(Text),
        ),
      );
      expect(wordText(0).style!.color, AyahWords.colorFor(WordStatus.correct));
      expect(wordText(1).style!.color, AyahWords.colorFor(WordStatus.error));
      expect(find.text(StringsAr.retry), findsOneWidget);
      expect(find.text(StringsAr.nextAyah), findsNothing);

      await tester.tap(find.byKey(const ValueKey('word-1')));
      await settle(tester);
      expect(find.text('إسقاط كلمة'), findsOneWidget);
      expect(find.text(StringsAr.severityError), findsOneWidget);
    },
  );

  testWidgets('recitation: a clean attempt shows "next ayah"', (tester) async {
    final engine = OneShotEngine((ref) => [AyahCompleteEvent(ref, const [])]);
    final c = await container(tester, engine: engine);
    await tester.runAsync(
      () => c.read(sessionProvider.notifier).open(Riwaya.warsh, 1, 1),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const TilawaApp(home: RecitationScreen()),
      ),
    );
    await settle(tester);
    await tester.tap(find.text(StringsAr.listen));
    await settle(tester);
    expect(find.text(StringsAr.nextAyah), findsOneWidget);
  });
}
