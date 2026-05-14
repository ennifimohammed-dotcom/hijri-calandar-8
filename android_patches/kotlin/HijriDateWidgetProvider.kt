package com.hijricalendar.hijri_calendar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

/**
 * Home-screen widget: "Hijri Date" (Phase 1 of the widget system).
 *
 * The premium card itself is rendered on the Flutter side
 * (WidgetSyncService -> HijriDateWidgetView) to a PNG via
 * `home_widget`'s `renderFlutterWidget`. This provider runs in the
 * launcher's process — no Flutter engine, no app state here — and its
 * only job is to load that PNG into the widget's ImageView.
 *
 * `home_widget` publishes the PNG's absolute path under the
 * "hijri_date_widget_image" key (see WidgetSyncService._imageKey) in
 * the SharedPreferences instance passed to [onUpdate] as [widgetData].
 *
 * Until the first render lands, the layout's drawable background
 * (a royal-green rounded rectangle) is shown, so a freshly-placed
 * widget never looks broken.
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
                    // Corrupt / half-written file — keep the placeholder
                    // background rather than crash the launcher.
                }
            }

            // Tapping the widget opens the app normally. Phase 1 keeps
            // this a plain launch (no deep-link, no change to the app's
            // boot flow); carrying the tapped date is a Phase 2 item.
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_IMMUTABLE or
                        PendingIntent.FLAG_UPDATE_CURRENT,
                )
                views.setOnClickPendingIntent(
                    R.id.widget_hijri_date_root,
                    pendingIntent,
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
