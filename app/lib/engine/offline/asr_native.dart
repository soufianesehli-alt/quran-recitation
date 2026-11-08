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
  Pointer<Int16>,
  Int32,
  Pointer<Utf8>,
  Int32,
  Int32,
  Int32,
);
typedef _Transcribe = int Function(
  Pointer<Void>,
  Pointer<Int16>,
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
typedef _LoadBackendsN = Void Function(Pointer<Utf8>);
typedef _LoadBackends = void Function(Pointer<Utf8>);
typedef _InfoN = Pointer<Utf8> Function();
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
      _loadBackends = lib.lookupFunction<_LoadBackendsN, _LoadBackends>(
        'tilawa_asr_load_backends',
      ),
      _info = lib.lookupFunction<_InfoN, _InfoN>('tilawa_asr_system_info'),
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
  final _LoadBackends _loadBackends;
  final Pointer<Utf8> Function() _info;
  final _Free _free;
  Pointer<Void> _h = nullptr;

  /// Loads the CPU backend variants from [dir] (Android: the app's native library folder) so
  /// the fastest one this CPU supports is used.
  void loadBackends(String? dir) {
    final p = dir == null ? nullptr : dir.toNativeUtf8();
    try {
      _loadBackends(p.cast());
    } finally {
      if (p != nullptr) calloc.free(p);
    }
  }

  /// Active CPU features (diagnostics only).
  String systemInfo() => _info().toDartString();

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
    int audioCtx = -1,
    int beamSize = 5,
  }) {
    if (_h == nullptr) throw StateError('model not loaded');
    final buf = calloc<Int16>(samples.length);
    final promptPtr = prompt == null ? nullptr : prompt.toNativeUtf8();
    final out = calloc<Pointer<Uint8>>();
    try {
      final view = buf.asTypedList(samples.length)..setAll(0, samples);
      final n = _transcribe(
        _h,
        buf,
        samples.length,
        promptPtr.cast(),
        threads,
        audioCtx,
        beamSize,
      );
      view.fillRange(
        0,
        view.length,
        0,
      ); // do not leave audio in freed native memory
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
    this.backendDir,
    this.threads = 4,
    this.beamSize = 5,
  });

  /// Host tests only; on Android the library is found by name.
  final String? libraryPath;

  /// Folder holding the ggml CPU variant libraries (Android: nativeLibraryDir).
  final String? backendDir;
  final int threads;

  /// Beam size for the final pass of a segment (1 = greedy). Live previews are always greedy.
  final int beamSize;

  /// Active CPU features after [load] (diagnostics only).
  String systemInfo = '';

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
      backendDir,
      threads,
    ]);
    _send = await ready.future;
    final ok = await _call(['load', modelPath]);
    if (ok is! String) throw StateError('ASR model failed to load');
    systemInfo = ok;
  }

  @override
  Future<List<HypWord>> transcribe(
    Int16List samples, {
    String? prompt,
    bool fast = false,
  }) async {
    final res = await _call([
      'run',
      TransferableTypedData.fromList([samples]),
      prompt,
      fast ? 1 : beamSize,
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
    w.loadBackends(args[2] as String?);
    final threads = args[3] as int;
    inbox.listen((raw) {
      final m = raw as List;
      final id = m[0] as int;
      try {
        switch (m[1]) {
          case 'load':
            reply.send([id, w.load(m[2] as String) ? w.systemInfo() : false]);
          case 'run':
            final samples = (m[2] as TransferableTypedData)
                .materialize()
                .asInt16List();
            final toks = w.transcribe(
              samples,
              prompt: m[3] as String?,
              threads: threads,
              beamSize: m[4] as int,
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
