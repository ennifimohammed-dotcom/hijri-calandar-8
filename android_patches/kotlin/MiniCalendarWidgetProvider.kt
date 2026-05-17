package com.hijricalendar.hijri_calendar

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
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
 * Month navigation
 * ================
 * The payload carries a WINDOW of months (today ± windowRadius).
 * The user's currently displayed month is an OFFSET stored in this
 * provider's own SharedPreferences ("mini_calendar_state"). The
 * header has three buttons:
 *
 *   * prev   -> shift offset by -1 (clamped at -windowRadius);
 *   * today  -> reset offset to 0;
 *   * next   -> shift offset by +1 (clamped at +windowRadius).
 *
 * Each button is a custom-action broadcast PendingIntent targeting
 * THIS receiver (explicit Intent component). onReceive intercepts
 * the action, updates the offset, and re-renders via onUpdate. The
 * cached JSON window already contains all the months in range, so
 * month switching is INSTANT — no Flutter callback, no app launch.
 *
 * The offset persists across launcher redraws (it lives in
 * SharedPreferences), and survives data refreshes (which only
 * rewrite the JSON, not our local state).
 *
 * Visual model
 * ============
 * Per-cell rendering mirrors the in-app `_DayCell`
 * (lib/screens/calendar_screen.dart) — same background priority
 * (today > selected > ayyam-al-bid > ramadan), same Friday rule,
 * same dot behaviour (up to 3 dots tinted to each event's colour),
 * same dual-number layout (Hijri primary + Gregorian secondary).
 *
 * Crash-safety contract — onUpdate / onReceive MUST NEVER throw:
 *   * Every external call is wrapped in try/catch.
 *   * A missing, malformed, or partial payload falls back to the
 *     empty default layout — never an exception.
 *   * A top-level Throwable catch is the last-resort net.
 *   * Unknown actions are forwarded to super.onReceive so
 *     APPWIDGET_UPDATE / APPWIDGET_DELETED / ENABLED / DISABLED
 *     still dispatch correctly.
 *
 * RemoteViews compatibility:
 *   * Only @RemoteView-annotated classes are inflated (LinearLayout,
 *     FrameLayout, TextView, ImageView), so the layout passes the
 *     RemoteViews INFLATER_FILTER check on Android 12+.
 *   * Layout direction is set statically in XML
 *     (android:layoutDirection="locale") — View.setLayoutDirection
 *     is not @RemotableViewMethod. The nav chevrons carry
 *     android:autoMirrored="true" so they flip in RTL with no extra
 *     code.
 *   * Tints use ImageView.setColorFilter (IS @RemotableViewMethod).
 *
 * Logcat tag: "MiniCalWidget". To watch on a device:
 *   adb logcat -s MiniCalWidget
 */
class MiniCalendarWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val TAG = "MiniCalWidget"
        private const val DATA_KEY = "mini_calendar_data"

        /** Local SharedPreferences (separate from home_widget's store)
         *  for the user's current view offset. Kept separate so the
         *  Dart side never accidentally clobbers it during data
         *  refreshes. */
        private const val LOCAL_PREFS = "mini_calendar_state"
        private const val OFFSET_KEY = "view_offset"

        /** In-widget navigation actions. Namespaced under the app's
         *  package to avoid collisions; PendingIntents are explicit
         *  (Intent with component set) so other apps can't trigger
         *  them even though the receiver is exported. */
        const val ACTION_PREV: String =
            "com.hijricalendar.hijri_calendar.MINI_CAL_PREV"
        const val ACTION_NEXT: String =
            "com.hijricalendar.hijri_calendar.MINI_CAL_NEXT"
        const val ACTION_TODAY: String =
            "com.hijricalendar.hijri_calendar.MINI_CAL_TODAY"

        /** Fallback accent (royal green) for missing/invalid payloads. */
        private const val FALLBACK_ACCENT: Int = 0xFF2D7D5F.toInt()
        private const val FALLBACK_ACCENT_PALE: Int = 0xFFE5F0E9.toInt()
        private const val FALLBACK_GOLD_PALE: Int = 0xFFFDF5E8.toInt()
    }

    // ── onReceive — intercept nav actions, forward the rest ─────

    override fun onReceive(context: Context, intent: Intent) {
        try {
            when (intent.action) {
                ACTION_PREV -> shiftOffset(context, -1)
                ACTION_NEXT -> shiftOffset(context, +1)
                ACTION_TODAY -> setOffset(context, 0)
                else -> super.onReceive(context, intent)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "onReceive failed (suppressed)", t)
            // Best-effort: let the default dispatcher run so an
            // unrelated APPWIDGET_UPDATE we crashed on still tries
            // to do its job.
            try {
                super.onReceive(context, intent)
            } catch (_: Throwable) {
                // Truly nothing we can do; never let it escape.
            }
        }
    }

    // ── View-offset state (local SharedPreferences) ─────────────

    private fun localPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(LOCAL_PREFS, Context.MODE_PRIVATE)

    private fun readOffset(context: Context): Int =
        try {
            localPrefs(context).getInt(OFFSET_KEY, 0)
        } catch (e: Exception) {
            Log.w(TAG, "readOffset failed; using 0", e)
            0
        }

    private fun writeOffset(context: Context, value: Int) {
        try {
            localPrefs(context).edit().putInt(OFFSET_KEY, value).apply()
        } catch (e: Exception) {
            Log.w(TAG, "writeOffset($value) failed", e)
        }
    }

    private fun shiftOffset(context: Context, delta: Int) {
        val current = readOffset(context)
        val radius = readWindowRadius(context)
        val target = current + delta
        if (target in -radius..radius) {
            // Within the pre-baked window — instant native nav.
            writeOffset(context, target)
            Log.d(TAG, "Nav: offset $current -> $target (in-window)")
            triggerSelfUpdate(context)
        } else {
            // Out of the cached window — there is no pre-built JSON
            // for this month, so we can't render it natively. Open
            // the in-app calendar at the target Hijri month instead
            // — the app's calendar is truly infinite (PageView with
            // unbounded indices), so navigation continues from there.
            // The widget's own offset is not advanced; the next sync
            // (triggered when AppProvider notifies after the launch)
            // will re-centre the cached window.
            Log.d(TAG, "Nav: offset $current beyond window ±$radius — launching app")
            launchAppAtOffset(context, target)
        }
    }

    /** Hijri month arithmetic with 12-month wrap. Pure integer ops,
     *  no Hijri kernel call — same wrap logic as `_buildMonth` in
     *  lib/widgets_home/mini_calendar_data.dart and as
     *  `_MonthlyView.hijriForIndex` in calendar_screen.dart. */
    private fun addMonths(hy: Int, hm: Int, delta: Int): Pair<Int, Int> {
        var y = hy
        var m = hm + delta
        while (m < 1) { m += 12; y -= 1 }
        while (m > 12) { m -= 12; y += 1 }
        return Pair(y, m)
    }

    /** Out-of-window navigation: starts the app on the target Hijri
     *  month so the user can keep navigating in the in-app calendar.
     *  Builds the same Intent that `HomeWidgetLaunchIntent.getActivity`
     *  would, but fires it directly (we're already in a user-initiated
     *  widget broadcast, so the background-activity-start restrictions
     *  on Android 10+ don't apply here). */
    private fun launchAppAtOffset(context: Context, targetOffset: Int) {
        try {
            val prefs = HomeWidgetPlugin.getData(context)
            val json = prefs.getString(DATA_KEY, null) ?: return
            val data = JSONObject(json)
            val todayHy = data.optInt("todayHy", 0)
            val todayHm = data.optInt("todayHm", 0)
            if (todayHy == 0 || todayHm == 0) {
                Log.w(TAG, "launchAppAtOffset: payload missing today coords")
                return
            }
            val (hy, hm) = addMonths(todayHy, todayHm, targetOffset)
            // Month-only URI (no `hd`). The Dart side's _onWidgetUri
            // recognises this as "navigate to month, don't select a
            // day" — same flow the in-app `_MonthlyView` uses.
            val uri = Uri.parse("hijribadr://widget/mini_calendar?hy=$hy&hm=$hm")
            val intent = Intent(context, MainActivity::class.java).apply {
                action = "es.antonborri.home_widget.action.LAUNCH"
                data = uri
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            Log.d(TAG, "launchAppAtOffset($targetOffset) -> hy=$hy hm=$hm")
        } catch (e: Exception) {
            Log.e(TAG, "launchAppAtOffset failed", e)
        }
    }

    private fun setOffset(context: Context, value: Int) {
        if (readOffset(context) == value) {
            Log.d(TAG, "setOffset($value) no-op")
            return
        }
        writeOffset(context, value)
        Log.d(TAG, "Nav reset to $value")
        triggerSelfUpdate(context)
    }

    /** Reads the window radius from the cached JSON so the native
     *  side stays in lock-step with whatever the Dart side decided
     *  (no hard-coded magic number to keep in sync). */
    private fun readWindowRadius(context: Context): Int {
        return try {
            val prefs = HomeWidgetPlugin.getData(context)
            val json = prefs.getString(DATA_KEY, null) ?: return 0
            JSONObject(json).optInt("windowRadius", 0)
        } catch (e: Exception) {
            Log.w(TAG, "readWindowRadius failed; clamping to 0", e)
            0
        }
    }

    /** Re-renders all live instances of this widget without going
     *  through Dart — used after a nav button changes the offset.
     *  The cached JSON window already has all the months, so this
     *  is purely a local RemoteViews refresh. */
    private fun triggerSelfUpdate(context: Context) {
        try {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, MiniCalendarWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            val prefs = HomeWidgetPlugin.getData(context)
            onUpdate(context, mgr, ids, prefs)
        } catch (e: Exception) {
            Log.e(TAG, "triggerSelfUpdate failed", e)
        }
    }

    // ── onUpdate — same crash-safe shell as before ──────────────

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        try {
            val json = try {
                widgetData.getString(DATA_KEY, null)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to read widget SharedPreferences", e)
                null
            }
            // Parse the payload ONCE up front so we can decide which
            // layout to inflate (LTR vs forced-RTL) AND pass the
            // parsed object straight to renderGrid — no double-parse.
            val parsed: JSONObject? = if (json != null) {
                try {
                    JSONObject(json)
                } catch (e: Exception) {
                    Log.w(TAG, "JSON parse failed; using empty layout", e)
                    null
                }
            } else null
            val isRtl = parsed?.optBoolean("isRtl", false) ?: false
            val layoutId = if (isRtl) {
                R.layout.widget_mini_calendar_rtl
            } else {
                R.layout.widget_mini_calendar
            }
            Log.d(
                TAG,
                "onUpdate: widgets=${appWidgetIds.size}, hasData=${parsed != null}, isRtl=$isRtl",
            )

            for (widgetId in appWidgetIds) {
                val views = try {
                    RemoteViews(context.packageName, layoutId)
                } catch (e: Exception) {
                    Log.e(TAG, "RemoteViews construction failed for $widgetId", e)
                    continue
                }

                if (parsed != null) {
                    try {
                        renderGrid(context, views, parsed)
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

    // ── Rendering ───────────────────────────────────────────────

    private fun renderGrid(context: Context, views: RemoteViews, data: JSONObject) {
        val pkg = context.packageName
        fun id(name: String): Int = context.resources.getIdentifier(name, "id", pkg)

        val isDark = data.optBoolean("isDark", false)
        val accent = parseColor(data.optString("accent"), FALLBACK_ACCENT)
        val accentPale = parseColor(data.optString("accentPale"), FALLBACK_ACCENT_PALE)
        val goldPale = parseColor(data.optString("goldPale"), FALLBACK_GOLD_PALE)
        val windowRadius = data.optInt("windowRadius", 0)

        // Theme colours — mirror lib/theme.dart (AppColors).
        val textMain = if (isDark) 0xFFF0EBE0.toInt() else 0xFF1A1A1A.toInt()
        val textMuted = if (isDark) 0xFF6A7585.toInt() else 0xFF999999.toInt()
        // Weekday header is INTENTIONALLY one step lighter than the
        // in-app `_buildWeekdayHeader` — the widget header is the
        // subdued companion: regular weight + softer grey.
        val weekdayMuted = if (isDark) 0xFF7B8595.toInt() else 0xFFB0B0B0.toInt()
        val textOnAccent = 0xFFFFFFFF.toInt()
        // Mirrors `_DayCell`'s `Colors.white70` for today.
        val secondaryOnAccent = 0xB3FFFFFF.toInt()

        // Themed rounded background.
        views.setInt(
            R.id.widget_mini_calendar_root, "setBackgroundResource",
            if (isDark) R.drawable.mc_bg_dark else R.drawable.mc_bg_light,
        )

        // Pick the month matching the user's current view offset.
        // Clamp so a stale stored offset can't render an empty widget.
        val rawOffset = readOffset(context)
        val viewOffset = rawOffset.coerceIn(-windowRadius, windowRadius)
        if (viewOffset != rawOffset) {
            // Drift after a window-radius change: snap back into range.
            writeOffset(context, viewOffset)
        }
        val monthData = pickMonth(data, viewOffset) ?: pickMonth(data, 0)
        if (monthData == null) {
            Log.w(TAG, "renderGrid: no month data in payload")
            return
        }
        Log.d(
            TAG,
            "renderGrid: viewOffset=$viewOffset, hy=${monthData.optInt("hy")}, hm=${monthData.optInt("hm")}",
        )

        val hy = monthData.optInt("hy", 0)
        val hm = monthData.optInt("hm", 0)
        val visibleRows = monthData.optInt("visibleRows", 6)

        // Title — Hijri month/year (primary) + Gregorian (secondary).
        views.setTextViewText(R.id.mc_title, monthData.optString("title"))
        views.setTextColor(R.id.mc_title, textMain)
        views.setTextViewText(R.id.mc_greg_title, monthData.optString("gregTitle"))
        views.setTextColor(R.id.mc_greg_title, textMuted)

        // Weekday header — Friday (index 4) gets the accent, like
        // the app's monthly grid header.
        val weekdays = data.optJSONArray("weekdays")
        for (i in 0..6) {
            val wdId = id("mc_wd_$i")
            if (wdId == 0) continue
            views.setTextViewText(wdId, weekdays?.optString(i) ?: "")
            views.setTextColor(wdId, if (i == 4) accent else weekdayMuted)
        }

        // Day cells.
        renderCells(
            context, views, monthData, hy, hm,
            accent, accentPale, goldPale,
            textMain, textOnAccent, secondaryOnAccent, textMuted,
            { name -> id(name) },
        )

        // Hide the 6th row when the month doesn't reach into it.
        views.setViewVisibility(
            R.id.mc_row_5,
            if (visibleRows >= 6) View.VISIBLE else View.GONE,
        )

        // Nav controls. Prev/next stay active-looking at all times —
        // out-of-window taps fall through to launching the app at
        // the target month (see `shiftOffset`), so the widget feels
        // infinite even though the cached JSON window is bounded.
        setupNavButtons(
            context, views,
            currentOffset = viewOffset,
            accent = accent,
            mutedColor = weekdayMuted,
        )
    }

    private fun pickMonth(data: JSONObject, offset: Int): JSONObject? {
        val months = data.optJSONArray("months") ?: return null
        for (k in 0 until months.length()) {
            val m = months.optJSONObject(k) ?: continue
            if (m.optInt("offset", Int.MAX_VALUE) == offset) return m
        }
        return null
    }

    private fun renderCells(
        context: Context,
        views: RemoteViews,
        monthData: JSONObject,
        hy: Int,
        hm: Int,
        accent: Int,
        accentPale: Int,
        goldPale: Int,
        textMain: Int,
        textOnAccent: Int,
        secondaryOnAccent: Int,
        textMuted: Int,
        id: (String) -> Int,
    ) {
        val cells = monthData.optJSONArray("cells")
        var rendered = 0
        for (i in 0..41) {
            val cellId = id("mc_cell_$i")
            val hlId = id("mc_hl_$i")
            val numId = id("mc_num_$i")
            val gregId = id("mc_greg_$i")
            val dot1Id = id("mc_dot1_$i")
            val dot2Id = id("mc_dot2_$i")
            val dot3Id = id("mc_dot3_$i")
            if (cellId == 0 || hlId == 0 || numId == 0 || gregId == 0 ||
                dot1Id == 0 || dot2Id == 0 || dot3Id == 0
            ) continue
            val dotIds = intArrayOf(dot1Id, dot2Id, dot3Id)

            val cell = cells?.optJSONObject(i)
            val d = cell?.optInt("d", 0) ?: 0
            if (d < 1) {
                // Blank padding cell.
                views.setTextViewText(numId, "")
                views.setTextViewText(gregId, "")
                views.setViewVisibility(gregId, View.GONE)
                views.setViewVisibility(hlId, View.GONE)
                for (dotId in dotIds) views.setViewVisibility(dotId, View.GONE)
                views.setOnClickPendingIntent(cellId, null)
                continue
            }

            views.setTextViewText(numId, d.toString())

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
                    views.setTextColor(numId, if (isFri) accent else textMain)
                }
                else -> {
                    views.setViewVisibility(hlId, View.GONE)
                    views.setTextColor(numId, if (isFri) accent else textMain)
                }
            }

            // Gregorian secondary day number.
            val g = cell?.optInt("g", 0) ?: 0
            if (g > 0) {
                views.setTextViewText(gregId, g.toString())
                views.setTextColor(
                    gregId,
                    if (isToday) secondaryOnAccent else textMuted,
                )
                views.setViewVisibility(gregId, View.VISIBLE)
            } else {
                views.setTextViewText(gregId, "")
                views.setViewVisibility(gregId, View.GONE)
            }

            // Up to 3 event dots.
            val dots = cell?.optJSONArray("dots")
            val dotCount = dots?.length() ?: 0
            for (k in 0..2) {
                val dotId = dotIds[k]
                if (k < dotCount) {
                    views.setViewVisibility(dotId, View.VISIBLE)
                    val raw = parseColor(dots!!.optString(k), accent)
                    val tint = if (isToday) secondaryOnAccent else raw
                    views.setInt(dotId, "setColorFilter", tint)
                } else {
                    views.setViewVisibility(dotId, View.GONE)
                }
            }

            // Per-day tap — opens the app on this exact Hijri date.
            try {
                val uri = Uri.parse(
                    "hijribadr://widget/mini_calendar?hy=$hy&hm=$hm&hd=$d",
                )
                val pi = HomeWidgetLaunchIntent.getActivity(
                    context, MainActivity::class.java, uri,
                )
                views.setOnClickPendingIntent(cellId, pi)
            } catch (e: Exception) {
                Log.w(TAG, "Click PendingIntent failed for day $d", e)
            }
            rendered++
        }
        Log.d(TAG, "renderCells: filled $rendered day cells")
    }

    /** Wires the prev / today / next header buttons.
     *
     *  Prev / Next: always active-looking and always clickable. The
     *  broadcast handler (`shiftOffset`) decides whether to navigate
     *  natively (in-window) or to launch the app at the target month
     *  (out-of-window) — so the widget feels truly infinite.
     *
     *  Today: muted when already on offset 0 (no navigation needed),
     *  accent when off it so the eye is drawn back. */
    private fun setupNavButtons(
        context: Context,
        views: RemoteViews,
        currentOffset: Int,
        accent: Int,
        mutedColor: Int,
    ) {
        views.setInt(R.id.mc_btn_prev, "setColorFilter", mutedColor)
        views.setOnClickPendingIntent(
            R.id.mc_btn_prev, navPendingIntent(context, ACTION_PREV))

        views.setInt(R.id.mc_btn_next, "setColorFilter", mutedColor)
        views.setOnClickPendingIntent(
            R.id.mc_btn_next, navPendingIntent(context, ACTION_NEXT))

        if (currentOffset == 0) {
            views.setInt(R.id.mc_btn_today, "setColorFilter", mutedColor)
            views.setOnClickPendingIntent(R.id.mc_btn_today, null)
        } else {
            views.setInt(R.id.mc_btn_today, "setColorFilter", accent)
            views.setOnClickPendingIntent(
                R.id.mc_btn_today,
                navPendingIntent(context, ACTION_TODAY),
            )
        }
    }

    private fun navPendingIntent(context: Context, action: String): PendingIntent {
        // Explicit intent (component set via `Intent(context, class)`)
        // so other apps can't trigger this even though the receiver
        // is exported. requestCode is per-action so the three nav
        // PendingIntents stay distinct.
        val intent = Intent(context, MiniCalendarWidgetProvider::class.java)
            .setAction(action)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, action.hashCode(), intent, flags)
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
