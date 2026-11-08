import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa/domain/ayah_gate.dart';
import 'package:tilawa/domain/models/finding.dart';
import 'package:tilawa/domain/models/quran.dart';
import 'package:tilawa/domain/models/riwaya.dart';

Finding f({
  Severity severity = Severity.error,
  double confidence = 0.95,
  bool blocking = true,
}) => Finding(
  wordIndex: 0,
  word: 'w',
  errorType: ErrorType.substitution,
  ruleId: 'word.substitution',
  ruleNameAr: 'إبدال كلمة',
  severity: severity,
  confidence: confidence,
  messageAr: '-',
  ruleIsBlocking: blocking,
);

void main() {
  group('Riwaya', () {
    test('ids match backend /check values', () {
      expect(Riwaya.fromId('hafs'), Riwaya.hafs);
      expect(Riwaya.fromId('warsh'), Riwaya.warsh);
      expect(() => Riwaya.fromId('qalun'), throwsArgumentError);
    });

    test('Hafs and Warsh use different ayah numbering', () {
      expect(Riwaya.hafs.numbering, isNot(Riwaya.warsh.numbering));
    });

    test('AyahRef equality includes the riwaya', () {
      const h = AyahRef(riwaya: Riwaya.hafs, surah: 1, ayah: 1);
      const w = AyahRef(riwaya: Riwaya.warsh, surah: 1, ayah: 1);
      expect(h, isNot(w));
      expect(h, const AyahRef(riwaya: Riwaya.hafs, surah: 1, ayah: 1));
    });
  });

  group('AyahGate', () {
    const gate = AyahGate();

    test('no findings: can advance', () => expect(gate.canAdvance([]), isTrue));

    test('high-confidence error of a validated rule blocks', () {
      expect(gate.canAdvance([f()]), isFalse);
    });

    test('needsReview never blocks, even at full confidence', () {
      expect(
        gate.canAdvance([f(severity: Severity.needsReview, confidence: 1)]),
        isTrue,
      );
    });

    test('low-confidence error does not block', () {
      expect(gate.canAdvance([f(confidence: 0.6)]), isTrue);
    });

    test('rule not yet validated (blocking: false) never blocks', () {
      expect(gate.canAdvance([f(blocking: false, confidence: 1)]), isTrue);
    });

    test('continue-anyway offered after max attempts', () {
      expect(gate.offerContinueAnyway(2), isFalse);
      expect(gate.offerContinueAnyway(3), isTrue);
    });
  });
}
