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
 * bitmap) so every day can carry its own per-day tap intent. Runs in
 * the launcher's process with no Flutter engine; gets all of its data
 * from a JSON payload the app side
 * (WidgetSyncService -> MiniCalendarData) publishes under the
 * "mini_calendar_data" key.
 *
 * Visual model
 * ============
 * The cell rendering mirrors the in-app `_DayCell`
 * (lib/screens/calendar_screen.dart) — same background priority
 * (today > selected > ayyam-al-bid > ramadan), same Friday rule
 * (accent text when not otherwise overridden), same dot behaviour
 * (up to 3, each painted in the event's actual colour).
 *
 * The per-cell highlight is a single white rounded-rect ImageView
 * (`mc_cell_hl`) tinted at runtime via setColorFilter, so it follows
 * the user's chosen AccentBus swatch without baking a drawable per
 * palette. Same trick for the dots (`mc_dot_solid`).
 *
 * Crash-safety contract — onUpdate MUST NEVER throw:
 *   * Every external call is wrapped in try/catch.
 *   * A missing, malformed, or partial payload falls back to the
 *     empty default layout — never an exception.
 *   * Failure to build a single cell's click intent is logged and
 *     skipped; the rest of the grid still renders.
 *   * A top-level Throwable catch is the last-resort net.
 *
 * RemoteViews compatibility notes:
 *   * Only @RemoteView-annotated classes are inflated (LinearLayout,
 *     FrameLayout, TextView, ImageView), so the layout passes the
 *     RemoteViews INFLATER_FILTER check on Android 12+.
 *   * Layout direction is set statically in XML
 *     (android:layoutDirection="locale") — View.setLayoutDirection
 *     is not @RemotableViewMethod.
 *   * The highlight + dot tints use ImageView.setColorFilter, which
 *     IS @RemotableViewMethod.
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

        /** Fallback accent-pale companion (matches AppColors.greenPale tone). */
        private const val FALLBACK_ACCENT_PALE: Int = 0xFFE5F0E9.toInt()

        /** Fallback gold-pale for Ramadan tinting (matches AppColors.goldPale). */
        private const val FALLBACK_GOLD_PALE: Int = 0xFFFDF5E8.toInt()
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
            Log.e(TAG, "onUpdate failed at top level (suppressed)", t)
        }
    }

    private fun renderGrid(context: Context, views: RemoteViews, data: JSONObject) {
        val pkg = context.packageName
        fun id(name: String): Int = context.resources.getIdentifier(name, "id", pkg)

        val isDark = data.optBoolean("isDark", false)
        val accent = parseColor(data.optString("accent"), FALLBACK_ACCENT)
        val accentPale = parseColor(data.optString("accentPale"), FALLBACK_ACCENT_PALE)
        val goldPale = parseColor(data.optString("goldPale"), FALLBACK_GOLD_PALE)
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
        val textOnAccent = 0xFFFFFFFF.toInt()
        // When today is filled with accent, dots use translucent white
        // (mirrors `_DayCell`'s `Colors.white70` for today).
        val dotOnAccent = 0xB3FFFFFF.toInt()

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
        // the app's monthly grid header.
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
            val hlId = id("mc_hl_$i")
            val numId = id("mc_num_$i")
            val dot1Id = id("mc_dot1_$i")
            val dot2Id = id("mc_dot2_$i")
            val dot3Id = id("mc_dot3_$i")
            if (cellId == 0 || hlId == 0 || numId == 0 ||
                dot1Id == 0 || dot2Id == 0 || dot3Id == 0
            ) continue
            val dotIds = intArrayOf(dot1Id, dot2Id, dot3Id)

            val cell = cells?.optJSONObject(i)
            val d = cell?.optInt("d", 0) ?: 0
            if (d < 1) {
                // Blank padding cell — clear text, highlight, every dot, tap.
                views.setTextViewText(numId, "")
                views.setViewVisibility(hlId, View.GONE)
                for (dotId in dotIds) views.setViewVisibility(dotId, View.GONE)
                views.setOnClickPendingIntent(cellId, null)
                continue
            }

            views.setTextViewText(numId, d.toString())

            // Background state (mirrors _DayCell priority): today >
            // selected > ayyam > ramadan. The highlight ImageView is
            // a white rounded-rect tinted to the right palette colour.
            val bg = cell?.optString("bg", "") ?: ""
            val isFri = cell?.optBoolean("fri", false) ?: false
            val isToday = bg == "today"

            when (bg) {
                "today" -> {
                    views.setViewVisibility(hlId, View.VISIBLE)
                    views.setInt(hlId, "setColorFilter", accent)
                    views.setTextColor(numId, textOnAccent)
                }
                "selected", "ayyam" -> {
                    views.setViewVisibility(hlId, View.VISIBLE)
                    views.setInt(hlId, "setColorFilter", accentPale)
                    views.setTextColor(numId, accent)
                }
                "ramadan" -> {
                    views.setViewVisibility(hlId, View.VISIBLE)
                    views.setInt(hlId, "setColorFilter", goldPale)
                    // Ramadan still respects the Friday accent text rule.
                    views.setTextColor(numId, if (isFri) accent else textMain)
                }
                else -> {
                    views.setViewVisibility(hlId, View.GONE)
                    views.setTextColor(numId, if (isFri) accent else textMain)
                }
            }

            // Up to 3 event dots — tinted to the event's actual colour
            // via setColorFilter on a shared white circle drawable.
            val dots = cell?.optJSONArray("dots")
            val dotCount = dots?.length() ?: 0
            for (k in 0..2) {
                val dotId = dotIds[k]
                if (k < dotCount) {
                    views.setViewVisibility(dotId, View.VISIBLE)
                    val raw = parseColor(dots!!.optString(k), accent)
                    val tint = if (isToday) dotOnAccent else raw
                    views.setInt(dotId, "setColorFilter", tint)
                } else {
                    views.setViewVisibility(dotId, View.GONE)
                }
            }

            // Per-day tap — opens the app on this exact Hijri date.
            // Each cell's URI differs, so the PendingIntents stay
            // distinct even though HomeWidgetLaunchIntent uses
            // requestCode 0 (the data URI is part of
            // Intent.filterEquals).
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

    /** Parses a "#AARRGGBB" string, falling back to the supplied default. */
    private fun parseColor(value: String?, fallback: Int): Int {
        if (value.isNullOrEmpty()) return fallback
        return try {
            Color.parseColor(value)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Bad colour '$value' — using fallback", e)
            fallback
        }
    }
}
