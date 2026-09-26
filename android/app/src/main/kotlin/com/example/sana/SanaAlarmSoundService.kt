package com.example.sana

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class SanaAlarmSoundService : Service() {

    companion object {

        const val ACTION_START =
            "com.example.sana.action.START_ALARM"

        const val ACTION_STOP =
            "com.example.sana.action.STOP_ALARM"

        private const val CHANNEL_ID =
            "sana_alarm_service"

        private const val NOTIFICATION_ID =
            9701
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

        val action = intent?.action

        if (action == ACTION_STOP) {
            stopAlarm()
            stopSelf()
            return START_NOT_STICKY
        }

        if (action == ACTION_START || action == null) {
            startAlarm()
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
                    com.example.sana.R.mipmap.ic_launcher
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

        try {
            player = MediaPlayer().apply {

                setWakeMode(
                    applicationContext,
                    PowerManager.PARTIAL_WAKE_LOCK
                )

                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(
                            AudioAttributes.USAGE_ALARM
                        )
                        .setContentType(
                            AudioAttributes.CONTENT_TYPE_MUSIC
                        )
                        .setLegacyStreamType(
                            android.media.AudioManager.STREAM_ALARM
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
        } catch (e: Exception) {
            android.util.Log.e(
                "SANA",
                "MediaPlayer alarm start error",
                e
            )
        }
    }

    private fun stopAlarm() {

        try {
            player?.stop()
        } catch (_: Exception) {
        }

        try {
            player?.reset()
        } catch (_: Exception) {
        }

        try {
            player?.release()
        } catch (_: Exception) {
        }

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

            val channel =
                NotificationChannel(
                    CHANNEL_ID,
                    "SANA Alarm",
                    NotificationManager.IMPORTANCE_LOW
                )

            /*
             * Foreground-service placeholder channel.
             * Audio is produced by MediaPlayer, not by this channel.
             * Kept silent and low-importance so it does not compete
             * with the real alarm notification.
             */
            channel.setSound(null, null)
            channel.enableVibration(false)

            manager.createNotificationChannel(
                channel
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