import 'dart:convert';

enum NotificationMode { alert, discret }

enum LockScreenVisibility { hideContent, doNotShow }

enum NotificationSound { brightline, alpha, arrow, custom }

extension NotificationSoundX on NotificationSound {
  String get key {
    switch (this) {
      case NotificationSound.brightline:
        return 'brightline';
      case NotificationSound.alpha:
        return 'alpha';
      case NotificationSound.arrow:
        return 'arrow';
      case NotificationSound.custom:
        return 'custom';
    }
  }

  String get displayName {
    switch (this) {
      case NotificationSound.brightline:
        return 'Brightline';
      case NotificationSound.alpha:
        return 'Alpha';
      case NotificationSound.arrow:
        return 'Arrow';
      case NotificationSound.custom:
        return 'Personnalisé';
    }
  }

  static NotificationSound fromKey(String? key) {
    switch (key) {
      case 'alpha':
        return NotificationSound.alpha;
      case 'arrow':
        return NotificationSound.arrow;
      case 'custom':
        return NotificationSound.custom;
      case 'brightline':
      default:
        return NotificationSound.brightline;
    }
  }
}

class NotificationSettings {
  final bool enabled;
  final NotificationMode mode;
  final bool popupEnabled;
  final bool vibrationEnabled;
  final NotificationSound sound;
  final String? customSoundPath;
  final double volume;
  final LockScreenVisibility lockScreenVisibility;

  const NotificationSettings({
    this.enabled = true,
    this.mode = NotificationMode.alert,
    this.popupEnabled = false,
    this.vibrationEnabled = false,
    this.sound = NotificationSound.brightline,
    this.customSoundPath,
    this.volume = 1.0,
    this.lockScreenVisibility = LockScreenVisibility.hideContent,
  });

  NotificationSettings copyWith({
    bool? enabled,
    NotificationMode? mode,
    bool? popupEnabled,
    bool? vibrationEnabled,
    NotificationSound? sound,
    String? customSoundPath,
    bool clearCustomSoundPath = false,
    double? volume,
    LockScreenVisibility? lockScreenVisibility,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      popupEnabled: popupEnabled ?? this.popupEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      sound: sound ?? this.sound,
      customSoundPath: clearCustomSoundPath
          ? null
          : (customSoundPath ?? this.customSoundPath),
      volume: volume ?? this.volume,
      lockScreenVisibility: lockScreenVisibility ?? this.lockScreenVisibility,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'mode': mode.name,
        'popupEnabled': popupEnabled,
        'vibrationEnabled': vibrationEnabled,
        'sound': sound.key,
        'customSoundPath': customSoundPath,
        'volume': volume,
        'lockScreenVisibility': lockScreenVisibility.name,
      };

  factory NotificationSettings.fromJson(Map<String, dynamic> j) {
    return NotificationSettings(
      enabled: (j['enabled'] as bool?) ?? true,
      mode: NotificationMode.values.firstWhere(
        (e) => e.name == j['mode'],
        orElse: () => NotificationMode.alert,
      ),
      popupEnabled: (j['popupEnabled'] as bool?) ?? false,
      vibrationEnabled: (j['vibrationEnabled'] as bool?) ?? false,
      sound: NotificationSoundX.fromKey(j['sound'] as String?),
      customSoundPath: j['customSoundPath'] as String?,
      volume: (j['volume'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 1.0,
      lockScreenVisibility: LockScreenVisibility.values.firstWhere(
        (e) => e.name == j['lockScreenVisibility'],
        orElse: () => LockScreenVisibility.hideContent,
      ),
    );
  }

  String encode() => jsonEncode(toJson());

  factory NotificationSettings.decode(String source) {
    if (source.isEmpty) return const NotificationSettings();
    return NotificationSettings.fromJson(
        jsonDecode(source) as Map<String, dynamic>);
  }

  /// Stable ID hash used to derive a unique Android channel per
  /// distinct combination of audio/visual parameters.
  String get channelSignature {
    final soundPart = sound == NotificationSound.custom
        ? 'custom_${(customSoundPath ?? '').hashCode.abs()}'
        : sound.key;
    return '${mode.name}_${soundPart}_v${(volume * 10).round()}'
        '_vib${vibrationEnabled ? 1 : 0}'
        '_pop${popupEnabled ? 1 : 0}'
        '_lock${lockScreenVisibility.name}';
  }
}
