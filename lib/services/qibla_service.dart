import 'dart:math' as math;

/// Pure-math helpers for the Qibla screen.
///
/// No sensors, no I/O, no async — everything in here is a
/// deterministic function of its inputs so the Qibla feature can
/// be reasoned about (and unit-tested later) without spinning up
/// platform plugins.
///
/// Holy reference point is the Kaaba in Makkah (constants below),
/// matching what every standard Islamic Qibla utility uses.
class QiblaService {
  QiblaService._();

  /// Latitude of the Kaaba, in degrees (WGS-84).
  static const double kaabaLat = 21.4225;

  /// Longitude of the Kaaba, in degrees (WGS-84).
  static const double kaabaLng = 39.8262;

  /// Mean Earth radius in kilometres — the value used by every
  /// standard Haversine implementation.
  static const double earthRadiusKm = 6371.0;

  /// Initial great-circle bearing from `(lat, lng)` to the Kaaba,
  /// in degrees clockwise from True North (0..360).
  ///
  /// "Initial" because along a great-circle path the bearing
  /// rotates as you travel; we report the angle at the starting
  /// point, which is what the user needs to face right now to
  /// pray in the Qibla direction.
  static double bearingTo(double lat, double lng) {
    final lat1 = lat * math.pi / 180;
    const lat2 = kaabaLat * math.pi / 180;
    final dLng = (kaabaLng - lng) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  /// Great-circle distance from `(lat, lng)` to the Kaaba, in
  /// kilometres. Haversine formula — accurate enough for the
  /// "city to Makkah" display we show under the compass.
  static double distanceTo(double lat, double lng) {
    final lat1 = lat * math.pi / 180;
    const lat2 = kaabaLat * math.pi / 180;
    final dLat = (kaabaLat - lat) * math.pi / 180;
    final dLng = (kaabaLng - lng) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Exponential moving average over a circular range (0..360).
  /// Handles the 0/360 wrap-around correctly — without this an
  /// even-step rotation between 350° and 10° would briefly snap
  /// through the long way round and look like jitter.
  ///
  /// `alpha` is the smoothing coefficient: bigger = snappier,
  /// smaller = calmer. ~0.15 is a good compass default.
  static double smoothHeading(
      double previous, double current, double alpha) {
    double delta = current - previous;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    double result = previous + alpha * delta;
    if (result < 0) result += 360;
    if (result >= 360) result -= 360;
    return result;
  }

  /// Shortest signed angular distance from `from` to `to`, in
  /// degrees, in the range [-180, 180]. Used to decide whether
  /// the user is currently facing the Qibla (delta absolute value
  /// below the alignment threshold).
  static double shortestAngleDelta(double from, double to) {
    double d = to - from;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d;
  }
}
