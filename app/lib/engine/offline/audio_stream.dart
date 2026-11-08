import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Microphone → 16 kHz mono PCM16 chunks, **in memory only** (docs/SPEC.md §1, §5 step 1).
///
/// Uses `record`'s streaming API: with no output path its Android PCM engine writes to a
/// stream container and never creates a file (verified in record_android 2.2.0 source).
abstract class AudioSource {
  Future<bool> hasPermission();
  Future<Stream<Int16List>> start();
  Future<void> stop();
}

class MicAudioSource implements AudioSource {
  MicAudioSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  static const sampleRate = 16000;
  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Int16List>> start() async {
    final bytes = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: false,
        noiseSuppress: true,
      ),
    );
    return bytes.map(pcm16FromBytes);
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  Future<void> dispose() => _recorder.dispose();
}

/// Little-endian PCM16 bytes → samples (copies, so the platform buffer can be released).
Int16List pcm16FromBytes(Uint8List b) {
  final n = b.length ~/ 2;
  final out = Int16List(n);
  final view = ByteData.sublistView(b);
  for (var i = 0; i < n; i++) {
    out[i] = view.getInt16(i * 2, Endian.little);
  }
  return out;
}
