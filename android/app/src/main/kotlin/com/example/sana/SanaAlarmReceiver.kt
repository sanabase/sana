package com.example.sana

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import java.util.Calendar

class SanaAlarmReceiver : BroadcastReceiver() {

    companion object {

        const val ACTION_ALARM =
            "com.example.sana.action.MEDICATION_ALARM"

        private const val CHANNEL_ID =
            "sana_native_alarm"

        fun schedule(
            context: Context,
            notificationId: Int,
            reminderId: String,
            triggerAtMillis: Long,
            daily: Boolean,
            name: String,
            dosage: String,
            reminderTime: String,
            reminderDate: String,
            photoBase64: String?
        ): String {

            if (notificationId <= 0) {
                return "INVALID"
            }

            if (reminderId.isBlank()) {
                return "INVALID"
            }

            if (triggerAtMillis <= 0L) {
                return "INVALID"
            }

            val alarmManager =
                context.getSystemService(
                    Context.ALARM_SERVICE
                ) as AlarmManager

            val alarmIntent =
                Intent(
                    context,
                    SanaAlarmReceiver::class.java
                ).apply {
                    action = ACTION_ALARM

                    putExtra(
                        "notification_id",
                        notificationId
                    )

                    putExtra(
                        "reminder_id",
                        reminderId
                    )

                    putExtra(
                        "daily",
                        daily
                    )

                    putExtra(
                        "name",
                        name
                    )

                    putExtra(
                        "dosage",
                        dosage
                    )

                    putExtra(
                        "reminder_time",
                        reminderTime
                    )

                    putExtra(
                        "reminder_date",
                        reminderDate
                    )

                    putExtra(
                        "photo_base64",
                        photoBase64
                    )
                }

            val pendingIntent =
                PendingIntent.getBroadcast(
                    context,
                    notificationId,
                    alarmIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
                )

            val showIntent =
                PendingIntent.getActivity(
                    context,
                    notificationId,
                    Intent(
                        context,
                        MainActivity::class.java
                    ).apply {
                        flags =
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP

                        putExtra(
                            "native_alarm",
                            true
                        )

                        putExtra(
                            "notification_id",
                            notificationId
                        )

                        putExtra(
                            "reminder_id",
                            reminderId
                        )

                        putExtra(
                            "daily",
                            daily
                        )

                        putExtra(
                            "name",
                            name
                        )

                        putExtra(
                            "dosage",
                            dosage
                        )

                        putExtra(
                            "reminder_time",
                            reminderTime
                        )

                        putExtra(
                            "reminder_date",
                            reminderDate
                        )

                        putExtra(
                            "photo_base64",
                            photoBase64
                        )
                    },
                    PendingIntent.FLAG_UPDATE_CURRENT or
                        PendingIntent.FLAG_IMMUTABLE
                )

            var scheduledStatus = "FAILED"

            try {

                val exactAllowed =
                    if (
                        Build.VERSION.SDK_INT >=
                        Build.VERSION_CODES.S
                    ) {
                        alarmManager.canScheduleExactAlarms()
                    } else {
                        true
                    }

                if (exactAllowed) {

                    val alarmClockInfo =
                        AlarmManager.AlarmClockInfo(
                            triggerAtMillis,
                            showIntent
                        )

                    try {
                        alarmManager.setAlarmClock(
                            alarmClockInfo,
                            pendingIntent
                        )

                        scheduledStatus = "EXACT"

                    } catch (_: SecurityException) {

                        scheduledStatus =
                            scheduleInexact(
                                alarmManager,
                                triggerAtMillis,
                                pendingIntent
                            )
                    }

                } else {

                    scheduledStatus =
                        scheduleInexact(
                            alarmManager,
                            triggerAtMillis,
                            pendingIntent
                        )
                }

                if (
                    scheduledStatus != "EXACT" &&
                    scheduledStatus != "INEXACT"
                ) {
                    return "FAILED"
                }

                try {

                    SanaAlarmCache.save(
                        context = context,
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

                } catch (cacheError: Exception) {

                    alarmManager.cancel(
                        pendingIntent
                    )

                    pendingIntent.cancel()

                    throw cacheError
                }

                return scheduledStatus

            } catch (_: Exception) {
                return "FAILED"
            }
        }

        private fun scheduleInexact(
            alarmManager: AlarmManager,
            triggerAtMillis: Long,
            pendingIntent: PendingIntent
        ): String {

            return try {

                if (
                    Build.VERSION.SDK_INT >=
                    Build.VERSION_CODES.M
                ) {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                } else {
                    @Suppress("DEPRECATION")
                    alarmManager.set(
                        AlarmManager.RTC_WAKEUP,
                        triggerAtMillis,
                        pendingIntent
                    )
                }

                "INEXACT"

            } catch (_: Exception) {
                "FAILED"
            }
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

            alarmManager.cancel(
                pendingIntent
            )

            pendingIntent.cancel()

            SanaAlarmCache.remove(
                context,
                notificationId
            )
        }

        fun cancelReminder(
            context: Context,
            reminderId: String
        ) {

            val entries =
                SanaAlarmCache.all(context)
                    .filter {
                        it.reminderId == reminderId
                    }

            for (entry in entries) {
                cancel(
                    context,
                    entry.notificationId
                )
            }
        }

        fun rescheduleAll(
            context: Context
        ) {

            // Preserve alarms created by the previous
            // SharedPreferences implementation.
            SanaAlarmCache.migrateLegacyAlarms(
                context
            )

            val now =
                System.currentTimeMillis()

            val entries =
                SanaAlarmCache.all(context)

            for (entry in entries) {

                if (entry.daily) {

                    val next =
                        nextDailyTrigger(
                            entry,
                            now
                        )

                    schedule(
                        context = context,
                        notificationId = entry.notificationId,
                        reminderId = entry.reminderId,
                        triggerAtMillis = next,
                        daily = true,
                        name = entry.name,
                        dosage = entry.dosage,
                        reminderTime = entry.reminderTime,
                        reminderDate = entry.reminderDate,
                        photoBase64 = entry.photoBase64
                    )

                } else if (
                    entry.triggerAtMillis <= now
                ) {

                    SanaAlarmCache.remove(
                        context,
                        entry.notificationId
                    )

                } else {

                    schedule(
                        context = context,
                        notificationId = entry.notificationId,
                        reminderId = entry.reminderId,
                        triggerAtMillis = entry.triggerAtMillis,
                        daily = false,
                        name = entry.name,
                        dosage = entry.dosage,
                        reminderTime = entry.reminderTime,
                        reminderDate = entry.reminderDate,
                        photoBase64 = entry.photoBase64
                    )
                }
            }
        }

        private fun nextDailyTrigger(
            entry: SanaAlarmCache.Entry,
            nowMillis: Long
        ): Long {

            val calendar =
                Calendar.getInstance()

            calendar.timeInMillis = nowMillis

            var hour =
                calendar.get(
                    Calendar.HOUR_OF_DAY
                )

            var minute =
                calendar.get(
                    Calendar.MINUTE
                )

            val parsed =
                parseTime(
                    entry.reminderTime
                )

            if (parsed != null) {
                hour = parsed.first
                minute = parsed.second
            } else {

                val previous =
                    Calendar.getInstance()

                previous.timeInMillis =
                    entry.triggerAtMillis

                hour =
                    previous.get(
                        Calendar.HOUR_OF_DAY
                    )

                minute =
                    previous.get(
                        Calendar.MINUTE
                    )
            }

            calendar.set(
                Calendar.HOUR_OF_DAY,
                hour
            )

            calendar.set(
                Calendar.MINUTE,
                minute
            )

            calendar.set(
                Calendar.SECOND,
                0
            )

            calendar.set(
                Calendar.MILLISECOND,
                0
            )

            if (
                calendar.timeInMillis <=
                nowMillis
            ) {
                calendar.add(
                    Calendar.DAY_OF_YEAR,
                    1
                )
            }

            return calendar.timeInMillis
        }

        private fun parseTime(
            value: String
        ): Pair<Int, Int>? {

            val text =
                value.trim()

            if (text.isEmpty()) {
                return null
            }

            val regex =
                Regex(
                    """^(\d{1,2}):(\d{2})\s*(AM|PM)?$""",
                    RegexOption.IGNORE_CASE
                )

            val match =
                regex.matchEntire(text)
                    ?: return null

            var hour =
                match.groupValues[1]
                    .toIntOrNull()
                    ?: return null

            val minute =
                match.groupValues[2]
                    .toIntOrNull()
                    ?: return null

            val meridiem =
                match.groupValues[3]
                    .uppercase()

            if (
                minute !in 0..59
            ) {
                return null
            }

            if (meridiem == "AM") {

                if (hour !in 1..12) {
                    return null
                }

                if (hour == 12) {
                    hour = 0
                }

            } else if (meridiem == "PM") {

                if (hour !in 1..12) {
                    return null
                }

                if (hour != 12) {
                    hour += 12
                }

            } else {

                if (hour !in 0..23) {
                    return null
                }
            }

            return Pair(
                hour,
                minute
            )
        }
    }

    override fun onReceive(
        context: Context,
        intent: Intent?
    ) {

        if (
            intent?.action != ACTION_ALARM
        ) {
            return
        }

        val notificationId =
            intent.getIntExtra(
                "notification_id",
                0
            )

        if (notificationId <= 0) {
            return
        }

        /*
         * The cache is the authority.
         *
         * If the cache is gone, the reminder was cancelled/deleted
         * and this stale AlarmManager delivery must not resurrect it.
         */
        val cached =
            SanaAlarmCache.read(
                context,
                notificationId
            ) ?: return

        val reminderId =
            cached.reminderId

        val daily =
            cached.daily

        createChannel(
            context
        )

        /*
         * Send the COMPLETE offline payload to MainActivity.
         */
        val broadcast =
            Intent(
                MainActivity.ACTION_NATIVE_ALARM
            ).apply {

                setPackage(
                    context.packageName
                )

                putExtra(
                    "notification_id",
                    cached.notificationId
                )

                putExtra(
                    "reminder_id",
                    cached.reminderId
                )

                putExtra(
                    "daily",
                    cached.daily
                )

                putExtra(
                    "name",
                    cached.name
                )

                putExtra(
                    "dosage",
                    cached.dosage
                )

                putExtra(
                    "reminder_time",
                    cached.reminderTime
                )

                putExtra(
                    "reminder_date",
                    cached.reminderDate
                )

                putExtra(
                    "photo_base64",
                    cached.photoBase64
                )
            }

        context.sendBroadcast(
            broadcast
        )

        /*
         * Start the existing alarm sound service.
         */
        val soundIntent =
            Intent(
                context,
                SanaAlarmSoundService::class.java
            ).apply {
                action =
                    SanaAlarmSoundService.ACTION_START
            }

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.O
        ) {
            context.startForegroundService(
                soundIntent
            )
        } else {
            context.startService(
                soundIntent
            )
        }

        /*
         * Full-screen activity PendingIntent.
         */
        val activityIntent =
            Intent(
                context,
                MainActivity::class.java
            ).apply {

                flags =
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP

                putExtra(
                    "native_alarm",
                    true
                )

                putExtra(
                    "notification_id",
                    cached.notificationId
                )

                putExtra(
                    "reminder_id",
                    cached.reminderId
                )

                putExtra(
                    "daily",
                    cached.daily
                )

                putExtra(
                    "name",
                    cached.name
                )

                putExtra(
                    "dosage",
                    cached.dosage
                )

                putExtra(
                    "reminder_time",
                    cached.reminderTime
                )

                putExtra(
                    "reminder_date",
                    cached.reminderDate
                )

                putExtra(
                    "photo_base64",
                    cached.photoBase64
                )
            }

        val activityPendingIntent =
            PendingIntent.getActivity(
                context,
                cached.notificationId,
                activityIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    PendingIntent.FLAG_IMMUTABLE
            )

        val manager =
            context.getSystemService(
                Context.NOTIFICATION_SERVICE
            ) as NotificationManager

        val bodyParts =
            mutableListOf<String>()

        if (cached.dosage.isNotBlank()) {
            bodyParts.add(
                cached.dosage
            )
        }

        if (cached.reminderTime.isNotBlank()) {
            bodyParts.add(
                cached.reminderTime
            )
        }

        val body =
            if (bodyParts.isEmpty()) {
                "Medication reminder"
            } else {
                bodyParts.joinToString(
                    " • "
                )
            }

        val builder =
            NotificationCompat.Builder(
                context,
                CHANNEL_ID
            )
                .setSmallIcon(
                    R.mipmap.ic_launcher
                )
                .setContentTitle(
                    if (cached.name.isBlank()) {
                        "SANA"
                    } else {
                        cached.name
                    }
                )
                .setContentText(
                    body
                )
                .setCategory(
                    NotificationCompat.CATEGORY_ALARM
                )
                .setPriority(
                    NotificationCompat.PRIORITY_MAX
                )
                .setVisibility(
                    NotificationCompat.VISIBILITY_PUBLIC
                )
                .setOngoing(true)
                .setAutoCancel(false)
                .setSilent(true)

        /*
         * Android 14+ can revoke/restrict full-screen intent access.
         * If it is unavailable, keep the alarm notification instead of
         * failing the alarm.
         */
        val fullScreenAllowed =
            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.UPSIDE_DOWN_CAKE
            ) {
                manager.canUseFullScreenIntent()
            } else {
                true
            }

        if (fullScreenAllowed) {
            builder.setFullScreenIntent(
                activityPendingIntent,
                true
            )
        } else {
            builder.setContentIntent(
                activityPendingIntent
            )
        }

        manager.notify(
            cached.notificationId,
            builder.build()
        )

        /*
         * Daily reminders continue automatically.
         *
         * IMPORTANT:
         * This schedules tomorrow BEFORE the user presses TAKEN.
         * Therefore daily TAKEN must NOT call cancelNativeAlarm().
         */
        if (daily) {

            val next =
                nextDailyTrigger(
                    cached,
                    System.currentTimeMillis()
                )

            schedule(
                context = context,
                notificationId = cached.notificationId,
                reminderId = cached.reminderId,
                triggerAtMillis = next,
                daily = true,
                name = cached.name,
                dosage = cached.dosage,
                reminderTime = cached.reminderTime,
                reminderDate = cached.reminderDate,
                photoBase64 = cached.photoBase64
            )

        } else {

            /*
             * The one-time alarm has fired.
             * It must not be scheduled again.
             */
            SanaAlarmCache.remove(
                context,
                cached.notificationId
            )
        }
    }

    private fun createChannel(
        context: Context
    ) {

        if (
            Build.VERSION.SDK_INT <
            Build.VERSION_CODES.O
        ) {
            return
        }

        val manager =
            context.getSystemService(
                NotificationManager::class.java
            )

        /*
         * KEEP THE EXISTING CHANNEL ID.
         */
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "SANA Alarm",
                NotificationManager.IMPORTANCE_HIGH
            )

        channel.setSound(
            null,
            null
        )

        channel.enableVibration(
            false
        )

        manager.createNotificationChannel(
            channel
        )
    }
}