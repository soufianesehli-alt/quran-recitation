import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa/app/quran_fonts.dart';
import 'package:tilawa/domain/models/riwaya.dart';

void main() {
  test('each riwaya has its own bundled font', () {
    expect(QuranFonts.familyFor(Riwaya.hafs), QuranFonts.amiriQuran);
    expect(QuranFonts.familyFor(Riwaya.warsh), QuranFonts.kfgqpcWarsh);
  });

  test(
    'the KFGQPC Warsh font ships unmodified with its embedded license text',
    () {
      expect(File('assets/fonts/uthmanic_warsh_v21.ttf').lengthSync(), 871636);
      final lic = File('assets/fonts/KFGQPC-Warsh-font-license.txt')
          .readAsStringSync();
      expect(lic, contains('ELECTRONIC END-USER LICENSE AGREEMENT'));
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('family: KfgqpcWarsh'),
      );
    },
  );

  test('the font ships with its OFL license and is declared in pubspec', () {
    expect(File('assets/fonts/AmiriQuran-Regular.ttf').existsSync(), isTrue);
    final ofl = File('assets/fonts/AmiriQuran-OFL.txt').readAsStringSync();
    expect(ofl, contains('SIL Open Font License, Version 1.1'));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: AmiriQuran'));
    expect(pubspec, contains('assets/fonts/AmiriQuran-OFL.txt'));
  });

  testWidgets('Quran text renders with the Hafs font, right to left', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            'ٱلْحَمْدُ', // a word from Tanzil 1:2
            style: TextStyle(fontFamily: QuranFonts.familyFor(Riwaya.hafs)),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.style!.fontFamily, 'AmiriQuran');
  });
}
