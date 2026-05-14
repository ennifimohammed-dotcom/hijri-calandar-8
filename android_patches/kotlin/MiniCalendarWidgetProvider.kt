package com.hijricalendar.hijri_calendar

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * Home-screen widget: "Mini Calendar".
 *
 * Unlike the Hijri Date / Islamic Day widgets (Flutter widgets
 * rendered to PNGs), this one is rendered NATIVELY — a real 6x7 grid
 * of TextView cells — so every day can carry its own tap target that
 * opens the app on that exact date.
 *
 * It runs in the launcher's process with no Flutter engine, so it
 * gets all of its data from a JSON payload the app side
 * (WidgetSyncService -> MiniCalendarData) publishes under the
 * "mini_calendar_data" key. onUpdate parses that JSON and fills the
 * generated layout (widget_mini_calendar.xml) by id.
 *
 * Robust by construction: a missing or malformed payload simply
 * leaves the default (empty) layout — it never throws out of
 * onUpdate, so it can't crash the launcher.
 */
class MiniCalendarWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val json = widgetData.getString("mini_calendar_data", null)
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_mini_calendar)
            try {
                if (json != null) renderGrid(context, views, JSONObject(json))
            } catch (e: Exception) {
                // Malformed / missing data — leave the default layout.
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun renderGrid(context: Context, views: RemoteViews, data: JSONObject) {
        val pkg = context.packageName
        fun id(name: String): Int = context.resources.getIdentifier(name, "id", pkg)

        val isDark = data.optBoolean("isDark", false)
        val isRtl = data.optBoolean("isRtl", false)
        val accent = parseColor(data.optString("accent"))
        val hy = data.optInt("hy")
        val hm = data.optInt("hm")
        val visibleRows = data.optInt("visibleRows", 6)

        // Theme colours — mirror lib/theme.dart (AppColors).
        val textMain = if (isDark) 0xFFF0EBE0.toInt() else 0xFF1A1A1A.toInt()
        val textMuted = if (isDark) 0xFF6A7585.toInt() else 0xFF999999.toInt()
        // ~25% accent wash behind today's cell.
        val todayWash = (accent and 0x00FFFFFF) or 0x40000000

        // Themed rounded background + app-locale layout direction
        // (the widget process can't see the app's chosen locale, so
        // the direction is driven by the payload, not the device).
        views.setInt(
            R.id.widget_mini_calendar_root, "setBackgroundResource",
            if (isDark) R.drawable.mc_bg_dark else R.drawable.mc_bg_light,
        )
        views.setInt(
            R.id.widget_mini_calendar_root, "setLayoutDirection",
            if (isRtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR,
        )

        // Title — Hijri month/year (primary) + Gregorian (secondary).
        views.setTextViewText(R.id.mc_title, data.optString("title"))
        views.setTextColor(R.id.mc_title, textMain)
        views.setTextViewText(R.id.mc_greg_title, data.optString("gregTitle"))
        views.setTextColor(R.id.mc_greg_title, textMuted)

        // Weekday header — Friday (index 4) gets the accent, exactly
        // like the app's monthly grid.
        val weekdays = data.optJSONArray("weekdays")
        for (i in 0..6) {
            val wdId = id("mc_wd_$i")
            if (wdId == 0) continue
            views.setTextViewText(wdId, weekdays?.optString(i) ?: "")
            views.setTextColor(wdId, if (i == 4) accent else textMuted)
        }

        // Day cells.
        val cells = data.optJSONArray("cells")
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
                // Islamic takes visual priority when a day has both.
                views.setInt(
                    dotId, "setBackgroundResource",
                    if (isl) R.drawable.mc_dot_islamic else R.drawable.mc_dot_event,
                )
            } else {
                views.setViewVisibility(dotId, View.GONE)
            }

            // Per-day tap → opens the app on this exact Hijri date.
            // Each cell's URI differs, so the PendingIntents stay
            // distinct even though home_widget uses requestCode 0
            // (the data URI is part of Intent.filterEquals).
            val uri = Uri.parse("hijribadr://widget/mini_calendar?hy=$hy&hm=$hm&hd=$d")
            views.setOnClickPendingIntent(
                cellId,
                HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, uri,
                ),
            )
        }

        // Hide the 6th row when the month doesn't reach into it.
        views.setViewVisibility(
            R.id.mc_row_5,
            if (visibleRows >= 6) View.VISIBLE else View.GONE,
        )
    }

    /** Parses a "#AARRGGBB" string, falling back to the royal-green accent. */
    private fun parseColor(value: String?): Int {
        if (value.isNullOrEmpty()) return 0xFF2D7D5F.toInt()
        return try {
            Color.parseColor(value)
        } catch (e: IllegalArgumentException) {
            0xFF2D7D5F.toInt()
        }
    }
}
