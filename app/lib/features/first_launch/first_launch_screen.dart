import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings_ar.dart';
import '../../engine/offline/audio_stream.dart';
import '../selection/selection_screen.dart';

/// First launch (docs/SPEC.md §7): what the app does, the no-recording promise, mic permission.
class FirstLaunchScreen extends ConsumerStatefulWidget {
  const FirstLaunchScreen({super.key, this.requestPermission});

  /// Injected in tests; defaults to the microphone permission request.
  final Future<bool> Function()? requestPermission;

  @override
  ConsumerState<FirstLaunchScreen> createState() => _FirstLaunchScreenState();
}

class _FirstLaunchScreenState extends ConsumerState<FirstLaunchScreen> {
  bool _denied = false;

  Future<void> _allow() async {
    final ok =
        await (widget.requestPermission ??
            () => MicAudioSource().hasPermission())();
    if (!mounted) return;
    if (!ok) {
      setState(() => _denied = true);
      return;
    }
    await ref
        .read(settingsProvider.notifier)
        .change((s) => s.copyWith(firstLaunchDone: true));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const SelectionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            Icon(
              Icons.mic_none,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              StringsAr.welcomeTitle,
              style: t.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(StringsAr.welcomeBody, style: t.bodyLarge),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: Text(StringsAr.noAudioStored, style: t.titleMedium),
                subtitle: const Text(StringsAr.privacyBody),
              ),
            ),
            const SizedBox(height: 12),
            const Text(StringsAr.reviewNotice),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _allow,
              icon: const Icon(Icons.mic),
              label: const Text(StringsAr.allowMic),
            ),
            if (_denied) ...[
              const SizedBox(height: 12),
              Text(
                StringsAr.micDenied,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
