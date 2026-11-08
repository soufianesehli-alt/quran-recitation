import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa/domain/models/quran.dart';
import 'package:tilawa/domain/models/riwaya.dart';
import 'package:tilawa/engine/engine_capabilities.dart';
import 'package:tilawa/engine/offline/offline_engine.dart';
import 'package:tilawa/engine/online/online_engine.dart';
import 'package:tilawa/engine/recitation_engine.dart';

void main() {
  test('OfflineEngine is a RecitationEngine that never uses the network', () {
    final RecitationEngine e = OfflineEngine();
    expect(e.capabilities.usesNetwork, isFalse);
    expect(e.capabilities.supports(RuleFamily.words), isTrue);
    expect(e.capabilities.supports(RuleFamily.makharij), isFalse);
  });

  test('no riwaya is acoustically validated yet => acoustic results are needsReview', () {
    expect(OfflineEngine().capabilities.acousticallyValidated, isEmpty);
  });

  test('OnlineEngine is a V2 stub that throws', () {
    final RecitationEngine e = OnlineEngine();
    expect(() => e.init(Riwaya.hafs), throwsUnimplementedError);
    expect(
      () => e.start(const AyahRef(riwaya: Riwaya.hafs, surah: 1, ayah: 1)),
      throwsUnimplementedError,
    );
  });
}
