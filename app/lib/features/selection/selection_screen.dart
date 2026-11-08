import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../../app/quran_fonts.dart';
import '../../core/l10n/strings_ar.dart';
import '../../domain/models/quran.dart';
import '../../domain/models/riwaya.dart';
import '../recitation/recitation_screen.dart';
import '../settings/settings_screen.dart';

final _surahsProvider = FutureProvider.family<List<Surah>, Riwaya>(
  (ref, r) async => (await ref.watch(quranRepoProvider(r).future)).surahs(),
);

final _unlockedProvider = FutureProvider.family<int, (Riwaya, int)>(
  (ref, k) async =>
      (await ref.watch(appStoreProvider.future)).lastUnlocked(k.$1, k.$2),
);

/// Choose riwaya, surah and starting ayah (docs/SPEC.md §1).
class SelectionScreen extends ConsumerStatefulWidget {
  const SelectionScreen({super.key});

  @override
  ConsumerState<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends ConsumerState<SelectionScreen> {
  int _surah = 1;
  int _ayah = 1;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final riwaya = settings?.riwaya ?? Riwaya.hafs;
    final surahs = ref.watch(_surahsProvider(riwaya));
    final unlocked = ref.watch(_unlockedProvider((riwaya, _surah))).value ?? 0;
    final font = QuranFonts.familyFor(riwaya);

    return Scaffold(
      appBar: AppBar(
        title: const Text(StringsAr.appTitle),
        actions: [
          IconButton(
            tooltip: StringsAr.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  StringsAr.riwaya,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SegmentedButton<Riwaya>(
                  segments: [
                    for (final r in Riwaya.values)
                      ButtonSegment(value: r, label: Text(r.nameAr)),
                  ],
                  selected: {riwaya},
                  onSelectionChanged: (s) {
                    setState(() {
                      _surah = 1;
                      _ayah = 1;
                    });
                    ref
                        .read(settingsProvider.notifier)
                        .change((x) => x.copyWith(riwaya: s.first));
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  StringsAr.surah,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                surahs.when(
                  data: (list) => DropdownButtonFormField<int>(
                    key: ValueKey(riwaya),
                    initialValue: _surah,
                    isExpanded: true,
                    menuMaxHeight: 420,
                    items: [
                      for (final s in list)
                        DropdownMenuItem(
                          value: s.number,
                          child: Row(
                            children: [
                              SizedBox(width: 36, child: Text('${s.number}')),
                              Expanded(
                                child: Text(
                                  s.nameAr,
                                  style: TextStyle(
                                    fontFamily: font,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                              Text(
                                '${s.ayahCount}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _surah = v ?? 1;
                      _ayah = 1;
                    }),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('تعذّر تحميل السور.'),
                ),
                const SizedBox(height: 24),
                Text(
                  StringsAr.startAyah,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final count =
                        surahs.value
                            ?.firstWhere((s) => s.number == _surah)
                            .ayahCount ??
                        1;
                    return DropdownButtonFormField<int>(
                      key: ValueKey('$riwaya-$_surah'),
                      initialValue: _ayah.clamp(1, count),
                      menuMaxHeight: 420,
                      items: [
                        for (var a = 1; a <= count; a++)
                          DropdownMenuItem(value: a, child: Text('$a')),
                      ],
                      onChanged: (v) => setState(() => _ayah = v ?? 1),
                    );
                  },
                ),
                if (unlocked > 0) ...[
                  const SizedBox(height: 8),
                  Text('${StringsAr.lastUnlocked}: $unlocked'),
                ],
                const SizedBox(height: 32),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(StringsAr.start),
                  onPressed: surahs.hasValue
                      ? () async {
                          // Start loading the model now, so it is ready when the
                          // reciter taps "listen".
                          ref.read(engineProvider(riwaya).future).ignore();
                          await ref
                              .read(sessionProvider.notifier)
                              .open(riwaya, _surah, _ayah);
                          if (!context.mounted) return;
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const RecitationScreen(),
                            ),
                          );
                          ref.invalidate(_unlockedProvider((riwaya, _surah)));
                        }
                      : null,
                ),
                if (!kReleaseMode) ...[
                  const SizedBox(height: 16),
                  const Text('نسخة تطوير', textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
