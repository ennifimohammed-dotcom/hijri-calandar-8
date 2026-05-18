import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/widget_sync_service.dart';
import '../theme.dart';
import 'add_event_screen.dart';
import 'calendar_screen.dart';
import 'event_bank_screen.dart';
import 'settings_screen.dart';
import 'converter_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  /// The widget-driven `AddEventScreen` route currently on the
  /// navigator, if any. Tracked so a second widget double-tap
  /// REPLACES the previous New Event screen instead of stacking
  /// another modal on top — matches the "only one Create Event
  /// screen may exist at a time" UX contract.
  Route<dynamic>? _activeAddEventRoute;

  @override
  void initState() {
    super.initState();
    // A home-screen-widget tap asks for the monthly view. The view
    // mode itself is switched on the provider by WidgetSyncService;
    // here we only make sure the bottom nav is on the Calendar tab.
    WidgetSyncService.instance.openMonthlyTick.addListener(_onOpenMonthly);
    // A Mini Calendar day cell DOUBLE-TAP asks for the New Event
    // screen prefilled with that day. WidgetSyncService detects the
    // double tap from the URI stream and exposes the prefilled
    // start [DateTime] via this notifier — we just push the route.
    WidgetSyncService.instance.openAddEventForDate
        .addListener(_onOpenAddEventForDate);
    // Cold-start catch-up: when the user double-taps a widget cell
    // while the app is fully closed, the launch URI is processed by
    // `WidgetSyncService._checkColdLaunch` from the post-frame
    // callback in main.dart, which can complete BEFORE HomeScreen
    // mounts. The listener above only catches FUTURE changes, so
    // kick the handler once for any value that was set before we
    // started listening. The handler is null-safe — does nothing
    // if the notifier is already null.
    if (WidgetSyncService.instance.openAddEventForDate.value != null) {
      _onOpenAddEventForDate();
    }
  }

  @override
  void dispose() {
    WidgetSyncService.instance.openMonthlyTick.removeListener(_onOpenMonthly);
    WidgetSyncService.instance.openAddEventForDate
        .removeListener(_onOpenAddEventForDate);
    super.dispose();
  }

  void _onOpenMonthly() {
    if (mounted && _currentIndex != 0) {
      setState(() => _currentIndex = 0);
    }
  }

  void _onOpenAddEventForDate() {
    final dt = WidgetSyncService.instance.openAddEventForDate.value;
    // Skip the re-fire that happens when we reset to null below.
    if (dt == null) return;
    // Consume immediately so the listener doesn't re-trigger if any
    // unrelated setState bounces through the build.
    WidgetSyncService.instance.openAddEventForDate.value = null;
    if (!mounted) return;
    // Push AFTER the current frame so we don't navigate during a
    // build phase that the notifier change might have landed in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);

      // De-stack: if a previous widget-driven AddEventScreen is
      // still on the navigator, drop it before pushing the
      // replacement — so the user can never end up with multiple
      // New Event screens piled on top of each other from
      // repeated widget double-taps.
      final previous = _activeAddEventRoute;
      if (previous != null) {
        try {
          navigator.removeRoute(previous);
        } catch (_) {
          // Route was already removed (e.g. the user popped it
          // manually between the cleanup callback queuing and now).
          // Safe to ignore — _activeAddEventRoute is cleared below.
        }
        _activeAddEventRoute = null;
      }

      final route = MaterialPageRoute<void>(
        builder: (_) => AddEventScreen(initialStart: dt),
      );
      _activeAddEventRoute = route;
      // Clear our reference once the route is popped (back press,
      // Save, Cancel, etc.) so the next widget double-tap doesn't
      // try to remove a stale route.
      route.popped.whenComplete(() {
        if (mounted && identical(_activeAddEventRoute, route)) {
          _activeAddEventRoute = null;
        }
      });
      navigator.push(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final isDark = p.themeMode == ThemeMode.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.bg,
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          CalendarScreen(),
          EventBankScreen(),
          ConverterScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(p, isDark),
      // FAB removed — the inline "+" button on the monthly view's
      // events header now opens the new-event screen.
    );
  }

  BottomNavigationBar _buildBottomNav(AppProvider p, bool isDark) {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (i) => setState(() => _currentIndex = i),
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      selectedItemColor: AppColors.green,
      unselectedItemColor: isDark ? AppColors.darkText3 : AppColors.text3,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: appFont(
          fontSize: 10, fontWeight: FontWeight.w700),
      unselectedLabelStyle: appFont(fontSize: 10),
      elevation: 8,
      items: [
        BottomNavigationBarItem(
            icon: const Icon(Icons.calendar_month_rounded),
            label: p.label('calendar')),
        BottomNavigationBarItem(
            icon: const Icon(Icons.mosque_rounded),
            label: p.label('events')),
        BottomNavigationBarItem(
            icon: const Icon(Icons.swap_horiz_rounded),
            label: p.locale == 'ar' ? 'محوّل'
                : p.locale == 'fr' ? 'Convertir' : 'Convert'),
        BottomNavigationBarItem(
            icon: const Icon(Icons.settings_rounded),
            label: p.label('settings')),
      ],
    );
  }

}
