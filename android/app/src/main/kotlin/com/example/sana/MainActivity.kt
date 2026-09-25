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
import io.flutter.embedding.android.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {

    companion object {

        const val ACTION_NATIVE_ALARM =
            "com.example.sana.action.NATIVE_ALARM"
    }

    private val channelName =
        "sana/alarm"

    private var alarmChannel:
        MethodChannel? = null

    /*
     * Queue instead of a single pending alarm.
     *
     * This prevents a second alarm event from overwriting
     * the first one before Flutter is ready.
     */
    private val pendingAlarms =
        ArrayDeque<Map<String, Any>>()

    private val alarmReceiver =
        object : BroadcastReceiver() {

            override fun onReceive(
                context: Context,
                intent: Intent
            ) {

                if (
                    intent.action !=
                    ACTION_NATIVE_ALARM
                ) {
                    return
                }

                val data =
                    alarmDataFromIntent(
                        intent
                    )

                if (data != null) {
                    pendingAlarms.addLast(
                        data
                    )

                    deliverPendingAlarms()
                }
            }
        }

    override fun onCreate(
        savedInstanceState: Bundle?
    ) {

        super.onCreate(
            savedInstanceState
        )

        ContextCompat.registerReceiver(
            this,
            alarmReceiver,
            IntentFilter(
                ACTION_NATIVE_ALARM
            ),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )

        handleAlarmIntent(
            intent
        )
    }

    override fun onNewIntent(
        intent: Intent
    ) {

        super.onNewIntent(
            intent
        )

        setIntent(
            intent
        )

        handleAlarmIntent(
            intent
        )
    }

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {

        super.configureFlutterEngine(
            flutterEngine
        )

        alarmChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                channelName
            )

        alarmChannel?.setMethodCallHandler {
                call,
                result ->

            when (call.method) {

                "nativeAlarmReady" -> {

                    deliverPendingAlarms()

                    result.success(
                        null
                    )
                }

                "canScheduleNativeAlarm" -> {

                    val alarmManager =
                        getSystemService(
                            Context.ALARM_SERVICE
                        ) as AlarmManager

                    result.success(
                        if (
                            Build.VERSION.SDK_INT >=
                            Build.VERSION_CODES.S
                        ) {
                            alarmManager
                                .canScheduleExactAlarms()
                        } else {
                            true
                        }
                    )
                }

                "requestNativeAlarmPermission" -> {

                    if (
                        Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.S
                    ) {

                        val settingsIntent =
                            Intent(
                                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.parse(
                                    "package:$packageName"
                                )
                            )

                        startActivity(
                            settingsIntent
                        )
                    }

                    result.success(
                        null
                    )
                }

                "scheduleNativeAlarm" -> {

                    try {

                        val notificationId =
                            call.argument<Int>(
                                "notificationId"
                            )
                                ?: throw IllegalArgumentException(
                                    "notificationId"
                                )

                        val reminderId =
                            call.argument<String>(
                                "reminderId"
                            )
                                ?: throw IllegalArgumentException(
                                    "reminderId"
                                )

                        val triggerAtMillis =
                            call.argument<Long>(
                                "triggerAtMillis"
                            )
                                ?: throw IllegalArgumentException(
                                    "triggerAtMillis"
                                )

                        val daily =
                            call.argument<Boolean>(
                                "daily"
                            ) ?: false

                        val name =
                            call.argument<String>(
                                "name"
                            ) ?: ""

                        val dosage =
                            call.argument<String>(
                                "dosage"
                            ) ?: ""

                        val reminderTime =
                            call.argument<String>(
                                "reminderTime"
                            ) ?: ""

                        val reminderDate =
                            call.argument<String>(
                                "reminderDate"
                            ) ?: ""

                        val photoBase64 =
                            call.argument<String>(
                                "photoBase64"
                            )

                        val status =
                            SanaAlarmReceiver.schedule(
                                context = this,
                                notificationId = notificationId,
                                reminderId = reminderId,
                                triggerAtMillis = triggerAtMillis,
                                daily = daily,
                                name = name,
                                dosage = dosage,
                                reminderTime = reminderTime,
                                reminderDate = reminderDate,
                                photoBase64 = photoBase64
                            )

                        result.success(
                            status
                        )

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
                        call.argument<Int>(
                            "notificationId"
                        )

                    if (
                        notificationId != null
                    ) {

                        SanaAlarmReceiver.cancel(
                            this,
                            notificationId
                        )
                    }

                    result.success(
                        null
                    )
                }

                "cancelNativeReminder" -> {

                    val reminderId =
                        call.argument<String>(
                            "reminderId"
                        )

                    if (
                        !reminderId.isNullOrBlank()
                    ) {

                        SanaAlarmReceiver.cancelReminder(
                            this,
                            reminderId
                        )
                    }

                    result.success(
                        null
                    )
                }

                "clearAllNativeAlarms" -> {
                    SanaAlarmReceiver.cancelAll(this)

                    val serviceIntent =
                        Intent(
                            this,
                            SanaAlarmSoundService::class.java
                        ).setAction(
                            SanaAlarmSoundService.ACTION_STOP
                        )

                    startService(serviceIntent)

                    result.success(null)
                }

                "knownNativeReminderIds" -> {
                    result.success(
                        SanaAlarmCache.knownReminderIds(this)
                    )
                }

                "dismissNativeAlarmNotification" -> {

                    val notificationId =
                        call.argument<Int>(
                            "notificationId"
                        )

                    if (
                        notificationId != null
                    ) {

                        val manager =
                            getSystemService(
                                Context.NOTIFICATION_SERVICE
                            ) as NotificationManager

                        manager.cancel(
                            notificationId
                        )
                    }

                    result.success(
                        null
                    )
                }

                "startAlarmSound" -> {

                    val serviceIntent =
                        Intent(
                            this,
                            SanaAlarmSoundService::class.java
                        ).setAction(
                            SanaAlarmSoundService.ACTION_START
                        )

                    if (
                        Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.O
                    ) {

                        startForegroundService(
                            serviceIntent
                        )

                    } else {

                        startService(
                            serviceIntent
                        )
                    }

                    result.success(
                        null
                    )
                }

                "stopAlarmSound" -> {

                    val notificationId =
                        call.argument<Int>(
                            "notificationId"
                        )

                    val serviceIntent =
                        Intent(
                            this,
                            SanaAlarmSoundService::class.java
                        ).setAction(
                            SanaAlarmSoundService.ACTION_STOP
                        )

                    startService(
                        serviceIntent
                    )

                    if (
                        notificationId != null
                    ) {

                        val manager =
                            getSystemService(
                                Context.NOTIFICATION_SERVICE
                            ) as NotificationManager

                        manager.cancel(
                            notificationId
                        )
                    }

                    result.success(
                        null
                    )
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun handleAlarmIntent(
        intent: Intent?
    ) {

        if (
            intent?.getBooleanExtra(
                "native_alarm",
                false
            ) != true
        ) {
            return
        }

        val data =
            alarmDataFromIntent(
                intent
            )

        if (data != null) {

            pendingAlarms.addLast(
                data
            )

            deliverPendingAlarms()
        }
    }

    private fun alarmDataFromIntent(
        intent: Intent
    ): Map<String, Any>? {

        val notificationId =
            intent.getIntExtra(
                "notification_id",
                0
            )

        val reminderId =
            intent.getStringExtra(
                "reminder_id"
            )
                ?: return null

        val daily =
            intent.getBooleanExtra(
                "daily",
                false
            )

        val name =
            intent.getStringExtra(
                "name"
            ) ?: ""

        val dosage =
            intent.getStringExtra(
                "dosage"
            ) ?: ""

        val reminderTime =
            intent.getStringExtra(
                "reminder_time"
            ) ?: ""

        val reminderDate =
            intent.getStringExtra(
                "reminder_date"
            ) ?: ""

        val photoBase64 =
            intent.getStringExtra(
                "photo_base64"
            ) ?: ""

        return mapOf(
            "notificationId" to
                notificationId,

            "reminderId" to
                reminderId,

            "daily" to
                daily,

            "name" to
                name,

            "dosage" to
                dosage,

            "reminderTime" to
                reminderTime,

            "reminderDate" to
                reminderDate,

            "photoBase64" to
                photoBase64
        )
    }

    private fun deliverPendingAlarms() {

        val channel =
            alarmChannel
                ?: return

        while (
            pendingAlarms.isNotEmpty()
        ) {

            val alarm =
                pendingAlarms.removeFirst()

            channel.invokeMethod(
                "nativeAlarmTriggered",
                alarm
            )
        }
    }

    override fun onDestroy() {

        try {
            unregisterReceiver(
                alarmReceiver
            )
        } catch (_: Exception) {
        }

        super.onDestroy()
    }
}