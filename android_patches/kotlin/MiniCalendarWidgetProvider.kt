package com.hijricalendar.hijri_calendar

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * Home-screen widget: "Mini Calendar".
 *
 * Renders a real 6x7 grid of tappable cells (rather than a Flutter
 * bitmap) so every day cell can carry its own per-day tap intent.
 * Runs in the launcher's process with no Flutter engine; gets all of
 * its data from a JSON payload the app side
 * (WidgetSyncService -> MiniCalendarData) publishes under the
 * "mini_calendar_data" key.
 *
 * Crash-safety contract — onUpdate MUST NEVER throw:
 *   * Every external call is wrapped in try/catch.
 *   * A missing, malformed, or partial payload falls back to the
 *     empty default layout — never an exception.
 *   * Failure to build a single cell's click intent is logged and
 *     skipped; the rest of the grid still renders.
 *   * A top-level Throwable catch is the last-resort net.
 *
 * If a crash escaped onUpdate the launcher would refuse to host the
 * widget ("Can't add widget") so this is structural, not paranoia.
 *
 * RemoteViews compatibility notes (the bugs this version fixes):
 *   * The dot is an <ImageView>, NOT a plain <View>. RemoteViews'
 *     INFLATER_FILTER on Android 12+ rejects classes without
 *     @RemoteView; android.view.View doesn't have it and was
 *     causing the layout to fail to inflate on real devices.
 *   * Layout direction is set statically in XML
 *     (android:layoutDirection="locale") because
 *     View.setLayoutDirection is NOT @RemotableViewMethod —
 *     calling it through RemoteViews.setInt would throw
 *     ActionException as soon as data was applied.
 *   * Dot src is swapped with setImageViewResource (direct
 *     RemoteViews method backed by @RemotableViewMethod
 *     ImageView.setImageResource).
 *
 * Logcat tag: "MiniCalWidget". To watch on a device:
 *   adb logcat -s MiniCalWidget
 */
class MiniCalendarWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val TAG = "MiniCalWidget"
        private const val DATA_KEY = "mini_calendar_data"

        /** Fallback accent (royal green) for missing/invalid payloads. */
        private const val FALLBACK_ACCENT: Int = 0xFF2D7D5F.toInt()
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        // Top-level net: under no circumstances let an exception
        // escape this method — the launcher would mark the widget
        // invalid and refuse to host it on subsequent adds.
        try {
            val json = try {
                widgetData.getString(DATA_KEY, null)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to read widget SharedPreferences", e)
                null
            }
            Log.d(
                TAG,
                "onUpdate: widgets=${appWidgetIds.size}, hasData=${json != null}",
            )

            for (widgetId in appWidgetIds) {
                val views = try {
                    RemoteViews(context.packageName, R.layout.widget_mini_calendar)
                } catch (e: Exception) {
                    Log.e(TAG, "RemoteViews construction failed for $widgetId", e)
                    continue
                }

                if (json != null) {
                    try {
                        val data = JSONObject(json)
                        renderGrid(context, views, data)
                        Log.d(TAG, "Rendered grid for widget $widgetId")
                    } catch (e: Exception) {
                        // Bad JSON / partial render — fall through to push the
                        // default (empty) layout rather than crash.
                        Log.w(
                            TAG,
                            "Render failed for widget $widgetId; pushing empty layout",
                            e,
                        )
                    }
                } else {
                    Log.d(TAG, "No data yet for widget $widgetId; empty layout")
                }

                try {
                    appWidgetManager.updateAppWidget(widgetId, views)
                    Log.d(TAG, "updateAppWidget OK for $widgetId")
                } catch (e: Exception) {
                    Log.e(TAG, "updateAppWidget failed for $widgetId", e)
                }
            }
        } catch (t: Throwable) {
            // Last-resort net — must never propagate out of onUpdate.
            Log.e(TAG, "onUpdate failed at top level (suppressed)", t)
        }
    }

    private fun renderGrid(context: Context, views: RemoteViews, data: JSONObject) {
        val pkg = context.packageName
        fun id(name: String): Int = context.resources.getIdentifier(name, "id", pkg)

        val isDark = data.optBoolean("isDark", false)
        val accent = parseColor(data.optString("accent"))
        val hy = data.optInt("hy", 0)
        val hm = data.optInt("hm", 0)
        val visibleRows = data.optInt("visibleRows", 6)

        Log.d(
            TAG,
            "renderGrid: isDark=$isDark, hy=$hy, hm=$hm, visibleRows=$visibleRows",
        )

        // Theme colours — mirror lib/theme.dart (AppColors).
        val textMain = if (isDark) 0xFFF0EBE0.toInt() else 0xFF1A1A1A.toInt()
        val textMuted = if (isDark) 0xFF6A7585.toInt() else 0xFF999999.toInt()
        // ~25% accent wash behind today's cell.
        val todayWash = (accent and 0x00FFFFFF) or 0x40000000

        // Themed rounded background. (Layout direction is set
        // STATICALLY in the XML via android:layoutDirection="locale"
        // — View.setLayoutDirection is not @RemotableViewMethod.)
        views.setInt(
            R.id.widget_mini_calendar_root, "setBackgroundResource",
            if (isDark) R.drawable.mc_bg_dark else R.drawable.mc_bg_light,
        )

        // Title — Hijri month/year (primary) + Gregorian (secondary).
        views.setTextViewText(R.id.mc_title, data.optString("title"))
        views.setTextColor(R.id.mc_title, textMain)
        views.setTextViewText(R.id.mc_greg_title, data.optString("gregTitle"))
        views.setTextColor(R.id.mc_greg_title, textMuted)

        // Weekday header — Friday (index 4) gets the accent, like
        // the app's monthly grid.
        val weekdays = data.optJSONArray("weekdays")
        for (i in 0..6) {
            val wdId = id("mc_wd_$i")
            if (wdId == 0) continue
            views.setTextViewText(wdId, weekdays?.optString(i) ?: "")
            views.setTextColor(wdId, if (i == 4) accent else textMuted)
        }

        // Day cells.
        val cells = data.optJSONArray("cells")
        var rendered = 0
        for (i in 0..41) {
            val cellId = id("mc_cell_$i")
            val numId = id("mc_num_$i")
            val dotId = id("mc_dot_$i")
            if (cellId == 0 || numId == 0 || dotId == 0) continue

            val cell = cells?.optJSONObject(i)
            val d = cell?.optInt("d", 0) ?: 0
            if (d < 1) {
                // Blank padding cell — clear text, dot, highlight, tap.
                views.setTextViewText(numId, "")
                views.setViewVisibility(dotId, View.GONE)
                views.setInt(cellId, "setBackgroundColor", Color.TRANSPARENT)
                views.setOnClickPendingIntent(cellId, null)
                continue
            }

            views.setTextViewText(numId, d.toString())
            val today = cell?.optBoolean("today", false) ?: false
            views.setTextColor(numId, if (today) accent else textMain)
            views.setInt(
                cellId, "setBackgroundColor",
                if (today) todayWash else Color.TRANSPARENT,
            )

            val isl = cell?.optBoolean("isl", false) ?: false
            val evt = cell?.optBoolean("evt", false) ?: false
            if (isl || evt) {
                views.setViewVisibility(dotId, View.VISIBLE)
                // Swap the ImageView's `src` (NOT background). Islamic
                // takes visual priority when a day has both.
                views.setImageViewResource(
                    dotId,
                    if (isl) R.drawable.mc_dot_islamic else R.drawable.mc_dot_event,
                )
            } else {
                views.setViewVisibility(dotId, View.GONE)
            }

            // Per-day tap. Each cell's URI differs, so the
            // PendingIntents stay distinct even though
            // HomeWidgetLaunchIntent uses requestCode 0 (the data
            // URI is part of Intent.filterEquals).
            try {
                val uri = Uri.parse("hijribadr://widget/mini_calendar?hy=$hy&hm=$hm&hd=$d")
                val pi = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, uri,
                )
                views.setOnClickPendingIntent(cellId, pi)
            } catch (e: Exception) {
                Log.w(TAG, "Click PendingIntent failed for day $d", e)
            }
            rendered++
        }
        Log.d(TAG, "renderGrid: filled $rendered day cells")

        // Hide the 6th row when the month doesn't reach into it.
        views.setViewVisibility(
            R.id.mc_row_5,
            if (visibleRows >= 6) View.VISIBLE else View.GONE,
        )
    }

    /** Parses a "#AARRGGBB" string, falling back to the royal-green accent. */
    private fun parseColor(value: String?): Int {
        if (value.isNullOrEmpty()) return FALLBACK_ACCENT
        return try {
            Color.parseColor(value)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Bad accent colour '$value' — using fallback", e)
            FALLBACK_ACCENT
        }
    }
}
