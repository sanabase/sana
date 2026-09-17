package com.example.sana

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val ACTION_NATIVE_ALARM =
            "com.example.sana.action.NATIVE_ALARM"
    }

    private val channelName = "sana/alarm"

    private var alarmChannel: MethodChannel? = null

    private var pendingAlarm: Map<String, Any>? = null

    private val alarmReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(
                context: Context,
                intent: Intent
            ) {
                if (intent.action != ACTION_NATIVE_ALARM) {
                    return
                }

                val data = alarmDataFromIntent(intent)

                if (data != null) {
                    pendingAlarm = data
                    deliverPendingAlarm()
                }
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        ContextCompat.registerReceiver(
            this,
            alarmReceiver,
            IntentFilter(ACTION_NATIVE_ALARM),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )

        handleAlarmIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAlarmIntent(intent)
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        alarmChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        alarmChannel?.setMethodCallHandler { call, result ->

            when (call.method) {

                "nativeAlarmReady" -> {
                    deliverPendingAlarm()
                    result.success(null)
                }

                "canScheduleNativeAlarm" -> {
                    val alarmManager =
                        getSystemService(Context.ALARM_SERVICE)
                            as AlarmManager

                    result.success(
                        if (Build.VERSION.SDK_INT >=
                            Build.VERSION_CODES.S
                        ) {
                            alarmManager.canScheduleExactAlarms()
                        } else {
                            true
                        }
                    )
                }

                "requestNativeAlarmPermission" -> {
                    if (Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.S
                    ) {
                        val settingsIntent = Intent(
                            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                            Uri.parse("package:$packageName")
                        )

                        startActivity(settingsIntent)
                    }

                    result.success(null)
                }

                "scheduleNativeAlarm" -> {
                    try {
                        val notificationId =
                            call.argument<Int>("notificationId")
                                ?: throw IllegalArgumentException(
                                    "notificationId"
                                )

                        val reminderId =
                            call.argument<String>("reminderId")
                                ?: throw IllegalArgumentException(
                                    "reminderId"
                                )

                         val triggerAtMillis =


                             call.argument<Long>("triggerAtMillis")


                                 ?: throw IllegalArgumentException(


                                     "triggerAtMillis"


                                 )



                         val photoPath =


                             call.argument<String>("photoPath") ?: ""

                        val daily =
                            call.argument<Boolean>("daily") ?: false

                         SanaAlarmReceiver.schedule(


                             this,


                             notificationId,


                             reminderId,


                             triggerAtMillis,


                             daily,


                             photoPath


                         )

                        result.success(null)
                    } catch (e: Exception) {
                        result.error(
                            "ALARM_SCHEDULE_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                "cancelNativeAlarm" -> {
                    val notificationId =
                        call.argument<Int>("notificationId")

                    if (notificationId != null) {
                        SanaAlarmReceiver.cancel(
                            this,
                            notificationId
                        )
                    }

                    result.success(null)
                }

                "startAlarmSound" -> {
                    val serviceIntent = Intent(
                        this,
                        SanaAlarmSoundService::class.java
                    ).setAction(
                        SanaAlarmSoundService.ACTION_START
                    )

                    if (Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.O
                    ) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }

                    result.success(null)
                }

                "stopAlarmSound" -> {
                    val notificationId =
                        call.argument<Int>("notificationId")

                    val serviceIntent = Intent(
                        this,
                        SanaAlarmSoundService::class.java
                    ).setAction(
                        SanaAlarmSoundService.ACTION_STOP
                    )

                    startService(serviceIntent)

                    if (notificationId != null) {
                        val manager =
                            getSystemService(
                                Context.NOTIFICATION_SERVICE
                            ) as NotificationManager

                        manager.cancel(notificationId)
                    }

                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun handleAlarmIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("native_alarm", false) != true) {
            return
        }

        val data = alarmDataFromIntent(intent)

        if (data != null) {
            pendingAlarm = data
            deliverPendingAlarm()
        }
    }

    private fun alarmDataFromIntent(intent: Intent): Map<String, Any>? {

        val notificationId =
            intent.getIntExtra("notification_id", 0)

        val reminderId =
            intent.getStringExtra("reminder_id") ?: return null

        val daily =
            intent.getBooleanExtra("daily", false)

        return mapOf(
            "notificationId" to notificationId,
            "reminderId" to reminderId,
            "daily" to daily
        )
    }

    private fun deliverPendingAlarm() {
        val channel = alarmChannel ?: return
        val alarm = pendingAlarm ?: return

        pendingAlarm = null

        channel.invokeMethod(
            "nativeAlarmTriggered",
            alarm
        )
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(alarmReceiver)
        } catch (_: Exception) {
        }

        super.onDestroy()
    }
}