import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/strings_ar.dart';
import '../../domain/models/finding.dart';

/// Bottom sheet for one word (docs/SPEC.md §7): rule name, expected vs observed, explanation.
class FeedbackSheet extends StatelessWidget {
  const FeedbackSheet({
    super.key,
    required this.word,
    required this.findings,
    this.fontFamily,
    this.attempts = 0,
  });

  final String word;
  final List<Finding> findings;
  final String? fontFamily;
  final int attempts;

  static Future<void> show(
    BuildContext context, {
    required String word,
    required List<Finding> findings,
    String? fontFamily,
    int attempts = 0,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => FeedbackSheet(
      word: word,
      findings: findings,
      fontFamily: fontFamily,
      attempts: attempts,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              word,
              style: TextStyle(fontFamily: fontFamily, fontSize: 34),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (findings.isEmpty)
              const Text(StringsAr.noFindings, textAlign: TextAlign.center),
            for (final f in findings) ...[
              Row(
                children: [
                  _SeverityChip(f.severity),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f.ruleNameAr, style: t.titleMedium)),
                ],
              ),
              const SizedBox(height: 8),
              if (f.expected != null)
                _row(StringsAr.expected, f.expected!, fontFamily),
              if (f.observed != null) _row(StringsAr.heard, f.observed!, null),
              const SizedBox(height: 6),
              Text(f.messageAr, style: t.bodyLarge),
              if (!kReleaseMode)
                Text(
                  'ثقة: ${(f.confidence * 100).toStringAsFixed(0)}٪ · ${f.ruleId}',
                  style: t.bodySmall,
                ),
              const Divider(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, String? font) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Text(value, style: TextStyle(fontFamily: font, fontSize: 22)),
        ),
      ],
    ),
  );
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip(this.severity);
  final Severity severity;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (severity) {
      Severity.error => (StringsAr.severityError, Colors.red.shade700),
      Severity.needsReview => (
        StringsAr.severityReview,
        Colors.orange.shade800,
      ),
      Severity.info => (StringsAr.severityInfo, Colors.blueGrey),
    };
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: color,
      visualDensity: VisualDensity.compact,
    );
  }
}
