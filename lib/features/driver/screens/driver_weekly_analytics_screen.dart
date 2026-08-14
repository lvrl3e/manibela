import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/driver_operations_log.dart';

/// Rolls up a chosen 7-day window of [DriverOperationsLog] entries into
/// totals, averages, and a simple day-by-day net income chart. Defaults to
/// the last 7 days; prev/next arrows let the driver page back through
/// earlier weeks.
class DriverWeeklyAnalyticsScreen extends StatefulWidget {
  const DriverWeeklyAnalyticsScreen({super.key});

  @override
  State<DriverWeeklyAnalyticsScreen> createState() => _DriverWeeklyAnalyticsScreenState();
}

class _DriverWeeklyAnalyticsScreenState extends State<DriverWeeklyAnalyticsScreen> {
  static const List<String> _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const List<String> _monthAbbrev = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  // 0 = the 7-day window ending today, -1 = the 7 days before that, etc.
  // Never allowed to go positive (into the future).
  int _weekOffset = 0;

  /// Keeps this screen live while it's open — a day logged/edited/deleted
  /// (including directly in the database) should show up here without
  /// the driver having to leave and come back, same as every other
  /// backend-synced list in this app.
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    DriverOperationsLog.syncFromBackend().then((_) {
      if (mounted) setState(() {});
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      DriverOperationsLog.syncFromBackend().then((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  DateTime get _windowEnd {
    final today = DateTime.now();
    return DateTime(today.year, today.month, today.day).subtract(Duration(days: -7 * _weekOffset));
  }

  DateTime get _windowStart => _windowEnd.subtract(const Duration(days: 6));

  void _goToPreviousWeek() => setState(() => _weekOffset -= 1);

  void _goToNextWeek() {
    if (_weekOffset >= 0) return;
    setState(() => _weekOffset += 1);
  }

  String _formatShort(DateTime d) => '${_monthAbbrev[d.month - 1]} ${d.day}';

  @override
  Widget build(BuildContext context) {
    final windowStart = _windowStart;
    final windowEnd = _windowEnd;
    final entries = DriverOperationsLog.entriesBetween(windowStart, windowEnd);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWeekSelector(windowStart, windowEnd),
                  const SizedBox(height: 16),
                  if (entries.isEmpty) const _EmptyAnalyticsState() else _buildContent(windowEnd, entries),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekSelector(DateTime windowStart, DateTime windowEnd) {
    final label = _weekOffset == 0
        ? 'This Week (${_formatShort(windowStart)} – ${_formatShort(windowEnd)})'
        : '${_formatShort(windowStart)} – ${_formatShort(windowEnd)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E4E8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _WeekNavButton(icon: Icons.chevron_left_rounded, onTap: _goToPreviousWeek),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          _WeekNavButton(
            icon: Icons.chevron_right_rounded,
            onTap: _weekOffset >= 0 ? null : _goToNextWeek,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(DateTime windowEnd, List<DriverOperationsEntry> entries) {
    final totalEarnings = entries.fold<double>(0, (sum, e) => sum + e.totalEarnings);
    final totalExpenses = entries.fold<double>(0, (sum, e) => sum + e.totalExpenses);
    final totalDistance = entries.fold<double>(0, (sum, e) => sum + e.distanceKm);
    final totalFuel = entries.fold<double>(0, (sum, e) => sum + e.fuelExpense);
    final netIncome = totalEarnings - totalExpenses;
    final avgIncomePerKm = totalDistance > 0 ? totalEarnings / totalDistance : 0;
    final avgFuelCostPerKm = totalDistance > 0 ? totalFuel / totalDistance : 0;

    // Build the 7 calendar days in the selected window, oldest first,
    // matching a logged entry to each day where one exists.
    final days = List<DateTime>.generate(7, (i) => windowEnd.subtract(Duration(days: 6 - i)));
    final entryByDay = <int, DriverOperationsEntry>{};
    for (final e in entries) {
      entryByDay[DateTime(e.date.year, e.date.month, e.date.day).millisecondsSinceEpoch] = e;
    }
    final maxNet = entries.fold<double>(
      0,
      (max, e) => e.netIncome.abs() > max ? e.netIncome.abs() : max,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Total Earnings',
                value: '₱${totalEarnings.toStringAsFixed(0)}',
                iconBg: AppColors.qrTileBg,
                iconColor: AppColors.qrIconColor,
                icon: Icons.payments_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Total Expenses',
                value: '₱${totalExpenses.toStringAsFixed(0)}',
                iconBg: const Color(0xFFFFF1F1),
                iconColor: const Color(0xFFE23F3F),
                icon: Icons.local_gas_station_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Net Income',
                value: '₱${netIncome.toStringAsFixed(0)}',
                iconBg: const Color(0xFFDBEAFE),
                iconColor: AppColors.logoBlue,
                icon: Icons.trending_up_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Distance Driven',
                value: '${totalDistance.toStringAsFixed(0)} km',
                iconBg: AppColors.settingsTileBg,
                iconColor: AppColors.settingsIconColor,
                icon: Icons.route_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Net Income by Day', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1E4E8)),
          ),
          child: SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: _DayBar(
                      label: _weekdayLabels[day.weekday - 1],
                      entry: entryByDay[DateTime(day.year, day.month, day.day).millisecondsSinceEpoch],
                      maxMagnitude: maxNet,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Averages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1E4E8)),
          ),
          child: Column(
            children: [
              _SummaryRow(label: 'Income per km', value: '₱${avgIncomePerKm.toStringAsFixed(2)}'),
              const Divider(height: 20),
              _SummaryRow(label: 'Fuel Cost per km', value: '₱${avgFuelCostPerKm.toStringAsFixed(2)}'),
              const Divider(height: 20),
              _SummaryRow(label: 'Days Logged', value: '${entries.length} / 7'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, Color(0xFFFFDE7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: const Padding(
                padding: EdgeInsets.all(13),
                child: Icon(Icons.arrow_back, size: 22, color: Colors.black87),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Weekly Analytics',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.onPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Any 7-day window, at a glance',
                  style: TextStyle(fontSize: 10, color: Colors.black.withOpacity(0.55)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _WeekNavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 22, color: enabled ? AppColors.logoBlue : Colors.black26),
        ),
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final String label;
  final DriverOperationsEntry? entry;
  final double maxMagnitude;

  const _DayBar({required this.label, required this.entry, required this.maxMagnitude});

  @override
  Widget build(BuildContext context) {
    final net = entry?.netIncome ?? 0;
    final ratio = maxMagnitude > 0 ? (net.abs() / maxMagnitude).clamp(0.05, 1.0) : 0.0;
    final barHeight = entry == null ? 4.0 : (ratio * 100).clamp(4.0, 100.0);
    final barColor = net >= 0 ? AppColors.logoBlue : const Color(0xFFE23F3F);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 18,
          height: barHeight,
          decoration: BoxDecoration(
            color: entry == null ? const Color(0xFFE6E6E7) : barColor,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black54)),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color iconBg;
  final Color iconColor;
  final IconData icon;

  const _StatTile({
    required this.label,
    required this.value,
    required this.iconBg,
    required this.iconColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E4E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
        Text(value, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _EmptyAnalyticsState extends StatelessWidget {
  const _EmptyAnalyticsState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bar_chart_rounded, size: 56, color: Colors.black26),
            const SizedBox(height: 12),
            const Text(
              'No data yet',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black45),
            ),
            const SizedBox(height: 4),
            const Text(
              'Log your Daily Operations to see analytics here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
