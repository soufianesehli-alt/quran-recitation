import '../../domain/models/quran.dart';
import '../../domain/models/riwaya.dart';
import '../engine_capabilities.dart';
import '../live_event.dart';
import '../recitation_engine.dart';

/// V2 only: streams audio to FastAPI `/v2` over WebSocket for makharij/sifat analysis.
/// In V1 every method throws, and nothing in the app constructs it.
class OnlineEngine implements RecitationEngine {
  @override
  EngineCapabilities get capabilities => const EngineCapabilities(
    families: {},
    usesNetwork: true,
    acousticallyValidated: {},
  );

  @override
  Future<void> init(Riwaya riwaya) =>
      throw UnimplementedError('OnlineEngine is V2');

  @override
  Stream<LiveEvent> start(AyahRef ayah, {int fromWordIndex = 0}) =>
      throw UnimplementedError('OnlineEngine is V2');

  @override
  Future<void> stop() => throw UnimplementedError('OnlineEngine is V2');
}
