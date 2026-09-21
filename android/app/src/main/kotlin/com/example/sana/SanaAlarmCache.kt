package com.example.sana

import android.content.Context
import org.json.JSONObject
import java.io.File

object SanaAlarmCache {

    data class Entry(
        val notificationId: Int,
        val reminderId: String,
        val triggerAtMillis: Long,
        val daily: Boolean,
        val name: String,
        val dosage: String,
        val reminderTime: String,
        val reminderDate: String,
        val photoBase64: String?
    )

    private const val DIRECTORY_NAME = "sana_alarm_cache"
    private const val FILE_PREFIX = "alarm_"
    private const val FILE_SUFFIX = ".json"

    private const val LEGACY_PREFS = "sana_native_alarms"
    private const val LEGACY_KEY = "alarms"

    private fun directory(context: Context): File {
        val directory = File(
            context.filesDir,
            DIRECTORY_NAME
        )

        if (!directory.exists()) {
            directory.mkdirs()
        }

        return directory
    }

    private fun file(
        context: Context,
        notificationId: Int
    ): File {
        return File(
            directory(context),
            "$FILE_PREFIX$notificationId$FILE_SUFFIX"
        )
    }

    @Synchronized
    fun save(
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
    ) {
        val target = file(
            context,
            notificationId
        )

        val temporary = File(
            target.parentFile,
            "${target.name}.tmp"
        )

        val json = JSONObject()

        json.put(
            "notificationId",
            notificationId
        )

        json.put(
            "reminderId",
            reminderId
        )

        json.put(
            "triggerAtMillis",
            triggerAtMillis
        )

        json.put(
            "daily",
            daily
        )

        json.put(
            "name",
            name
        )

        json.put(
            "dosage",
            dosage
        )

        json.put(
            "reminderTime",
            reminderTime
        )

        json.put(
            "reminderDate",
            reminderDate
        )

        if (photoBase64.isNullOrBlank()) {
            json.put(
                "photoBase64",
                JSONObject.NULL
            )
        } else {
            json.put(
                "photoBase64",
                photoBase64
            )
        }

        temporary.writeText(
            json.toString(),
            Charsets.UTF_8
        )

        if (target.exists()) {
            target.delete()
        }

        if (!temporary.renameTo(target)) {
            temporary.delete()
            throw IllegalStateException(
                "Unable to commit alarm cache"
            )
        }
    }

    @Synchronized
    fun read(
        context: Context,
        notificationId: Int
    ): Entry? {

        val target = file(
            context,
            notificationId
        )

        if (!target.exists()) {
            return null
        }

        return try {
            val json = JSONObject(
                target.readText(Charsets.UTF_8)
            )

            val photo =
                if (
                    json.isNull("photoBase64")
                ) {
                    null
                } else {
                    json.optString(
                        "photoBase64",
                        ""
                    ).ifBlank { null }
                }

            Entry(
                notificationId = json.getInt(
                    "notificationId"
                ),
                reminderId = json.getString(
                    "reminderId"
                ),
                triggerAtMillis = json.getLong(
                    "triggerAtMillis"
                ),
                daily = json.optBoolean(
                    "daily",
                    false
                ),
                name = json.optString(
                    "name",
                    ""
                ),
                dosage = json.optString(
                    "dosage",
                    ""
                ),
                reminderTime = json.optString(
                    "reminderTime",
                    ""
                ),
                reminderDate = json.optString(
                    "reminderDate",
                    ""
                ),
                photoBase64 = photo
            )
        } catch (_: Exception) {
            null
        }
    }

    @Synchronized
    fun remove(
        context: Context,
        notificationId: Int
    ) {
        val target = file(
            context,
            notificationId
        )

        if (target.exists()) {
            target.delete()
        }
    }

    @Synchronized
    fun all(
        context: Context
    ): List<Entry> {

        val directory = directory(context)

        val files =
            directory.listFiles()
                ?.filter {
                    it.isFile &&
                        it.name.startsWith(FILE_PREFIX) &&
                        it.name.endsWith(FILE_SUFFIX)
                }
                ?: emptyList()

        return files.mapNotNull { current ->
            try {
                val notificationId =
                    current.name
                        .removePrefix(FILE_PREFIX)
                        .removeSuffix(FILE_SUFFIX)
                        .toInt()

                read(
                    context,
                    notificationId
                )
            } catch (_: Exception) {
                null
            }
        }
    }

    @Synchronized
    fun migrateLegacyAlarms(
        context: Context
    ) {

        val legacy =
            context.getSharedPreferences(
                LEGACY_PREFS,
                Context.MODE_PRIVATE
            )

        val stored =
            legacy.getStringSet(
                LEGACY_KEY,
                emptySet()
            ) ?: emptySet()

        for (value in stored) {

            val parts =
                value.split("|")

            if (parts.size != 4) {
                continue
            }

            val notificationId =
                parts[0].toIntOrNull()
                    ?: continue

            val reminderId =
                parts[1]

            val triggerAtMillis =
                parts[2].toLongOrNull()
                    ?: continue

            val daily =
                parts[3].toBoolean()

            if (read(
                    context,
                    notificationId
                ) != null
            ) {
                continue
            }

            try {
                save(
                    context = context,
                    notificationId = notificationId,
                    reminderId = reminderId,
                    triggerAtMillis = triggerAtMillis,
                    daily = daily,
                    name = "",
                    dosage = "",
                    reminderTime = "",
                    reminderDate = if (daily) {
                        "daily"
                    } else {
                        ""
                    },
                    photoBase64 = null
                )
            } catch (_: Exception) {
                // Keep going so one bad legacy record
                // cannot prevent the other alarms from migrating.
            }
        }
    }
}