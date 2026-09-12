package com.example.meditrack

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class SanaAlarmSoundService : Service() {

    companion object {
        const val ACTION_START =
            "com.example.meditrack.action.START_ALARM"

        const val ACTION_STOP =
            "com.example.meditrack.action.STOP_ALARM"

        private const val CHANNEL_ID =
            "sana_alarm_service"

        private const val NOTIFICATION_ID = 9701
    }

    private var player: MediaPlayer? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {

        when (intent?.action) {
            ACTION_START -> startAlarm()

            ACTION_STOP -> {
                stopAlarm()
                stopSelf()
                return START_NOT_STICKY
            }
        }

        return START_STICKY
    }

    private fun startAlarm() {

        val notification =
            NotificationCompat.Builder(
                this,
                CHANNEL_ID
            )
                .setSmallIcon(
                    com.example.meditrack.R.mipmap.ic_launcher
                )
                .setContentTitle("SANA")
                .setContentText("Medication alarm")
                .setOngoing(true)
                .setCategory(
                    NotificationCompat.CATEGORY_ALARM
                )
                .setPriority(
                    NotificationCompat.PRIORITY_MAX
                )
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo
                    .FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(
                NOTIFICATION_ID,
                notification
            )
        }

        if (player?.isPlaying == true) {
            return
        }

        val uri =
            RingtoneManager.getDefaultUri(
                RingtoneManager.TYPE_ALARM
            ) ?: RingtoneManager.getDefaultUri(
                RingtoneManager.TYPE_NOTIFICATION
            )

        player?.release()

        player = MediaPlayer().apply {

            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(
                        AudioAttributes.USAGE_ALARM
                    )
                    .setContentType(
                        AudioAttributes.CONTENT_TYPE_SONIFICATION
                    )
                    .build()
            )

            setDataSource(
                this@SanaAlarmSoundService,
                uri
            )

            isLooping = true

            prepare()
            start()
        }
    }

    private fun stopAlarm() {
        try {
            player?.stop()
        } catch (_) {
        }

        player?.release()
        player = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(
                STOP_FOREGROUND_REMOVE
            )
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            val manager =
                getSystemService(
                    NotificationManager::class.java
                )

            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "SANA Alarm",
                    NotificationManager.IMPORTANCE_HIGH
                )
            )
        }
    }

    override fun onDestroy() {
        stopAlarm()
        super.onDestroy()
    }

    override fun onBind(
        intent: Intent?
    ): IBinder? = null
}