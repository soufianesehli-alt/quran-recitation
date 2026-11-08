import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa/core/arabic/normalizer.dart';

void main() {
  test(
    'Dart normalizer matches the shared vectors (same as the Python build)',
    () {
      final json = jsonDecode(
        File('../tools/normalizer_vectors.json').readAsStringSync(),
      );
      final vectors = (json['vectors'] as List).cast<Map<String, dynamic>>();
      expect(vectors, isNotEmpty);
      for (final v in vectors) {
        expect(
          ArabicNormalizer.normalize(v['in'] as String),
          v['out'],
          reason: v['in'] as String,
        );
      }
    },
  );
}
