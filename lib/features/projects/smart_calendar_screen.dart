import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/models/models.dart';
import '../../core/widgets/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../auth/providers/auth_controller.dart';
import 'providers/projects_providers.dart';
import 'widgets/project_card.dart';

const List<String> _kArabicMonths = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

// Week starts on Saturday (Gulf convention).
const List<String> _kWeekdays = [
  'سبت',
  'أحد',
  'اثن',
  'ثلا',
  'أرب',
  'خمي',
  'جمع',
];

String _fmtDate(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// Maps a weekday (Mon=1..Sun=7) to a Saturday-first column index (Sat=0).
int _columnFor(DateTime day) => (day.weekday + 1) % 7;

/// True when [day] falls within a project's [startDate, endDate] (date-only).
bool _onDay(ProjectModel p, DateTime day) {
  final start = DateUtils.dateOnly(p.startDate);
  final end = DateUtils.dateOnly(p.endDate);
  return !day.isBefore(start) && !day.isAfter(end);
}

bool _intersectsWeek(ProjectModel p, DateTime today) {
  final weekEnd = today.add(const Duration(days: 7));
  final start = DateUtils.dateOnly(p.startDate);
  final end = DateUtils.dateOnly(p.endDate);
  return !end.isBefore(today) && !start.isAfter(weekEnd);
}

enum _CalMode { calendar, list }

enum _CalFilter { all, today, week, active, pendingClosure, completed }

extension _CalFilterView on _CalFilter {
  String get label => switch (this) {
    _CalFilter.all => 'الكل',
    _CalFilter.today => 'اليوم',
    _CalFilter.week => 'هذا الأسبوع',
    _CalFilter.active => 'نشط',
    _CalFilter.pendingClosure => 'بانتظار الإغلاق',
    _CalFilter.completed => 'منتهي',
  };

  bool matches(ProjectModel p, DateTime today) => switch (this) {
    _CalFilter.all => true,
    _CalFilter.today => _onDay(p, today),
    _CalFilter.week => _intersectsWeek(p, today),
    _CalFilter.active => p.isActive,
    _CalFilter.pendingClosure => p.hasPendingClosure,
    _CalFilter.completed => p.isCompleted,
  };
}

/// Full-page wrapper (own scaffold) for routes that push the calendar — used by
/// the manager "More" menu. The photographer reaches it via a shell tab, which
/// already provides the scaffold, so it embeds [SmartCalendarScreen] directly.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SumouScaffold(
      appBar: SumouAppBar(
        title: 'التقويم',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: const SmartCalendarScreen(),
    );
  }
}

/// Smart calendar / schedule view (body-only; the host provides the scaffold).
///
/// Role-scoped via [calendarProjectsProvider]. Mock-backed, read-only — tapping
/// a project opens the existing details screen. No reminders/notifications.
class SmartCalendarScreen extends ConsumerStatefulWidget {
  const SmartCalendarScreen({super.key});

  @override
  ConsumerState<SmartCalendarScreen> createState() =>
      _SmartCalendarScreenState();
}

class _SmartCalendarScreenState extends ConsumerState<SmartCalendarScreen> {
  _CalMode _mode = _CalMode.calendar;
  _CalFilter _filter = _CalFilter.all;
  late DateTime _focusedMonth;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateUtils.dateOnly(DateTime.now());
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDay = now;
  }

  void _shiftMonth(int delta) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    });
  }

  void _openDetails(String id) => context.push(AppRoutes.projectDetailsPath(id));

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(calendarProjectsProvider);
    final role = ref.watch(authControllerProvider).activeRole;
    final userId = ref.watch(
      authControllerProvider.select((s) => s.currentUser?.id),
    );
    final today = DateUtils.dateOnly(DateTime.now());

    return projectsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('تعذّر تحميل التقويم')),
      data: (all) {
        final projects = all.where((p) => _filter.matches(p, today)).toList();
        return Column(
          children: [
            _ModeToggle(
              mode: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
            const SizedBox(height: 12),
            _FilterBar(
              selected: _filter,
              onSelected: (f) => setState(() => _filter = f),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _mode == _CalMode.calendar
                  ? _CalendarView(
                      projects: projects,
                      today: today,
                      focusedMonth: _focusedMonth,
                      selectedDay: _selectedDay,
                      role: role,
                      userId: userId,
                      onShiftMonth: _shiftMonth,
                      onSelectDay: (d) => setState(() => _selectedDay = d),
                      onOpen: _openDetails,
                    )
                  : _ListView(
                      projects: projects,
                      today: today,
                      role: role,
                      userId: userId,
                      onOpen: _openDetails,
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ---- shared helpers ---------------------------------------------------------

List<ProjectModel> _projectsOnDay(List<ProjectModel> all, DateTime day) =>
    all.where((p) => _onDay(p, day)).toList();

/// The viewer's own role/photo type on a project (photographer only).
String? _roleLabel(ProjectModel p, String? userId, RoleType? role) {
  if (role != RoleType.photographer || userId == null) return null;
  for (final r in p.teamRoles) {
    if (r.userId == userId) return r.type;
  }
  return null;
}

/// A simple, role-aware "next action" hint for a project.
String _smartAction(ProjectModel p, RoleType? role) {
  if (role == RoleType.manager) {
    if (p.hasPendingClosure) return 'مراجعة طلب الإغلاق';
    return 'عرض التفاصيل';
  }
  if (role == RoleType.photographer) {
    if (p.isActive) return 'تحديث المرحلة';
    return 'عرض التفاصيل';
  }
  return 'عرض التفاصيل';
}

Widget _projectTile(
  ProjectModel p,
  RoleType? role,
  String? userId,
  void Function(String id) onOpen,
) {
  return ProjectCard(
    project: p,
    roleLabel: _roleLabel(p, userId, role),
    actionLabel: _smartAction(p, role),
    onTap: () => onOpen(p.id),
  );
}

// ---- calendar view ----------------------------------------------------------

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    required this.projects,
    required this.today,
    required this.focusedMonth,
    required this.selectedDay,
    required this.role,
    required this.userId,
    required this.onShiftMonth,
    required this.onSelectDay,
    required this.onOpen,
  });

  final List<ProjectModel> projects;
  final DateTime today;
  final DateTime focusedMonth;
  final DateTime selectedDay;
  final RoleType? role;
  final String? userId;
  final void Function(int delta) onShiftMonth;
  final void Function(DateTime day) onSelectDay;
  final void Function(String id) onOpen;

  List<DateTime?> _cells() {
    final first = DateTime(focusedMonth.year, focusedMonth.month, 1);
    final leading = _columnFor(first);
    final daysInMonth = DateUtils.getDaysInMonth(
      focusedMonth.year,
      focusedMonth.month,
    );
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(focusedMonth.year, focusedMonth.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final cells = _cells();
    final weeks = [
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];
    final dayProjects = _projectsOnDay(projects, selectedDay);

    return ListView(
      children: [
        // Month header.
        Row(
          children: [
            IconButton(
              onPressed: () => onShiftMonth(-1),
              icon: const Icon(Icons.chevron_right),
              tooltip: 'الشهر السابق',
            ),
            Expanded(
              child: Text(
                '${_kArabicMonths[focusedMonth.month - 1]} ${focusedMonth.year}',
                style: AppTextStyles.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              onPressed: () => onShiftMonth(1),
              icon: const Icon(Icons.chevron_left),
              tooltip: 'الشهر التالي',
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Weekday labels.
        Row(
          children: [
            for (final w in _kWeekdays)
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (final week in weeks)
          SizedBox(
            height: 54,
            child: Row(
              children: [
                for (final day in week)
                  Expanded(
                    child: day == null
                        ? const SizedBox.shrink()
                        : _DayCell(
                            day: day,
                            isToday: DateUtils.isSameDay(day, today),
                            isSelected: DateUtils.isSameDay(day, selectedDay),
                            dayProjects: _projectsOnDay(projects, day),
                            onTap: () => onSelectDay(day),
                          ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        const _Legend(),
        const SizedBox(height: 16),
        SumouSectionHeader(title: 'مشاريع ${_fmtDate(selectedDay)}'),
        const SizedBox(height: 12),
        if (dayProjects.isEmpty)
          const SumouEmptyState(
            title: 'لا توجد مشاريع في هذا اليوم',
            message: 'اختر يوماً آخر من التقويم',
            icon: Icons.event_busy_outlined,
          )
        else
          for (final p in dayProjects) ...[
            _projectTile(p, role, userId, onOpen),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.dayProjects,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final List<ProjectModel> dayProjects;
  final VoidCallback onTap;

  static const int _maxDots = 3;

  @override
  Widget build(BuildContext context) {
    final extra = dayProjects.length - _maxDots;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentGreen.withValues(alpha: 0.15)
              : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.accentGreen : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: AppTextStyles.body.copyWith(
                color: isToday ? AppColors.accentGreen : null,
                fontWeight: isToday ? FontWeight.bold : null,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final p in dayProjects.take(_maxDots)) ...[
                    _Dot(color: sumouStatusForProject(p.status).color),
                    const SizedBox(width: 2),
                  ],
                  if (extra > 0)
                    Text(
                      '+$extra',
                      style: AppTextStyles.label.copyWith(
                        fontSize: 9,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: const [
        _LegendItem(color: AppColors.projectTeal, label: 'نشط'),
        _LegendItem(color: AppColors.financeYellow, label: 'بانتظار الإغلاق'),
        _LegendItem(color: AppColors.textMuted, label: 'منتهي'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyles.label.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

// ---- list view --------------------------------------------------------------

enum _Bucket { today, tomorrow, week, later }

extension _BucketView on _Bucket {
  String get label => switch (this) {
    _Bucket.today => 'اليوم',
    _Bucket.tomorrow => 'غدًا',
    _Bucket.week => 'هذا الأسبوع',
    _Bucket.later => 'لاحقًا',
  };
}

class _ListView extends StatelessWidget {
  const _ListView({
    required this.projects,
    required this.today,
    required this.role,
    required this.userId,
    required this.onOpen,
  });

  final List<ProjectModel> projects;
  final DateTime today;
  final RoleType? role;
  final String? userId;
  final void Function(String id) onOpen;

  _Bucket _bucketFor(ProjectModel p) {
    if (_onDay(p, today)) return _Bucket.today;
    final start = DateUtils.dateOnly(p.startDate);
    final diff = start.difference(today).inDays;
    if (diff == 1) return _Bucket.tomorrow;
    if (diff >= 2 && diff <= 7) return _Bucket.week;
    return _Bucket.later;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <_Bucket, List<ProjectModel>>{};
    for (final p in projects) {
      grouped.putIfAbsent(_bucketFor(p), () => []).add(p);
    }
    if (projects.isEmpty) {
      return const SumouEmptyState(
        title: 'لا توجد مشاريع',
        message: 'ستظهر هنا مشاريعك القادمة',
        icon: Icons.event_note_outlined,
      );
    }
    return ListView(
      children: [
        for (final bucket in _Bucket.values)
          if ((grouped[bucket] ?? const []).isNotEmpty) ...[
            SumouSectionHeader(title: bucket.label),
            const SizedBox(height: 12),
            for (final p in grouped[bucket]!) ...[
              _projectTile(p, role, userId, onOpen),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

// ---- top controls -----------------------------------------------------------

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _CalMode mode;
  final ValueChanged<_CalMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SegmentButton(
            label: 'التقويم',
            icon: Icons.calendar_month_outlined,
            selected: mode == _CalMode.calendar,
            onTap: () => onChanged(_CalMode.calendar),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SegmentButton(
            label: 'القائمة',
            icon: Icons.view_agenda_outlined,
            selected: mode == _CalMode.list,
            onTap: () => onChanged(_CalMode.list),
          ),
        ),
      ],
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accentGreen : AppColors.textMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentGreen.withValues(alpha: 0.15)
              : AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accentGreen : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.label.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final _CalFilter selected;
  final ValueChanged<_CalFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _CalFilter.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = _CalFilter.values[i];
          return _FilterChip(
            label: f.label,
            selected: selected == f,
            onTap: () => onSelected(f),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accentGreen : AppColors.textMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentGreen.withValues(alpha: 0.15)
              : AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accentGreen : AppColors.border,
          ),
        ),
        child: Text(label, style: AppTextStyles.label.copyWith(color: color)),
      ),
    );
  }
}
