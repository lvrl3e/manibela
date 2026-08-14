import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/driver_operations_log.dart';

/// Rolls up a chosen calendar month's [DriverOperationsLog] entries into
/// totals, averages, a week-by-week net income chart, and a "best day"
/// performance callout. Defaults to the current month; prev/next arrows
/// let the driver page back through earlier months.
class DriverMonthlyAnalyticsScreen extends StatefulWidget {
  const DriverMonthlyAnalyticsScreen({super.key});

  @override
  State<DriverMonthlyAnalyticsScreen> createState() => _DriverMonthlyAnalyticsScreenState();
}

class _DriverMonthlyAnalyticsScreenState extends State<DriverMonthlyAnalyticsScreen> {
  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  // 0 = current month, -1 = one month back, etc. Never allowed to go
  // positive (into the future).
  int _monthOffset = 0;

  /// Keeps this screen live while it's open — same reasoning as
  /// DriverWeeklyAnalyticsScreen's own poll timer.
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

  DateTime get _selectedMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month + _monthOffset, 1);
  }

  DateTime get _selectedMonthEnd {
    final month = _selectedMonth;
    return DateTime(month.year, month.month + 1, 0);
  }

  void _goToPreviousMonth() => setState(() => _monthOffset -= 1);

  void _goToNextMonth() {
    if (_monthOffset >= 0) return;
    setState(() => _monthOffset += 1);
  }

  @override
  Widget build(BuildContext context) {
    final month = _selectedMonth;
    final entries = DriverOperationsLog.entriesBetween(month, _selectedMonthEnd);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(context, month),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMonthSelector(month),
                  const SizedBox(height: 16),
                  if (entries.isEmpty) const _EmptyAnalyticsState() else _buildContent(entries),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector(DateTime month) {
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
          _MonthNavButton(icon: Icons.chevron_left_rounded, onTap: _goToPreviousMonth),
          Text(
            '${_monthNames[month.month - 1]} ${month.year}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          _MonthNavButton(
            icon: Icons.chevron_right_rounded,
            onTap: _monthOffset >= 0 ? null : _goToNextMonth,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<DriverOperationsEntry> entries) {
    final totalEarnings = entries.fold<double>(0, (sum, e) => sum + e.totalEarnings);
    final totalExpenses = entries.fold<double>(0, (sum, e) => sum + e.totalExpenses);
    final totalDistance = entries.fold<double>(0, (sum, e) => sum + e.distanceKm);
    final totalFuel = entries.fold<double>(0, (sum, e) => sum + e.fuelExpense);
    final netIncome = totalEarnings - totalExpenses;
    final avgIncomePerKm = totalDistance > 0 ? totalEarnings / totalDistance : 0;
    final avgFuelCostPerKm = totalDistance > 0 ? totalFuel / totalDistance : 0;

    final bestDay = entries.reduce((a, b) => a.netIncome >= b.netIncome ? a : b);

    // Bucket entries into week-of-month (1-5) for the chart.
    final weeklyNet = List<double>.filled(5, 0);
    for (final e in entries) {
      final weekIndex = ((e.date.day - 1) ~/ 7).clamp(0, 4);
      weeklyNet[weekIndex] += e.netIncome;
    }
    final maxWeekly = weeklyNet.fold<double>(0, (max, v) => v.abs() > max ? v.abs() : max);

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
        const Text('Best Day This Month', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: Color(0xFF166534), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_monthNames[bestDay.date.month - 1]} ${bestDay.date.day} — ₱${bestDay.netIncome.toStringAsFixed(0)} net income',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF166534)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Net Income by Week', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
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
                for (int i = 0; i < weeklyNet.length; i++)
                  Expanded(
                    child: _WeekBar(label: 'Wk${i + 1}', net: weeklyNet[i], maxMagnitude: maxWeekly),
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
              _SummaryRow(label: 'Days Logged', value: '${entries.length}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, DateTime month) {
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
                  'Monthly Analytics',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.onPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_monthNames[month.month - 1]} performance',
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

class _MonthNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _MonthNavButton({required this.icon, required this.onTap});

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

class _WeekBar extends StatelessWidget {
  final String label;
  final double net;
  final double maxMagnitude;

  const _WeekBar({required this.label, required this.net, required this.maxMagnitude});

  @override
  Widget build(BuildContext context) {
    final hasData = net != 0;
    final ratio = maxMagnitude > 0 ? (net.abs() / maxMagnitude).clamp(0.05, 1.0) : 0.0;
    final barHeight = hasData ? (ratio * 100).clamp(4.0, 100.0) : 4.0;
    final barColor = net >= 0 ? AppColors.logoBlue : const Color(0xFFE23F3F);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 22,
          height: barHeight,
          decoration: BoxDecoration(
            color: hasData ? barColor : const Color(0xFFE6E6E7),
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
            const Icon(Icons.insights_rounded, size: 56, color: Colors.black26),
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
