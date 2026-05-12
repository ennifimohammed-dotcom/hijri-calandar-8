import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_settings.dart';
import '../utils/app_logger.dart';

class NotificationSettingsService {
  static const _kKey = 'notification_settings_v1';

  static final NotificationSettingsService _instance =
      NotificationSettingsService._();
  factory NotificationSettingsService() => _instance;
  NotificationSettingsService._();

  NotificationSettings _settings = const NotificationSettings();
  bool _loaded = false;

  NotificationSettings get settings => _settings;

  Future<NotificationSettings> load() async {
    if (_loaded) return _settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw != null && raw.isNotEmpty) {
        _settings = NotificationSettings.decode(raw);
      }
    } catch (e, stack) {
      AppLogger.error('NotificationSettingsService.load failed', error: e, stack: stack);
    }
    _loaded = true;
    return _settings;
  }

  Future<void> save(NotificationSettings settings) async {
    _settings = settings;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKey, settings.encode());
    } catch (e, stack) {
      AppLogger.error('NotificationSettingsService.save failed', error: e, stack: stack);
    }
  }

  Future<NotificationSettings> update(
      NotificationSettings Function(NotificationSettings) updater) async {
    final next = updater(_settings);
    await save(next);
    return next;
  }
}
