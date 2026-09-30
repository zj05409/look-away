package io.github.zj05409.lookaway

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts the timer after a reboot or app update if the user had it enabled. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                if (Store(context).enabled) {
                    runCatching { TimerService.send(context, TimerService.ACTION_START) }
                }
            }
        }
    }
}
