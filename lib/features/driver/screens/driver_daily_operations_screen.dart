import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/driver_operations_log.dart';

/// Lets the driver log today's odometer readings, earnings, and expenses,
/// then computes the numbers that actually matter: distance driven, net
/// income, income per km, and fuel cost per km. Saved entries feed the
/// Weekly/Monthly analytics screens too.
class DriverDailyOperationsScreen extends StatefulWidget {
  const DriverDailyOperationsScreen({super.key});

  @override
  State<DriverDailyOperationsScreen> createState() => _DriverDailyOperationsScreenState();
}

class _DriverDailyOperationsScreenState extends State<DriverDailyOperationsScreen> {
  late final TextEditingController _startOdoController;
  late final TextEditingController _endOdoController;
  late final TextEditingController _earningsController;
  late final TextEditingController _fuelController;
  late final TextEditingController _otherController;

  /// True until the initial fresh sync (see initState) resolves — the
  /// form is always built from whatever's cached locally (instant, never
  /// blank on a slow connection); this only drives a small non-blocking
  /// "Checking for updates..." hint so the driver isn't left wondering
  /// why their fields briefly changed if the sync corrects something.
  bool _isSyncing = true;

  @override
  void initState() {
    super.initState();
    final existing = DriverOperationsLog.todayEntry;
    _startOdoController = TextEditingController(text: _numOrEmpty(existing?.startOdo));
    _endOdoController = TextEditingController(text: _numOrEmpty(existing?.endOdo));
    _earningsController = TextEditingController(text: _numOrEmpty(existing?.totalEarnings));
    _fuelController = TextEditingController(text: _numOrEmpty(existing?.fuelExpense));
    _otherController = TextEditingController(text: _numOrEmpty(existing?.otherExpenses));

    for (final c in [_startOdoController, _endOdoController, _earningsController, _fuelController, _otherController]) {
      c.addListener(_onFieldChanged);
    }

    // A fresh sync before this form is really usable — if today's entry
    // (or the lack of one) changed on the backend since the last sync
    // (e.g. an admin deleted it directly in the database), the driver
    // should see that reflected, not a stale local copy pre-filled into
    // the fields they're about to edit. Only re-populates the fields if
    // the driver hasn't already started typing (see _dirty) — a slow
    // sync shouldn't be able to clobber input made in the meantime.
    DriverOperationsLog.syncFromBackend().then((_) {
      if (!mounted) return;
      setState(() {
        if (!_dirty) {
          final refreshed = DriverOperationsLog.todayEntry;
          _startOdoController.text = _numOrEmpty(refreshed?.startOdo);
          _endOdoController.text = _numOrEmpty(refreshed?.endOdo);
          _earningsController.text = _numOrEmpty(refreshed?.totalEarnings);
          _fuelController.text = _numOrEmpty(refreshed?.fuelExpense);
          _otherController.text = _numOrEmpty(refreshed?.otherExpenses);
        }
        _isSyncing = false;
      });
    });
  }

  /// Whether the driver has touched any field since this screen opened —
  /// checked by the post-sync refresh above so it never overwrites input
  /// made while the sync was still in flight.
  bool _dirty = false;

  String _numOrEmpty(double? value) {
    if (value == null || value == 0) return '';
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toString();
  }

  @override
  void dispose() {
    for (final c in [_startOdoController, _endOdoController, _earningsController, _fuelController, _otherController]) {
      c.removeListener(_onFieldChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onFieldChanged() => setState(() => _dirty = true);

  double _parse(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  DriverOperationsEntry get _draftEntry => DriverOperationsEntry(
        date: DateTime.now(),
        startOdo: _parse(_startOdoController),
        endOdo: _parse(_endOdoController),
        totalEarnings: _parse(_earningsController),
        fuelExpense: _parse(_fuelController),
        otherExpenses: _parse(_otherController),
      );

  Future<void> _handleSave() async {
    final startOdo = _parse(_startOdoController);
    final endOdo = _parse(_endOdoController);

    if (endOdo < startOdo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End odometer cannot be less than start odometer.')),
      );
      return;
    }

    await DriverOperationsLog.save(_draftEntry);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Today's operations saved.")),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final entry = _draftEntry;

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
                  if (_isSyncing)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Checking for updates...',
                        style: TextStyle(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.w600),
                      ),
                    ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFFCACA)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Color(0xFFE23F3F), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Only fill this in once your driving for the day is done. '
                            'Enter your final odometer reading and totals after your '
                            'shift — not while you\'re still on the road.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7A1F1F),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle(title: 'Odometer'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _NumberField(
                          label: 'Start (km)',
                          controller: _startOdoController,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NumberField(
                          label: 'End (km)',
                          controller: _endOdoController,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle(title: 'Earnings'),
                  const SizedBox(height: 10),
                  _NumberField(
                    label: 'Total Daily Earnings (₱)',
                    controller: _earningsController,
                  ),
                  const SizedBox(height: 20),
                  const _SectionTitle(title: 'Expenses'),
                  const SizedBox(height: 10),
                  _NumberField(
                    label: 'Fuel Expense (₱)',
                    controller: _fuelController,
                  ),
                  const SizedBox(height: 12),
                  _NumberField(
                    label: 'Other Expenses (₱)',
                    controller: _otherController,
                    hint: 'Food, maintenance, toll, etc.',
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle(title: 'Summary'),
                  const SizedBox(height: 10),
                  _buildSummaryCard(entry),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.onPrimary),
                      ),
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

  Widget _buildSummaryCard(DriverOperationsEntry entry) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E4E8)),
      ),
      child: Column(
        children: [
          _SummaryRow(label: 'Distance Traveled', value: '${entry.distanceKm.toStringAsFixed(1)} km'),
          const Divider(height: 20),
          _SummaryRow(label: 'Total Expenses', value: '₱${entry.totalExpenses.toStringAsFixed(2)}'),
          const Divider(height: 20),
          _SummaryRow(
            label: 'Income per km',
            value: '₱${entry.incomePerKm.toStringAsFixed(2)}',
          ),
          const Divider(height: 20),
          _SummaryRow(
            label: 'Fuel Cost per km',
            value: '₱${entry.fuelCostPerKm.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: entry.netIncome >= 0 ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Net Income',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                Text(
                  '₱${entry.netIncome.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: entry.netIncome >= 0 ? const Color(0xFF166534) : const Color(0xFFB91C1C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
                  'Daily Operations',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.onPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Track today’s earnings and expenses',
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

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;

  const _NumberField({required this.label, required this.controller, this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E6E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black)),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.only(top: 6),
              border: InputBorder.none,
              hintText: hint ?? '0',
              hintStyle: TextStyle(color: Colors.grey.shade400),
            ),
          ),
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
