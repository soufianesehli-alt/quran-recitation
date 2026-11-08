import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Installs a bundled ASR model (a Flutter asset) as a file, because whisper.cpp loads models
/// from a path. Model weights only: no audio is ever written.
class ModelRepository {
  /// Expected size from the bundled manifest (tools/models/*.manifest.json), so an installed
  /// model is recognised without loading ~80 MB into memory on every launch.
  static Future<int?> expectedBytes(String assetPath) async {
    final name = p.basename(assetPath); // quran-whisper-base-q8_0.bin
    final model = name.replaceFirst(
      RegExp(r'-q\d_\d\.bin$'),
      '',
    ); // quran-whisper-base
    try {
      final m = jsonDecode(
        await rootBundle.loadString('assets/models/$model.manifest.json'),
      );
      return ((m['outputs'] as Map)[name] as Map)['bytes'] as int;
    } catch (_) {
      return null;
    }
  }

  static Future<String> install(String assetPath) async {
    final dir = await getApplicationSupportDirectory();
    final target = File(p.join(dir.path, 'models', p.basename(assetPath)));
    final expected = await expectedBytes(assetPath);
    if (expected != null &&
        await target.exists() &&
        await target.length() == expected) {
      return target.path;
    }
    final data = await rootBundle.load(assetPath);
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.part');
    await tmp.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    await tmp.rename(target.path);
    return target.path;
  }

  static Future<bool> isBundled(String assetPath) async =>
      (await expectedBytes(assetPath)) != null;
}
