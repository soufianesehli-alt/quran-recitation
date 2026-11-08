package com.almathaba.tilawa

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Device facts used to pick the recogniser tier (tools/benchmark_device.md). No IDs.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tilawa/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "info") {
                    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val mi = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
                    result.success(
                        mapOf(
                            "totalRamMb" to (mi.totalMem / (1024 * 1024)).toInt(),
                            "primaryAbi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"),
                            "cpuCores" to Runtime.getRuntime().availableProcessors(),
                            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
                            "sdkInt" to Build.VERSION.SDK_INT,
                        )
                    )
                } else {
                    result.notImplemented()
                }
            }
    }
}
