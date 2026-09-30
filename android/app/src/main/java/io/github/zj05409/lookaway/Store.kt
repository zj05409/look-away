package io.github.zj05409.lookaway

import android.content.Context
import android.content.SharedPreferences

/** SharedPreferences persistence for settings and the running schedule. */
class Store(context: Context) {
    private val appContext = context.applicationContext
    private val prefs: SharedPreferences =
        appContext.getSharedPreferences("look-away", Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    fun loadConfig(): TimerConfig {
        val defaults = TimerConfig()
        return TimerConfig(
            workMinutes = prefs.getInt("workMinutes", defaults.workMinutes),
            breakMinutes = prefs.getInt("breakMinutes", defaults.breakMinutes),
            warningMinutes = prefs.getInt("warningMinutes", defaults.warningMinutes),
            penaltyMinutes = prefs.getInt("penaltyMinutes", defaults.penaltyMinutes),
            reminderMessage = prefs.getString("reminderMessage", null)
                ?: appContext.getString(R.string.default_reminder),
        ).sanitized()
    }

    fun saveConfig(config: TimerConfig) {
        val clean = config.sanitized()
        prefs.edit()
            .putInt("workMinutes", clean.workMinutes)
            .putInt("breakMinutes", clean.breakMinutes)
            .putInt("warningMinutes", clean.warningMinutes)
            .putInt("penaltyMinutes", clean.penaltyMinutes)
            .putString(
                "reminderMessage",
                clean.reminderMessage.ifEmpty { appContext.getString(R.string.default_reminder) },
            )
            .apply()
    }

    fun loadState(): TimerState {
        val phase = runCatching { Phase.valueOf(prefs.getString("phase", null) ?: "") }
            .getOrDefault(Phase.WORKING)
        return TimerState(
            phase = phase,
            workedMs = prefs.getLong("workedMs", 0),
            extensionMs = prefs.getLong("extensionMs", 0),
            paused = prefs.getBoolean("paused", false),
            warningSent = prefs.getBoolean("warningSent", false),
            breakEndsAt = prefs.getLong("breakEndsAt", 0),
            appliedPenaltyMinutes = prefs.getInt("appliedPenaltyMinutes", 0),
            pendingPenaltyMinutes = prefs.getInt("pendingPenaltyMinutes", 0),
            inactiveSince = prefs.getLong("inactiveSince", 0),
            waitingForCall = prefs.getBoolean("waitingForCall", false),
        )
    }

    fun saveState(state: TimerState) {
        prefs.edit()
            .putString("phase", state.phase.name)
            .putLong("workedMs", state.workedMs)
            .putLong("extensionMs", state.extensionMs)
            .putBoolean("paused", state.paused)
            .putBoolean("warningSent", state.warningSent)
            .putLong("breakEndsAt", state.breakEndsAt)
            .putInt("appliedPenaltyMinutes", state.appliedPenaltyMinutes)
            .putInt("pendingPenaltyMinutes", state.pendingPenaltyMinutes)
            .putLong("inactiveSince", state.inactiveSince)
            .putBoolean("waitingForCall", state.waitingForCall)
            .apply()
    }

    private companion object {
        const val KEY_ENABLED = "enabled"
    }
}
