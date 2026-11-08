import 'dart:math' as math;
import 'dart:typed_data';

enum VadEventType { speechStart, pause, longPause }

class VadEvent {
  const VadEvent(this.type, this.atMs, {this.pauseMs = 0});

  final VadEventType type;

  /// Time of the event from the start of the session.
  final int atMs;

  /// Length of the silence for pause events.
  final int pauseMs;
}

/// Energy voice-activity detector with an adaptive noise floor (docs/SPEC.md §5 step 2).
///
/// Deterministic and model-free, so it runs identically on every phone tier. Emits:
/// - [VadEventType.speechStart] when speech begins (again after every pause);
/// - [VadEventType.pause] once silence lasts [pauseMs] (a waqf candidate);
/// - [VadEventType.longPause] once silence lasts [longPauseMs] (end of the ayah attempt).
class EnergyVad {
  EnergyVad({
    this.sampleRate = 16000,
    this.frameMs = 20,
    this.speechMarginDb = 8,
    this.pauseMs = 500,
    this.longPauseMs = 1500,
    this.minSpeechMs = 100,
  });

  final int sampleRate;
  final int frameMs;
  final double speechMarginDb;
  final int pauseMs;
  final int longPauseMs;
  final int minSpeechMs;

  double _noiseDb = -60;
  bool _floorReady = false;
  int _framesSeen = 0;
  bool _inSpeech = false;
  int _speechRunMs = 0;
  int _silenceRunMs = 0;
  bool _pauseSent = false;
  bool _longPauseSent = false;
  final List<int> _carry = [];

  int get _frameSamples => sampleRate * frameMs ~/ 1000;
  bool get inSpeech => _inSpeech;

  /// Level of the last frame in dB (for the on-screen microphone meter).
  double lastDb = -90;
  double get noiseFloorDb => _noiseDb;

  /// Feeds samples, returns the events they trigger, in order.
  List<VadEvent> process(Int16List samples) {
    final events = <VadEvent>[];
    _carry.addAll(samples);
    while (_carry.length >= _frameSamples) {
      final frame = _carry.sublist(0, _frameSamples);
      _carry.removeRange(0, _frameSamples);
      _framesSeen++;
      final now = _framesSeen * frameMs;
      final db = _rmsDb(frame);
      lastDb = db;

      // Calibrate the noise floor on the first 200 ms, then track it during silence only.
      if (!_floorReady) {
        _noiseDb = _framesSeen == 1 ? db : 0.8 * _noiseDb + 0.2 * db;
        if (_framesSeen * frameMs >= 200) _floorReady = true;
        continue;
      }
      final speech = db > _noiseDb + speechMarginDb;
      if (speech) {
        _speechRunMs += frameMs;
        if (!_inSpeech && _speechRunMs >= minSpeechMs) {
          _inSpeech = true;
          _silenceRunMs = 0;
          _pauseSent = false;
          _longPauseSent = false;
          events.add(VadEvent(VadEventType.speechStart, now - _speechRunMs));
        }
        if (_inSpeech) _silenceRunMs = 0;
      } else {
        _speechRunMs = 0;
        _noiseDb = 0.95 * _noiseDb + 0.05 * db;
        // Count silence while speaking, and after a short pause until the long pause fires.
        if (_inSpeech || (_pauseSent && !_longPauseSent)) {
          _silenceRunMs += frameMs;
          if (_inSpeech && _silenceRunMs >= pauseMs) {
            _inSpeech =
                false; // speech resuming after this starts a new segment
            _pauseSent = true;
            events.add(
              VadEvent(VadEventType.pause, now, pauseMs: _silenceRunMs),
            );
          }
          if (_pauseSent && !_longPauseSent && _silenceRunMs >= longPauseMs) {
            _longPauseSent = true;
            events.add(
              VadEvent(VadEventType.longPause, now, pauseMs: _silenceRunMs),
            );
          }
        }
      }
    }
    return events;
  }

  void reset() {
    _noiseDb = -60;
    _floorReady = false;
    _framesSeen = 0;
    _inSpeech = false;
    _speechRunMs = 0;
    _silenceRunMs = 0;
    _pauseSent = false;
    _longPauseSent = false;
    _carry.clear();
  }

  static double _rmsDb(List<int> frame) {
    var sum = 0.0;
    for (final s in frame) {
      sum += s * s;
    }
    final rms = math.sqrt(sum / frame.length) / 32768.0;
    return 20 * math.log(rms + 1e-9) / math.ln10;
  }
}
