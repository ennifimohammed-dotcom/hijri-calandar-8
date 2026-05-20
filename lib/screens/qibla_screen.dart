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

      final stream = FlutterCompass.events;
      if (stream == null) {
        setState(() {
          _loading = false;
          _position = pos;
          _qiblaBearing = bearing;
          _distanceKm = distance;
          _compassUnavailable = true;
        });
        unawaited(_fetchPlaceName(pos));
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
      unawaited(_fetchPlaceName(pos));
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
  Future<void> _fetchPlaceName(Position pos) async {
    try {
      // The `geocoding` package doesn't expose a per-call
      // `localeIdentifier` parameter on `placemarkFromCoordinates`
      // — the locale is set once via the platform interface's
      // `setLocaleIdentifier(...)` global. Wiring that into the
      // app's locale system here would couple us to a transitive
      // API surface, so we take the safe fallback: ask the
      // platform geocoder in the DEVICE locale. Names still come
      // back fully-localised; they just track the system locale
      // rather than the app's chosen language. Best-effort by
      // design — any failure leaves `_placeName` null and the
      // screen falls back to coordinates-only.
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
      HapticFeedback.lightImpact();
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
        final dialSize = math.min(320.0, shortSide - 80);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),
              // City, Country — quietly placed at the top. When
              // reverse geocoding hasn't returned yet (or
              // failed), we just hide this line; the
              // coordinates underneath still convey "we know
              // where you are".
              if (placeName != null && placeName!.isNotEmpty) ...[
                Text(
                  placeName!,
                  textAlign: TextAlign.center,
                  style: appFont(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textMain,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
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
              const SizedBox(height: 10),
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
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 10),
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

  /// Cardinal labels in the user's app locale. Arabic uses the
  /// single-letter convention requested by the spec; every other
  /// locale falls back to standard English compass letters.
  List<String> _localizedCardinals(String loc) {
    if (loc == 'ar') {
      // Per spec: N → ش, E → ش, S → ج, W → غ.
      return const ['ش', 'ش', 'ج', 'غ'];
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
// magnetometer reports persistently poor accuracy.
// ────────────────────────────────────────────────────────────
class _CalibrationCard extends StatelessWidget {
  final AppProvider provider;
  final bool isDark;
  final VoidCallback onDismiss;

  const _CalibrationCard({
    required this.provider,
    required this.isDark,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.darkSurface : AppColors.white;
    final textMain = isDark ? AppColors.darkText : AppColors.text;
    final textMuted = isDark ? AppColors.darkText3 : AppColors.text3;
    const goldSoft = Color(0xFFE5C68C);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: goldSoft.withValues(alpha: 0.40),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.12),
                blurRadius: 22,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFF0D89A), Color(0xFFC8943A)],
                  ),
                ),
                child: const Icon(
                  Icons.gesture_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.label('qibla_calibrate_title'),
                      style: appFont(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textMain,
                        letterSpacing: 0.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      provider.label('qibla_calibrate'),
                      style: appFont(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w400,
                        color: textMuted,
                        height: 1.35,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: provider.label('qibla_dismiss'),
                onPressed: onDismiss,
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

// ────────────────────────────────────────────────────────────
// Compass painter — premium Islamic dial.
//
// Z-order matters here: cardinal labels are painted AFTER the
// Qibla ray + Kaaba marker so that, when the Qibla bearing is
// close to a cardinal direction (e.g. East), the marker can
// never visually hide its letter. The marker also got slightly
// smaller, and the labels sit closer to the outer ring so they
// orbit the marker rather than overlap it.
// ────────────────────────────────────────────────────────────
class _CompassPainter extends CustomPainter {
  final double heading;
  final double qiblaBearing;
  final bool aligned;
  final double pulse;
  final bool compassUnavailable;
  final List<String> cardinals; // [N, E, S, W] in the active locale
  final bool isDark;

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
  });

  Color get _accentSoft => isDark
      ? const Color(0xFF1F3A2D)
      : const Color(0xFFEAF1EB);
  Color get _accentDeep => isDark
      ? const Color(0xFF0E2218)
      : const Color(0xFFD7E5DA);
  Color get _textMain =>
      isDark ? const Color(0xFFFAF5E8) : const Color(0xFF1A1A1A);
  Color get _textMuted =>
      isDark ? const Color(0xFFA9B7AD) : const Color(0xFF7A8A80);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 16;

    // Soft outer halo — premium glow that pulls the eye to the
    // dial without overwhelming the otherwise-clean screen.
    final halo = Paint()
      ..color = _goldSoft.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawCircle(center, radius + 6, halo);

    // Aligned pulse — soft green halo around the dial.
    if (aligned) {
      final glowR = radius + 6 + pulse * 6;
      canvas.drawCircle(
        center,
        glowR,
        Paint()
          ..color = _alignedGlow.withValues(alpha: 0.35 + pulse * 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
      );
    }

    // Dial fill — subtle accent radial gradient, light in the
    // centre and deepening slightly toward the edge so the dial
    // reads as its own surface against the clean screen.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [_accentSoft, _accentDeep],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // Outer gold ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _goldDeep.withValues(alpha: 0.55)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    // Inner decorative ring.
    canvas.drawCircle(
      center,
      radius * 0.74,
      Paint()
        ..color = _goldSoft.withValues(alpha: 0.22)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );

    // Rotate the dial so North follows True North relative to
    // the phone's current heading.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-heading * math.pi / 180);

    // Tick marks — every 10°, with the four cardinals
    // emphasised.
    for (int deg = 0; deg < 360; deg += 10) {
      final a = (deg - 90) * math.pi / 180;
      final isCardinal = deg % 90 == 0;
      final isHalfCard = deg % 30 == 0;
      final tickLen = isCardinal ? 12.0 : (isHalfCard ? 7.0 : 4.0);
      canvas.drawLine(
        Offset(radius * math.cos(a), radius * math.sin(a)),
        Offset(
          (radius - tickLen) * math.cos(a),
          (radius - tickLen) * math.sin(a),
        ),
        Paint()
          ..color = isCardinal
              ? _goldSoft.withValues(alpha: 0.85)
              : _textMuted.withValues(alpha: isHalfCard ? 0.55 : 0.35)
          ..strokeWidth = isCardinal ? 1.5 : 0.7
          ..strokeCap = StrokeCap.round,
      );
    }

    // Qibla bearing ray — drawn BEFORE the cardinal letters so
    // the letters paint on top when they collide visually.
    final qa = (qiblaBearing - 90) * math.pi / 180;
    canvas.drawLine(
      Offset(20 * math.cos(qa), 20 * math.sin(qa)),
      Offset(
        (radius - 32) * math.cos(qa),
        (radius - 32) * math.sin(qa),
      ),
      Paint()
        ..color = aligned ? _alignedGlow : _goldDeep
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );
    // Slightly smaller Kaaba marker so its silhouette can't
    // swallow an adjacent cardinal letter.
    final markerCenter = Offset(
      (radius - 22) * math.cos(qa),
      (radius - 22) * math.sin(qa),
    );
    canvas.drawCircle(
      markerCenter,
      8.5,
      Paint()
        ..shader = RadialGradient(
          colors: aligned
              ? const [Color(0xFF9FE3B5), Color(0xFF3F8A5E)]
              : const [_goldSoft, _goldDeep],
        ).createShader(
          Rect.fromCircle(center: markerCenter, radius: 8.5),
        ),
    );
    // Counter-rotated Kaaba glyph at the marker — small font so
    // the cardinal letters orbiting around it stay dominant.
    canvas.save();
    canvas.translate(markerCenter.dx, markerCenter.dy);
    canvas.rotate(heading * math.pi / 180);
    final ktp = TextPainter(
      text: const TextSpan(
        text: '🕋',
        style: TextStyle(fontSize: 11, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ktp.paint(canvas, Offset(-ktp.width / 2, -ktp.height / 2));
    canvas.restore();

    // Cardinal letters — PAINTED LAST inside the rotated dial
    // so they win every z-order collision with the Qibla
    // marker. North is the most prominent (gold, bigger,
    // bolder); the other three are quieter.
    for (int i = 0; i < 4; i++) {
      final a = (i * 90 - 90) * math.pi / 180;
      final pos = Offset(
        (radius - 18) * math.cos(a),
        (radius - 18) * math.sin(a),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: cardinals[i],
          style: TextStyle(
            color: i == 0 ? _goldSoft : _textMain.withValues(alpha: 0.78),
            fontSize: i == 0 ? 18 : 14,
            fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
            height: 1.0,
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

    // Fixed top indicator — small downward gold triangle just
    // above the dial showing where the phone is currently
    // pointing.
    final tip = Offset(center.dx, center.dy - radius - 2);
    final indicator = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - 7, tip.dy - 12)
      ..lineTo(tip.dx + 7, tip.dy - 12)
      ..close();
    canvas.drawPath(
      indicator,
      Paint()
        ..color = aligned ? _alignedGlow : _goldSoft
        ..style = PaintingStyle.fill,
    );

    // Centre crescent — same hand-drawn brand mark used by the
    // home-screen widgets.
    _drawCrescent(canvas, center, 12);

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
          center.dy - hintTp.height / 2,
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
      old.cardinals[0] != cardinals[0];
}
