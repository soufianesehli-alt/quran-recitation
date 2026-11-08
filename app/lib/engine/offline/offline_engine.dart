import '../../domain/models/quran.dart';
import '../../domain/models/riwaya.dart';
import '../engine_capabilities.dart';
import '../live_event.dart';
import '../recitation_engine.dart';

/// V1 engine: mic → VAD → on-device ASR constrained to the expected ayah → word alignment
/// → madd/ghunnah checks. Implemented in Phase 3 (pipeline) and Phase 4 (tajweed checks).
class OfflineEngine implements RecitationEngine {
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    families: {RuleFamily.words, RuleFamily.madd, RuleFamily.ghunnah},
    usesNetwork: false,
    // Empty until a model trained/validated per riwaya exists: every acoustic finding
    // is needsReview for now.
    acousticallyValidated: {},
  );

  @override
  Future<void> init(Riwaya riwaya) =>
      throw UnimplementedError('OfflineEngine.init: Phase 3');

  @override
  Stream<LiveEvent> start(AyahRef ayah) =>
      throw UnimplementedError('OfflineEngine.start: Phase 3');

  @override
  Future<void> stop() async {}
}
