import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/l10n/strings_ar.dart';

class TilawaApp extends StatelessWidget {
  const TilawaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: StringsAr.appTitle,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B5E20),
        useMaterial3: true,
      ),
      home: const _PlaceholderHome(),
    );
  }
}

/// Phase 1 placeholder. Replaced by features/selection in Phase 3.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(StringsAr.appTitle)),
      body: const Column(
        children: [
          MaterialBanner(
            content: Text(StringsAr.offlineBanner),
            actions: [SizedBox.shrink()],
          ),
          Expanded(child: Center(child: Text(StringsAr.noAudioStored))),
        ],
      ),
    );
  }
}
