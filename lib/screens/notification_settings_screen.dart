import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/notification_settings.dart';
import '../providers/app_provider.dart';
import '../services/notification_service.dart';
import '../theme.dart';

/// Notification settings screen.
/// UI strictly matches the provided iOS-style screenshots:
///   - Toggle: Autorisation des notifications
///   - Radios: Alerte / Discret
///   - Switch: Affichage sous forme de pop-up
///   - Sound: Brightline / Alpha / Arrow / Personaliser
///   - Slider: Volume des notifications
///   - Switch: Vibreur
///   - Lock screen: Masquer le contenu / Ne pas afficher les notifications
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  /// Whether the user has dark theme enabled. Refreshed at the
  /// top of every `build` from the live AppProvider. All the
  /// colour getters below derive their value from this flag.
  bool _isDark = false;

  // ── Theme-aware palette ──────────────────────────────────
  // Replaces the previous hardcoded iOS-blue/light-only palette
  // so the Notifications screen finally lines up with the rest
  // of the app and supports dark mode end-to-end.
  Color get _bg        => _isDark ? AppColors.darkBg      : AppColors.bg;
  Color get _surface   => _isDark ? AppColors.darkSurface : AppColors.white;
  Color get _label     => _isDark ? AppColors.darkText    : AppColors.text;
  Color get _sub       => _isDark ? AppColors.darkText3   : AppColors.text3;
  Color get _separator => _isDark ? AppColors.darkBorder  : AppColors.border;

  /// Primary brand accent. The whole notification screen used
  /// to render in iOS-blue (`0xFF0A7CFF`) — now it picks up the
  /// app's regional/theme-aware green so every screen reads as
  /// part of the same visual identity.
  Color get _accent => AppColors.green;

  // Localized text helpers — all user-facing strings on this screen
  // route through here so the screen follows the chosen UI locale.
  String _t(String locale, _Tr key) => key.value(locale);

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    _isDark = p.themeMode == ThemeMode.dark;
    final s = p.notificationSettings;
    final loc = p.locale;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: _label),
        title: Text(
          _t(loc, _Tr.title),
          style: appFont(
            color: _label,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _buildAuthorizationCard(p, s, loc),
            const SizedBox(height: 18),
            _buildMainCard(p, s, loc),
            const SizedBox(height: 24),
            _buildTestButton(loc),
          ],
        ),
      ),
    );
  }

  // ── 1. Authorization toggle ──────────────────────────────
  Widget _buildAuthorizationCard(
      AppProvider p, NotificationSettings s, String loc) {
    return _card(
      child: _row(
        title: _t(loc, _Tr.authorization),
        titleColor: _accent,
        trailing: _iosSwitch(
          value: s.enabled,
          onChanged: (v) => p.updateNotificationSettings(
            (cur) => cur.copyWith(enabled: v),
          ),
        ),
      ),
    );
  }

  // ── 2. Main card: mode + popup + sound + volume + vibrate + lock ──
  Widget _buildMainCard(AppProvider p, NotificationSettings s, String loc) {
    final disabled = !s.enabled;
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: IgnorePointer(
        ignoring: disabled,
        child: _card(
          child: Column(
            children: [
              _radioRow(
                label: _t(loc, _Tr.alert),
                selected: s.mode == NotificationMode.alert,
                onTap: () => p.updateNotificationSettings(
                  (cur) => cur.copyWith(mode: NotificationMode.alert),
                ),
              ),
              _Divider(color: _separator),
              _radioRow(
                label: _t(loc, _Tr.discret),
                selected: s.mode == NotificationMode.discret,
                onTap: () => p.updateNotificationSettings(
                  (cur) => cur.copyWith(mode: NotificationMode.discret),
                ),
              ),
              _Divider(color: _separator),
              _row(
                title: _t(loc, _Tr.popup),
                trailing: _iosSwitch(
                  value: s.popupEnabled,
                  onChanged: (v) => p.updateNotificationSettings(
                    (cur) => cur.copyWith(popupEnabled: v),
                  ),
                ),
              ),
              _Divider(color: _separator),
              _soundRow(p, s, loc),
              _Divider(color: _separator),
              // Volume slider — restored here so it remains
              // available for both the agenda notification surface
              // and the per-event reminder surface (both routes
              // open this screen). It was previously removed from
              // the main app Settings only.
              _volumeRow(p, s, loc),
              _Divider(color: _separator),
              _row(
                title: _t(loc, _Tr.vibrator),
                trailing: _iosSwitch(
                  value: s.vibrationEnabled,
                  onChanged: (v) => p.updateNotificationSettings(
                    (cur) => cur.copyWith(vibrationEnabled: v),
                  ),
                ),
              ),
              _Divider(color: _separator),
              // Lock-screen visibility selector — restored alongside
              // the volume slider for the same reason.
              _lockScreenRow(p, s, loc),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sound row with sub-screen ────────────────────────────
  Widget _soundRow(AppProvider p, NotificationSettings s, String loc) {
    final label = s.sound == NotificationSound.custom &&
            (s.customSoundPath?.isNotEmpty ?? false)
        ? _basename(s.customSoundPath!)
        : _localizedSoundName(s.sound, loc);
    return InkWell(
      onTap: () => _openSoundPicker(p, s, loc),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(loc, _Tr.sound),
                    style: appFont(
                      fontSize: 16,
                      color: _label,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: appFont(
                      fontSize: 13,
                      color: _accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _sub),
          ],
        ),
      ),
    );
  }

  String _localizedSoundName(NotificationSound s, String loc) {
    if (s == NotificationSound.custom) {
      return loc == 'ar' ? 'مخصّص'
          : loc == 'es' ? 'Personalizado'
          : loc == 'en' ? 'Custom'
          : 'Personnalisé';
    }
    return s.displayName; // Brightline / Alpha / Arrow are brand names
  }

  Widget _volumeRow(AppProvider p, NotificationSettings s, String loc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t(loc, _Tr.volume),
                  style: appFont(
                    fontSize: 16,
                    color: _label,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${(s.volume * 100).round()}%',
                style: appFont(
                  fontSize: 13,
                  color: _sub,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Icon(Icons.volume_down_rounded, color: _sub, size: 20),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _accent,
                    inactiveTrackColor: _separator,
                    thumbColor: Colors.white,
                    overlayColor: _accent.withValues(alpha: 0.15),
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 9),
                  ),
                  child: Slider(
                    value: s.volume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) => p.updateNotificationSettings(
                      (cur) => cur.copyWith(volume: v),
                      previewSound: false,
                    ),
                    onChangeEnd: (v) {
                      NotificationService().previewSound();
                    },
                  ),
                ),
              ),
              Icon(Icons.volume_up_rounded, color: _sub, size: 20),
            ],
          ),
        ],
      ),
    );
  }

  // ── Lock screen action sheet ─────────────────────────────
  Widget _lockScreenRow(AppProvider p, NotificationSettings s, String loc) {
    final label = s.lockScreenVisibility == LockScreenVisibility.doNotShow
        ? _t(loc, _Tr.lockDoNotShow)
        : _t(loc, _Tr.lockHideContent);
    return InkWell(
      onTap: () => _openLockScreenSheet(p, s, loc),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(loc, _Tr.lockScreen),
                    style: appFont(
                      fontSize: 16,
                      color: _label,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: appFont(
                      fontSize: 13,
                      color: _accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _sub),
          ],
        ),
      ),
    );
  }

  // ── Test button ──────────────────────────────────────────
  Widget _buildTestButton(String loc) {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          await NotificationService().showTestNotification();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_t(loc, _Tr.testSent))),
          );
        },
        icon: Icon(Icons.notifications_active_rounded, color: _accent),
        label: Text(
          _t(loc, _Tr.sendTest),
          style: appFont(
            color: _accent,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Bottom sheets ────────────────────────────────────────
  //
  // The sound picker has to fit 11 rows (10 built-in tones +
  // "Custom"). The previous version called `showModalBottomSheet`
  // with its default constraints (≤ ~50 % of screen height) and
  // an unscrollable `Column`, so once the list overflowed the
  // sheet, everything past the visible area was silently clipped
  // — that's why users only saw 7 sounds and "Custom" was
  // missing. Fix: opt in to `isScrollControlled: true`, cap at
  // 80 % of viewport, and make the option list itself scrollable.
  void _openSoundPicker(AppProvider p, NotificationSettings s, String loc) {
    final viewport = MediaQuery.of(context).size.height;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: viewport * 0.85),
      builder: (ctx) {
        NotificationSound selected = s.sound;
        return StatefulBuilder(
          builder: (ctx, setSheet) => _sheet(
            title: _t(loc, _Tr.soundTitle),
            scrollable: true,
            children: [
              for (final option in NotificationSound.values)
                _sheetOption(
                  label: option == NotificationSound.custom
                      ? _t(loc, _Tr.customize)
                      : option.displayName,
                  selected: selected == option,
                  onTap: () async {
                    setSheet(() => selected = option);
                    if (option == NotificationSound.custom) {
                      final res = await FilePicker.platform.pickFiles(
                        type: FileType.audio,
                        allowMultiple: false,
                      );
                      if (res != null && res.files.single.path != null) {
                        final path = res.files.single.path!;
                        await p.updateNotificationSettings(
                          (cur) => cur.copyWith(
                            sound: NotificationSound.custom,
                            customSoundPath: path,
                          ),
                        );
                      } else {
                        return;
                      }
                    } else {
                      await p.updateNotificationSettings(
                        (cur) => cur.copyWith(
                          sound: option,
                          clearCustomSoundPath: true,
                        ),
                      );
                    }
                    NotificationService().previewSound();
                    if (mounted) Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 8),
              _sheetCancel(ctx, loc),
            ],
          ),
        );
      },
    );
  }

  void _openLockScreenSheet(AppProvider p, NotificationSettings s, String loc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _sheet(
          title: _t(loc, _Tr.lockScreen),
          children: [
            _sheetOption(
              label: _t(loc, _Tr.lockHideContent),
              selected:
                  s.lockScreenVisibility == LockScreenVisibility.hideContent,
              onTap: () async {
                await p.updateNotificationSettings(
                  (cur) => cur.copyWith(
                    lockScreenVisibility: LockScreenVisibility.hideContent,
                  ),
                );
                if (mounted) Navigator.pop(ctx);
              },
            ),
            _sheetOption(
              label: _t(loc, _Tr.lockDoNotShow),
              selected:
                  s.lockScreenVisibility == LockScreenVisibility.doNotShow,
              onTap: () async {
                await p.updateNotificationSettings(
                  (cur) => cur.copyWith(
                    lockScreenVisibility: LockScreenVisibility.doNotShow,
                  ),
                );
                if (mounted) Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
            _sheetCancel(ctx, loc),
          ],
        );
      },
    );
  }

  // ── Reusable widgets ─────────────────────────────────────
  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _row({
    required String title,
    required Widget trailing,
    Color? titleColor,
  }) {
    final resolvedColor = titleColor ?? _label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: appFont(
                fontSize: 16,
                color: resolvedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _radioRow({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _radio(selected),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: appFont(
                  fontSize: 16,
                  color: _label,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _radio(bool selected) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? _accent : _sub,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }

  Widget _iosSwitch({required bool value, required ValueChanged<bool> onChanged}) {
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeColor: Colors.white,
      activeTrackColor: _accent,
    );
  }

  Widget _sheet({
    required String title,
    required List<Widget> children,
    bool scrollable = false,
  }) {
    // The option rows (everything except the dedicated cancel
    // marker) get wrapped in a scroll view when the caller asks
    // for it — that's how the 11-row sound picker stops getting
    // its tail clipped by the modal-sheet's height constraint.
    final options =
        children.where((w) => w is! _SheetCancelMarker).toList();
    final optionsBlock = scrollable
        ? Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: options,
              ),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: options,
          );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        title,
                        style: appFont(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _label,
                        ),
                      ),
                    ),
                    _Divider(color: _separator),
                    optionsBlock,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...children.whereType<_SheetCancelMarker>().map((w) => w.child),
          ],
        ),
      ),
    );
  }

  Widget _sheetOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _radio(selected),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: appFont(
                  fontSize: 15,
                  color: _label,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetCancel(BuildContext ctx, String loc) {
    return _SheetCancelMarker(
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: () => Navigator.pop(ctx),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                _t(loc, _Tr.cancel),
                style: appFont(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _label,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }
}

class _Divider extends StatelessWidget {
  /// Optional override so callers can pass the theme-aware
  /// `_separator` getter; falls back to the legacy light-mode
  /// separator if not supplied.
  final Color? color;
  const _Divider({this.color});
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.only(left: 16),
        color: color ?? const Color(0xFFE2E3E5),
      );
}

class _SheetCancelMarker extends StatelessWidget {
  final Widget child;
  const _SheetCancelMarker({required this.child});
  @override
  Widget build(BuildContext context) => child;
}

// ─── Localization keys ──────────────────────────────────────────────
//
// All user-facing strings on this screen route through _Tr so the
// content follows the chosen UI locale (ar / fr / en / es).
enum _Tr {
  title,
  authorization,
  alert,
  discret,
  popup,
  sound,
  soundTitle,
  customize,
  volume,
  vibrator,
  lockScreen,
  lockHideContent,
  lockDoNotShow,
  cancel,
  sendTest,
  testSent,
}

extension _TrX on _Tr {
  String value(String loc) {
    switch (this) {
      case _Tr.title:
        return loc == 'ar' ? 'الإشعارات'
            : loc == 'es' ? 'Notificaciones'
            : loc == 'en' ? 'Notifications'
            : 'Notifications';
      case _Tr.authorization:
        return loc == 'ar' ? 'السماح بالإشعارات'
            : loc == 'es' ? 'Autorización de notificaciones'
            : loc == 'en' ? 'Allow notifications'
            : 'Autorisation des notifications';
      case _Tr.alert:
        return loc == 'ar' ? 'تنبيه'
            : loc == 'es' ? 'Alerta'
            : loc == 'en' ? 'Alert'
            : 'Alerte';
      case _Tr.discret:
        return loc == 'ar' ? 'صامت'
            : loc == 'es' ? 'Discreto'
            : loc == 'en' ? 'Silent'
            : 'Discret';
      case _Tr.popup:
        return loc == 'ar' ? 'العرض كنافذة منبثقة'
            : loc == 'es' ? 'Mostrar como ventana emergente'
            : loc == 'en' ? 'Show as pop-up'
            : 'Affichage sous forme de pop-up';
      case _Tr.sound:
        return loc == 'ar' ? 'الصوت'
            : loc == 'es' ? 'Sonido'
            : loc == 'en' ? 'Sound'
            : 'Son';
      case _Tr.soundTitle:
        return loc == 'ar' ? 'صوت الإشعار'
            : loc == 'es' ? 'Sonido de notificación'
            : loc == 'en' ? 'Notification sound'
            : 'Son de notification';
      case _Tr.customize:
        return loc == 'ar' ? 'تخصيص'
            : loc == 'es' ? 'Personalizar'
            : loc == 'en' ? 'Customize'
            : 'Personaliser';
      case _Tr.volume:
        return loc == 'ar' ? 'مستوى صوت الإشعارات'
            : loc == 'es' ? 'Volumen de notificaciones'
            : loc == 'en' ? 'Notification volume'
            : 'Volume des notifications';
      case _Tr.vibrator:
        return loc == 'ar' ? 'الاهتزاز'
            : loc == 'es' ? 'Vibración'
            : loc == 'en' ? 'Vibration'
            : 'Vibreur';
      case _Tr.lockScreen:
        return loc == 'ar' ? 'شاشة القفل'
            : loc == 'es' ? 'Pantalla de bloqueo'
            : loc == 'en' ? 'Lock screen'
            : 'Écran de verrouillage';
      case _Tr.lockHideContent:
        return loc == 'ar' ? 'إخفاء المحتوى'
            : loc == 'es' ? 'Ocultar el contenido'
            : loc == 'en' ? 'Hide content'
            : 'Masquer le contenu';
      case _Tr.lockDoNotShow:
        return loc == 'ar' ? 'عدم إظهار الإشعارات'
            : loc == 'es' ? 'No mostrar las notificaciones'
            : loc == 'en' ? "Don't show notifications"
            : 'Ne pas afficher les notifications';
      case _Tr.cancel:
        return loc == 'ar' ? 'إلغاء'
            : loc == 'es' ? 'Cancelar'
            : loc == 'en' ? 'Cancel'
            : 'Annuler';
      case _Tr.sendTest:
        return loc == 'ar' ? 'إرسال إشعار تجريبي'
            : loc == 'es' ? 'Enviar una notificación de prueba'
            : loc == 'en' ? 'Send a test notification'
            : 'Envoyer une notification test';
      case _Tr.testSent:
        return loc == 'ar' ? 'تم إرسال إشعار تجريبي'
            : loc == 'es' ? 'Notificación de prueba enviada'
            : loc == 'en' ? 'Test notification sent'
            : 'Notification test envoyée';
    }
  }
}
