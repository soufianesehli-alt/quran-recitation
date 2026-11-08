import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the "no audio on disk, no audio in logs, no network in V1" rules (docs/SPEC.md §1,
/// docs/ARCHITECTURE.md §6) at source level.
/// Source without comments, so prose like "streams to a WebSocket" is not flagged.
String code(File f) => f
    .readAsStringSync()
    .split('\n')
    .map((l) => l.replaceFirst(RegExp(r'//.*'), ''))
    .join('\n');

void main() {
  final engineFiles = Directory('lib/engine')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  test('engine code cannot touch files, paths or the network', () {
    final banned = RegExp(
      r"import 'dart:io'|package:path_provider|package:http|dart:_http|HttpClient|WebSocket|File\(",
    );
    final offenders = [
      for (final f in engineFiles)
        if (banned.hasMatch(code(f))) f.path,
    ];
    expect(offenders, isEmpty);
  });

  test('engine code does not print or log', () {
    final offenders = [
      for (final f in engineFiles)
        if (RegExp(r'\bprint\(|debugPrint\(|(?<!math\.)\blog\(')
            .hasMatch(code(f)))
          f.path,
    ];
    expect(offenders, isEmpty);
  });

  test('no networking package in V1 dependencies', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final p in ['http:', 'dio:', 'web_socket_channel:', 'firebase']) {
      expect(pubspec.contains(p), isFalse, reason: p);
    }
  });
}
