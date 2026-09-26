package com.example.sana

import android.content.Context

object SanaNativeOwner {

    private const val PREFS =
        "sana_native_owner"

    private const val KEY =
        "owner_key"

    @Synchronized
    fun write(
        context: Context,
        ownerKey: String,
    ) {
        context.getSharedPreferences(
            PREFS,
            Context.MODE_PRIVATE
        )
            .edit()
            .putString(
                KEY,
                ownerKey,
            )
            .apply()
    }

    @Synchronized
    fun read(
        context: Context,
    ): String {
        return context.getSharedPreferences(
            PREFS,
            Context.MODE_PRIVATE
        )
            .getString(
                KEY,
                "",
            ) ?: ""
    }
}