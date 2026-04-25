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

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    final s = p.notificationSettings;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: _label),
        title: Text(
          'Notifications d\'Agenda',
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
            _buildAuthorizationCard(p, s),
            const SizedBox(height: 18),
            _buildMainCard(p, s),
            const SizedBox(height: 24),
            _buildTestButton(),
          ],
        ),
      ),
    );
  }

  // ── 1. Authorization toggle ──────────────────────────────
  Widget _buildAuthorizationCard(AppProvider p, NotificationSettings s) {
    return _card(
      child: _row(
        title: 'Autorisation des notifications',
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
  Widget _buildMainCard(AppProvider p, NotificationSettings s) {
    final disabled = !s.enabled;
    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: IgnorePointer(
        ignoring: disabled,
        child: _card(
          child: Column(
            children: [
              _radioRow(
                label: 'Alerte',
                selected: s.mode == NotificationMode.alert,
                onTap: () => p.updateNotificationSettings(
                  (cur) => cur.copyWith(mode: NotificationMode.alert),
                ),
              ),
              const _Divider(),
              _radioRow(
                label: 'Discret',
                selected: s.mode == NotificationMode.discret,
                onTap: () => p.updateNotificationSettings(
                  (cur) => cur.copyWith(mode: NotificationMode.discret),
                ),
              ),
              const _Divider(),
              _row(
                title: 'Affichage sous forme de pop-up',
                trailing: _iosSwitch(
                  value: s.popupEnabled,
                  onChanged: (v) => p.updateNotificationSettings(
                    (cur) => cur.copyWith(popupEnabled: v),
                  ),
                ),
              ),
              const _Divider(),
              _soundRow(p, s),
              const _Divider(),
              _volumeRow(p, s),
              const _Divider(),
              _row(
                title: 'Vibreur',
                trailing: _iosSwitch(
                  value: s.vibrationEnabled,
                  onChanged: (v) => p.updateNotificationSettings(
                    (cur) => cur.copyWith(vibrationEnabled: v),
                  ),
                ),
              ),
              const _Divider(),
              _lockScreenRow(p, s),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sound row with sub-screen ────────────────────────────
  Widget _soundRow(AppProvider p, NotificationSettings s) {
    final label = s.sound == NotificationSound.custom &&
            (s.customSoundPath?.isNotEmpty ?? false)
        ? _basename(s.customSoundPath!)
        : s.sound.displayName;
    return InkWell(
      onTap: () => _openSoundPicker(p, s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Son',
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

  Widget _volumeRow(AppProvider p, NotificationSettings s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Volume des notifications',
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
  Widget _lockScreenRow(AppProvider p, NotificationSettings s) {
    final label = s.lockScreenVisibility == LockScreenVisibility.doNotShow
        ? 'Ne pas afficher les notifications'
        : 'Masquer le contenu';
    return InkWell(
      onTap: () => _openLockScreenSheet(p, s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Écran de verrouillage',
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
  Widget _buildTestButton() {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          await NotificationService().showTestNotification();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notification test envoyée')),
          );
        },
        icon: const Icon(Icons.notifications_active_rounded, color: _blue),
        label: Text(
          'Envoyer une notification test',
          style: GoogleFonts.cairo(
            color: _blue,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ── Bottom sheets ────────────────────────────────────────
  void _openSoundPicker(AppProvider p, NotificationSettings s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        NotificationSound selected = s.sound;
        return StatefulBuilder(
          builder: (ctx, setSheet) => _sheet(
            title: 'Son de notification',
            children: [
              for (final option in NotificationSound.values)
                _sheetOption(
                  label: option == NotificationSound.custom
                      ? 'Personaliser'
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
              _sheetCancel(ctx),
            ],
          ),
        );
      },
    );
  }

  void _openLockScreenSheet(AppProvider p, NotificationSettings s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _sheet(
          title: 'Écran de verrouillage',
          children: [
            _sheetOption(
              label: 'Masquer le contenu',
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
              label: 'Ne pas afficher les notifications',
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
            _sheetCancel(ctx),
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

  Widget _sheetCancel(BuildContext ctx) {
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
                'Annuler',
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
