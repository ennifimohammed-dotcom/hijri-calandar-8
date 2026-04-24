# تقويم الهجري — Hijri Calendar App

تطبيق تقويم هجري احترافي مبني بـ Flutter، مستوحى من Google Calendar و Apple Calendar.

## المميزات | Features

- 📅 عرض شهري بالتاريخ الهجري والميلادي
- 🕌 بنك الأحداث الإسلامية (١٢ حدثاً قابلاً للتفعيل)
- ✦ إضافة أحداث شخصية بتواريخ هجرية
- 🌕 تمييز الأيام البيض (١٣، ١٤، ١٥)
- 🌙 تمييز شهر رمضان
- 🌗 وضع داكن / فاتح
- 🌍 4 لغات: العربية، الفرنسية، الإنجليزية، الإسبانية
- 💾 حفظ محلي تلقائي

## بناء APK عبر GitHub Actions

1. ارفع المشروع على GitHub (push إلى main/master)
2. انتقل إلى **Actions** → **Build Flutter APK**
3. انتظر الاكتمال (حوالي 5 دقائق)
4. حمّل الـ APK من **Artifacts**

## البناء المحلي | Local Build

```bash
flutter pub get
flutter build apk --release
```

الـ APK في: `build/app/outputs/flutter-apk/app-release.apk`

## المتطلبات | Requirements

- Flutter SDK (stable channel)
- Java 17
- Android SDK (API 21+)

## البنية | Structure

```
lib/
├── main.dart              # Entry point
├── theme.dart             # Colors & typography
├── models/event_model.dart
├── data/islamic_events.dart
├── providers/app_provider.dart
└── screens/
    ├── home_screen.dart
    ├── calendar_screen.dart
    ├── event_bank_screen.dart
    ├── add_event_screen.dart
    └── settings_screen.dart
```

---
Built with ❤️ using Flutter | مبني بـ Flutter
