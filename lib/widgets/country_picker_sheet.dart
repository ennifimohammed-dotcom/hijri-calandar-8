import 'package:flutter/material.dart';

import '../data/hijri_countries.dart';
import '../theme.dart';

/// Reusable country picker bottom sheet for the Hybrid Hijri
/// Calendar. Returns the [HijriCountry] the user tapped, or
/// `null` if they dismissed the sheet without picking one.
///
/// Used in two places today:
///   * `lib/screens/settings_screen.dart` — the existing
///     "change source" sheet that the country tile opens.
///   * `lib/screens/onboarding_screen.dart` — the "Choose
///     manually" branch of the new first-launch flow (Phase
///     7-improvement-2).
///
/// Why a shared sheet?
///   The settings screen has its own private `_CountryPickerSheet`
///   that we INTENTIONALLY leave in place — touching it would
///   risk a regression in an already-shipped flow. This public
///   alternative is a leaner version (no last-sync info, no
///   refresh button, no auto-detect — just the picker) tuned for
///   contexts where you want a pure "pick a country" outcome
///   that the caller can wire up to its own state machine.
Future<HijriCountry?> showHijriCountryPicker({
  required BuildContext context,
  required String activeCountryCode,
  required String locale,
  required bool isDark,
}) async {
  return showModalBottomSheet<HijriCountry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _HijriCountryPickerSheet(
      activeCountryCode: activeCountryCode,
      locale: locale,
      isDark: isDark,
    ),
  );
}

class _HijriCountryPickerSheet extends StatefulWidget {
  final String activeCountryCode;
  final String locale;
  final bool isDark;

  const _HijriCountryPickerSheet({
    required this.activeCountryCode,
    required this.locale,
    required this.isDark,
  });

  @override
  State<_HijriCountryPickerSheet> createState() =>
      _HijriCountryPickerSheetState();
}

class _HijriCountryPickerSheetState
    extends State<_HijriCountryPickerSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final loc = widget.locale;
    final media = MediaQuery.of(context);

    final filtered = _filter.isEmpty
        ? kHijriCountries
        : kHijriCountries.where((c) {
            final needle = _filter.toLowerCase();
            return c.localizedName(loc).toLowerCase().contains(needle) ||
                c.code.toLowerCase().contains(needle);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
        ),
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Column(
          children: [
            // Grab handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 10),
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.text3.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title + close
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      loc == 'ar'
                          ? 'اختر البلد'
                          : loc == 'fr'
                              ? 'Choisir le pays'
                              : loc == 'es'
                                  ? 'Seleccionar país'
                                  : 'Select country',
                      style: appFont(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.darkText : AppColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: isDark ? AppColors.darkText3 : AppColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            // Search field
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                onChanged: (v) => setState(() => _filter = v),
                style: appFont(
                  fontSize: 13,
                  color: isDark ? AppColors.darkText : AppColors.text,
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: AppColors.text3,
                  ),
                  hintText: loc == 'ar'
                      ? 'ابحث…'
                      : loc == 'fr'
                          ? 'Rechercher…'
                          : loc == 'es'
                              ? 'Buscar…'
                              : 'Search…',
                  hintStyle: appFont(fontSize: 13, color: AppColors.text3),
                  filled: true,
                  fillColor: isDark ? AppColors.darkBg : AppColors.bg,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.border,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.gold,
                      width: 1.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.border,
                    ),
                  ),
                ),
              ),
            ),
            // Country list
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  final active = widget.activeCountryCode == c.code;
                  return _CountryRow(
                    country: c,
                    active: active,
                    locale: loc,
                    isDark: isDark,
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryRow extends StatelessWidget {
  final HijriCountry country;
  final bool active;
  final String locale;
  final bool isDark;
  final VoidCallback onTap;
  const _CountryRow({
    required this.country,
    required this.active,
    required this.locale,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: active
                ? AppColors.green.withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? AppColors.green.withValues(alpha: 0.55)
                  : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Text(country.flag, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      country.localizedName(locale),
                      style: appFont(
                        fontSize: 13.5,
                        fontWeight: active
                            ? FontWeight.w800
                            : FontWeight.w700,
                        color: isDark ? AppColors.darkText : AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      country.localizedAuthority(locale),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appFont(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: AppColors.green,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
