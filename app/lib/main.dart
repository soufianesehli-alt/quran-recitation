import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'app/app.dart';

void main() {
  // Bundled third-party licenses, shown on the licenses screen (attribution).
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Amiri Quran font',
    ], await rootBundle.loadString('assets/fonts/AmiriQuran-OFL.txt'));
  });
  runApp(const TilawaApp());
}
