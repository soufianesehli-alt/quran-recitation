import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/model_repository.dart';
import '../../domain/device_tier.dart';
import '../../engine/offline/asr_native.dart';
import '../../engine/offline/audio_stream.dart';
import '../../engine/offline/ring_buffer.dart';

/// DEV BUILDS ONLY (reached from settings under kDebugMode): device tier, timing metrics and
/// an on-device speed test. Audio for the speed test stays in memory and is zeroed after use.
class DebugScreen extends ConsumerStatefulWidget {
  const DebugScreen({super.key});

  @override
  ConsumerState<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends ConsumerState<DebugScreen> {
  final List<String> _bench = [];
  bool _running = false;

  static String _pct(List<num> v, double q) {
    if (v.isEmpty) return '-';
    final s = [...v]..sort();
    return s[((s.length - 1) * q).round()].toStringAsFixed(0);
  }

  Future<void> _runBenchmark() async {
    setState(() {
      _running = true;
      _bench
        ..clear()
        ..add('اقرأ آيةً قصيرة الآن (5 ثوانٍ)…');
    });
    final mic = MicAudioSource();
    final buf = PcmRingBuffer(capacitySamples: MicAudioSource.sampleRate * 6);
    try {
      if (!await mic.hasPermission()) throw StateError('no mic permission');
      final sub = (await mic.start()).listen(buf.write);
      await Future<void>.delayed(const Duration(seconds: 5));
      await sub.cancel();
      await mic.stop();
      final audio = buf.last(buf.length);
      setState(
        () => _bench.add(
          'صوت: ${audio.length * 1000 ~/ MicAudioSource.sampleRate} ms (في الذاكرة فقط)',
        ),
      );
      final info = await ref.read(deviceInfoProvider.future);
      for (final asset in [AsrSetup.baseModel, AsrSetup.tinyModel]) {
        if (!await ModelRepository.isBundled(asset)) continue;
        final path = await ModelRepository.install(asset);
        final asr = IsolateAsrBackend(
          threads: info.cpuCores.clamp(2, 6),
          beamSize: 5,
          backendDir: info.nativeLibDir,
        );
        final load = Stopwatch()..start();
        await asr.load(path);
        final loadMs = load.elapsedMilliseconds;
        final name = asset.split('/').last.replaceAll('.bin', '');
        if (asset == AsrSetup.baseModel) {
          setState(() => _bench.add('CPU: ${asr.systemInfo}'));
        }
        for (final fast in [true, false]) {
          final run = Stopwatch()..start();
          final words = await asr.transcribe(
            Int16List.fromList(audio),
            fast: fast,
          );
          final runMs = run.elapsedMilliseconds;
          setState(
            () => _bench.add(
              '$name ${fast ? "مباشر (greedy)" : "نهائي (beam 5)"}: '
              'تحميل $loadMs ms · تعرّف $runMs ms · ${words.length} كلمة',
            ),
          );
        }
        await asr.dispose();
      }
      audio.fillRange(0, audio.length, 0);
    } catch (e) {
      setState(() => _bench.add('خطأ: $e'));
    } finally {
      buf.clear();
      await mic.dispose();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(deviceInfoProvider).value;
    final setup = ref.watch(asrSetupProvider).value;
    final m = ref.watch(metricsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('التشخيص')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (info != null)
            Text(
              'الجهاز: ${info.model}\nالذاكرة: ${info.totalRamMb} MB · المعالج: ${info.primaryAbi} × ${info.cpuCores}\n'
              'Android SDK ${info.sdkInt} · الفئة: ${info.tier.name}',
            ),
          if (setup != null)
            Text(
              'النموذج: ${setup.modelAsset.split('/').last} · beam=${setup.beamSize} · '
              'مباشر=${setup.liveHighlighting} · threads=${setup.threads}',
            ),
          const Divider(),
          for (final e in m.entries)
            Text(
              '${e.key}: n=${e.value.length} · p50=${_pct(e.value, 0.5)} · p95=${_pct(e.value, 0.95)}',
            ),
          if (m.isEmpty) const Text('لا قياسات بعد. جرّب تلاوة آية.'),
          TextButton(
            onPressed: () => ref.read(metricsProvider.notifier).clear(),
            child: const Text('مسح القياسات'),
          ),
          const Divider(),
          FilledButton.icon(
            onPressed: _running ? null : _runBenchmark,
            icon: const Icon(Icons.speed),
            label: const Text('قياس السرعة على هذا الهاتف'),
          ),
          for (final line in _bench) Text(line),
        ],
      ),
    );
  }
}
