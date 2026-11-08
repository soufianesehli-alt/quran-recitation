import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../../app/quran_fonts.dart';
import '../../core/l10n/strings_ar.dart';
import '../../domain/models/finding.dart';
import '../../domain/models/quran.dart';
import '../../engine/live_event.dart';
import '../feedback/feedback_sheet.dart';

/// Live recitation screen (docs/SPEC.md §7): current word underlined, words turn green /
/// orange / red, tap a word for details, gate buttons below.
class RecitationScreen extends ConsumerWidget {
  const RecitationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final ctrl = ref.read(sessionProvider.notifier);
    final font = QuranFonts.familyFor(s.riwaya);
    final setup = ref.watch(asrSetupProvider).value;

    return PopScope(
      onPopInvokedWithResult: (_, _) => ctrl.stop(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('${s.riwaya.nameAr} · ${s.surah}:${s.ayahNumber}'),
        ),
        body: Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: s.ayah == null
                  ? Center(
                      child: s.phase == SessionPhase.error
                          ? Text(s.messageAr ?? '')
                          : const CircularProgressIndicator(),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (s.ayah!.basmalaPrefixChars > 0)
                            Text(
                              s.ayah!.textUthmani
                                  .substring(0, s.ayah!.basmalaPrefixChars)
                                  .trim(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: font,
                                fontSize: 24,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                          const SizedBox(height: 12),
                          AyahWords(
                            ayah: s.ayah!,
                            fontFamily: font,
                            statuses: s.statuses,
                            currentWord: s.phase == SessionPhase.listening
                                ? s.currentWord
                                : null,
                            onTapWord: (w) => FeedbackSheet.show(
                              context,
                              word: w.uthmani,
                              findings: s.findings
                                  .where((f) => f.wordIndex == w.index)
                                  .toList(),
                              fontFamily: font,
                              attempts: s.attempts[w.index] ?? 0,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (s.findings.isNotEmpty)
                            const Text(
                              StringsAr.tapWordHint,
                              textAlign: TextAlign.center,
                            ),
                          if (setup != null && !setup.liveHighlighting)
                            const Text(
                              StringsAr.perSegmentMode,
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                    ),
            ),
            _Controls(state: s, controller: ctrl),
          ],
        ),
      ),
    );
  }
}

/// The ayah as tappable words. Each word keeps its exact source text (never modified).
class AyahWords extends StatelessWidget {
  const AyahWords({
    super.key,
    required this.ayah,
    required this.fontFamily,
    required this.statuses,
    required this.currentWord,
    required this.onTapWord,
  });

  final Ayah ayah;
  final String fontFamily;
  final Map<int, WordStatus> statuses;
  final int? currentWord;
  final void Function(Word) onTapWord;

  static Color? colorFor(WordStatus? s) => switch (s) {
    WordStatus.correct => Colors.green.shade700,
    WordStatus.needsReview => Colors.orange.shade800,
    WordStatus.error => Colors.red.shade700,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final w in ayah.words)
          InkWell(
            key: ValueKey('word-${w.index}'),
            onTap: () => onTapWord(w),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Text(
                w.uthmani,
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: 30,
                  height: 1.9,
                  color: colorFor(statuses[w.index]),
                  decoration: currentWord == w.index
                      ? TextDecoration.underline
                      : null,
                  decorationThickness: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state, required this.controller});

  final SessionState state;
  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final cs = Theme.of(context).colorScheme;
    final blocking = s.findings
        .where((f) => f.severity == Severity.error && f.ruleIsBlocking)
        .length;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (s.messageAr != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  s.messageAr!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color:
                        s.phase == SessionPhase.failed ||
                            s.phase == SessionPhase.error
                        ? cs.error
                        : null,
                  ),
                ),
              ),
            if (s.phase == SessionPhase.failed && blocking > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'عدد الأخطاء المانعة: $blocking',
                  textAlign: TextAlign.center,
                ),
              ),
            switch (s.phase) {
              SessionPhase.loading => const SizedBox.shrink(),
              SessionPhase.preparingEngine => const Column(
                children: [
                  LinearProgressIndicator(),
                  SizedBox(height: 8),
                  Text(StringsAr.preparing),
                ],
              ),
              SessionPhase.listening => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Microphone meter: shows the reciter that their voice is heard.
                  Row(
                    children: [
                      Icon(
                        s.speaking ? Icons.graphic_eq : Icons.mic_none,
                        color: s.speaking ? Colors.green.shade700 : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          key: const ValueKey('mic-level'),
                          value: s.micLevel,
                          minHeight: 6,
                          color: s.speaking
                              ? Colors.green.shade700
                              : cs.outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: controller.stop,
                    icon: const Icon(Icons.stop),
                    label: const Text(
                      '${StringsAr.listening}  ·  ${StringsAr.stopListening}',
                    ),
                  ),
                ],
              ),
              SessionPhase.ready || SessionPhase.error => FilledButton.icon(
                onPressed: controller.start,
                icon: const Icon(Icons.mic),
                label: const Text(StringsAr.listen),
              ),
              SessionPhase.failed => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: controller.retry,
                    icon: const Icon(Icons.replay),
                    label: const Text(StringsAr.retry),
                  ),
                  if (s.offerContinue) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: controller.continueAnyway,
                      child: const Text(StringsAr.continueAnyway),
                    ),
                  ],
                ],
              ),
              SessionPhase.passed =>
                s.hasNextAyah
                    ? FilledButton.icon(
                        onPressed: () => controller.next(),
                        icon: const Icon(
                          Icons.arrow_back,
                        ), // RTL: "forward" points left
                        label: const Text(StringsAr.nextAyah),
                      )
                    : const Text(
                        StringsAr.surahEnd,
                        textAlign: TextAlign.center,
                      ),
            },
          ],
        ),
      ),
    );
  }
}
