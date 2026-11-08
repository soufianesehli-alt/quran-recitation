import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Installs a bundled ASR model (a Flutter asset) as a file, because whisper.cpp loads models
/// from a path. Model weights only: no audio is ever written.
class ModelRepository {
  static Future<String> install(String assetPath) async {
    final dir = await getApplicationSupportDirectory();
    final target = File(p.join(dir.path, 'models', p.basename(assetPath)));
    final data = await rootBundle.load(assetPath);
    if (!await target.exists() || await target.length() != data.lengthInBytes) {
      await target.parent.create(recursive: true);
      final tmp = File('${target.path}.part');
      await tmp.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await tmp.rename(target.path);
    }
    return target.path;
  }

  static Future<bool> isBundled(String assetPath) async {
    try {
      await rootBundle.load(assetPath);
      return true;
    } catch (_) {
      return false;
    }
  }
}
