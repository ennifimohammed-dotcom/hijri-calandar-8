package com.hijricalendar.hijri_calendar

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-triggers the Flutter app on boot so the notification engine
 * can rebuild its 30-day rolling schedule.
 *
 * flutter_local_notifications already restores zoned-scheduled
 * notifications from its database after BOOT_COMPLETED via its
 * own ScheduledNotificationBootReceiver. This receiver is an
 * additional guard that boots the app context.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_PACKAGE_REPLACED -> {
                // No-op: flutter_local_notifications handles scheduled
                // notification restoration. The Flutter side will
                // reschedule its 30-day window the next time the app
                // is opened (and again at midnight).
            }
        }
    }
}
