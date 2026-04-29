import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/notification_settings.dart';
import '../providers/app_provider.dart';
import '../services/notification_service.dart';

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
  static const _bg = Color(0xFFE9EAEC);
  static const _cardWhite = Colors.white;
  static const _blue = Color(0xFF0A7CFF);
  static const _separator = Color(0xFFE2E3E5);
  static const _label = Color(0xFF1C1C1E);
  static const _sub = Color(0xFF8E8E93);

  // Localized text helpers — all user-facing strings on this screen
  // route through here so the screen follows the chosen UI locale.
  String _t(String locale, _Tr key) => key.value(locale);

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final s = p.notificationSettings;
    final loc = p.locale;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: _label),
        title: Text(
          _t(loc, _Tr.title),
          style: GoogleFonts.cairo(
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
        titleColor: _blue,
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
              const _Divider(),
              _radioRow(
                label: _t(loc, _Tr.discret),
                selected: s.mode == NotificationMode.discret,
                onTap: () => p.updateNotificationSettings(
                  (cur) => cur.copyWith(mode: NotificationMode.discret),
                ),
              ),
              const _Divider(),
              _row(
                title: _t(loc, _Tr.popup),
                trailing: _iosSwitch(
                  value: s.popupEnabled,
                  onChanged: (v) => p.updateNotificationSettings(
                    (cur) => cur.copyWith(popupEnabled: v),
                  ),
                ),
              ),
              const _Divider(),
              _soundRow(p, s, loc),
              const _Divider(),
              _row(
                title: _t(loc, _Tr.vibrator),
                trailing: _iosSwitch(
                  value: s.vibrationEnabled,
                  onChanged: (v) => p.updateNotificationSettings(
                    (cur) => cur.copyWith(vibrationEnabled: v),
                  ),
                ),
              ),
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
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      color: _label,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: _blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _sub),
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
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    color: _label,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '${(s.volume * 100).round()}%',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: _sub,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.volume_down_rounded, color: _sub, size: 20),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _blue,
                    inactiveTrackColor: _separator,
                    thumbColor: Colors.white,
                    overlayColor: _blue.withValues(alpha: 0.15),
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
              const Icon(Icons.volume_up_rounded, color: _sub, size: 20),
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
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      color: _label,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: _blue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: _sub),
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
        icon: const Icon(Icons.notifications_active_rounded, color: _blue),
        label: Text(
          _t(loc, _Tr.sendTest),
          style: GoogleFonts.cairo(
            color: _blue,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Bottom sheets ────────────────────────────────────────
  void _openSoundPicker(AppProvider p, NotificationSettings s, String loc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        NotificationSound selected = s.sound;
        return StatefulBuilder(
          builder: (ctx, setSheet) => _sheet(
            title: _t(loc, _Tr.soundTitle),
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
        color: _cardWhite,
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
    Color titleColor = _label,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: titleColor,
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
                style: GoogleFonts.cairo(
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
          color: selected ? _blue : _sub,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: _blue,
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
      activeTrackColor: _blue,
    );
  }

  Widget _sheet({required String title, required List<Widget> children}) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      title,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _label,
                      ),
                    ),
                  ),
                  const _Divider(),
                  ...children.where((w) => w is! _SheetCancelMarker),
                ],
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
                style: GoogleFonts.cairo(
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: () => Navigator.pop(ctx),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                _t(loc, _Tr.cancel),
                style: GoogleFonts.cairo(
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
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
        height: 1,
        margin: const EdgeInsets.only(left: 16),
        color: const Color(0xFFE2E3E5),
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
        return loc == 'ar' ? 'إشعارات الأجندة'
            : loc == 'es' ? 'Notificaciones de la agenda'
            : loc == 'en' ? 'Calendar notifications'
            : "Notifications d'Agenda";
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
