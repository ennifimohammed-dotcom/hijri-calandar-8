import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/widget_sync_service.dart';
import '../theme.dart';
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

  @override
  void initState() {
    super.initState();
    // A home-screen-widget tap asks for the monthly view. The view
    // mode itself is switched on the provider by WidgetSyncService;
    // here we only make sure the bottom nav is on the Calendar tab.
    WidgetSyncService.instance.openMonthlyTick.addListener(_onOpenMonthly);
  }

  @override
  void dispose() {
    WidgetSyncService.instance.openMonthlyTick.removeListener(_onOpenMonthly);
    super.dispose();
  }

  void _onOpenMonthly() {
    if (mounted && _currentIndex != 0) {
      setState(() => _currentIndex = 0);
    }
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
