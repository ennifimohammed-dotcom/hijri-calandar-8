import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'providers/app_provider.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/widget_sync_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Every launch starts at the splash screen, which decides — based on
  // SharedPreferences — whether to route into onboarding (first run)
  // or directly into the home screen.
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider()..init(),
      child: const HijriCalendarApp(),
    ),
  );
}

class HijriCalendarApp extends StatefulWidget {
  const HijriCalendarApp({super.key});

  @override
  State<HijriCalendarApp> createState() => _HijriCalendarAppState();
}

class _HijriCalendarAppState extends State<HijriCalendarApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Bind the home-screen widget sync layer once the first frame is
    // up, so the AppProvider is reachable via context. Best-effort —
    // WidgetSyncService swallows and logs its own failures, so this
    // can never affect app startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetSyncService.instance.bind(context.read<AppProvider>());
    });
  }

  @override
  void dispose() {
    WidgetSyncService.instance.unbind();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh the rolling 30-day window whenever the app
      // returns to foreground (covers post-midnight transitions).
      NotificationService().scheduleMidnightReschedule();
      // Repaint the home-screen widget too — covers a date rollover
      // or a settings change made while the app was backgrounded.
      WidgetSyncService.instance.requestSync();
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
      home: const SplashScreen(),
    );
  }
}
