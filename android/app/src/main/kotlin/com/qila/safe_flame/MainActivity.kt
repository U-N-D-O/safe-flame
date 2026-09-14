package com.qila.safeflame

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.undu.safeflame.FlameService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "com.qila.safeflame/control"
        const val CAMERA_PERMISSION_REQUEST = 4101
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isRunning" -> {
                        val running = getSharedPreferences("safe_flame_state", MODE_PRIVATE)
                            .getBoolean("running", false)
                        result.success(running)
                    }

                    "start" -> {
                        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
                            result.success(false)
                        } else {
                            val mode = call.argument<Int>("mode") ?: 0
                            val intent = Intent(this, FlameService::class.java)
                                .setAction(FlameService.ACTION_START)
                                .putExtra(FlameService.EXTRA_MODE, mode)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        }
                    }

                    "stop" -> {
                        startService(Intent(this, FlameService::class.java).setAction(FlameService.ACTION_STOP))
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
