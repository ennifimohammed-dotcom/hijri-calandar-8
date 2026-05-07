import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/notification_service.dart';
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

class HijriCalendarApp extends StatefulWidget {
  final bool showOnboarding;
  const HijriCalendarApp({super.key, required this.showOnboarding});

  @override
  State<HijriCalendarApp> createState() => _HijriCalendarAppState();
}

class _HijriCalendarAppState extends State<HijriCalendarApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh the rolling 30-day window whenever the app
      // returns to foreground (covers post-midnight transitions).
      NotificationService().scheduleMidnightReschedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isRtl = provider.locale == 'ar';
    // Push the user-picked font into AppTheme before its theme
    // getters re-evaluate, so MaterialApp.theme / darkTheme rebuild
    // with the right Google-Fonts text styles.
    AppTheme.setActiveFontFamily(provider.fontFamily);
    return MaterialApp(
      title: 'بدر | badr',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: provider.themeMode,
      locale: Locale(provider.locale),
      supportedLocales: const [
        Locale('ar'),
        Locale('fr'),
        Locale('en'),
        Locale('es'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // The user's chosen font scale is applied uniformly across
        // every Text in the app via a MediaQuery override.
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(provider.fontScale),
          ),
          child: Directionality(
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        );
      },
      home: widget.showOnboarding
          ? const OnboardingScreen()
          : const HomeScreen(),
    );
  }
}
