import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guard for the V1 "no network" rule (docs/SPEC.md §4). The merged release
/// manifest of a built APK is checked by tools/check_release_manifest.sh.
void main() {
  final main = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();
  final release = File('android/app/src/release/AndroidManifest.xml')
      .readAsStringSync();
  final permission = RegExp(
    r'<uses-permission[^>]*android:name="([^"]+)"[^>]*>',
  );

  test('main manifest requests RECORD_AUDIO and nothing else', () {
    final perms = permission.allMatches(main).map((m) => m.group(1)).toList();
    expect(perms, ['android.permission.RECORD_AUDIO']);
  });

  test('release manifest removes INTERNET and ACCESS_NETWORK_STATE', () {
    for (final p in ['INTERNET', 'ACCESS_NETWORK_STATE']) {
      expect(
        release,
        matches(RegExp('android.permission.$p"\\s+tools:node="remove"')),
        reason: p,
      );
    }
  });
}
