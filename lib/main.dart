import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  bool showOnboarding = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    showOnboarding = !(prefs.getBool('onboarding_complete') ?? false);
  } catch (_) {}

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider()..init(),
      child: HijriCalendarApp(showOnboarding: showOnboarding),
    ),
  );
}

class HijriCalendarApp extends StatelessWidget {
  final bool showOnboarding;
  const HijriCalendarApp({super.key, required this.showOnboarding});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isRtl = provider.locale == 'ar';
    return MaterialApp(
      title: 'تقويم الهجري',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: provider.themeMode,
      locale: Locale(provider.locale),
      supportedLocales: const [
        Locale('ar'), Locale('fr'), Locale('en'), Locale('es'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: showOnboarding ? const OnboardingScreen() : const HomeScreen(),
    );
  }
}
