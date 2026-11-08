import '../domain/models/quran.dart';
import '../domain/models/riwaya.dart';
import 'engine_capabilities.dart';
import 'live_event.dart';

/// Contract shared by the V1 offline engine and the V2 online engine (docs/SPEC.md §5).
///
/// Privacy invariant for EVERY implementation: audio lives only in memory, is discarded as
/// soon as it is processed, and is never written to disk, logs or (V1) the network.
abstract class RecitationEngine {
  /// Loads text, rules and model for [riwaya]. Must be called before [start].
  Future<void> init(Riwaya riwaya);

  /// Starts listening for [ayah] and emits live events until the ayah completes or
  /// [stop] is called. The stream closes after [AyahCompleteEvent].
  /// [fromWordIndex] restarts inside the ayah (re-recitation from a waqf segment, §7).
  Stream<LiveEvent> start(AyahRef ayah, {int fromWordIndex = 0});

  /// Stops listening and releases the microphone and all audio buffers.
  Future<void> stop();

  EngineCapabilities get capabilities;
}
