import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  // Bundled third-party licences, shown on the licences screen (attribution).
  LicenseRegistry.addLicense(() async* {
    for (final (name, asset) in [
      ('Amiri Quran font', 'assets/fonts/AmiriQuran-OFL.txt'),
      (
        'KFGQPC Uthmanic Warsh font',
        'assets/fonts/KFGQPC-Warsh-font-license.txt',
      ),
      ('whisper.cpp', 'assets/licenses/whisper.cpp-MIT.txt'),
      (
        'Quran Whisper models (tarteel-ai)',
        'assets/licenses/quran-whisper-models-Apache-2.0.txt',
      ),
    ]) {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString(asset));
    }
  });
  runApp(const ProviderScope(child: TilawaApp()));
}
