import 'package:flutter/material.dart';

import '../theme.dart';

/// "Rationale" dialog shown before we request the GPS permission
/// or run a one-shot location read.
///
/// Why a rationale dialog at all?
///   * Google Play's permission policy requires apps to explain
///     WHY they need a sensitive permission BEFORE the OS prompt
///     appears. Apps that just trigger the system dialog "out of
///     the blue" risk a Play Console warning and a worse grant
///     rate from suspicious users.
///   * The user asked for an explicit "the app should tell the
///     user to allow GPS" message — that's exactly this dialog.
///
/// Behaviour
///   * Returns `true` if the user taps the primary CTA ("Allow"),
///     `false` if they tap Cancel or dismiss with the system back
///     gesture. Callers must treat `false` as a graceful no-op,
///     not an error.
///   * Strings are inlined per-locale because this is a one-shot
///     dialog with five translation slots — going through the
///     provider's `label(...)` map for five new keys would be
///     more boilerplate than the dialog body itself.
///   * Used in two places today:
///       - Onboarding's "Auto-detect" card (first launch).
///       - Settings → Hijri source → "Auto-detect" pill.
///     A future caller (e.g. a "switch to my current trip
///     country" hint) can drop in with no further work.
Future<bool> showGpsRationaleDialog({
  required BuildContext context,
  required String locale,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  // Localized strings. Keep them short enough that the dialog
  // doesn't push the CTAs below the fold on a small screen.
  final title = switch (locale) {
    'ar' => 'السماح بالوصول إلى الموقع',
    'fr' => 'Autoriser l\'accès à la position',
    'es' => 'Permitir el acceso a la ubicación',
    _ => 'Allow location access',
  };
  final body = switch (locale) {
    'ar' =>
      'يحتاج التطبيق إلى موقعك لتحديد بلدك تلقائياً '
          'واختيار التقويم الرسمي المناسب.\n\n'
          'لا يُرسل موقعك إلى أي خادم — يُستعمل محلياً على '
          'هاتفك فقط.',
    'fr' =>
      'L\'application a besoin de votre position pour détecter '
          'automatiquement votre pays et choisir le calendrier '
          'officiel adapté.\n\n'
          'Votre position n\'est envoyée à aucun serveur — '
          'elle est utilisée uniquement sur votre téléphone.',
    'es' =>
      'La aplicación necesita tu ubicación para detectar '
          'automáticamente tu país y elegir el calendario '
          'oficial adecuado.\n\n'
          'Tu ubicación no se envía a ningún servidor — se '
          'usa únicamente en tu teléfono.',
    _ =>
      'The app needs your location to automatically detect your '
          'country and pick the right official calendar.\n\n'
          'Your location is never sent to any server — it stays '
          'on your device.',
  };
  final allow = switch (locale) {
    'ar' => 'السماح',
    'fr' => 'Autoriser',
    'es' => 'Permitir',
    _ => 'Allow',
  };
  final cancel = switch (locale) {
    'ar' => 'إلغاء',
    'fr' => 'Annuler',
    'es' => 'Cancelar',
    _ => 'Cancel',
  };

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    // Route through the root navigator so the dialog is hosted
    // ABOVE any local routes (PageView inside Onboarding, nested
    // ModalBottomSheets, etc.) — without this, a dialog opened
    // from inside a PageView page can occasionally be obscured
    // by the page's own Material ancestor and the user sees a
    // dim barrier but no dialog content.
    useRootNavigator: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => Dialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hero icon in the accent color so the dialog
            // visually echoes the source picker and the Qibla
            // screen (which also uses location).
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppColors.green,
                    Color.lerp(AppColors.green, Colors.black, 0.25)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.green.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.my_location_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.darkText : AppColors.text,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? AppColors.darkText2
                    : AppColors.text2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      cancel,
                      style: appFont(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkText3
                            : AppColors.text3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      allow,
                      style: appFont(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  return result ?? false;
}

/// Sister dialog to [showGpsRationaleDialog] — shown when the
/// device's master Location switch is OFF. Granting the app
/// permission won't help in that state because no chip is
/// providing positions, so we route the user to the OS-level
/// settings page instead of triggering a useless permission
/// request.
///
/// Returns `true` if the user tapped "Open settings" (caller
/// should then call `CountryDetector.openLocationSettings()`),
/// `false` on Cancel / dismiss.
Future<bool> showGpsServiceOffDialog({
  required BuildContext context,
  required String locale,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final title = switch (locale) {
    'ar' => 'GPS متوقّف على الجهاز',
    'fr' => 'GPS désactivé sur l\'appareil',
    'es' => 'GPS desactivado en el dispositivo',
    _ => 'Location is OFF on this device',
  };
  final body = switch (locale) {
    'ar' =>
      'لتحديد بلدك تلقائياً، يجب أوّلاً تفعيل الموقع (GPS) '
          'من إعدادات الهاتف.\n\n'
          'اضغط "فتح الإعدادات" لتفعيله، ثم ارجع وأعد المحاولة.',
    'fr' =>
      'Pour détecter automatiquement votre pays, activez '
          'd\'abord la localisation (GPS) dans les réglages '
          'du téléphone.\n\n'
          'Appuyez sur "Ouvrir les réglages", activez-la, '
          'puis revenez et réessayez.',
    'es' =>
      'Para detectar tu país automáticamente, activa primero '
          'la ubicación (GPS) en los ajustes del teléfono.\n\n'
          'Pulsa "Abrir ajustes", actívala y vuelve para '
          'reintentar.',
    _ =>
      'To auto-detect your country, first turn ON Location '
          '(GPS) in your phone\'s system settings.\n\n'
          'Tap "Open settings", flip the switch, then come '
          'back and try again.',
  };
  final openSettings = switch (locale) {
    'ar' => 'فتح الإعدادات',
    'fr' => 'Ouvrir les réglages',
    'es' => 'Abrir ajustes',
    _ => 'Open settings',
  };
  final cancel = switch (locale) {
    'ar' => 'إلغاء',
    'fr' => 'Annuler',
    'es' => 'Cancelar',
    _ => 'Cancel',
  };

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    useRootNavigator: true,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => Dialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning-tinted icon — gold instead of green, so
            // the user feels they need to ACT (vs. just
            // consent in the rationale dialog).
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFF0D89A),
                    Color(0xFFC8943A),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.darkText : AppColors.text,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 12.5,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? AppColors.darkText2
                    : AppColors.text2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      cancel,
                      style: appFont(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkText3
                            : AppColors.text3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC8943A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      openSettings,
                      style: appFont(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  return result ?? false;
}
