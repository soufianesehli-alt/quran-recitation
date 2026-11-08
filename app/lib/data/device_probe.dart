import 'package:flutter/services.dart';

import '../domain/device_tier.dart';

/// Reads RAM / ABI / cores from Android (MainActivity "tilawa/device" channel).
class DeviceProbe {
  static const _channel = MethodChannel('tilawa/device');

  static Future<DeviceInfo> read() async {
    final m =
        await _channel.invokeMapMethod<String, Object?>('info') ?? const {};
    return DeviceInfo(
      totalRamMb: (m['totalRamMb'] as int?) ?? 0,
      primaryAbi: (m['primaryAbi'] as String?) ?? 'unknown',
      cpuCores: (m['cpuCores'] as int?) ?? 4,
      model: (m['model'] as String?) ?? 'unknown',
      sdkInt: (m['sdkInt'] as int?) ?? 0,
    );
  }
}
