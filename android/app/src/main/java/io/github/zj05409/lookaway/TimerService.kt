package io.github.zj05409.lookaway

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock

/** Read-only view of the schedule for the activity, refreshed every tick. */
data class Snapshot(
    val phase: Phase,
    val remainingMs: Long,
    val totalMs: Long,
    val paused: Boolean,
    val active: Boolean,
    val waitingForCall: Boolean,
    val warningSent: Boolean,
    val pendingPenaltyMinutes: Int,
)

/**
 * Foreground service that owns the [TimerEngine]: counts phone-in-use time,
 * raises the break overlay, and keeps an ongoing countdown notification.
 */
class TimerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var store: Store
    private lateinit var engine: TimerEngine
    private lateinit var overlay: BreakOverlay
    private lateinit var notifications: NotificationManager
    private lateinit var powerManager: PowerManager
    private lateinit var keyguardManager: KeyguardManager
    private lateinit var audioManager: AudioManager

    private var lastTickElapsed = 0L
    private var lastActive = false
    private var lastPersistElapsed = 0L
    private var lastNotificationKey = ""
    private var receiverRegistered = false

    private val tickRunnable = object : Runnable {
        override fun run() {
            tick()
            // Tick every second while the screen is on; only occasionally while it is off.
            handler.postDelayed(this, if (powerManager.isInteractive) 1_000L else 30_000L)
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            handler.removeCallbacks(tickRunnable)
            handler.post(tickRunnable)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        store = Store(this)
        engine = TimerEngine(store.loadConfig(), store.loadState())
        notifications = getSystemService(NotificationManager::class.java)
        powerManager = getSystemService(PowerManager::class.java)
        keyguardManager = getSystemService(KeyguardManager::class.java)
        audioManager = getSystemService(AudioManager::class.java)
        overlay = BreakOverlay(
            this,
            onSkip = { handleEvents(engine.skipBreak()) },
            onStartWorking = { handleEvents(engine.startWorking()) },
        )
        createChannels()

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, filter)
        receiverRegistered = true

        lastTickElapsed = SystemClock.elapsedRealtime()
        lastActive = isUserActive()
        if (!lastActive) engine.userLeft(System.currentTimeMillis())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        when (intent?.action) {
            ACTION_TOGGLE_PAUSE -> engine.setPaused(!engine.state.paused)
            ACTION_BREAK_NOW -> handleEvents(engine.startBreak(System.currentTimeMillis()))
            ACTION_EXTEND -> {
                engine.extend()
                notifications.cancel(NOTIFICATION_WARNING)
            }
            ACTION_RESTART -> handleEvents(engine.restart())
            ACTION_RELOAD_CONFIG -> engine.updateConfig(store.loadConfig())
            ACTION_STOP -> if (engine.state.phase == Phase.WORKING) {
                store.enabled = false
                persist()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }
        store.enabled = true
        persist()
        handler.removeCallbacks(tickRunnable)
        handler.post(tickRunnable)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(tickRunnable)
        if (receiverRegistered) unregisterReceiver(screenReceiver)
        overlay.hide()
        persist()
        snapshot = null
        super.onDestroy()
    }

    private fun tick() {
        val nowElapsed = SystemClock.elapsedRealtime()
        val delta = (nowElapsed - lastTickElapsed).coerceIn(0L, MAX_TICK_MS)
        lastTickElapsed = nowElapsed
        val now = System.currentTimeMillis()

        val active = isUserActive()
        val activeMs = if (active && lastActive) delta else 0L
        if (active != lastActive) {
            if (active) handleEvents(engine.userReturned(now)) else engine.userLeft(now)
            lastActive = active
            persist()
        }

        handleEvents(engine.tick(now, activeMs, isInCall()))
        render(now, active)

        if (nowElapsed - lastPersistElapsed >= PERSIST_INTERVAL_MS) persist()
    }

    /** Applies side effects of engine events (overlay, alerts) and saves the new state. */
    private fun handleEvents(events: List<TimerEvent>) {
        if (events.isEmpty()) return
        for (event in events) {
            when (event) {
                TimerEvent.PRE_BREAK_WARNING -> showWarning()
                TimerEvent.BREAK_STARTED -> notifications.cancel(NOTIFICATION_WARNING)
                TimerEvent.BREAK_COMPLETED -> showBreakComplete()
                TimerEvent.BREAK_ENDED -> {
                    notifications.cancel(NOTIFICATION_ALERT)
                    overlay.hide()
                }
                TimerEvent.RESTED -> Unit
            }
        }
        persist()
        render(System.currentTimeMillis(), isUserActive())
    }

    private fun render(now: Long, active: Boolean) {
        val state = engine.state
        val remaining = engine.remainingMs(now)

        if (state.phase == Phase.WORKING) {
            overlay.hide()
        } else {
            overlay.show()
            overlay.update(state.phase, remaining, engine.config.reminderMessage)
        }

        snapshot = Snapshot(
            phase = state.phase,
            remainingMs = remaining,
            totalMs = engine.totalMs(),
            paused = state.paused,
            active = active,
            waitingForCall = state.waitingForCall,
            warningSent = state.warningSent,
            pendingPenaltyMinutes = state.pendingPenaltyMinutes,
        )
        updateOngoingNotification(now, active)
    }

    private fun persist() {
        store.saveState(engine.state)
        lastPersistElapsed = SystemClock.elapsedRealtime()
    }

    private fun isUserActive(): Boolean =
        powerManager.isInteractive && !keyguardManager.isKeyguardLocked

    private fun isInCall(): Boolean = when (audioManager.mode) {
        AudioManager.MODE_IN_CALL, AudioManager.MODE_IN_COMMUNICATION -> true
        else -> false
    }

    // region Notifications

    private fun createChannels() {
        notifications.createNotificationChannel(
            NotificationChannel(
                CHANNEL_STATUS,
                getString(R.string.channel_status),
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) },
        )
        notifications.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ALERTS,
                getString(R.string.channel_alerts),
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
    }

    private fun startInForeground() {
        val notification = buildOngoingNotification(System.currentTimeMillis(), isUserActive())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ONGOING,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ONGOING, notification)
        }
    }

    private fun updateOngoingNotification(now: Long, active: Boolean) {
        val state = engine.state
        val remaining = engine.remainingMs(now)
        val counting = when (state.phase) {
            Phase.WORKING -> active && !state.paused && !state.waitingForCall
            Phase.BREAK -> true
            Phase.BREAK_COMPLETE -> false
        }
        // The chronometer counts down on its own; rebuild only when what it shows changes.
        val key = listOf(
            state.phase, state.paused, active, state.waitingForCall, state.warningSent,
            if (counting) (now + remaining) / 5_000 else remaining / 60_000,
        ).joinToString("|")
        if (key == lastNotificationKey) return
        lastNotificationKey = key
        notifications.notify(NOTIFICATION_ONGOING, buildOngoingNotification(now, active))
    }

    private fun buildOngoingNotification(now: Long, active: Boolean): Notification {
        val state = engine.state
        val remaining = engine.remainingMs(now)
        val builder = Notification.Builder(this, CHANNEL_STATUS)
            .setSmallIcon(R.drawable.ic_notification)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(openAppIntent())

        when (state.phase) {
            Phase.WORKING -> {
                val title = when {
                    state.paused -> getString(R.string.status_paused)
                    state.waitingForCall -> getString(R.string.status_waiting_for_call)
                    !active -> getString(R.string.status_idle)
                    else -> getString(R.string.status_working)
                }
                builder.setContentTitle(title)
                if (active && !state.paused && !state.waitingForCall) {
                    builder.setContentText(getString(R.string.until_break))
                    countdown(builder, now + remaining)
                } else {
                    builder.setContentText(getString(R.string.remaining_value, formatClock(remaining)))
                }
                builder.addAction(
                    action(
                        if (state.paused) R.string.resume else R.string.pause,
                        ACTION_TOGGLE_PAUSE,
                    ),
                )
                if (state.warningSent) builder.addAction(action(R.string.extend, ACTION_EXTEND))
                builder.addAction(action(R.string.break_now, ACTION_BREAK_NOW))
            }
            Phase.BREAK -> {
                builder.setContentTitle(getString(R.string.status_break))
                    .setContentText(engine.config.reminderMessage)
                countdown(builder, now + remaining)
            }
            Phase.BREAK_COMPLETE -> builder
                .setContentTitle(getString(R.string.break_complete))
                .setContentText(getString(R.string.break_complete_detail))
        }
        return builder.build()
    }

    private fun countdown(builder: Notification.Builder, endsAt: Long) {
        builder.setWhen(endsAt)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
    }

    private fun showWarning() {
        val minutes = engine.config.warningMinutes
        val notification = Notification.Builder(this, CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(resources.getQuantityString(R.plurals.warning_title, minutes, minutes))
            .setContentText(engine.config.reminderMessage)
            .setStyle(Notification.BigTextStyle().bigText(engine.config.reminderMessage))
            .setAutoCancel(true)
            .setContentIntent(openAppIntent())
            .addAction(action(R.string.extend, ACTION_EXTEND))
            .build()
        notifications.notify(NOTIFICATION_WARNING, notification)
    }

    private fun showBreakComplete() {
        val notification = Notification.Builder(this, CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.break_complete))
            .setContentText(getString(R.string.break_complete_detail))
            .setAutoCancel(true)
            .setContentIntent(openAppIntent())
            .build()
        notifications.notify(NOTIFICATION_ALERT, notification)
    }

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun action(titleRes: Int, action: String): Notification.Action {
        val pending = PendingIntent.getForegroundService(
            this,
            action.hashCode(),
            Intent(this, TimerService::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Action.Builder(null, getString(titleRes), pending).build()
    }

    // endregion

    companion object {
        const val ACTION_START = "io.github.zj05409.lookaway.START"
        const val ACTION_TOGGLE_PAUSE = "io.github.zj05409.lookaway.TOGGLE_PAUSE"
        const val ACTION_BREAK_NOW = "io.github.zj05409.lookaway.BREAK_NOW"
        const val ACTION_EXTEND = "io.github.zj05409.lookaway.EXTEND"
        const val ACTION_RESTART = "io.github.zj05409.lookaway.RESTART"
        const val ACTION_RELOAD_CONFIG = "io.github.zj05409.lookaway.RELOAD_CONFIG"
        const val ACTION_STOP = "io.github.zj05409.lookaway.STOP"

        private const val CHANNEL_STATUS = "status"
        private const val CHANNEL_ALERTS = "alerts"
        private const val NOTIFICATION_ONGOING = 1
        private const val NOTIFICATION_WARNING = 2
        private const val NOTIFICATION_ALERT = 3
        private const val MAX_TICK_MS = 5_000L
        private const val PERSIST_INTERVAL_MS = 15_000L

        @Volatile
        var snapshot: Snapshot? = null
            private set

        fun send(context: Context, action: String) {
            context.startForegroundService(Intent(context, TimerService::class.java).setAction(action))
        }
    }
}
