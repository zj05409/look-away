package io.github.zj05409.lookaway

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TimerEngineTest {
    private val config = TimerConfig(workMinutes = 10, breakMinutes = 5, warningMinutes = 1, penaltyMinutes = 2)

    private fun engine(state: TimerState = TimerState()) = TimerEngine(config, state)

    @Test
    fun workTimeOnlyCountsActiveUse() {
        val e = engine()
        e.tick(now = 0, activeMs = 0, inCall = false)
        assertEquals(10 * MINUTE_MS, e.workRemainingMs)
        e.tick(now = 1_000, activeMs = 1_000, inCall = false)
        assertEquals(10 * MINUTE_MS - 1_000, e.workRemainingMs)
    }

    @Test
    fun warnsOnceThenStartsBreak() {
        val e = engine()
        val warning = e.tick(0, 9 * MINUTE_MS + 1, false)
        assertEquals(listOf(TimerEvent.PRE_BREAK_WARNING), warning)
        assertTrue(e.tick(1, 1_000, false).isEmpty())
        val started = e.tick(2, MINUTE_MS, false)
        assertEquals(listOf(TimerEvent.BREAK_STARTED), started)
        assertEquals(Phase.BREAK, e.state.phase)
        assertEquals(2 + 5 * MINUTE_MS, e.state.breakEndsAt)
    }

    @Test
    fun breakWaitsForCallToEnd() {
        val e = engine()
        assertTrue(e.tick(0, 10 * MINUTE_MS, inCall = true).none { it == TimerEvent.BREAK_STARTED })
        assertTrue(e.state.waitingForCall)
        assertEquals(listOf(TimerEvent.BREAK_STARTED), e.tick(5, 0, inCall = false))
    }

    @Test
    fun breakCompletesOnWallClockAndNeedsConfirmation() {
        val e = engine()
        e.startBreak(now = 0)
        assertTrue(e.tick(5 * MINUTE_MS - 1, 0, false).isEmpty())
        assertEquals(listOf(TimerEvent.BREAK_COMPLETED), e.tick(5 * MINUTE_MS, 0, false))
        assertEquals(Phase.BREAK_COMPLETE, e.state.phase)
        assertEquals(listOf(TimerEvent.BREAK_ENDED), e.startWorking())
        assertEquals(Phase.WORKING, e.state.phase)
        assertEquals(10 * MINUTE_MS, e.workRemainingMs)
    }

    @Test
    fun skippingAddsPenaltyToNextBreak() {
        val e = engine()
        e.startBreak(now = 0)
        assertEquals(listOf(TimerEvent.BREAK_ENDED), e.skipBreak())
        assertEquals(2, e.state.pendingPenaltyMinutes)
        e.startBreak(now = 100)
        assertEquals(2, e.state.appliedPenaltyMinutes)
        assertEquals(0, e.state.pendingPenaltyMinutes)
        assertEquals(100 + 7 * MINUTE_MS, e.state.breakEndsAt)
    }

    @Test
    fun startWorkingIsIgnoredDuringBreak() {
        val e = engine()
        e.startBreak(now = 0)
        assertTrue(e.startWorking().isEmpty())
        assertEquals(Phase.BREAK, e.state.phase)
    }

    @Test
    fun pausedTimerDoesNotAdvanceOrBreak() {
        val e = engine()
        e.setPaused(true)
        assertTrue(e.tick(0, 20 * MINUTE_MS, false).isEmpty())
        assertEquals(10 * MINUTE_MS, e.workRemainingMs)
    }

    @Test
    fun extendAddsThreeMinutesAndRearmsWarning() {
        val e = engine()
        e.tick(0, 9 * MINUTE_MS + 30_000, false)
        assertTrue(e.state.warningSent)
        e.extend()
        assertFalse(e.state.warningSent)
        assertEquals(3 * MINUTE_MS + 30_000, e.workRemainingMs)
    }

    @Test
    fun puttingPhoneAwayForABreakLengthResetsWork() {
        val e = engine()
        e.tick(0, 4 * MINUTE_MS, false)
        e.userLeft(now = 1_000)
        assertEquals(listOf(TimerEvent.RESTED), e.userReturned(now = 1_000 + 5 * MINUTE_MS))
        assertEquals(10 * MINUTE_MS, e.workRemainingMs)
    }

    @Test
    fun shortAbsenceKeepsWorkProgress() {
        val e = engine()
        e.tick(0, 4 * MINUTE_MS, false)
        e.userLeft(now = 1_000)
        assertTrue(e.userReturned(now = 1_000 + MINUTE_MS).isEmpty())
        assertEquals(6 * MINUTE_MS, e.workRemainingMs)
    }

    @Test
    fun changingBreakLengthMidBreakKeepsElapsedRest() {
        val e = engine()
        e.startBreak(now = 0)
        e.updateConfig(config.copy(breakMinutes = 8))
        assertEquals(8 * MINUTE_MS, e.state.breakEndsAt)
    }

    @Test
    fun restartDuringBreakCountsAsSkip() {
        val e = engine()
        e.startBreak(now = 0)
        e.restart()
        assertEquals(Phase.WORKING, e.state.phase)
        assertEquals(2, e.state.pendingPenaltyMinutes)
    }

    @Test
    fun configIsClamped() {
        val c = TimerConfig(workMinutes = 0, breakMinutes = 999, warningMinutes = -1, penaltyMinutes = 100).sanitized()
        assertEquals(1, c.workMinutes)
        assertEquals(180, c.breakMinutes)
        assertEquals(0, c.warningMinutes)
        assertEquals(60, c.penaltyMinutes)
    }
}
