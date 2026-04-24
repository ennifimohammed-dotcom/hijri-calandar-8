import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import 'calendar_screen.dart';
import 'event_bank_screen.dart';
import 'add_event_screen.dart';
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
      floatingActionButton: _currentIndex == 0
          ? _buildFab(context, p) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
      selectedLabelStyle: GoogleFonts.cairo(
          fontSize: 10, fontWeight: FontWeight.w700),
      unselectedLabelStyle: GoogleFonts.cairo(fontSize: 10),
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

  Widget _buildFab(BuildContext context, AppProvider p) {
    return FloatingActionButton.extended(
      onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AddEventScreen())),
      backgroundColor: AppColors.green,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
      label: Text(p.label('add_event'),
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 13)),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    );
  }
}
