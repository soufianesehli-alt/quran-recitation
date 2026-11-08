import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings_ar.dart';
import '../../domain/models/riwaya.dart';
import '../../domain/settings.dart';
import '../debug/debug_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const AppSettings();
    final n = ref.read(settingsProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text(StringsAr.settings)),
      body: ListView(
        children: [
          ListTile(title: const Text(StringsAr.reReciteMode)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ReReciteMode>(
              segments: const [
                ButtonSegment(
                  value: ReReciteMode.segment,
                  label: Text(StringsAr.fromSegment),
                ),
                ButtonSegment(
                  value: ReReciteMode.fullAyah,
                  label: Text(StringsAr.fromAyah),
                ),
              ],
              selected: {s.reReciteMode},
              onSelectionChanged: (v) =>
                  n.change((x) => x.copyWith(reReciteMode: v.first)),
            ),
          ),
          ListTile(
            title: const Text(StringsAr.maxAttempts),
            trailing: DropdownButton<int>(
              value: s.maxAttempts,
              items: [
                for (var i = 1; i <= 10; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (v) => n.change((x) => x.copyWith(maxAttempts: v)),
            ),
          ),
          ListTile(title: const Text(StringsAr.liveMode)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'auto', label: Text(StringsAr.liveAuto)),
                ButtonSegment(value: 'on', label: Text(StringsAr.liveOn)),
                ButtonSegment(value: 'off', label: Text(StringsAr.liveOff)),
              ],
              selected: {
                switch (s.liveHighlighting) {
                  null => 'auto',
                  true => 'on',
                  false => 'off',
                },
              },
              onSelectionChanged: (v) {
                final bool? value = switch (v.first) {
                  'on' => true,
                  'off' => false,
                  _ => null,
                };
                n.change((x) => x.copyWith(liveHighlighting: () => value));
                ref.invalidate(engineProvider);
              },
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text(
              'خيارات أوجه المدّ تُضاف مع محرك أحكام التجويد في المرحلة القادمة.',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text(StringsAr.sources),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AttributionScreen(),
              ),
            ),
          ),
          if (kDebugMode) ...[
            const Divider(),
            ListTile(
              title: Text(
                StringsAr.devSection,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            SwitchListTile(
              title: const Text(StringsAr.devBlocking),
              value: s.devBlockingWordRules,
              onChanged: (v) {
                n.change((x) => x.copyWith(devBlockingWordRules: v));
                ref.invalidate(engineProvider);
              },
            ),
            ListTile(
              title: const Text('النموذج'),
              trailing: DropdownButton<ModelChoice>(
                value: s.modelChoice,
                items: const [
                  DropdownMenuItem(
                    value: ModelChoice.auto,
                    child: Text('تلقائي'),
                  ),
                  DropdownMenuItem(
                    value: ModelChoice.base,
                    child: Text('base'),
                  ),
                  DropdownMenuItem(
                    value: ModelChoice.tiny,
                    child: Text('tiny (تجريبي)'),
                  ),
                ],
                onChanged: (v) {
                  n.change((x) => x.copyWith(modelChoice: v));
                  ref.invalidate(engineProvider);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text(StringsAr.debugScreen),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DebugScreen()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sources and licences (required attribution: Tanzil terms, font licences, model licence).
class AttributionScreen extends ConsumerWidget {
  const AttributionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text(StringsAr.sources)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final r in Riwaya.values)
            ref
                .watch(quranRepoProvider(r))
                .when(
                  data: (repo) => FutureBuilder(
                    future: repo.sourceInfo(),
                    builder: (context, snap) {
                      final i = snap.data;
                      if (i == null) return const SizedBox.shrink();
                      return Card(
                        child: ListTile(
                          title: Text('${r.nameAr}: ${i.source}'),
                          subtitle: Text(
                            '${i.sourceUrl}\nالإصدار: ${i.version}\n${i.license}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
          const Card(
            child: ListTile(
              title: Text('نماذج التعرّف على التلاوة'),
              subtitle: Text(
                'tarteel-ai/whisper-base-ar-quran و whisper-tiny-ar-quran (Apache-2.0)\nمحرك whisper.cpp (MIT)',
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: StringsAr.appTitle,
            ),
            child: const Text('نصوص التراخيص الكاملة'),
          ),
        ],
      ),
    );
  }
}
