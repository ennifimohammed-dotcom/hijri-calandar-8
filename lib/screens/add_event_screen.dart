import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/event_model.dart';
import '../theme.dart';

/// Add / Edit Event screen — structural layout only.
///
/// This is a deliberate placeholder skeleton. It establishes the
/// section structure that subsequent steps will fill in:
///   * Title field
///   * Event-kind selector (event / task / birthday)
///   * Time section placeholder
///   * Recurrence section placeholder
///   * Notifications section placeholder
///   * Save button
///
/// No business logic, no validation, no services.
class AddEventScreen extends StatefulWidget {
  final AppEvent? existingEvent;
  const AddEventScreen({super.key, this.existingEvent});

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  EventKind _kind = EventKind.event;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _TitleField(),
            SizedBox(height: 12),
            _KindSelector(),
            SizedBox(height: 12),
            _SectionPlaceholder(
              icon: Icons.schedule_rounded,
              title: 'Time',
            ),
            SizedBox(height: 12),
            _SectionPlaceholder(
              icon: Icons.repeat_rounded,
              title: 'Recurrence',
            ),
            SizedBox(height: 12),
            _SectionPlaceholder(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
            ),
          ],
        ),
      ),
      bottomNavigationBar: const _SaveBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: AppColors.navy),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Add Event',
        style: GoogleFonts.cairo(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
      centerTitle: true,
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: AppColors.border),
      ),
    );
  }
}

// ─── Inherited holder so child widgets can read state without props ──
// (Used to keep the layout-only file flat and avoid prop drilling for
// what is, at this stage, a placeholder skeleton. Subsequent steps will
// move the relevant state up into a proper controller / provider.)

// ─── Section widgets ────────────────────────────────────────────────

class _TitleField extends StatelessWidget {
  const _TitleField();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_AddEventScreenState>()!;
    return _Card(
      child: TextField(
        controller: state._titleCtrl,
        style: GoogleFonts.cairo(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: 'Event title',
          hintStyle: GoogleFonts.cairo(
            fontSize: 16,
            color: AppColors.text3,
          ),
        ),
      ),
    );
  }
}

class _KindSelector extends StatelessWidget {
  const _KindSelector();

  static const _options = <(EventKind, String, IconData)>[
    (EventKind.event, 'Event', Icons.event_rounded),
    (EventKind.task, 'Task', Icons.check_circle_outline_rounded),
    (EventKind.birthday, 'Birthday', Icons.cake_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_AddEventScreenState>()!;
    return _Card(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: _options.map((o) {
          final selected = state._kind == o.$1;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => state.setState(() => state._kind = o.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.green : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? AppColors.green : AppColors.border,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      o.$3,
                      size: 18,
                      color: selected ? Colors.white : AppColors.text2,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      o.$2,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : AppColors.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SectionPlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionPlaceholder({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.greenPale,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.text3,
          ),
        ],
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: const BoxDecoration(
          color: AppColors.white,
          border: Border(
            top: BorderSide(color: AppColors.border),
          ),
        ),
        child: ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            'Save',
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared primitives ──────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
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
}
