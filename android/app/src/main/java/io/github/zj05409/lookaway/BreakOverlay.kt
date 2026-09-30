package io.github.zj05409.lookaway

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Full-screen black break overlay drawn above every app ("Display over other apps").
 * Android cannot hide the notification shade or the home gesture from a third-party
 * app, but the overlay stays on top of whatever app is opened until the break ends.
 */
class BreakOverlay(
    private val context: Context,
    private val onSkip: () -> Unit,
    private val onStartWorking: () -> Unit,
) {
    private val windowManager = context.getSystemService(WindowManager::class.java)
    private var root: View? = null
    private lateinit var timerText: TextView
    private lateinit var completionGroup: LinearLayout
    private lateinit var reminderText: TextView
    private lateinit var skipButton: HoldButton
    private lateinit var startButton: TextView

    val isShowing: Boolean
        get() = root != null

    fun canShow(): Boolean = Settings.canDrawOverlays(context)

    fun show() {
        if (root != null || !canShow()) return
        val view = buildView()
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.OPAQUE,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        try {
            windowManager.addView(view, params)
            root = view
        } catch (e: RuntimeException) {
            // Permission revoked between the check and addView.
            Log.w(TAG, "Unable to show break overlay", e)
        }
    }

    fun hide() {
        val view = root ?: return
        root = null
        runCatching { windowManager.removeView(view) }
    }

    fun update(phase: Phase, remainingMs: Long, reminder: String) {
        if (root == null) return
        val complete = phase == Phase.BREAK_COMPLETE
        timerText.visibility = if (complete) View.GONE else View.VISIBLE
        completionGroup.visibility = if (complete) View.VISIBLE else View.GONE
        skipButton.visibility = if (complete) View.GONE else View.VISIBLE
        startButton.visibility = if (complete) View.VISIBLE else View.GONE
        timerText.text = formatClock(remainingMs)
        if (reminderText.text.toString() != reminder) reminderText.text = reminder
    }

    @SuppressLint("SetTextI18n")
    private fun buildView(): View {
        val ctx = context
        val frame = object : FrameLayout(ctx) {
            // Swallow Back so the overlay cannot be dismissed with it.
            override fun dispatchKeyEvent(event: KeyEvent): Boolean {
                if (event.keyCode == KeyEvent.KEYCODE_BACK) return true
                return super.dispatchKeyEvent(event)
            }
        }
        frame.setBackgroundColor(LookAwayColors.background)
        frame.isFocusableInTouchMode = true

        val center = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(ctx.dp(28), 0, ctx.dp(28), 0)
        }

        timerText = TextView(ctx).apply {
            setTextColor(LookAwayColors.text)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 72f)
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(ctx.dp(36), ctx.dp(14), ctx.dp(36), ctx.dp(14))
            background = roundedBackground(ctx, 0x1FFFFFFF, 32)
        }
        center.addView(timerText, wrap())

        completionGroup = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            addView(TextView(ctx).apply {
                text = "✓"
                setTextColor(LookAwayColors.success)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 56f)
                typeface = Typeface.DEFAULT_BOLD
            }, wrap())
            addView(TextView(ctx).apply {
                setText(R.string.break_complete)
                setTextColor(LookAwayColors.text)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
                typeface = Typeface.DEFAULT_BOLD
            }, wrap())
            addView(TextView(ctx).apply {
                setText(R.string.break_complete_detail)
                setTextColor(LookAwayColors.secondaryText)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setPadding(0, ctx.dp(8), 0, 0)
            }, wrap())
        }
        center.addView(completionGroup, wrap())

        reminderText = TextView(ctx).apply {
            setTextColor(LookAwayColors.secondaryText)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.25f)
            setPadding(0, ctx.dp(28), 0, 0)
        }
        center.addView(reminderText, wrap())

        frame.addView(
            center,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ),
        )

        val bottom = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
        ).apply { bottomMargin = ctx.dp(72) }

        skipButton = HoldButton(
            ctx,
            label = ctx.getString(R.string.skip),
            holdingLabel = ctx.getString(R.string.keep_holding),
            progressColor = LookAwayColors.destructive,
            onConfirm = onSkip,
        ).apply {
            setTextColor(LookAwayColors.destructive)
            background = roundedBackground(ctx, 0x22FF7873)
            alpha = 0.3f
            minWidth = ctx.dp(160)
        }
        frame.addView(skipButton, bottom)

        startButton = TextView(ctx).apply {
            setText(R.string.start_working)
            setTextColor(LookAwayColors.text)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            minWidth = ctx.dp(240)
            setPadding(ctx.dp(36), ctx.dp(18), ctx.dp(36), ctx.dp(18))
            background = roundedBackground(ctx, LookAwayColors.accent, 20)
            setOnClickListener { onStartWorking() }
        }
        frame.addView(startButton, FrameLayout.LayoutParams(bottom))

        return frame
    }

    private fun wrap() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.WRAP_CONTENT,
        LinearLayout.LayoutParams.WRAP_CONTENT,
    ).apply { gravity = Gravity.CENTER_HORIZONTAL }

    private companion object {
        const val TAG = "LookAwayOverlay"
    }
}
