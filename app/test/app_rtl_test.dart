import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilawa/app/app.dart';
import 'package:tilawa/core/l10n/strings_ar.dart';

void main() {
  testWidgets('app is Arabic, right-to-left, and shows the offline banner', (
    tester,
  ) async {
    await tester.pumpWidget(const TilawaApp());
    await tester.pumpAndSettle();

    final ctx = tester.element(find.text(StringsAr.offlineBanner));
    expect(Directionality.of(ctx), TextDirection.rtl);
    expect(find.text(StringsAr.noAudioStored), findsOneWidget);
  });
}
