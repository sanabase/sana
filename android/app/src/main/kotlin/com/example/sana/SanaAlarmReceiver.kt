package com.example.sana

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat
import java.io.File
import java.util.Calendar

class SanaAlarmReceiver : BroadcastReceiver() {

    companion object {

        const val ACTION_ALARM =
            "com.example.sana.action.MEDICATION_ALARM"

        private const val CHANNEL_ID =
            "sana_native_alarm"

        private const val PREFS =
            "sana_native_alarms"

        private const val KEY_ALARMS =
            "alarms"

        fun schedule(
            context: Context,
            notificationId: Int,
            reminderId: String,
            triggerAtMillis: Long,
            daily: Boolean,
            photoPath: String = ""
        ) {
            val alarmManager =
                context.getSystemService(
                    Context.ALARM_SERVICE
                ) as AlarmManager

            val intent =
                Intent(
                    context,
                    SanaAlarmReceiver::class.java
                ).apply {
                    action = ACTION_ALARM
                    putExtra("notification_id", notificationId)
                    putExtra("reminder_id", reminderId)
                    putExtra("daily", daily)
                    putExtra("photo_path", photoPath)
                }

            val pendingIntent =
                PendingIntent.getBroadcast(
                    context,
                    notificationId,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
                )

            val showIntent =
                PendingIntent.getActivity(
                    context,
                    notificationId,
                    Intent(context, MainActivity::class.java).apply {
                        flags =
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
                )

            val alarmClockInfo =
                AlarmManager.AlarmClockInfo(
                    triggerAtMillis,
                    showIntent
                )

            alarmManager.setAlarmClock(
                alarmClockInfo,
                pendingIntent
            )

            saveAlarm(
                context,
                notificationId,
                reminderId,
                triggerAtMillis,
                daily
            )
        }

        fun cancel(
            context: Context,
            notificationId: Int
        ) {
            val alarmManager =
                context.getSystemService(
                    Context.ALARM_SERVICE
                ) as AlarmManager

            val intent =
                Intent(
                    context,
                    SanaAlarmReceiver::class.java
                ).apply {
                    action = ACTION_ALARM
                }

            val pendingIntent =
                PendingIntent.getBroadcast(
                    context,
                    notificationId,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
                )

            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()

            removeAlarm(context, notificationId)
        }

        private fun saveAlarm(
            context: Context,
            notificationId: Int,
            reminderId: String,
            triggerAtMillis: Long,
            daily: Boolean,
            photoPath: String = ""
        ) {
            val prefs =
                context.getSharedPreferences(
                    PREFS,
                    Context.MODE_PRIVATE
                )

            val stored =
                prefs.getStringSet(
                    KEY_ALARMS,
                    emptySet()
                ) ?: emptySet()

            val current = stored.toMutableSet()

            current.removeAll {
                it.startsWith("$notificationId|")
            }

            current.add(
                "$notificationId|$reminderId|$triggerAtMillis|$daily"
            )

            prefs.edit()
                .putStringSet(KEY_ALARMS, current)
                .apply()
        }

        private fun removeAlarm(
            context: Context,
            notificationId: Int
        ) {
            val prefs =
                context.getSharedPreferences(
                    PREFS,
                    Context.MODE_PRIVATE
                )

            val stored =
                prefs.getStringSet(
                    KEY_ALARMS,
                    emptySet()
                ) ?: emptySet()

            val current = stored.toMutableSet()

            current.removeAll {
                it.startsWith("$notificationId|")
            }

            prefs.edit()
                .putStringSet(KEY_ALARMS, current)
                .apply()
        }

        fun loadDownsampledBitmap(path: String, maxDim: Int): Bitmap? {
            if (path.isEmpty()) return null
            val f = File(path)
            if (!f.exists()) return null
            return try {
                val opts = BitmapFactory.Options()
                opts.inJustDecodeBounds = true
                BitmapFactory.decodeFile(path, opts)
                var scale = 1
                while (opts.outWidth / scale > maxDim || opts.outHeight / scale > maxDim) {
                    scale *= 2
                }
                val opts2 = BitmapFactory.Options()
                opts2.inSampleSize = scale
                BitmapFactory.decodeFile(path, opts2)
            } catch (_: Exception) { null }
        }

        fun rescheduleAll(context: Context) {

            val prefs =
                context.getSharedPreferences(
                    PREFS,
                    Context.MODE_PRIVATE
                )

            val alarms =
                prefs.getStringSet(
                    KEY_ALARMS,
                    emptySet()
                ) ?: emptySet()

            val now = System.currentTimeMillis()

            alarms.forEach { value ->

                val parts = value.split("|")

                if (parts.size != 4) {
                    return@forEach
                }

                val notificationId =
                    parts[0].toIntOrNull()
                        ?: return@forEach

                val reminderId = parts[1]

                var triggerAtMillis =
                    parts[2].toLongOrNull()
                        ?: return@forEach

                val daily = parts[3].toBoolean()

                if (daily) {

                    while (triggerAtMillis <= now) {
                        triggerAtMillis +=
                            24L * 60L * 60L * 1000L
                    }

                    saveAlarm(
                        context,
                        notificationId,
                        reminderId,
                        triggerAtMillis,
                        true
                    )

                } else if (triggerAtMillis <= now) {
                    removeAlarm(context, notificationId)
                    return@forEach
                }

                schedule(
                    context,
                    notificationId,
                    reminderId,
                    triggerAtMillis,
                    daily
                )
            }
        }
    }

    override fun onReceive(
        context: Context,
        intent: Intent?
    ) {
        if (intent?.action != ACTION_ALARM) {
            return
        }

        val notificationId =
            intent.getIntExtra("notification_id", 0)

        val photoPath = intent.getStringExtra("photo_path") ?: ""

        val reminderId =
            intent.getStringExtra("reminder_id") ?: return

        val daily =
            intent.getBooleanExtra("daily", false)

        createChannel(context)

        val broadcast =
            Intent(MainActivity.ACTION_NATIVE_ALARM).apply {
                setPackage(context.packageName)
                putExtra("notification_id", notificationId)
                putExtra("reminder_id", reminderId)
                putExtra("daily", daily)
            }

        context.sendBroadcast(broadcast)

        val soundIntent =
            Intent(
                context,
                SanaAlarmSoundService::class.java
            ).apply {
                action = SanaAlarmSoundService.ACTION_START
            }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(soundIntent)
        } else {
            context.startService(soundIntent)
        }

        val activityIntent =
            Intent(
                context,
                MainActivity::class.java
            ).apply {
                flags =
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP

                putExtra("native_alarm", true)
                putExtra("notification_id", notificationId)
                putExtra("reminder_id", reminderId)
                putExtra("daily", daily)
            }

        val activityPendingIntent =
            PendingIntent.getActivity(
                context,
                notificationId,
                activityIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )

        val notification =
            NotificationCompat.Builder(
                context,
                CHANNEL_ID
            )
                .setSmallIcon(R.mipmap.ic_launcher)
                .apply {
                    val bmp = loadDownsampledBitmap(photoPath, 256)
                    if (bmp != null) setLargeIcon(bmp)
                }
                .setContentTitle("SANA")
                .setContentText("Medication reminder")
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setOngoing(true)
                .setAutoCancel(false)
                .setSilent(true)
                .setFullScreenIntent(
                    activityPendingIntent,
                    true
                )
                .build()

        val manager =
            context.getSystemService(
                Context.NOTIFICATION_SERVICE
            ) as NotificationManager

        manager.notify(notificationId, notification)

        if (daily) {

            val prefs =
                context.getSharedPreferences(
                    PREFS,
                    Context.MODE_PRIVATE
                )

            val stored =
                prefs.getStringSet(
                    KEY_ALARMS,
                    emptySet()
                ) ?: emptySet()

            val record =
                stored.firstOrNull {
                    it.startsWith("$notificationId|")
                }

            var hour = 0
            var minute = 0

            if (record != null) {
                val parts = record.split("|")

                if (parts.size == 4) {
                    val oldTrigger =
                        parts[2].toLongOrNull() ?: 0L

                    if (oldTrigger > 0L) {
                        val cal = Calendar.getInstance()
                        cal.timeInMillis = oldTrigger
                        hour = cal.get(Calendar.HOUR_OF_DAY)
                        minute = cal.get(Calendar.MINUTE)
                    }
                }
            }

            val next = Calendar.getInstance()
            next.set(Calendar.HOUR_OF_DAY, hour)
            next.set(Calendar.MINUTE, minute)
            next.set(Calendar.SECOND, 0)
            next.set(Calendar.MILLISECOND, 0)

            if (!next.after(Calendar.getInstance())) {
                next.add(Calendar.DAY_OF_YEAR, 1)
            }

            schedule(
                context,
                notificationId,
                reminderId,
                next.timeInMillis,
                true
            )

        } else {

            removeAlarm(context, notificationId)
        }
    }

    private fun createChannel(context: Context) {

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager =
            context.getSystemService(
                NotificationManager::class.java
            )

        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "SANA Alarm",
                NotificationManager.IMPORTANCE_HIGH
            )

        channel.setSound(null, null)
        channel.enableVibration(false)

        manager.createNotificationChannel(channel)
    }
}