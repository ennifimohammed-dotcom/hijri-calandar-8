import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_provider.dart';
import '../theme.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;
  String _selectedLang = 'ar';

  void _next(AppProvider p) {
    if (_page < 2) {
      _ctrl.nextPage(duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut);
    } else {
      _finish(p);
    }
  }

  Future<void> _finish(AppProvider p) async {
    p.setLocale(_selectedLang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (mounted) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AppProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Progress dots
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: _page == i ? 24 : 8, height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: _page == i ? AppColors.green : AppColors.border,
                    borderRadius: BorderRadius.circular(4)),
                )),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Page1(),
                  _Page2(selectedLang: _selectedLang,
                      onLangSelected: (l) => setState(() => _selectedLang = l)),
                  _Page3(p: p),
                ],
              ),
            ),
            // Button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: GestureDetector(
                onTap: () => _next(p),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                        color: AppColors.green.withValues(alpha: 0.4),
                        blurRadius: 16)]),
                  child: Center(child: Text(
                    _page < 2
                        ? (_selectedLang == 'ar' ? 'التالي →' : 'Suivant →')
                        : (_selectedLang == 'ar' ? '✓ ابدأ' : '✓ Commencer'),
                    style: appFont(fontSize: 16, fontWeight: FontWeight.w800,
                        color: Colors.white),
                  )),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page 1: Welcome ────────────────────────────────────────
class _Page1 extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🌙', style: TextStyle(fontSize: 80)),
          const SizedBox(height: 12),
          const Text('🗓', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 32),
          Text('تقويم الهجري',
            style: appFont(fontSize: 36, fontWeight: FontWeight.bold,
                color: AppColors.navy),
            textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text('احتفل بمواسم الإسلام',
            style: appFont(fontSize: 20, color: AppColors.text2),
            textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Hijri Calendar — Calendrier Islamique',
            style: appFont(fontSize: 13, color: AppColors.text3),
            textAlign: TextAlign.center),
          const SizedBox(height: 32),
          _FeaturePill(emoji: '🕌', text: 'أحداث إسلامية'),
          const SizedBox(height: 8),
          _FeaturePill(emoji: '🔔', text: 'تذكيرات ذكية'),
          const SizedBox(height: 8),
          _FeaturePill(emoji: '🌍', text: '4 لغات'),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final String emoji, text;
  const _FeaturePill({required this.emoji, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.greenPale,
      borderRadius: BorderRadius.circular(30)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Text(text, style: appFont(fontSize: 14,
            fontWeight: FontWeight.w700, color: AppColors.green)),
      ],
    ),
  );
}

// ── Page 2: Language ───────────────────────────────────────
class _Page2 extends StatelessWidget {
  final String selectedLang;
  final ValueChanged<String> onLangSelected;
  const _Page2({required this.selectedLang, required this.onLangSelected});

  @override
  Widget build(BuildContext context) {
    const langs = [
      ('ar', '🇸🇦', 'العربية', 'Arabic'),
      ('fr', '🇫🇷', 'Français', 'French'),
      ('en', '🇬🇧', 'English', 'English'),
      ('es', '🇪🇸', 'Español', 'Spanish'),
    ];
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Text('اختر لغتك',
            style: appFont(fontSize: 30, fontWeight: FontWeight.bold,
                color: AppColors.navy)),
          const SizedBox(height: 6),
          Text('Choose your language',
            style: appFont(fontSize: 14, color: AppColors.text3)),
          const SizedBox(height: 28),
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12, crossAxisSpacing: 12,
            childAspectRatio: 1.8,
            children: langs.map((l) {
              final active = selectedLang == l.$1;
              return GestureDetector(
                onTap: () => onLangSelected(l.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: active ? AppColors.navy : AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: active ? AppColors.navy : AppColors.border,
                      width: active ? 2 : 1),
                    boxShadow: active ? [BoxShadow(
                        color: AppColors.navy.withValues(alpha: 0.2),
                        blurRadius: 8)] : null),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l.$2, style: const TextStyle(fontSize: 28)),
                      const SizedBox(height: 4),
                      Text(l.$3, style: appFont(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: active ? Colors.white : AppColors.text)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Page 3: Islamic Events ─────────────────────────────────
class _Page3 extends StatefulWidget {
  final AppProvider p;
  const _Page3({required this.p});
  @override
  State<_Page3> createState() => _Page3State();
}

class _Page3State extends State<_Page3> {
  final _events = {
    'ramadan_start': true,
    'eid_alfitr':    true,
    'eid_aladha':    true,
    'ayyam_albid':   true,
    'arafat':        true,
  };

  final _labels = {
    'ramadan_start': ('🌙', 'رمضان / Ramadan'),
    'eid_alfitr':    ('🎉', 'عيد الفطر / Aïd al-Fitr'),
    'eid_aladha':    ('🎊', 'عيد الأضحى / Aïd al-Adha'),
    'ayyam_albid':   ('🌕', 'الأيام البيض'),
    'arafat':        ('🏔', 'عرفة / Arafat'),
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text('فعّل الأحداث الإسلامية',
            style: appFont(fontSize: 26, fontWeight: FontWeight.bold,
                color: AppColors.navy),
            textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text('Activer les événements islamiques',
            style: appFont(fontSize: 13, color: AppColors.text3)),
          const SizedBox(height: 20),
          ..._events.entries.map((e) {
            final lbl = _labels[e.key]!;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]),
              child: Row(
                children: [
                  Text(lbl.$1, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(lbl.$2,
                    style: appFont(fontSize: 13, fontWeight: FontWeight.w700,
                        color: AppColors.text))),
                  _SmToggle(
                    value: e.value,
                    onChanged: (v) {
                      setState(() => _events[e.key] = v);
                      widget.p.toggleIslamicEvent(e.key, v);
                    }),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SmToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SmToggle({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onChanged(!value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 44, height: 24, padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? AppColors.green : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(12)),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(width: 18, height: 18,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle))),
    ),
  );
}
