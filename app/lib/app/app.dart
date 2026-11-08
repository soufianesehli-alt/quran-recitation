import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/strings_ar.dart';
import '../features/first_launch/first_launch_screen.dart';
import '../features/selection/selection_screen.dart';
import 'providers.dart';

class TilawaApp extends StatelessWidget {
  const TilawaApp({super.key, this.home});

  /// Tests can inject a screen; the app decides between first launch and selection.
  final Widget? home;

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
      home: home ?? const _Root(),
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return settings.when(
      data: (s) => s.firstLaunchDone
          ? const SelectionScreen()
          : const FirstLaunchScreen(),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const SelectionScreen(),
    );
  }
}

/// Offline banner shown on every main screen in V1 (docs/SPEC.md §7).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        StringsAr.offlineBanner,
        style: TextStyle(color: cs.onSecondaryContainer),
        textAlign: TextAlign.center,
      ),
    );
  }
}
