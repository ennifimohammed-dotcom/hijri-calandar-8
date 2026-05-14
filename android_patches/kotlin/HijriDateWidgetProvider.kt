package com.hijricalendar.hijri_calendar

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Home-screen widget: "Hijri Date".
 *
 * The premium card is rendered on the Flutter side
 * (WidgetSyncService -> HijriDateWidgetView) to a full-bleed PNG via
 * `home_widget`'s `renderFlutterWidget`. This provider runs in the
 * launcher's process — no Flutter engine, no app state — and only
 * loads that PNG into the widget's ImageView. The ImageView shows it
 * with centerCrop, so it fills the whole widget with no background
 * behind it.
 *
 * Tapping the widget launches the app on its monthly calendar view:
 * the click PendingIntent carries a home_widget URI which the Flutter
 * side (WidgetSyncService) reads to switch to CalendarViewMode.monthly.
 * The intent is explicit (it targets MainActivity directly), so no
 * manifest intent-filter is needed.
 */
class HijriDateWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_hijri_date)

            // Load the Flutter-rendered card, if one has been produced.
            val imagePath = widgetData.getString("hijri_date_widget_image", null)
            if (imagePath != null) {
                try {
                    val file = File(imagePath)
                    if (file.exists()) {
                        val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                        if (bitmap != null) {
                            views.setImageViewBitmap(
                                R.id.widget_hijri_date_image,
                                bitmap,
                            )
                        }
                    }
                } catch (e: Exception) {
                    // Corrupt / half-written file — skip; the widget
                    // shows nothing rather than crashing the launcher.
                }
            }

            // Tap -> open the app on the monthly calendar view.
            val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("hijribadr://widget/hijri_date?view=monthly"),
            )
            views.setOnClickPendingIntent(
                R.id.widget_hijri_date_root,
                pendingIntent,
            )

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
