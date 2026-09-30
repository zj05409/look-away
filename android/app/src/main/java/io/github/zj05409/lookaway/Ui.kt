package io.github.zj05409.lookaway

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.os.SystemClock
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.widget.TextView

/** Shared look: true black, one warm-pink accent (same as the macOS app). */
object LookAwayColors {
    val accent = Color.rgb(255, 107, 199)
    val background = Color.BLACK
    val surface = Color.rgb(28, 28, 32)
    val text = Color.WHITE
    val secondaryText = Color.argb(170, 255, 255, 255)
    val destructive = Color.rgb(255, 120, 115)
    val success = Color.rgb(52, 199, 89)
}

fun Context.dp(value: Int): Int = TypedValue.applyDimension(
    TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics,
).toInt()

fun roundedBackground(context: Context, color: Int, radiusDp: Int = 14): GradientDrawable =
    GradientDrawable().apply {
        setColor(color)
        cornerRadius = context.dp(radiusDp).toFloat()
    }

fun formatClock(ms: Long): String {
    val total = ((ms.coerceAtLeast(0) + 999) / 1000).toInt()
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val seconds = total % 60
    return if (hours > 0) {
        String.format("%d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format("%02d:%02d", minutes, seconds)
    }
}

/**
 * Button that only fires after being held for [holdMs] — the same deliberate
 * friction as the Mac app's hold-to-skip / hold-to-restart controls.
 */
@SuppressLint("ViewConstructor")
class HoldButton(
    context: Context,
    private val label: String,
    private val holdingLabel: String,
    private val progressColor: Int,
    private val holdMs: Long = HOLD_CONFIRM_MS,
    private val onConfirm: () -> Unit,
) : TextView(context) {
    private val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = progressColor
        alpha = 90
    }
    private val progressRect = RectF()
    private var holdStartedAt = 0L
    private var holding = false

    private val ticker = object : Runnable {
        override fun run() {
            if (!holding) return
            invalidate()
            if (progress() >= 1f) {
                stopHolding()
                onConfirm()
            } else {
                postDelayed(this, 50)
            }
        }
    }

    init {
        text = label
        gravity = Gravity.CENTER
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        val padH = context.dp(18)
        val padV = context.dp(14)
        setPadding(padH, padV, padH, padV)
        isClickable = true
    }

    private fun progress(): Float =
        ((SystemClock.uptimeMillis() - holdStartedAt).toFloat() / holdMs).coerceIn(0f, 1f)

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                holding = true
                holdStartedAt = SystemClock.uptimeMillis()
                text = holdingLabel
                removeCallbacks(ticker)
                post(ticker)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> stopHolding()
        }
        return true
    }

    override fun onDetachedFromWindow() {
        stopHolding()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        if (holding) {
            val radius = context.dp(14).toFloat()
            progressRect.set(0f, 0f, width * progress(), height.toFloat())
            canvas.drawRoundRect(progressRect, radius, radius, progressPaint)
        }
        super.onDraw(canvas)
    }

    private fun stopHolding() {
        holding = false
        removeCallbacks(ticker)
        text = label
        invalidate()
    }

    companion object {
        const val HOLD_CONFIRM_MS = 11_000L
    }
}
