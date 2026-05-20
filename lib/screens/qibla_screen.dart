import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_provider.dart';
import '../services/qibla_service.dart';
import '../theme.dart';

/// Premium "Qibla" screen — a calm, spiritual compass dedicated to
/// pointing the user toward the Kaaba. Designed to feel like a
/// world-class Islamic utility rather than a generic compass app:
///
///   * Dark royal-green gradient backdrop with a soft gold glow
///     and a faint tessellating Islamic geometric texture
///     (the same visual language as the home-screen widgets).
///   * A custom-painted dial that smoothly rotates with the
///     phone's heading. A prominent gold ray + Kaaba marker
///     shows the great-circle bearing to Makkah; the dial's
///     cardinal letters (N, E, S, W) stay upright at any
///     rotation.
///   * When the user aligns the phone within a few degrees of
///     the Qibla, a soft green glow pulses around the dial,
///     the centre text reads "اتجاه القبلة صحيح", and a single
///     gentle haptic confirms it.
///   * Below the dial, a quiet info strip — coordinates,
///     distance to Makkah, exact Qibla angle, accuracy badge.
///     Optional "view on map" action opens the OS Maps app
///     with a route to the Kaaba.
///
/// Permission flow handles every state (granted, asking, denied,
/// permanently denied, services disabled) with a calm explanation
/// + a primary action. Sensor lifecycle is correctly paused /
/// resumed with the app's lifecycle to avoid battery drain.
///
/// Fully theme-aware (light / dark / accent / RTL / font scale) and
/// adds nothing to the app's existing state systems — this is a
/// standalone screen, not a provider extension.
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
  double _qiblaBearing = 0; // 0..360
  double _distanceKm = 0;

  double _smoothedHeading = 0; // 0..360
  double? _rawHeading; // null = no compass event yet
  double? _accuracyDegrees;
  bool _aligned = false;
  bool _hasFiredAlignHaptic = false;
  bool _compassUnavailable = false;

  /// Reusable smoothing coefficient. Bigger = snappier dial,
  /// smaller = calmer. 0.16 strikes a comfortable balance for
  /// a Qibla compass — the user can SEE small adjustments but
  /// the dial doesn't twitch on sensor noise.
  static const double _smoothingAlpha = 0.16;

  /// How close to the Qibla bearing (in degrees, absolute) we
  /// consider "aligned" — fires the success state + haptic.
  static const double _alignThresholdDegrees = 4;

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
    // Suspend the sensor stream when we're not on screen so the
    // compass doesn't keep the magnetometer hot in the background.
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
    _pulseCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Location + permission flow ───────────────────────────

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final servicesOn = await Geolocator.isLocationServiceEnabled();
      if (!servicesOn) {
        _emitError(_QiblaError.serviceDisabled);
        // Re-bootstrap automatically when the user toggles location
        // services back on from the OS quick settings.
        _serviceSub = Geolocator.getServiceStatusStream().listen((s) {
          if (s == ServiceStatus.enabled && _error == _QiblaError.serviceDisabled) {
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

      // No custom LocationSettings — `geolocator` 11.x deprecated
      // `desiredAccuracy` in favour of a `LocationSettings` object
      // whose constructor surface differs between minor versions.
      // The default is plenty here: we ask ONCE for a fix, the
      // bearing target is the Kaaba (thousands of km away), and
      // any reasonable position gives the user a correct Qibla.
      final pos = await Geolocator.getCurrentPosition();
      final bearing = QiblaService.bearingTo(pos.latitude, pos.longitude);
      final distance = QiblaService.distanceTo(pos.latitude, pos.longitude);

      // Compass stream — bail gracefully if the platform reports
      // no magnetometer (rare but real on tablets / emulators).
      final stream = FlutterCompass.events;
      if (stream == null) {
        setState(() {
          _loading = false;
          _position = pos;
          _qiblaBearing = bearing;
          _distanceKm = distance;
          _compassUnavailable = true;
        });
        return;
      }
      _compassSub?.cancel();
      _compassSub = stream.listen(_onCompass, onError: (_) {
        // A transient sensor read failure is fine — we'll just keep
        // showing the last known heading until the next event.
      });

      // No-compass-event safety net: if nothing arrives in 3 s,
      // assume the device doesn't actually have one and switch to
      // the "compass unavailable" state instead of staying loading.
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

  // ── Compass stream ───────────────────────────────────────

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
      // Single gentle confirmation — no looping haptic.
      HapticFeedback.lightImpact();
      _hasFiredAlignHaptic = true;
      _pulseCtrl
        ..stop()
        ..repeat(reverse: true);
    } else if (!_aligned && wasAligned) {
      _hasFiredAlignHaptic = false;
      _pulseCtrl
        ..stop()
        ..value = 0;
    }
    if (mounted) setState(() {});
  }

  // ── External map action ──────────────────────────────────

  Future<void> _openExternalMap() async {
    if (_position == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&origin=${_position!.latitude},${_position!.longitude}'
      '&destination=${QiblaService.kaabaLat},${QiblaService.kaabaLng}'
      '&travelmode=driving',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silently swallow — the button is non-essential polish.
    }
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final isDark = p.themeMode == ThemeMode.dark ||
        (p.themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          p.label('qibla'),
          style: appFont(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFAF5E8),
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_position != null)
            IconButton(
              tooltip: p.label('qibla_view_on_map'),
              onPressed: _openExternalMap,
              icon: const Icon(
                Icons.public_rounded,
                color: Color(0xFFF0D89A),
              ),
            ),
        ],
        iconTheme: const IconThemeData(color: Color(0xFFFAF5E8)),
      ),
      body: _QiblaBackdrop(
        isDark: isDark,
        accent: AppColors.green,
        child: SafeArea(
          child: _buildBody(p, isDark),
        ),
      ),
    );
  }

  Widget _buildBody(AppProvider p, bool isDark) {
    if (_loading) return _LoadingView(label: p.label('qibla_locating'));
    if (_error != null) {
      return _ErrorView(
        provider: p,
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
// Background: dark royal-green gradient + soft gold glow + faint
// Islamic-pattern texture. Same visual language as the widgets.
// ────────────────────────────────────────────────────────────
class _QiblaBackdrop extends StatelessWidget {
  final bool isDark;
  final Color accent;
  final Widget child;

  const _QiblaBackdrop({
    required this.isDark,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final deep = Color.lerp(accent, Colors.black, isDark ? 0.78 : 0.66)!;
    final mid = Color.lerp(accent, Colors.black, isDark ? 0.55 : 0.34)!;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [deep, mid],
        ),
      ),
      child: Stack(
        children: [
          // Soft gold glow in the top-end corner — same recipe as
          // WidgetCardShell so the screen feels like a sibling
          // surface to the home-screen widgets.
          Positioned(
            top: -80,
            right: Directionality.of(context) == TextDirection.rtl ? null : -80,
            left: Directionality.of(context) == TextDirection.rtl ? -80 : null,
            child: Container(
              width: 320,
              height: 320,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x4FD9B45A), Color(0x00D9B45A)],
                ),
              ),
            ),
          ),
          // Faint tessellating 8-point star texture — ~3 % opacity,
          // reads as depth rather than decoration.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _QiblaPatternPainter(
                  color: Colors.white.withOpacity(0.030),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _QiblaPatternPainter extends CustomPainter {
  final Color color;
  const _QiblaPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..isAntiAlias = true
      ..color = color;
    const double tile = 72;
    const double radius = tile * 0.32;
    double y = -tile;
    int row = 0;
    while (y < size.height + tile) {
      final xOffset = (row.isOdd) ? tile / 2 : 0.0;
      double x = -tile + xOffset;
      while (x < size.width + tile) {
        _drawStar(canvas, Offset(x, y), radius, paint);
        x += tile;
      }
      y += tile * 0.85;
      row += 1;
    }
  }

  void _drawStar(Canvas c, Offset cn, double r, Paint p) {
    final path = Path();
    final inner = r * 0.5;
    for (int i = 0; i < 16; i++) {
      final a = i * (math.pi / 8);
      final rad = i.isEven ? r : inner;
      final pt = Offset(cn.dx + rad * math.cos(a), cn.dy + rad * math.sin(a));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_QiblaPatternPainter old) => old.color != color;
}

// ────────────────────────────────────────────────────────────
// Loading view — calm centred spinner with one helper line.
// ────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  final String label;
  const _LoadingView({required this.label});

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
              valueColor: AlwaysStoppedAnimation(Color(0xFFF0D89A)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: appFont(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: const Color(0xFFCBD8CF),
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
  final _QiblaError error;
  final VoidCallback onPrimary;

  const _ErrorView({
    required this.provider,
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

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.explore_outlined,
              size: 56,
              color: Color(0xFFF0D89A),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFFAF5E8),
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
                color: const Color(0xFFCBD8CF),
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
// Compass view — the screen's main composition.
// ────────────────────────────────────────────────────────────
class _CompassView extends StatelessWidget {
  final AppProvider provider;
  final Position position;
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
    final coords = _formatCoords(position.latitude, position.longitude);
    final distanceText = _formatDistance(distanceKm, p.locale);
    final bearingText = '${qiblaBearing.toStringAsFixed(0)}°';

    final accuracyLabel = compassUnavailable
        ? p.label('qibla_compass_unavailable')
        : _accuracyLabel(p, accuracyDegrees);
    final accuracyColor = compassUnavailable
        ? const Color(0xFFE57373)
        : _accuracyColor(accuracyDegrees);
    final showCalibrate = !compassUnavailable &&
        accuracyDegrees != null &&
        accuracyDegrees! > 25;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Dial size scales with the available area but caps so the
        // compass never feels lost on a wide tablet.
        final shortSide = math.min(constraints.maxWidth, constraints.maxHeight);
        final dialSize = math.min(320.0, shortSide - 64);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              Text(
                coords,
                textAlign: TextAlign.center,
                style: appFont(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFFCBD8CF),
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 14),
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
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: aligned
                    ? Text(
                        p.label('qibla_aligned'),
                        key: const ValueKey('aligned'),
                        textAlign: TextAlign.center,
                        style: appFont(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF7DD89C),
                          letterSpacing: 0.3,
                        ),
                      )
                    : const SizedBox(height: 22, key: ValueKey('idle')),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _InfoChip(
                    icon: Icons.straighten_rounded,
                    label: '$distanceText  ${p.label('qibla_to_makkah')}',
                  ),
                  const SizedBox(width: 8),
                  _InfoChip(
                    icon: Icons.explore_rounded,
                    label: '${p.label('qibla_angle')}: $bearingText',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _AccuracyChip(label: accuracyLabel, color: accuracyColor),
              if (showCalibrate) ...[
                const SizedBox(height: 10),
                Text(
                  p.label('qibla_calibrate'),
                  textAlign: TextAlign.center,
                  style: appFont(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFFE5CB8F),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  String _formatCoords(double lat, double lng) {
    String fmt(double v, String pos, String neg) {
      final hem = v >= 0 ? pos : neg;
      return '${v.abs().toStringAsFixed(2)}° $hem';
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
    if (degrees == null) return const Color(0xFFE5CB8F);
    if (degrees < 15) return const Color(0xFF7DD89C);
    if (degrees < 25) return const Color(0xFFE5CB8F);
    return const Color(0xFFE57373);
  }
}

// ────────────────────────────────────────────────────────────
// Quiet pill displaying one info atom (distance / angle / etc).
// ────────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0x1AFFFFFF),
        border: Border.all(
          color: const Color(0xFFF0D89A).withOpacity(0.18),
          width: 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFFF0D89A)),
          const SizedBox(width: 6),
          Text(
            label,
            style: appFont(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFFAF5E8),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccuracyChip extends StatelessWidget {
  final String label;
  final Color color;
  const _AccuracyChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.5), blurRadius: 6),
            ],
          ),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: appFont(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: const Color(0xFFCBD8CF),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
// Compass painter — premium Islamic dial.
// ────────────────────────────────────────────────────────────
class _CompassPainter extends CustomPainter {
  final double heading; // user's facing direction (smoothed)
  final double qiblaBearing;
  final bool aligned;
  final double pulse; // 0..1 from the pulse controller
  final bool compassUnavailable;

  static const Color _goldSoft = Color(0xFFF0D89A);
  static const Color _goldDeep = Color(0xFFC8943A);
  static const Color _textMain = Color(0xFFFAF5E8);
  static const Color _textMuted = Color(0xFFA9B7AD);
  static const Color _alignedGlow = Color(0xFF7DD89C);

  _CompassPainter({
    required this.heading,
    required this.qiblaBearing,
    required this.aligned,
    required this.pulse,
    required this.compassUnavailable,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 14;

    // Aligned pulse — soft green halo around the dial.
    if (aligned) {
      final glowR = radius + 6 + pulse * 6;
      final glow = Paint()
        ..color = _alignedGlow.withOpacity(0.35 + pulse * 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(center, glowR, glow);
    }

    // Dial face — subtle radial gold tint, no hard edges.
    final dialPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          _goldSoft.withOpacity(0.08),
          _goldSoft.withOpacity(0.015),
          Colors.transparent,
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, dialPaint);

    // Outer gold ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _goldSoft.withOpacity(0.35)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );
    // Inner decorative ring.
    canvas.drawCircle(
      center,
      radius * 0.74,
      Paint()
        ..color = _goldSoft.withOpacity(0.12)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );

    // Rotate the dial so North follows True North relative to the
    // phone's current heading.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-heading * math.pi / 180);

    // Tick marks — every 10°, with the four cardinals emphasised.
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
              ? _goldSoft.withOpacity(0.7)
              : _textMuted.withOpacity(isHalfCard ? 0.55 : 0.35)
          ..strokeWidth = isCardinal ? 1.5 : 0.7
          ..strokeCap = StrokeCap.round,
      );
    }

    // Cardinal letters — N is bolder + gold, the rest are muted.
    // Counter-rotated per letter so each glyph stays upright as
    // the dial spins.
    const cardinals = ['N', 'E', 'S', 'W'];
    for (int i = 0; i < 4; i++) {
      final a = (i * 90 - 90) * math.pi / 180;
      final pos = Offset(
        (radius - 28) * math.cos(a),
        (radius - 28) * math.sin(a),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: cardinals[i],
          style: TextStyle(
            color: i == 0 ? _goldSoft : _textMain.withOpacity(0.70),
            fontSize: i == 0 ? 19 : 14,
            fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
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

    // Qibla bearing ray + Kaaba marker — the dial's most
    // prominent element.
    final qa = (qiblaBearing - 90) * math.pi / 180;
    canvas.drawLine(
      Offset(22 * math.cos(qa), 22 * math.sin(qa)),
      Offset((radius - 30) * math.cos(qa), (radius - 30) * math.sin(qa)),
      Paint()
        ..color = aligned ? _alignedGlow : _goldDeep
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    final markerCenter = Offset(
      (radius - 20) * math.cos(qa),
      (radius - 20) * math.sin(qa),
    );
    canvas.drawCircle(
      markerCenter,
      11,
      Paint()
        ..shader = RadialGradient(
          colors: aligned
              ? const [Color(0xFF9FE3B5), Color(0xFF3F8A5E)]
              : const [_goldSoft, _goldDeep],
        ).createShader(Rect.fromCircle(center: markerCenter, radius: 11)),
    );
    // Counter-rotated Kaaba glyph at the marker.
    canvas.save();
    canvas.translate(markerCenter.dx, markerCenter.dy);
    canvas.rotate(heading * math.pi / 180);
    final ktp = TextPainter(
      text: const TextSpan(
        text: '🕋',
        style: TextStyle(fontSize: 13, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    ktp.paint(canvas, Offset(-ktp.width / 2, -ktp.height / 2));
    canvas.restore();

    canvas.restore(); // end dial rotation

    // Fixed top indicator — a small downward gold triangle just
    // above the dial showing "what the phone is pointing at".
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

    // Centre — a small hand-drawn crescent (same brand mark as the
    // home-screen widget set).
    _drawCrescent(canvas, center, 13);

    if (compassUnavailable) {
      // No sensor — draw a quiet hint inside the dial.
      final hintTp = TextPainter(
        text: const TextSpan(
          text: '—',
          style: TextStyle(
            color: Color(0xFFA9B7AD),
            fontSize: 28,
            fontWeight: FontWeight.w300,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      hintTp.paint(
        canvas,
        Offset(center.dx - hintTp.width / 2, center.dy - hintTp.height / 2),
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
      old.compassUnavailable != compassUnavailable;
}
