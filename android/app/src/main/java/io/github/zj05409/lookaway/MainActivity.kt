package io.github.zj05409.lookaway

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var store: Store

    private lateinit var phaseText: TextView
    private lateinit var timerText: TextView
    private lateinit var progress: ProgressBar
    private lateinit var detailText: TextView
    private lateinit var runningControls: LinearLayout
    private lateinit var pauseButton: TextView
    private lateinit var stopButton: TextView
    private lateinit var enableButton: TextView

    private lateinit var overlayStatus: TextView
    private lateinit var overlayButton: TextView
    private lateinit var notificationStatus: TextView
    private lateinit var notificationButton: TextView
    private lateinit var batteryStatus: TextView
    private lateinit var batteryButton: TextView

    private lateinit var workField: EditText
    private lateinit var breakField: EditText
    private lateinit var warningField: EditText
    private lateinit var penaltyField: EditText
    private lateinit var reminderField: EditText

    private val refresher = object : Runnable {
        override fun run() {
            renderStatus()
            handler.postDelayed(this, 500)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = Store(this)
        setContentView(buildContent())
        loadSettingsIntoFields()
        if (store.enabled && TimerService.snapshot == null) {
            TimerService.send(this, TimerService.ACTION_START)
        }
    }

    override fun onResume() {
        super.onResume()
        renderPermissions()
        handler.post(refresher)
    }

    override fun onPause() {
        handler.removeCallbacks(refresher)
        super.onPause()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        renderPermissions()
    }

    // region Rendering

    private fun renderStatus() {
        val snap = TimerService.snapshot
        if (snap == null) {
            phaseText.setText(R.string.status_stopped)
            timerText.text = "--:--"
            progress.progress = 0
            detailText.setText(R.string.stopped_detail)
            runningControls.visibility = View.GONE
            enableButton.visibility = View.VISIBLE
            return
        }
        runningControls.visibility = View.VISIBLE
        enableButton.visibility = View.GONE

        phaseText.text = getString(
            when (snap.phase) {
                Phase.WORKING -> when {
                    snap.paused -> R.string.status_paused
                    snap.waitingForCall -> R.string.status_waiting_for_call
                    else -> R.string.status_working
                }
                Phase.BREAK -> R.string.status_break
                Phase.BREAK_COMPLETE -> R.string.break_complete
            },
        )
        timerText.text = formatClock(snap.remainingMs)
        progress.progress = if (snap.totalMs > 0) {
            (1000 * (1.0 - snap.remainingMs.toDouble() / snap.totalMs)).toInt().coerceIn(0, 1000)
        } else {
            1000
        }
        detailText.text = when {
            snap.pendingPenaltyMinutes > 0 && snap.phase == Phase.WORKING ->
                getString(R.string.pending_penalty, snap.pendingPenaltyMinutes)
            snap.phase == Phase.WORKING -> getString(R.string.counting_explainer)
            else -> ""
        }
        pauseButton.setText(if (snap.paused) R.string.resume else R.string.pause)
        stopButton.visibility = if (snap.phase == Phase.WORKING) View.VISIBLE else View.GONE
    }

    private fun renderPermissions() {
        val overlayOk = Settings.canDrawOverlays(this)
        overlayStatus.setText(if (overlayOk) R.string.permission_granted else R.string.permission_overlay_missing)
        overlayStatus.setTextColor(if (overlayOk) LookAwayColors.success else LookAwayColors.destructive)
        overlayButton.visibility = if (overlayOk) View.GONE else View.VISIBLE

        val notificationsOk = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        notificationStatus.setText(if (notificationsOk) R.string.permission_granted else R.string.permission_notifications_missing)
        notificationStatus.setTextColor(if (notificationsOk) LookAwayColors.success else LookAwayColors.secondaryText)
        notificationButton.visibility = if (notificationsOk) View.GONE else View.VISIBLE

        val batteryOk = getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)
        batteryStatus.setText(if (batteryOk) R.string.permission_granted else R.string.permission_battery_missing)
        batteryStatus.setTextColor(if (batteryOk) LookAwayColors.success else LookAwayColors.secondaryText)
        batteryButton.visibility = if (batteryOk) View.GONE else View.VISIBLE
    }

    // endregion

    // region Actions

    private fun enable() {
        requestNotificationsIfNeeded()
        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, R.string.permission_overlay_missing, Toast.LENGTH_LONG).show()
        }
        TimerService.send(this, TimerService.ACTION_START)
    }

    private fun requestNotificationsIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        }
    }

    private fun openOverlaySettings() {
        startActivity(
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")),
        )
    }

    @SuppressLint("BatteryLife")
    private fun openBatterySettings() {
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
        runCatching { startActivity(direct) }
            .onFailure { runCatching { startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) } }
    }

    private fun loadSettingsIntoFields() {
        val config = store.loadConfig()
        workField.setText(config.workMinutes.toString())
        breakField.setText(config.breakMinutes.toString())
        warningField.setText(config.warningMinutes.toString())
        penaltyField.setText(config.penaltyMinutes.toString())
        reminderField.setText(config.reminderMessage)
    }

    private fun saveSettings() {
        val current = store.loadConfig()
        fun EditText.minutes(fallback: Int) = text.toString().trim().toIntOrNull() ?: fallback
        val updated = TimerConfig(
            workMinutes = workField.minutes(current.workMinutes),
            breakMinutes = breakField.minutes(current.breakMinutes),
            warningMinutes = warningField.minutes(current.warningMinutes),
            penaltyMinutes = penaltyField.minutes(current.penaltyMinutes),
            reminderMessage = reminderField.text.toString(),
        ).sanitized()
        store.saveConfig(updated)
        loadSettingsIntoFields()
        if (TimerService.snapshot != null) {
            TimerService.send(this, TimerService.ACTION_RELOAD_CONFIG)
        }
        Toast.makeText(this, R.string.settings_saved, Toast.LENGTH_SHORT).show()
    }

    // endregion

    // region Layout

    private fun buildContent(): View {
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(32))
        }

        column.addView(TextView(this).apply {
            setText(R.string.app_name)
            setTextColor(LookAwayColors.accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
            typeface = Typeface.DEFAULT_BOLD
        })
        column.addView(label(getString(R.string.tagline), 15f, LookAwayColors.secondaryText), spaced(4))

        column.addView(statusCard(), spaced(20))
        column.addView(sectionTitle(R.string.section_permissions), spaced(28))
        column.addView(permissionsCard(), spaced(10))
        column.addView(sectionTitle(R.string.section_settings), spaced(28))
        column.addView(settingsCard(), spaced(10))
        column.addView(label(getString(R.string.about_text), 13f, LookAwayColors.secondaryText), spaced(24))

        val scroll = ScrollView(this).apply {
            setBackgroundColor(LookAwayColors.background)
            isFillViewport = true
            addView(column)
        }
        applySystemBarInsets(scroll)
        return scroll
    }

    private fun statusCard(): View = card().apply {
        phaseText = label("", 16f, LookAwayColors.secondaryText)
        addView(phaseText)

        timerText = TextView(this@MainActivity).apply {
            setTextColor(LookAwayColors.text)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 56f)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        addView(timerText, spaced(2))

        progress = ProgressBar(this@MainActivity, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 1000
            progressTintList = ColorStateList.valueOf(LookAwayColors.accent)
            progressBackgroundTintList = ColorStateList.valueOf(0x33FFFFFF)
        }
        addView(progress, spaced(8))

        detailText = label("", 14f, LookAwayColors.secondaryText)
        addView(detailText, spaced(8))

        runningControls = LinearLayout(this@MainActivity).apply {
            orientation = LinearLayout.VERTICAL
            val row = LinearLayout(this@MainActivity).apply { orientation = LinearLayout.HORIZONTAL }
            pauseButton = button(R.string.pause, LookAwayColors.surface) {
                TimerService.send(this@MainActivity, TimerService.ACTION_TOGGLE_PAUSE)
            }
            row.addView(pauseButton, weighted(end = 6))
            row.addView(
                button(R.string.break_now, LookAwayColors.surface) {
                    TimerService.send(this@MainActivity, TimerService.ACTION_BREAK_NOW)
                },
                weighted(start = 6),
            )
            addView(row, spaced(0))

            val restart = HoldButton(
                this@MainActivity,
                label = getString(R.string.restart_hold),
                holdingLabel = getString(R.string.keep_holding),
                progressColor = LookAwayColors.accent,
                onConfirm = { TimerService.send(this@MainActivity, TimerService.ACTION_RESTART) },
            ).apply {
                setTextColor(LookAwayColors.text)
                background = roundedBackground(this@MainActivity, LookAwayColors.surface)
            }
            addView(restart, spaced(10))

            stopButton = button(R.string.stop, LookAwayColors.surface, LookAwayColors.destructive) {
                TimerService.send(this@MainActivity, TimerService.ACTION_STOP)
            }
            addView(stopButton, spaced(10))
        }
        addView(runningControls, spaced(16))

        enableButton = button(R.string.enable, LookAwayColors.accent) { enable() }
        addView(enableButton, spaced(16))
    }

    private fun permissionsCard(): View = card().apply {
        overlayStatus = label("", 14f, LookAwayColors.secondaryText)
        overlayButton = button(R.string.grant, LookAwayColors.accent) { openOverlaySettings() }
        addView(permissionRow(R.string.permission_overlay, overlayStatus, overlayButton))

        notificationStatus = label("", 14f, LookAwayColors.secondaryText)
        notificationButton = button(R.string.grant, LookAwayColors.surface) { requestNotificationsIfNeeded() }
        addView(permissionRow(R.string.permission_notifications, notificationStatus, notificationButton), spaced(14))

        batteryStatus = label("", 14f, LookAwayColors.secondaryText)
        batteryButton = button(R.string.grant, LookAwayColors.surface) { openBatterySettings() }
        addView(permissionRow(R.string.permission_battery, batteryStatus, batteryButton), spaced(14))

        addView(label(getString(R.string.oem_hint), 13f, LookAwayColors.secondaryText), spaced(14))
    }

    private fun permissionRow(titleRes: Int, status: TextView, action: TextView): View =
        LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            val texts = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                addView(label(getString(titleRes), 16f, LookAwayColors.text))
                addView(status)
            }
            addView(texts, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(action, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { marginStart = dp(12) })
        }

    private fun settingsCard(): View = card().apply {
        workField = numberField()
        breakField = numberField()
        warningField = numberField()
        penaltyField = numberField()
        reminderField = EditText(this@MainActivity).apply {
            styleField(this)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            minLines = 2
        }
        addView(fieldRow(R.string.setting_work, workField))
        addView(fieldRow(R.string.setting_break, breakField), spaced(10))
        addView(fieldRow(R.string.setting_warning, warningField), spaced(10))
        addView(fieldRow(R.string.setting_penalty, penaltyField), spaced(10))
        addView(label(getString(R.string.setting_reminder), 15f, LookAwayColors.text), spaced(14))
        addView(reminderField, spaced(6))
        addView(button(R.string.save, LookAwayColors.accent) { saveSettings() }, spaced(16))
    }

    private fun fieldRow(titleRes: Int, field: EditText): View = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(
            label(getString(titleRes), 15f, LookAwayColors.text),
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        addView(field, LinearLayout.LayoutParams(dp(96), ViewGroup.LayoutParams.WRAP_CONTENT))
    }

    private fun numberField(): EditText = EditText(this).apply {
        styleField(this)
        inputType = InputType.TYPE_CLASS_NUMBER
        gravity = Gravity.CENTER
        maxLines = 1
    }

    private fun styleField(field: EditText) {
        field.setTextColor(LookAwayColors.text)
        field.setHintTextColor(LookAwayColors.secondaryText)
        field.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        field.background = roundedBackground(this, 0x22FFFFFF, 10)
        field.setPadding(dp(12), dp(10), dp(12), dp(10))
    }

    private fun card(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = roundedBackground(this@MainActivity, LookAwayColors.surface.withAlpha(0xCC), 20)
        setPadding(dp(18), dp(18), dp(18), dp(18))
    }

    private fun sectionTitle(res: Int): TextView =
        label(getString(res), 18f, LookAwayColors.text).apply { typeface = Typeface.DEFAULT_BOLD }

    private fun label(text: String, sizeSp: Float, color: Int): TextView = TextView(this).apply {
        this.text = text
        setTextColor(color)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        setLineSpacing(0f, 1.15f)
    }

    private fun button(
        textRes: Int,
        fill: Int,
        textColor: Int = LookAwayColors.text,
        onClick: () -> Unit,
    ): TextView = TextView(this).apply {
        setText(textRes)
        setTextColor(textColor)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(dp(16), dp(13), dp(16), dp(13))
        background = roundedBackground(this@MainActivity, if (fill == LookAwayColors.surface) 0x26FFFFFF else fill)
        setOnClickListener { onClick() }
    }

    private fun spaced(topDp: Int) = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
    ).apply { topMargin = dp(topDp) }

    private fun weighted(start: Int = 0, end: Int = 0) =
        LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
            marginStart = dp(start)
            marginEnd = dp(end)
        }

    /** targetSdk 35 draws edge-to-edge; keep content clear of the status and navigation bars. */
    private fun applySystemBarInsets(view: View) {
        view.setOnApplyWindowInsetsListener { v, insets ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
                v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            } else {
                @Suppress("DEPRECATION")
                v.setPadding(
                    insets.systemWindowInsetLeft,
                    insets.systemWindowInsetTop,
                    insets.systemWindowInsetRight,
                    insets.systemWindowInsetBottom,
                )
            }
            insets
        }
    }

    // endregion

    private fun Int.withAlpha(alpha: Int): Int = (this and 0x00FFFFFF) or (alpha shl 24)

    private companion object {
        const val REQUEST_NOTIFICATIONS = 1
    }
}
