package io.github.zj05409.lookaway

const val MINUTE_MS = 60_000L
const val EXTENSION_MINUTES = 3

enum class Phase { WORKING, BREAK, BREAK_COMPLETE }

enum class TimerEvent {
    PRE_BREAK_WARNING,
    BREAK_STARTED,
    BREAK_COMPLETED,
    BREAK_ENDED,

    /** The phone was put away for at least a break's length, so the work session starts over. */
    RESTED,
}

data class TimerConfig(
    val workMinutes: Int = 30,
    val breakMinutes: Int = 5,
    val warningMinutes: Int = 1,
    val penaltyMinutes: Int = 2,
    val reminderMessage: String = "",
) {
    fun sanitized(): TimerConfig = copy(
        workMinutes = workMinutes.coerceIn(1, 24 * 60),
        breakMinutes = breakMinutes.coerceIn(1, 180),
        warningMinutes = warningMinutes.coerceIn(0, 60),
        penaltyMinutes = penaltyMinutes.coerceIn(0, 60),
        reminderMessage = reminderMessage.trim().take(500),
    )
}

/**
 * Everything needed to resume the schedule after the process is killed.
 * Wall-clock fields use [System.currentTimeMillis] so they survive reboots.
 */
data class TimerState(
    val phase: Phase = Phase.WORKING,
    /** Phone-in-use time counted toward the current work session. */
    val workedMs: Long = 0,
    val extensionMs: Long = 0,
    val paused: Boolean = false,
    val warningSent: Boolean = false,
    val breakEndsAt: Long = 0,
    val appliedPenaltyMinutes: Int = 0,
    val pendingPenaltyMinutes: Int = 0,
    /** When the user stopped using the phone (screen off or locked); 0 while in use. */
    val inactiveSince: Long = 0,
    /** Work time is up, but a call is active: the break starts when it ends. */
    val waitingForCall: Boolean = false,
)

/**
 * Phone flavour of the macOS TimerEngine. Work time only accumulates while the
 * phone is actually in use (screen on and unlocked); a break always runs on the
 * wall clock. Pure Kotlin so it can be unit-tested without Android.
 */
class TimerEngine(config: TimerConfig, state: TimerState = TimerState()) {
    var config: TimerConfig = config.sanitized()
        private set
    var state: TimerState = state
        private set

    val workTotalMs: Long
        get() = config.workMinutes * MINUTE_MS + state.extensionMs

    val workRemainingMs: Long
        get() = (workTotalMs - state.workedMs).coerceAtLeast(0)

    val breakTotalMs: Long
        get() = (config.breakMinutes + state.appliedPenaltyMinutes) * MINUTE_MS

    fun breakRemainingMs(now: Long): Long = (state.breakEndsAt - now).coerceAtLeast(0)

    fun remainingMs(now: Long): Long = when (state.phase) {
        Phase.WORKING -> workRemainingMs
        Phase.BREAK -> breakRemainingMs(now)
        Phase.BREAK_COMPLETE -> 0
    }

    fun totalMs(): Long = when (state.phase) {
        Phase.WORKING -> workTotalMs
        Phase.BREAK -> breakTotalMs
        Phase.BREAK_COMPLETE -> 0
    }

    fun updateConfig(newConfig: TimerConfig) {
        val previous = config
        config = newConfig.sanitized()
        if (state.phase == Phase.BREAK && config.breakMinutes != previous.breakMinutes) {
            // Keep the time already rested; only the configured length changes.
            val deltaMs = (config.breakMinutes - previous.breakMinutes) * MINUTE_MS
            state = state.copy(breakEndsAt = state.breakEndsAt + deltaMs)
        }
        if (config.warningMinutes != previous.warningMinutes) {
            state = state.copy(warningSent = false)
        }
    }

    /**
     * Advances the schedule. [activeMs] is the phone-in-use time since the previous tick
     * (0 while the screen is off or locked).
     */
    fun tick(now: Long, activeMs: Long, inCall: Boolean): List<TimerEvent> {
        val events = mutableListOf<TimerEvent>()
        when (state.phase) {
            Phase.WORKING -> {
                if (state.paused) return events
                if (activeMs > 0) {
                    state = state.copy(workedMs = state.workedMs + activeMs)
                }
                val remaining = workRemainingMs
                val warningMs = config.warningMinutes * MINUTE_MS
                if (warningMs > 0 && !state.warningSent && remaining in 1..warningMs) {
                    state = state.copy(warningSent = true)
                    events += TimerEvent.PRE_BREAK_WARNING
                }
                if (remaining <= 0) {
                    if (inCall) {
                        if (!state.waitingForCall) state = state.copy(waitingForCall = true)
                    } else {
                        events += startBreak(now)
                    }
                }
            }
            Phase.BREAK -> if (now >= state.breakEndsAt) {
                state = state.copy(phase = Phase.BREAK_COMPLETE)
                events += TimerEvent.BREAK_COMPLETED
            }
            Phase.BREAK_COMPLETE -> Unit
        }
        return events
    }

    fun startBreak(now: Long): List<TimerEvent> {
        if (state.phase != Phase.WORKING) return emptyList()
        val applied = state.pendingPenaltyMinutes
        state = state.copy(
            phase = Phase.BREAK,
            appliedPenaltyMinutes = applied,
            pendingPenaltyMinutes = 0,
            breakEndsAt = now + (config.breakMinutes + applied) * MINUTE_MS,
            paused = false,
            warningSent = false,
            waitingForCall = false,
        )
        return listOf(TimerEvent.BREAK_STARTED)
    }

    /** Ends a break early; the configured penalty is added to the next break. */
    fun skipBreak(): List<TimerEvent> {
        if (state.phase != Phase.BREAK) return emptyList()
        state = state.copy(pendingPenaltyMinutes = state.pendingPenaltyMinutes + config.penaltyMinutes)
        return backToWork()
    }

    /** Explicit confirmation after the minimum break, like the Mac's "Start Working". */
    fun startWorking(): List<TimerEvent> {
        if (state.phase != Phase.BREAK_COMPLETE) return emptyList()
        return backToWork()
    }

    fun restart(): List<TimerEvent> {
        val events = when (state.phase) {
            Phase.BREAK -> skipBreak()
            Phase.BREAK_COMPLETE -> backToWork()
            Phase.WORKING -> emptyList()
        }
        state = state.copy(workedMs = 0, extensionMs = 0, paused = false, warningSent = false, waitingForCall = false)
        return events
    }

    fun extend() {
        if (state.phase != Phase.WORKING) return
        state = state.copy(extensionMs = state.extensionMs + EXTENSION_MINUTES * MINUTE_MS, warningSent = false)
    }

    fun setPaused(paused: Boolean) {
        if (state.phase != Phase.WORKING) return
        state = state.copy(paused = paused)
    }

    fun userLeft(now: Long) {
        if (state.inactiveSince == 0L) state = state.copy(inactiveSince = now)
    }

    fun userReturned(now: Long): List<TimerEvent> {
        val since = state.inactiveSince
        state = state.copy(inactiveSince = 0)
        val rested = since > 0 && now - since >= config.breakMinutes * MINUTE_MS
        if (rested && state.phase == Phase.WORKING && state.workedMs > 0) {
            state = state.copy(workedMs = 0, extensionMs = 0, warningSent = false, waitingForCall = false)
            return listOf(TimerEvent.RESTED)
        }
        return emptyList()
    }

    private fun backToWork(): List<TimerEvent> {
        state = state.copy(
            phase = Phase.WORKING,
            workedMs = 0,
            extensionMs = 0,
            warningSent = false,
            appliedPenaltyMinutes = 0,
            breakEndsAt = 0,
            waitingForCall = false,
        )
        return listOf(TimerEvent.BREAK_ENDED)
    }
}
