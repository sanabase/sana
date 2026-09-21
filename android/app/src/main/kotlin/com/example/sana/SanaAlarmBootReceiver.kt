package com.example.sana

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class SanaAlarmBootReceiver : BroadcastReceiver() {

    override fun onReceive(
        context: Context,
        intent: Intent?
    ) {

        when (intent?.action) {

            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> {

                SanaAlarmReceiver.rescheduleAll(
                    context
                )
            }

            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> {

                if (
                    Build.VERSION.SDK_INT >=
                    Build.VERSION_CODES.S
                ) {

                    val alarmManager =
                        context.getSystemService(
                            Context.ALARM_SERVICE
                        ) as AlarmManager

                    if (
                        alarmManager.canScheduleExactAlarms()
                    ) {
                        SanaAlarmReceiver.rescheduleAll(
                            context
                        )
                    }
                }
            }
        }
    }
}