/// Device tier (tools/benchmark_device.md): chooses the recogniser setup per phone.
enum DeviceTier { low, mid, high }

class DeviceInfo {
  const DeviceInfo({
    required this.totalRamMb,
    required this.primaryAbi,
    required this.cpuCores,
    required this.model,
    required this.sdkInt,
  });

  final int totalRamMb;
  final String primaryAbi;
  final int cpuCores;
  final String model;
  final int sdkInt;

  DeviceTier get tier {
    if (primaryAbi == 'armeabi-v7a' || totalRamMb < 3500) return DeviceTier.low;
    if (totalRamMb < 7000) return DeviceTier.mid;
    return DeviceTier.high;
  }
}

/// Recogniser setup derived from the tier (overridable in settings).
class AsrSetup {
  const AsrSetup({
    required this.modelAsset,
    required this.beamSize,
    required this.liveHighlighting,
    required this.threads,
  });

  final String modelAsset;
  final int beamSize;
  final bool liveHighlighting;
  final int threads;

  static const baseModel = 'assets/models/quran-whisper-base-q8_0.bin';
  static const tinyModel = 'assets/models/quran-whisper-tiny-q8_0.bin';

  /// Low tier keeps the more accurate base model but decodes greedily and reports after each
  /// pause instead of live: slower feedback is preferred to less reliable feedback.
  static AsrSetup forTier(DeviceTier tier, int cores) => switch (tier) {
    DeviceTier.high => AsrSetup(
      modelAsset: baseModel,
      beamSize: 5,
      liveHighlighting: true,
      threads: cores.clamp(2, 6),
    ),
    DeviceTier.mid => AsrSetup(
      modelAsset: baseModel,
      beamSize: 5,
      liveHighlighting: true,
      threads: cores.clamp(2, 4),
    ),
    DeviceTier.low => AsrSetup(
      modelAsset: baseModel,
      beamSize: 1,
      liveHighlighting: false,
      threads: cores.clamp(2, 4),
    ),
  };
}
