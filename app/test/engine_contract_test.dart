import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa/domain/models/quran.dart';
import 'package:tilawa/domain/models/riwaya.dart';
import 'package:tilawa/engine/engine_capabilities.dart';

import 'dart:typed_data';

import 'package:tilawa/engine/offline/asr_backend.dart';
import 'package:tilawa/engine/offline/audio_stream.dart';
import 'package:tilawa/engine/offline/word_aligner.dart';
import 'package:tilawa/engine/offline/offline_engine.dart';
import 'package:tilawa/engine/online/online_engine.dart';
import 'package:tilawa/engine/recitation_engine.dart';

void main() {
  test('OfflineEngine is a RecitationEngine that never uses the network', () {
    final RecitationEngine e = OfflineEngine(
      audio: _NoAudio(),
      asr: _NoAsr(),
      modelPath: 'unused',
      openQuran: (_) => throw UnimplementedError(),
    );
    expect(e.capabilities.usesNetwork, isFalse);
    expect(e.capabilities.supports(RuleFamily.words), isTrue);
    expect(e.capabilities.supports(RuleFamily.makharij), isFalse);
  });

  test('no riwaya is acoustically validated yet => acoustic results are needsReview', () {
    final e = OfflineEngine(
      audio: _NoAudio(),
      asr: _NoAsr(),
      modelPath: 'unused',
      openQuran: (_) => throw UnimplementedError(),
    );
    expect(e.capabilities.acousticallyValidated, isEmpty);
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

class _NoAudio implements AudioSource {
  @override
  Future<bool> hasPermission() async => false;
  @override
  Future<Stream<Int16List>> start() => throw UnimplementedError();
  @override
  Future<void> stop() async {}
}

class _NoAsr implements AsrBackend {
  @override
  Future<void> load(String modelPath) async {}
  @override
  Future<List<HypWord>> transcribe(
    Int16List samples, {
    String? prompt,
    bool fast = false,
  }) async => [];
  @override
  Future<void> dispose() async {}
}
