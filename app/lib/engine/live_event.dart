import '../domain/models/finding.dart';
import '../domain/models/quran.dart';

/// Status of one expected word after alignment (docs/SPEC.md §5, step 4).
enum WordStatus { pending, correct, needsReview, error }

/// Events emitted while an ayah is being recited.
sealed class LiveEvent {
  const LiveEvent(this.ayah);
  final AyahRef ayah;
}

/// The reciter is now on [wordIndex] (drives the underline).
final class CurrentWordEvent extends LiveEvent {
  const CurrentWordEvent(super.ayah, this.wordIndex);
  final int wordIndex;
}

/// [wordIndex] has been aligned and has a status (drives green/orange/red).
final class WordResultEvent extends LiveEvent {
  const WordResultEvent(super.ayah, this.wordIndex, this.status);
  final int wordIndex;
  final WordStatus status;
}

final class FindingEvent extends LiveEvent {
  const FindingEvent(super.ayah, this.finding);
  final Finding finding;
}

/// The ayah has ended (final pause or last word). [findings] is the complete list for
/// this attempt and is what the gate evaluates.
final class AyahCompleteEvent extends LiveEvent {
  const AyahCompleteEvent(super.ayah, this.findings);
  final List<Finding> findings;
}

/// Microphone level, about every 100 ms, in [0, 1] (for the on-screen meter only).
final class MicLevelEvent extends LiveEvent {
  const MicLevelEvent(super.ayah, this.level, {required this.speaking});
  final double level;
  final bool speaking;
}

/// Recoverable engine problem (e.g. microphone lost). [messageAr] is user-facing.
final class EngineErrorEvent extends LiveEvent {
  const EngineErrorEvent(super.ayah, this.messageAr);
  final String messageAr;
}
