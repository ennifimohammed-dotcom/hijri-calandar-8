import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/qibla_service.dart';
import '../theme.dart';

/// Premium "Qibla" screen — a calm, spiritual compass dedicated to
/// pointing the user toward the Kaaba.
///
/// Design language
///   * Screen-level surface follows the rest of the app
///     (`AppColors.bg` / `AppColors.darkBg`) — clean, minimal,
///     readable. NO full-screen dark gradient, NO background
///     Islamic pattern.
///   * The COMPASS DIAL is the only place that carries the
///     accent + gold branding (subtle accent-tinted dial face,
///     gold ring, gold cardinal labels, gold Qibla ray + Kaaba
///     marker). A soft gold halo behind the dial pulls the eye
///     to it without crowding the rest of the layout.
///   * "City, Country" + coordinates sit above the dial in
///     quiet typography. Distance / angle / accuracy live in a
///     premium card below the dial.
///   * When magnetometer accuracy drops, an elegant
///     calibration card slides up from the bottom with a
///     figure-8 hint; it auto-dismisses when accuracy
///     improves and can be manually closed.
///
/// What is preserved
///   * The compass / Qibla math (bearing, distance, smoothing,
///     alignment delta) lives in `QiblaService` and is
///     untouched.
///   * The sensor lifecycle (subscribe / pause / resume /
///     cancel) is byte-identical to the previous version.
///   * The permission flow (services off / denied / denied
///     forever / generic) is byte-identical.
///   * Theme system, locale system, navigation, RTL, and
///     accessibility scaling are all routed through the
///     existing AppProvider / Theme / Directionality plumbing.
class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<ServiceStatus>? _serviceSub;

  bool _loading = true;
  _QiblaError? _error;

  Position? _position;
  String? _placeName; // "City, Country" or null until/unless geocoded.
  /// Locale (`'ar' | 'fr' | 'en' | 'es'`) that the current `_placeName`
  /// was fetched in. Tracked so a runtime language change can
  /// trigger a single re-geocode without re-doing the whole
  /// bootstrap.
  String? _lastGeocodedLocale;

  double _qiblaBearing = 0; // 0..360
  double _distanceKm = 0;

  double _smoothedHeading = 0; // 0..360
  double? _rawHeading; // null = no compass event yet
  double? _accuracyDegrees;
  bool _aligned = false;
  bool _compassUnavailable = false;

  // Calibration card state ------------------------------------
  bool _showCalibration = false;
  bool _calibrationDismissed = false;
  Timer? _calibrationDebounce;

  /// Reusable smoothing coefficient. Bigger = snappier dial,
  /// smaller = calmer. 0.16 strikes a comfortable balance for
  /// a Qibla compass — the user can SEE small adjustments but
  /// the dial doesn't twitch on sensor noise.
  static const double _smoothingAlpha = 0.16;

  /// How close to the Qibla bearing (in degrees, absolute) we
  /// consider "aligned" — fires the success state + haptic.
  static const double _alignThresholdDegrees = 4;

  /// Accuracy threshold (degrees) above which the calibration
  /// card may surface. Sensors typically report 5-20° when
  /// stable, 30-60° when uncalibrated.
  static const double _lowAccuracyThreshold = 25;

  /// Wait this long with a sustained low-accuracy reading before
  /// showing the calibration card — avoids flashing it during a
  /// brief sensor blip.
  static const Duration _calibrationDebounceDelay =
      Duration(milliseconds: 1500);

  /// Pulse animation for the aligned glow ring. Cheap — runs only
  /// while the user is actually aligned; otherwise the controller
  /// stays at 0 and isn't repainted.
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..addListener(() {
        if (mounted) setState(() {});
      });
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _compassSub?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _compassSub?.resume();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If the user changed the app language while staying on the
    // Qibla screen, refresh the City, Country line into the new
    // locale. Skips the very first call (when `_lastGeocodedLocale`
    // is still null and the bootstrap fetch hasn't run yet).
    final pos = _position;
    final last = _lastGeocodedLocale;
    if (pos == null || last == null) return;
    final current = context.read<AppProvider>().locale;
    if (current != last) {
      _lastGeocodedLocale = current;
      unawaited(_fetchPlaceName(pos, current));
    }
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _serviceSub?.cancel();
    _calibrationDebounce?.cancel();
    _pulseCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Location + permission flow (unchanged) ──────────────────

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final servicesOn = await Geolocator.isLocationServiceEnabled();
      if (!servicesOn) {
        _emitError(_QiblaError.serviceDisabled);
        _serviceSub = Geolocator.getServiceStatusStream().listen((s) {
          if (s == ServiceStatus.enabled &&
              _error == _QiblaError.serviceDisabled) {
            _bootstrap();
          }
        });
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _emitError(_QiblaError.denied);
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _emitError(_QiblaError.deniedForever);
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      final bearing = QiblaService.bearingTo(pos.latitude, pos.longitude);
      final distance = QiblaService.distanceTo(pos.latitude, pos.longitude);

      final appLocale = mounted
          ? context.read<AppProvider>().locale
          : 'en';
      _lastGeocodedLocale = appLocale;

      final stream = FlutterCompass.events;
      if (stream == null) {
        setState(() {
          _loading = false;
          _position = pos;
          _qiblaBearing = bearing;
          _distanceKm = distance;
          _compassUnavailable = true;
        });
        unawaited(_fetchPlaceName(pos, appLocale));
        return;
      }
      _compassSub?.cancel();
      _compassSub = stream.listen(_onCompass, onError: (_) {});

      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        if (_rawHeading == null && _error == null && !_compassUnavailable) {
          setState(() => _compassUnavailable = true);
        }
      });

      setState(() {
        _loading = false;
        _position = pos;
        _qiblaBearing = bearing;
        _distanceKm = distance;
      });
      // Best-effort reverse geocoding — never blocks the screen
      // and a failure stays silent.
      unawaited(_fetchPlaceName(pos, appLocale));
    } catch (e) {
      _emitError(_QiblaError.generic);
    }
  }

  void _emitError(_QiblaError err) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
    });
  }

  /// Best-effort reverse geocoding. Uses the OS provider — no API
  /// key, no network call we control. If it returns nothing or
  /// throws, we silently fall back to coordinates-only display.
  ///
  /// `appLocale` lets the platform geocoder return city/country
  /// names in the user's chosen app language (Arabic, French,
  /// English, Spanish) rather than the device locale. Routed via
  /// the package's global `setLocaleIdentifier` — wrapped in a
  /// try-catch because some platforms ignore the override; the
  /// fetch still succeeds in those cases, just in the device
  /// locale.
  Future<void> _fetchPlaceName(Position pos, String appLocale) async {
    try {
      final bcp47 = switch (appLocale) {
        'ar' => 'ar',
        'fr' => 'fr_FR',
        'es' => 'es_ES',
        _ => 'en_US',
      };
      try {
        await setLocaleIdentifier(bcp47);
      } catch (_) {
        // Platform geocoder doesn't support a runtime locale
        // override — silently fall through to its default.
      }
      final marks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (!mounted || marks.isEmpty) return;
      final m = marks.first;
      final city =
          (m.locality?.isNotEmpty ?? false) ? m.locality! :
          (m.subAdministrativeArea?.isNotEmpty ?? false)
              ? m.subAdministrativeArea!
              : (m.administrativeArea ?? '');
      final country = m.country ?? '';
      final joined = (city.isNotEmpty && country.isNotEmpty)
          ? '$city, $country'
          : (city.isNotEmpty ? city : country);
      if (joined.isEmpty) return;
      setState(() => _placeName = joined);
    } catch (_) {
      // Silently swallow — graceful coordinates-only fallback.
    }
  }

  // ── Compass stream (unchanged logic + calibration trigger) ──

  void _onCompass(CompassEvent event) {
    final h = event.heading;
    if (h == null) return;
    _rawHeading = h;
    _accuracyDegrees = event.accuracy;
    _smoothedHeading = QiblaService.smoothHeading(
      _smoothedHeading,
      h,
      _smoothingAlpha,
    );
    final delta = QiblaService.shortestAngleDelta(
      _smoothedHeading,
      _qiblaBearing,
    );
    final wasAligned = _aligned;
    _aligned = delta.abs() <= _alignThresholdDegrees;
    if (_aligned && !wasAligned) {
      // Soft "click into place" — a primary light impact then a
      // quieter selection tick ~60ms later. The transition guard
      // above (`!wasAligned`) keeps this from spamming when the
      // user moves the phone around the alignment threshold.
      HapticFeedback.lightImpact();
      Future.delayed(const Duration(milliseconds: 65), () {
        if (mounted && _aligned) HapticFeedback.selectionClick();
      });
      _pulseCtrl
        ..stop()
        ..repeat(reverse: true);
    } else if (!_aligned && wasAligned) {
      _pulseCtrl
        ..stop()
        ..value = 0;
    }
    _updateCalibrationState();
    if (mounted) setState(() {});
  }

  /// Drives the calibration-card slide-in. Shows the card when
  /// magnetometer accuracy is consistently poor; hides it the
  /// moment accuracy improves OR the user explicitly dismisses
  /// it. The debounce stops a brief sensor blip from flashing
  /// the card.
  void _updateCalibrationState() {
    final acc = _accuracyDegrees;
    if (acc == null) return;
    final isLow = acc > _lowAccuracyThreshold;

    if (!isLow) {
      // Accuracy recovered — reset everything for the next time.
      _calibrationDebounce?.cancel();
      _calibrationDebounce = null;
      if (_calibrationDismissed) _calibrationDismissed = false;
      if (_showCalibration && mounted) {
        // Defer the state mutation to avoid stacking setState
        // calls inside the same compass event handler.
        Future.microtask(() {
          if (mounted) setState(() => _showCalibration = false);
        });
      }
      return;
    }

    // Already showing or already dismissed for this low spell —
    // nothing to do.
    if (_showCalibration || _calibrationDismissed) return;
    // Schedule the slide-in only if a debounce isn't already
    // pending.
    _calibrationDebounce ??= Timer(_calibrationDebounceDelay, () {
      _calibrationDebounce = null;
      if (!mounted) return;
      if (_accuracyDegrees == null) return;
      if (_accuracyDegrees! <= _lowAccuracyThreshold) return;
      if (_calibrationDismissed) return;
      setState(() => _showCalibration = true);
    });
  }

  void _dismissCalibration() {
    setState(() {
      _showCalibration = false;
      _calibrationDismissed = true;
    });
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final isDark = p.themeMode == ThemeMode.dark ||
        (p.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    final foreground = isDark ? AppColors.darkText : AppColors.text;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          p.label('qibla'),
          style: appFont(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: foreground,
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            _buildBody(p, isDark),
            // Calibration overlay — pinned to the bottom, slides
            // up when needed. Stays out of the layout flow when
            // hidden so the main composition never shifts.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_showCalibration,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  offset: _showCalibration
                      ? Offset.zero
                      : const Offset(0, 1.2),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _showCalibration ? 1 : 0,
                    child: _CalibrationCard(
                      provider: p,
                      isDark: isDark,
                      onDismiss: _dismissCalibration,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppProvider p, bool isDark) {
    if (_loading) {
      return _LoadingView(
        label: p.label('qibla_locating'),
        isDark: isDark,
      );
    }
    if (_error != null) {
      return _ErrorView(
        provider: p,
        isDark: isDark,
        error: _error!,
        onPrimary: () async {
          switch (_error!) {
            case _QiblaError.serviceDisabled:
              await Geolocator.openLocationSettings();
              _bootstrap();
              break;
            case _QiblaError.denied:
            case _QiblaError.generic:
              _bootstrap();
              break;
            case _QiblaError.deniedForever:
              await Geolocator.openAppSettings();
              break;
          }
        },
      );
    }
    return _CompassView(
      provider: p,
      position: _position!,
      placeName: _placeName,
      qiblaBearing: _qiblaBearing,
      distanceKm: _distanceKm,
      heading: _smoothedHeading,
      accuracyDegrees: _accuracyDegrees,
      aligned: _aligned,
      compassUnavailable: _compassUnavailable,
      pulse: _pulseCtrl.value,
      isDark: isDark,
    );
  }
}

/// Permission / lifecycle failure states the screen can settle in.
enum _QiblaError { serviceDisabled, denied, deniedForever, generic }

// ────────────────────────────────────────────────────────────
// Loading view — calm centred spinner with one helper line.
// ────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  final String label;
  final bool isDark;
  const _LoadingView({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(Color(0xFFC8943A)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: appFont(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: isDark ? AppColors.darkText3 : AppColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Error / permission view — calm explanation + one primary CTA.
// ────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final AppProvider provider;
  final bool isDark;
  final _QiblaError error;
  final VoidCallback onPrimary;

  const _ErrorView({
    required this.provider,
    required this.isDark,
    required this.error,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final (title, body, cta) = switch (error) {
      _QiblaError.serviceDisabled => (
          p.label('qibla_location_title'),
          p.label('qibla_location_disabled'),
          p.label('qibla_enable_location'),
        ),
      _QiblaError.denied => (
          p.label('qibla_location_title'),
          p.label('qibla_location_body'),
          p.label('qibla_enable_location'),
        ),
      _QiblaError.deniedForever => (
          p.label('qibla_location_title'),
          p.label('qibla_location_body'),
          p.label('qibla_open_settings'),
        ),
      _QiblaError.generic => (
          p.label('qibla_location_title'),
          p.label('qibla_hint'),
          p.label('qibla_retry'),
        ),
    };

    final textMain = isDark ? AppColors.darkText : AppColors.text;
    final textMuted = isDark ? AppColors.darkText3 : AppColors.text3;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.explore_outlined,
              size: 56,
              color: Color(0xFFC8943A),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: textMain,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onPrimary,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFC8943A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                cta,
                style: appFont(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Compass view — the screen's main composition on the
// light/dark theme surface.
// ────────────────────────────────────────────────────────────
class _CompassView extends StatelessWidget {
  final AppProvider provider;
  final Position position;
  final String? placeName;
  final double qiblaBearing;
  final double distanceKm;
  final double heading;
  final double? accuracyDegrees;
  final bool aligned;
  final bool compassUnavailable;
  final double pulse;
  final bool isDark;

  const _CompassView({
    required this.provider,
    required this.position,
    required this.placeName,
    required this.qiblaBearing,
    required this.distanceKm,
    required this.heading,
    required this.accuracyDegrees,
    required this.aligned,
    required this.compassUnavailable,
    required this.pulse,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final textMain = isDark ? AppColors.darkText : AppColors.text;
    final textMuted = isDark ? AppColors.darkText3 : AppColors.text3;

    final coords = _formatCoords(position.latitude, position.longitude);
    final distanceText = _formatDistance(distanceKm, p.locale);
    final bearingText = '${qiblaBearing.toStringAsFixed(0)}°';

    final accuracyLabel = compassUnavailable
        ? p.label('qibla_compass_unavailable')
        : _accuracyLabel(p, accuracyDegrees);
    final accuracyColor = compassUnavailable
        ? const Color(0xFFE57373)
        : _accuracyColor(accuracyDegrees);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Dial scales with the available area but caps so the
        // compass never floats lonely on a wide tablet.
        final shortSide =
            math.min(constraints.maxWidth, constraints.maxHeight);
        final dialSize = math.min(330.0, shortSide - 72);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // City, Country — quietly placed at the top. A
              // small location pin on the leading side makes
              // the line read as "where the calculation is
              // coming from" without shouting. When reverse
              // geocoding hasn't returned yet (or failed), the
              // coordinates underneath still convey "we know
              // where you are".
              if (placeName != null && placeName!.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.place_rounded,
                      size: 14,
                      color: Color(0xFFC8943A),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        placeName!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appFont(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textMain,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
              ],
              Text(
                coords,
                textAlign: TextAlign.center,
                style: appFont(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w400,
                  color: textMuted,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: dialSize,
                    height: dialSize,
                    child: CustomPaint(
                      painter: _CompassPainter(
                        heading: compassUnavailable ? 0 : heading,
                        qiblaBearing: qiblaBearing,
                        aligned: aligned,
                        pulse: pulse,
                        compassUnavailable: compassUnavailable,
                        cardinals: _localizedCardinals(p.locale),
                        isDark: isDark,
                        // Runtime accent — drives the dial face,
                        // halo, Qibla ray, and outer ring tint so
                        // the compass tracks whichever swatch the
                        // user picked in Settings. Gold remains
                        // the constant secondary accent.
                        accent: AppColors.green,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 22,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: aligned
                      ? Text(
                          p.label('qibla_aligned'),
                          key: const ValueKey('aligned'),
                          textAlign: TextAlign.center,
                          style: appFont(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF4FA46B),
                            letterSpacing: 0.3,
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('idle')),
                ),
              ),
              const SizedBox(height: 8),
              _InfoCard(
                provider: p,
                distanceText: distanceText,
                toMakkahLabel: p.label('qibla_to_makkah'),
                angleLabel: p.label('qibla_angle'),
                bearingText: bearingText,
                accuracyLabel: accuracyLabel,
                accuracyColor: accuracyColor,
                isDark: isDark,
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatCoords(double lat, double lng) {
    String fmt(double v, String pos, String neg) {
      final hem = v >= 0 ? pos : neg;
      return '$hem ${v.abs().toStringAsFixed(2)}°';
    }
    return '${fmt(lat, 'N', 'S')}   ${fmt(lng, 'E', 'W')}';
  }

  String _formatDistance(double km, String loc) {
    final rounded = km.round();
    final unit = switch (loc) {
      'ar' => 'كم',
      _ => 'km',
    };
    return '$rounded $unit';
  }

  String _accuracyLabel(AppProvider p, double? degrees) {
    if (degrees == null) return p.label('qibla_accuracy_medium');
    if (degrees < 15) return p.label('qibla_accuracy_high');
    if (degrees < 25) return p.label('qibla_accuracy_medium');
    return p.label('qibla_accuracy_low');
  }

  Color _accuracyColor(double? degrees) {
    if (degrees == null) return const Color(0xFFC8943A);
    if (degrees < 15) return const Color(0xFF4FA46B);
    if (degrees < 25) return const Color(0xFFC8943A);
    return const Color(0xFFE57373);
  }

  /// Cardinal labels in the user's app locale. Arabic uses
  /// short Arabic abbreviations; every other locale falls back
  /// to the standard English compass letters.
  ///
  /// Arabic mapping per spec:
  ///   N → شم  (short for شمال — kept as two letters to
  ///           disambiguate from East, which also starts with ش)
  ///   E → ش   (شرق)
  ///   S → ج   (جنوب)
  ///   W → غ   (غرب)
  List<String> _localizedCardinals(String loc) {
    if (loc == 'ar') {
      return const ['شم', 'ش', 'ج', 'غ'];
    }
    return const ['N', 'E', 'S', 'W'];
  }
}

// ────────────────────────────────────────────────────────────
// Bottom info card — distance, angle, accuracy in one elegant
// pane with a soft gold trim.
// ────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final AppProvider provider;
  final String distanceText;
  final String toMakkahLabel;
  final String angleLabel;
  final String bearingText;
  final String accuracyLabel;
  final Color accuracyColor;
  final bool isDark;

  const _InfoCard({
    required this.provider,
    required this.distanceText,
    required this.toMakkahLabel,
    required this.angleLabel,
    required this.bearingText,
    required this.accuracyLabel,
    required this.accuracyColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.darkSurface : AppColors.white;
    final textMain = isDark ? AppColors.darkText : AppColors.text;
    final textMuted = isDark ? AppColors.darkText3 : AppColors.text3;
    const goldSoft = Color(0xFFE5C68C);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: goldSoft.withValues(alpha: 0.30),
          width: 0.7,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  icon: Icons.straighten_rounded,
                  value: distanceText,
                  label: toMakkahLabel,
                  textMain: textMain,
                  textMuted: textMuted,
                ),
              ),
              Container(
                width: 0.8,
                height: 32,
                color: goldSoft.withValues(alpha: 0.35),
              ),
              Expanded(
                child: _StatBlock(
                  icon: Icons.explore_rounded,
                  value: bearingText,
                  label: angleLabel,
                  textMain: textMain,
                  textMuted: textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 0.7,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  goldSoft.withValues(alpha: 0.0),
                  goldSoft.withValues(alpha: 0.32),
                  goldSoft.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accuracyColor,
                  boxShadow: [
                    BoxShadow(
                      color: accuracyColor.withValues(alpha: 0.55),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                accuracyLabel,
                style: appFont(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: textMuted,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color textMain;
  final Color textMuted;

  const _StatBlock({
    required this.icon,
    required this.value,
    required this.label,
    required this.textMain,
    required this.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFC8943A)),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appFont(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: textMain,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appFont(
              fontSize: 10.5,
              fontWeight: FontWeight.w400,
              color: textMuted,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
// Calibration card — slides in from the bottom when the
// magnetometer reports persistently poor accuracy. Features a
// small animated lemniscate (figure-8) that traces the motion
// the user is being asked to perform, so the instruction reads
// even before the body text has been parsed.
// ────────────────────────────────────────────────────────────
class _CalibrationCard extends StatefulWidget {
  final AppProvider provider;
  final bool isDark;
  final VoidCallback onDismiss;

  const _CalibrationCard({
    required this.provider,
    required this.isDark,
    required this.onDismiss,
  });

  @override
  State<_CalibrationCard> createState() => _CalibrationCardState();
}

class _CalibrationCardState extends State<_CalibrationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final surface = isDark ? AppColors.darkSurface : AppColors.white;
    final textMain = isDark ? AppColors.darkText : AppColors.text;
    final textMuted = isDark ? AppColors.darkText3 : AppColors.text3;
    const goldSoft = Color(0xFFE5C68C);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: goldSoft.withValues(alpha: 0.42),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.14),
                blurRadius: 26,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => CustomPaint(
                    painter: _Figure8Painter(
                      t: _ctrl.value,
                      color: const Color(0xFFC8943A),
                      glow: goldSoft,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.provider.label('qibla_calibrate_title'),
                      style: appFont(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textMain,
                        letterSpacing: 0.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.provider.label('qibla_calibrate'),
                      style: appFont(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                        color: textMuted,
                        height: 1.40,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: widget.provider.label('qibla_dismiss'),
                onPressed: widget.onDismiss,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lightweight CustomPainter that draws a static lemniscate
/// (figure-8) outline with an animated dot tracing along its
/// path. The dot's position is computed from the standard
/// parametric form of a lemniscate of Bernoulli — pure math, no
/// extra deps, costs nothing at idle.
class _Figure8Painter extends CustomPainter {
  final double t;
  final Color color;
  final Color glow;
  _Figure8Painter({
    required this.t,
    required this.color,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final w = size.width * 0.42;
    final h = size.height * 0.30;

    Offset pointAt(double s) {
      final theta = s * 2 * math.pi;
      final denom = 1 + math.sin(theta) * math.sin(theta);
      return Offset(
        center.dx + (w * math.cos(theta)) / denom,
        center.dy + (h * math.sin(theta) * math.cos(theta)) / denom,
      );
    }

    // Static path — soft gold trail behind the moving dot.
    final path = Path();
    const segments = 64;
    for (int i = 0; i <= segments; i++) {
      final p = pointAt(i / segments);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.22)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Moving dot with soft halo.
    final dot = pointAt(t);
    canvas.drawCircle(
      dot,
      6.5,
      Paint()
        ..color = glow.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      dot,
      3.6,
      Paint()
        ..shader = RadialGradient(
          colors: [glow, color],
        ).createShader(Rect.fromCircle(center: dot, radius: 3.6)),
    );
  }

  @override
  bool shouldRepaint(_Figure8Painter old) =>
      old.t != t || old.color != color || old.glow != glow;
}

// ────────────────────────────────────────────────────────────
// Compass painter — premium Islamic dial.
//
// Visual stack (back-to-front):
//   1. Drop shadow under the dial — soft 3D lift.
//   2. Accent halo + gold halo — outer ambient glow.
//   3. Aligned pulse — green halo when on-Qibla.
//   4. Dial face — accent radial gradient (off-axis to suggest
//      a light source from the top-left).
//   5. Glass top highlight — vertical white-to-transparent
//      gradient masked to a thin top band; gives a subtle
//      "dome" feel without any heavy 3D engine.
//   6. Outer metallic ring — sweep gradient between two golds
//      so the rim catches light differently around the
//      circumference (premium metal look).
//   7. Inner decorative gold hairline.
//   8. Rotated dial content:
//        a. Tick marks (every 10°).
//        b. Qibla ray (accent → gold gradient).
//        c. Kaaba marker on its OWN inner orbit
//           (`radius * 0.62`) so it can never collide with
//           the outer cardinal labels.
//        d. Cardinal letters painted LAST, at `radius - 22`,
//           guaranteed visible above the ray.
//   9. Fixed top indicator triangle (gold gradient, with a
//      subtle gold glow underneath).
//   10. Centre crescent brand mark.
//
// Two colour roles:
//   * `accent` (runtime) — drives the dial face, halo, and the
//     start of the Qibla ray. Tracks `AppColors.green` so it
//     follows whichever swatch the user picked in Settings.
//   * Gold (constant `_goldSoft`/`_goldDeep`) — keeps the
//     metallic Islamic identity stable across swatches.
// ────────────────────────────────────────────────────────────
class _CompassPainter extends CustomPainter {
  final double heading;
  final double qiblaBearing;
  final bool aligned;
  final double pulse;
  final bool compassUnavailable;
  final List<String> cardinals; // [N, E, S, W] in the active locale
  final bool isDark;
  final Color accent;

  static const Color _goldSoft = Color(0xFFF0D89A);
  static const Color _goldDeep = Color(0xFFC8943A);
  static const Color _alignedGlow = Color(0xFF7DD89C);

  _CompassPainter({
    required this.heading,
    required this.qiblaBearing,
    required this.aligned,
    required this.pulse,
    required this.compassUnavailable,
    required this.cardinals,
    required this.isDark,
    required this.accent,
  });

  /// Light, slightly-desaturated tint of `accent` for the dial
  /// face centre. Computed in HSL so any swatch (green, navy,
  /// maroon, plum, teal, sky, rose, amber) lands at a calm
  /// pale-on-light / deep-on-dark surface without going neon.
  Color get _dialCenter {
    final hsl = HSLColor.fromColor(accent);
    if (isDark) {
      return hsl
          .withLightness((hsl.lightness * 0.55).clamp(0.10, 0.32))
          .withSaturation((hsl.saturation * 0.65).clamp(0.0, 1.0))
          .toColor();
    }
    return hsl
        .withLightness(0.94)
        .withSaturation((hsl.saturation * 0.28).clamp(0.0, 1.0))
        .toColor();
  }

  Color get _dialEdge {
    final hsl = HSLColor.fromColor(accent);
    if (isDark) {
      return hsl
          .withLightness((hsl.lightness * 0.30).clamp(0.05, 0.20))
          .withSaturation((hsl.saturation * 0.55).clamp(0.0, 1.0))
          .toColor();
    }
    return hsl
        .withLightness(0.84)
        .withSaturation((hsl.saturation * 0.45).clamp(0.0, 1.0))
        .toColor();
  }

  Color get _textMain =>
      isDark ? const Color(0xFFFAF5E8) : const Color(0xFF1A1A1A);
  Color get _textMuted =>
      isDark ? const Color(0xFFA9B7AD) : const Color(0xFF7A8A80);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 18;

    // 1) Drop shadow — soft, slightly offset so the dial reads
    //    as a raised disc on the screen surface.
    canvas.drawCircle(
      center.translate(0, 8),
      radius + 2,
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.55 : 0.13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    // 2a) Accent ambient halo.
    canvas.drawCircle(
      center,
      radius + 10,
      Paint()
        ..color = accent.withValues(alpha: isDark ? 0.20 : 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );
    // 2b) Gold halo — a touch lighter, layered on top so accent
    //     + gold mix.
    canvas.drawCircle(
      center,
      radius + 6,
      Paint()
        ..color = _goldSoft.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // 3) Aligned pulse — soft green halo when on-Qibla.
    if (aligned) {
      final glowR = radius + 6 + pulse * 6;
      canvas.drawCircle(
        center,
        glowR,
        Paint()
          ..color = _alignedGlow.withValues(alpha: 0.32 + pulse * 0.16)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }

    final dialRect = Rect.fromCircle(center: center, radius: radius);

    // 4) Dial face — off-axis radial gradient (centre slightly
    //    up-left) gives the disc subtle volume without faking a
    //    full 3D engine.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.28, -0.34),
          radius: 0.95,
          colors: [_dialCenter, _dialEdge],
          stops: const [0.0, 1.0],
        ).createShader(dialRect),
    );

    // 5) Glass top highlight — a soft white wash on the upper
    //    half clipped to the dial circle, producing the
    //    "glass dome" feel.
    canvas.save();
    canvas.clipPath(Path()..addOval(dialRect));
    final highlightRect = Rect.fromLTWH(
      center.dx - radius,
      center.dy - radius,
      radius * 2,
      radius * 0.95,
    );
    canvas.drawRect(
      highlightRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.07),
                  Colors.white.withValues(alpha: 0.00),
                ]
              : [
                  Colors.white.withValues(alpha: 0.32),
                  Colors.white.withValues(alpha: 0.00),
                ],
        ).createShader(highlightRect),
    );
    canvas.restore();

    // 6) Outer metallic ring — sweep gradient catches light
    //    around the rim. Two strokes layered (a thicker faint
    //    one + a thinner crisp one) reads as a small bevel.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: const [
            _goldSoft,
            _goldDeep,
            _goldSoft,
            _goldDeep,
            _goldSoft,
          ],
          stops: const [0.0, 0.30, 0.5, 0.70, 1.0],
        ).createShader(dialRect)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
    );
    // Faint inner shadow under the rim — sells the bevel.
    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.22 : 0.06)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke,
    );

    // 7) Inner decorative gold hairline.
    canvas.drawCircle(
      center,
      radius * 0.74,
      Paint()
        ..color = _goldSoft.withValues(alpha: 0.22)
        ..strokeWidth = 0.7
        ..style = PaintingStyle.stroke,
    );

    // 8) Rotated dial content — North follows True North.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-heading * math.pi / 180);

    // 8a) Tick marks — pulled in 4px so they don't kiss the rim.
    for (int deg = 0; deg < 360; deg += 10) {
      final a = (deg - 90) * math.pi / 180;
      final isCardinal = deg % 90 == 0;
      final isHalfCard = deg % 30 == 0;
      final tickLen = isCardinal ? 10.0 : (isHalfCard ? 6.0 : 3.5);
      final outerR = radius - 4;
      canvas.drawLine(
        Offset(outerR * math.cos(a), outerR * math.sin(a)),
        Offset(
          (outerR - tickLen) * math.cos(a),
          (outerR - tickLen) * math.sin(a),
        ),
        Paint()
          ..color = isCardinal
              ? _goldSoft.withValues(alpha: 0.90)
              : _textMuted.withValues(alpha: isHalfCard ? 0.55 : 0.30)
          ..strokeWidth = isCardinal ? 1.6 : 0.7
          ..strokeCap = StrokeCap.round,
      );
    }

    // 8b) Qibla ray — short, drawn from near the centre to JUST
    //     before the Kaaba marker. Gradient from a translucent
    //     accent tint into deep gold so the ray reads as light
    //     emerging from the dial.
    final qa = (qiblaBearing - 90) * math.pi / 180;
    final qrayStart = Offset(18 * math.cos(qa), 18 * math.sin(qa));
    final qrayEnd = Offset(
      (radius * 0.55) * math.cos(qa),
      (radius * 0.55) * math.sin(qa),
    );
    canvas.drawLine(
      qrayStart,
      qrayEnd,
      Paint()
        ..shader = LinearGradient(
          colors: aligned
              ? [_alignedGlow.withValues(alpha: 0.55), _alignedGlow]
              : [accent.withValues(alpha: 0.40), _goldDeep],
        ).createShader(Rect.fromPoints(qrayStart, qrayEnd))
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // 8c) Kaaba marker — its own inner orbit at `radius * 0.62`
    //     so the outer cardinal labels (at `radius - 22`) can
    //     NEVER overlap it.
    final markerR = radius * 0.62;
    final markerCenter = Offset(
      markerR * math.cos(qa),
      markerR * math.sin(qa),
    );
    // Soft glow under the marker.
    canvas.drawCircle(
      markerCenter,
      15,
      Paint()
        ..color = (aligned ? _alignedGlow : _goldDeep)
            .withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      markerCenter,
      9.5,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3),
          colors: aligned
              ? const [Color(0xFFB9EAC9), Color(0xFF3F8A5E)]
              : const [_goldSoft, _goldDeep],
        ).createShader(Rect.fromCircle(center: markerCenter, radius: 9.5)),
    );
    // Counter-rotated Kaaba glyph.
    canvas.save();
    canvas.translate(markerCenter.dx, markerCenter.dy);
    canvas.rotate(heading * math.pi / 180);
    final ktp = TextPainter(
      text: const TextSpan(
        text: '🕋',
        style: TextStyle(fontSize: 12, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ktp.paint(canvas, Offset(-ktp.width / 2, -ktp.height / 2));
    canvas.restore();

    // 8d) Cardinal letters — painted LAST so they always win the
    //     z-order. They sit at `radius - 22` (well outside the
    //     Kaaba marker's `radius * 0.62` orbit), so the two
    //     never collide visually.
    for (int i = 0; i < 4; i++) {
      final a = (i * 90 - 90) * math.pi / 180;
      final pos = Offset(
        (radius - 22) * math.cos(a),
        (radius - 22) * math.sin(a),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: cardinals[i],
          style: TextStyle(
            color: i == 0 ? _goldSoft : _textMain.withValues(alpha: 0.82),
            fontSize: i == 0 ? 17 : 13.5,
            fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
            height: 1.0,
            letterSpacing: 0.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(heading * math.pi / 180);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    canvas.restore(); // end dial rotation

    // 9) Fixed top indicator triangle — points down at the
    //    cardinal currently under the phone's heading. Soft
    //    glow under it sells it as a small jewel.
    final tip = Offset(center.dx, center.dy - radius - 2);
    canvas.drawCircle(
      Offset(tip.dx, tip.dy - 6),
      9,
      Paint()
        ..color = (aligned ? _alignedGlow : _goldDeep)
            .withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    final indicator = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 8, tip.dy - 14)
      ..lineTo(tip.dx + 8, tip.dy - 14)
      ..close();
    canvas.drawPath(
      indicator,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: aligned
              ? const [Color(0xFFB9EAC9), _alignedGlow]
              : const [_goldSoft, _goldDeep],
        ).createShader(Rect.fromLTWH(tip.dx - 8, tip.dy - 14, 16, 14)),
    );

    // 10) Centre crescent brand mark.
    _drawCrescent(canvas, center, 13);

    if (compassUnavailable) {
      // No sensor — quiet hint inside the dial.
      final hintTp = TextPainter(
        text: TextSpan(
          text: '—',
          style: TextStyle(
            color: _textMuted,
            fontSize: 28,
            fontWeight: FontWeight.w300,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      hintTp.paint(
        canvas,
        Offset(
          center.dx - hintTp.width / 2,
          center.dy - hintTp.height / 2 + 18,
        ),
      );
    }
  }

  void _drawCrescent(Canvas canvas, Offset center, double r) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final outer = Path()
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: r));
    final inner = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(r * 0.40, -r * 0.06),
          radius: r * 0.86,
        ),
      );
    final path = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..shader = const LinearGradient(
          colors: [Color(0xFFF0D89A), Color(0xFFC8943A)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.heading != heading ||
      old.qiblaBearing != qiblaBearing ||
      old.aligned != aligned ||
      old.pulse != pulse ||
      old.compassUnavailable != compassUnavailable ||
      old.isDark != isDark ||
      old.cardinals[0] != cardinals[0] ||
      old.accent != accent;
}
