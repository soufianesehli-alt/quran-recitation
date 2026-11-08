import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'asr_backend.dart';
import 'word_aligner.dart';

// ── Raw FFI bindings to app/native/tilawa_asr ───────────────────────────────────────────
typedef _InitN = Pointer<Void> Function(Pointer<Utf8>);
typedef _Init = Pointer<Void> Function(Pointer<Utf8>);
typedef _TranscribeN = Int32 Function(
  Pointer<Void>,
  Pointer<Float>,
  Int32,
  Pointer<Utf8>,
  Int32,
  Int32,
  Int32,
);
typedef _Transcribe = int Function(
  Pointer<Void>,
  Pointer<Float>,
  int,
  Pointer<Utf8>,
  int,
  int,
  int,
);
typedef _TokBytesN = Int32 Function(
  Pointer<Void>,
  Int32,
  Pointer<Pointer<Uint8>>,
);
typedef _TokBytes = int Function(Pointer<Void>, int, Pointer<Pointer<Uint8>>);
typedef _TokPN = Float Function(Pointer<Void>, Int32);
typedef _TokP = double Function(Pointer<Void>, int);
typedef _TokTN = Int64 Function(Pointer<Void>, Int32);
typedef _TokT = int Function(Pointer<Void>, int);
typedef _FreeN = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);

/// Synchronous wrapper around libtilawa_asr. Must run off the UI isolate.
class NativeWhisper {
  NativeWhisper(DynamicLibrary lib)
    : _init = lib.lookupFunction<_InitN, _Init>('tilawa_asr_init'),
      _transcribe = lib.lookupFunction<_TranscribeN, _Transcribe>(
        'tilawa_asr_transcribe',
      ),
      _tokBytes = lib.lookupFunction<_TokBytesN, _TokBytes>(
        'tilawa_asr_token_bytes',
      ),
      _tokP = lib.lookupFunction<_TokPN, _TokP>('tilawa_asr_token_p'),
      _tokT0 = lib.lookupFunction<_TokTN, _TokT>('tilawa_asr_token_t0_ms'),
      _tokT1 = lib.lookupFunction<_TokTN, _TokT>('tilawa_asr_token_t1_ms'),
      _free = lib.lookupFunction<_FreeN, _Free>('tilawa_asr_free');

  /// Opens the library bundled in the APK (or [path] on a host machine for tests).
  factory NativeWhisper.open([String? path]) =>
      NativeWhisper(DynamicLibrary.open(path ?? 'libtilawa_asr.so'));

  final _Init _init;
  final _Transcribe _transcribe;
  final _TokBytes _tokBytes;
  final _TokP _tokP;
  final _TokT _tokT0;
  final _TokT _tokT1;
  final _Free _free;
  Pointer<Void> _h = nullptr;

  bool load(String modelPath) {
    final p = modelPath.toNativeUtf8();
    try {
      _h = _init(p);
    } finally {
      calloc.free(p);
    }
    return _h != nullptr;
  }

  /// Returns tokens, or throws on failure. The float copy of the audio is freed (and zeroed)
  /// before returning.
  List<AsrToken> transcribe(
    Int16List samples, {
    String? prompt,
    int threads = 4,
    int audioCtx = 0,
    int beamSize = 5,
  }) {
    if (_h == nullptr) throw StateError('model not loaded');
    final buf = calloc<Float>(samples.length);
    final promptPtr = prompt == null ? nullptr : prompt.toNativeUtf8();
    final out = calloc<Pointer<Uint8>>();
    try {
      final f = buf.asTypedList(samples.length);
      for (var i = 0; i < samples.length; i++) {
        f[i] = samples[i] / 32768.0;
      }
      final n = _transcribe(
        _h,
        buf,
        samples.length,
        promptPtr.cast(),
        threads,
        audioCtx,
        beamSize,
      );
      f.fillRange(0, f.length, 0); // do not leave audio in freed native memory
      if (n < 0) throw StateError('transcription failed');
      final tokens = <AsrToken>[];
      for (var i = 0; i < n; i++) {
        final len = _tokBytes(_h, i, out);
        final bytes = len > 0 && out.value != nullptr
            ? Uint8List.fromList(out.value.asTypedList(len))
            : Uint8List(0);
        tokens.add(AsrToken(bytes, _tokP(_h, i), _tokT0(_h, i), _tokT1(_h, i)));
      }
      return tokens;
    } finally {
      calloc.free(buf);
      if (promptPtr != nullptr) calloc.free(promptPtr);
      calloc.free(out);
    }
  }

  void dispose() {
    if (_h != nullptr) _free(_h);
    _h = nullptr;
  }
}

// ── Background isolate owning the model ─────────────────────────────────────────────────

/// [AsrBackend] running [NativeWhisper] in a dedicated isolate so recognition never blocks
/// the UI. Audio crosses the isolate boundary as transferable memory, never as a file.
class IsolateAsrBackend implements AsrBackend {
  IsolateAsrBackend({
    this.libraryPath,
    this.threads = 4,
    this.audioCtx = 0,
    this.beamSize = 5,
  });

  final String? libraryPath;
  final int threads;
  final int audioCtx;

  /// 1 = greedy; >1 = beam search (default 5: far more robust with the prompt, ~1.6x slower).
  final int beamSize;

  Isolate? _isolate;
  SendPort? _send;
  final _replies = ReceivePort();
  final _pending = <int, Completer<Object?>>{};
  int _nextId = 0;

  @override
  Future<void> load(String modelPath) async {
    final ready = Completer<SendPort>();
    _replies.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else if (msg is List && msg.length == 2) {
        _pending.remove(msg[0] as int)?.complete(msg[1]);
      }
    });
    _isolate = await Isolate.spawn(_worker, [
      _replies.sendPort,
      libraryPath,
      threads,
      audioCtx,
      beamSize,
    ]);
    _send = await ready.future;
    final ok = await _call(['load', modelPath]);
    if (ok != true) throw StateError('ASR model failed to load: $ok');
  }

  @override
  Future<List<HypWord>> transcribe(Int16List samples, {String? prompt}) async {
    final res = await _call([
      'run',
      TransferableTypedData.fromList([samples]),
      prompt,
    ]);
    if (res is! List) throw StateError('ASR failed: $res');
    final tokens = [
      for (final t in res.cast<List>())
        AsrToken(
          (t[0] as TransferableTypedData).materialize().asUint8List(),
          t[1] as double,
          t[2] as int,
          t[3] as int,
        ),
    ];
    return groupTokensIntoWords(tokens);
  }

  Future<Object?> _call(List<Object?> msg) {
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _send!.send([id, ...msg]);
    return c.future;
  }

  @override
  Future<void> dispose() async {
    if (_send != null) await _call(['dispose']);
    _isolate?.kill();
    _replies.close();
    _isolate = null;
    _send = null;
  }

  static void _worker(List<Object?> args) {
    final reply = args[0] as SendPort;
    final inbox = ReceivePort();
    reply.send(inbox.sendPort);
    final w = NativeWhisper.open(args[1] as String?);
    final threads = args[2] as int;
    final audioCtx = args[3] as int;
    final beamSize = args[4] as int;
    inbox.listen((raw) {
      final m = raw as List;
      final id = m[0] as int;
      try {
        switch (m[1]) {
          case 'load':
            reply.send([id, w.load(m[2] as String)]);
          case 'run':
            final samples = (m[2] as TransferableTypedData)
                .materialize()
                .asInt16List();
            final toks = w.transcribe(
              samples,
              prompt: m[3] as String?,
              threads: threads,
              audioCtx: audioCtx,
              beamSize: beamSize,
            );
            samples.fillRange(0, samples.length, 0);
            reply.send([
              id,
              [
                for (final t in toks)
                  [
                    TransferableTypedData.fromList([t.bytes]),
                    t.p,
                    t.t0Ms,
                    t.t1Ms,
                  ],
              ],
            ]);
          case 'dispose':
            w.dispose();
            reply.send([id, true]);
            inbox.close();
        }
      } catch (e) {
        reply.send([id, e.toString()]);
      }
    });
  }
}
