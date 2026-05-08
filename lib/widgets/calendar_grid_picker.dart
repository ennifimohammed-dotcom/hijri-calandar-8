import 'package:flutter/material.dart';
import '../providers/app_provider.dart';
import '../utils/hijri_utils.dart';
import '../utils/text_format.dart';
import '../theme.dart';

/// Calendar-grid date picker dialog used by the New Event screen,
/// the converter screen, and the event-bank Zakat block.
///
/// Visually and functionally mirrors the monthly calendar view:
///   • Hijri (default) or Gregorian month grid
///   • prev/next month arrows in the header
///   • Hijri month name + small Gregorian subtitle (or vice-versa)
///   • 7-column day grid with the same selected/today cell visuals
///   • Western digits only — every numeric piece routes through
///     [TextFormat.toWesternDigits]
///
/// Region-synchronized: when in Hijri mode the dialog reads month
/// names from [AppProvider.getHijriMonthName], converts the active
/// (year, month, day) through [AppProvider.hijriToGregorian] and
/// computes the seed Hijri date from the inbound Gregorian via
/// [AppProvider.gregorianToHijri], so changing the user's region in
/// Settings instantly shifts what the picker displays.
///
/// The dialog returns the chosen Gregorian [DateTime] at midnight.
Future<DateTime?> showCalendarGridPicker({
  required BuildContext context,
  required DateTime initial,
  required bool useHijri,
  required String locale,
  required AppProvider provider,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CalendarGridPickerDialog(
      initial: initial,
      useHijri: useHijri,
      locale: locale,
      provider: provider,
    ),
  );
}

class CalendarGridPickerDialog extends StatefulWidget {
  final DateTime initial;
  final bool useHijri;
  final String locale;
  final AppProvider provider;
  const CalendarGridPickerDialog({
    super.key,
    required this.initial,
    required this.useHijri,
    required this.locale,
    required this.provider,
  });

  @override
  State<CalendarGridPickerDialog> createState() =>
      _CalendarGridPickerDialogState();
}

class _CalendarGridPickerDialogState extends State<CalendarGridPickerDialog> {
  late int _vYear;
  late int _vMonth;
  late int _selDay;
  late int _selMonth;
  late int _selYear;

  @override
  void initState() {
    super.initState();
    if (widget.useHijri) {
      final h = widget.provider.gregorianToHijri(widget.initial);
      _vYear = h.hYear;
      _vMonth = h.hMonth;
      _selYear = h.hYear;
      _selMonth = h.hMonth;
      _selDay = h.hDay;
    } else {
      _vYear = widget.initial.year;
      _vMonth = widget.initial.month;
      _selYear = widget.initial.year;
      _selMonth = widget.initial.month;
      _selDay = widget.initial.day;
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      var m = _vMonth + delta;
      var y = _vYear;
      while (m > 12) { m -= 12; y += 1; }
      while (m < 1)  { m += 12; y -= 1; }
      _vMonth = m;
      _vYear = y;
    });
  }

  int _daysInVisibleMonth() {
    if (widget.useHijri) {
      return HijriDate.daysInMonth(_vYear, _vMonth);
    }
    final firstNext = (_vMonth == 12)
        ? DateTime(_vYear + 1, 1, 1)
        : DateTime(_vYear, _vMonth + 1, 1);
    return firstNext.subtract(const Duration(days: 1)).day;
  }

  /// Weekday (1=Mon..7=Sun) of the visible month's first day.
  int _firstWeekday() {
    if (widget.useHijri) {
      try {
        return widget.provider
            .hijriToGregorian(_vYear, _vMonth, 1)
            .weekday;
      } catch (_) {
        return 1;
      }
    }
    return DateTime(_vYear, _vMonth, 1).weekday;
  }

  String _headerTitle() {
    if (widget.useHijri) {
      return TextFormat.toWesternDigits(
        '${widget.provider.getHijriMonthName(_vMonth, widget.locale)} $_vYear',
      );
    }
    final greg = DateTime(_vYear, _vMonth, 1);
    return TextFormat.toWesternDigits(
      TextFormat.formatGregorianMonthYear(greg, widget.locale),
    );
  }

  String _headerSubtitle() {
    if (widget.useHijri) {
      DateTime greg;
      try {
        greg = widget.provider.hijriToGregorian(_vYear, _vMonth, 1);
      } catch (_) {
        greg = DateTime.now();
      }
      return TextFormat.toWesternDigits(
        TextFormat.formatGregorianMonthYear(greg, widget.locale),
      );
    }
    final h = widget.provider.gregorianToHijri(DateTime(_vYear, _vMonth, 1));
    return TextFormat.toWesternDigits(
      '${widget.provider.getHijriMonthName(h.hMonth, widget.locale)} ${h.hYear}',
    );
  }

  bool _isSelected(int day) =>
      day == _selDay && _vMonth == _selMonth && _vYear == _selYear;

  bool _isVisibleToday(int day) {
    if (widget.useHijri) {
      final t = widget.provider.today;
      return _vYear == t.hYear && _vMonth == t.hMonth && day == t.hDay;
    }
    final tg = widget.provider.today.toGregorian();
    return _vYear == tg.year && _vMonth == tg.month && day == tg.day;
  }

  void _onPickDay(int day) {
    setState(() {
      _selDay = day;
      _selMonth = _vMonth;
      _selYear = _vYear;
    });
  }

  DateTime _resolveResult() {
    if (widget.useHijri) {
      try {
        return widget.provider
            .hijriToGregorian(_selYear, _selMonth, _selDay);
      } catch (_) {
        return DateTime.now();
      }
    }
    return DateTime(_selYear, _selMonth, _selDay);
  }

  String _cancelLabel(String loc) => loc == 'ar'
      ? 'إلغاء'
      : loc == 'es'
          ? 'Cancelar'
          : loc == 'en'
              ? 'Cancel'
              : 'Annuler';

  String _okLabel(String loc) =>
      loc == 'ar' ? 'موافق' : loc == 'es' ? 'OK' : 'OK';

  @override
  Widget build(BuildContext context) {
    final loc = widget.locale;
    final daysInMonth = _daysInVisibleMonth();
    final firstWeekday = _firstWeekday();
    // Saturday-first layout (matches the monthly calendar view).
    const weekStartIndexFromMonday = 5;
    final lead = (firstWeekday - weekStartIndexFromMonday) % 7;
    final leadingBlanks = lead < 0 ? lead + 7 : lead;

    final cells = <Widget>[];
    final weekdayLabels = loc == 'ar'
        ? const ['س', 'أ', 'ث', 'ر', 'خ', 'ج', 'ح']
        : loc == 'fr'
            ? const ['Sa', 'Di', 'Lu', 'Ma', 'Me', 'Je', 'Ve']
            : loc == 'es'
                ? const ['Sá', 'Do', 'Lu', 'Ma', 'Mi', 'Ju', 'Vi']
                : const ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    for (final w in weekdayLabels) {
      cells.add(Center(
        child: Text(
          w,
          style: appFont(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.text3,
          ),
        ),
      ));
    }
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final selected = _isSelected(d);
      final today = _isVisibleToday(d);
      final bg = today
          ? AppColors.green
          : selected
              ? AppColors.greenPale
              : Colors.transparent;
      final fg = today
          ? Colors.white
          : selected
              ? AppColors.green
              : AppColors.text;
      cells.add(GestureDetector(
        onTap: () => _onPickDay(d),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(today ? 14 : 10),
            boxShadow: today
                ? [
                    BoxShadow(
                      color: AppColors.green.withValues(alpha: 0.30),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              TextFormat.toWesternDigits('$d'),
              style: appFont(
                fontSize: 13,
                fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ));
    }

    return Dialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: AppColors.green,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _headerTitle(),
                        textAlign: TextAlign.center,
                        style: appFont(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _headerSubtitle(),
                        textAlign: TextAlign.center,
                        style: appFont(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: AppColors.green,
                ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: cells,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _cancelLabel(loc),
                    style: appFont(
                      color: AppColors.text2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, _resolveResult()),
                  child: Text(
                    _okLabel(loc),
                    style: appFont(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
