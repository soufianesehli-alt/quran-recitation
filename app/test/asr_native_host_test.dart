@Tags(['native'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa/engine/offline/asr_native.dart';

// Opt-in end-to-end check of libtilawa_asr + Dart FFI + isolate on a host machine:
//   TILAWA_ASR_LIB=<libtilawa_asr.so> TILAWA_ASR_MODEL=<ggml .bin> TILAWA_TEST_WAV=<16k mono wav>
//   flutter test test/asr_native_host_test.dart
// Skipped when the variables are not set (library and model are not committed).
void main() {
  final env = Platform.environment;
  final lib = env['TILAWA_ASR_LIB'],
      model = env['TILAWA_ASR_MODEL'],
      wav = env['TILAWA_TEST_WAV'];
  final skip = (lib == null || model == null || wav == null)
      ? 'native ASR env not set'
      : null;

  Int16List readWav(String path) {
    final b = File(path).readAsBytesSync();
    return Int16List.sublistView(
      Uint8List.fromList(b.sublist(44)),
    ); // PCM16 mono after header
  }

  test('isolate backend loads the model and returns timed words', () async {
    final asr = IsolateAsrBackend(
      libraryPath: lib,
      backendDir: env['TILAWA_ASR_BACKENDS'],
    );
    await asr.load(model!);
    final audio = readWav(wav!);
    final prompt = env['TILAWA_TEST_PROMPT'];

    final sw = Stopwatch()..start();
    final live = await asr.transcribe(audio, prompt: prompt, fast: true);
    final liveMs = sw.elapsedMilliseconds;
    sw.reset();
    final words = await asr.transcribe(audio, prompt: prompt);
    final finalMs = sw.elapsedMilliseconds;
    final info = asr.systemInfo;
    await asr.dispose();

    stdout
      ..writeln('CPU ${info.length > 80 ? info.substring(0, 80) : info}')
      ..writeln('LIVE ${liveMs}ms: ${live.map((w) => w.text).join(' ')}')
      ..writeln(
        'FINAL ${finalMs}ms: ${words.map((w) => '${w.text}(${w.confidence.toStringAsFixed(2)})').join(' ')}',
      );
    expect(words, isNotEmpty);
    for (final w in words) {
      expect(w.confidence, inInclusiveRange(0, 1));
      expect(w.startMs, isNotNull);
      expect(w.endMs! >= w.startMs!, isTrue);
    }
  }, skip: skip);
}
