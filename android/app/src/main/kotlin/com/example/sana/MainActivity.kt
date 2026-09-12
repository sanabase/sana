package com.example.sana

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {

    private val channelName = "sana/alarm"

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {
                "startAlarmSound" -> {
                    val intent = Intent(
                        this,
                        SanaAlarmSoundService::class.java
                    ).setAction(
                        SanaAlarmSoundService.ACTION_START
                    )

                    startForegroundService(intent)

                    result.success(null)
                }

                "stopAlarmSound" -> {
                    val intent = Intent(
                        this,
                        SanaAlarmSoundService::class.java
                    ).setAction(
                        SanaAlarmSoundService.ACTION_STOP
                    )

                    startService(intent)

                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}