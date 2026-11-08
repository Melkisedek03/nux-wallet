import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../locale_controller.dart';
import '../services/store_report_filter.dart';

/// Baris chip pemilih periode laporan Mode Toko — pasangan
/// tampilan dari filter bersama di
/// `services/store_report_filter.dart`, dipakai semua layar
/// laporan supaya saringannya selalu sama: Hari Ini,
/// 7 Hari Terakhir, 30 Hari Terakhir, Semua, dan Pilih Tanggal
/// (pemilih rentang tanggal; chip-nya menampilkan rentang yang
/// sedang aktif begitu dipilih).
class StoreReportPeriodChips extends StatelessWidget {
  const StoreReportPeriodChips({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Filter yang sedang aktif.
  final StoreReportFilter value;

  /// Dipanggil setiap pilihan berubah (preset langsung,
  /// custom sesudah pemilih tanggal ditutup dengan pilihan).
  final ValueChanged<StoreReportFilter> onChanged;

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: now,
      initialDateRange:
          (value.customStart != null && value.customEnd != null)
          ? DateTimeRange(start: value.customStart!, end: value.customEnd!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)),
              end: now,
            ),
    );
    if (picked == null) return;
    onChanged(
      StoreReportFilter(
        StoreReportPeriod.custom,
        customStart: picked.start,
        customEnd: picked.end,
      ),
    );
  }

  String _customLabel(BuildContext context) {
    final l10n = context.l10n;
    final start = value.customStart;
    final end = value.customEnd;
    if (!value.isCustom || start == null || end == null) {
      return l10n.storePeriodCustom;
    }
    final fmt = DateFormat.MMMd(l10n.localeName);
    return '${fmt.format(start)} – ${fmt.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget chip(StoreReportPeriod period, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: value.period == period,
        onSelected: (_) =>
            onChanged(StoreReportFilter.preset(period)),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(StoreReportPeriod.today, l10n.storeFilterToday),
          chip(StoreReportPeriod.last7Days, l10n.storePeriod7Days),
          chip(StoreReportPeriod.last30Days, l10n.storePeriod30Days),
          chip(StoreReportPeriod.all, l10n.storePeriodAll),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: const Icon(Icons.date_range_rounded, size: 16),
              label: Text(_customLabel(context)),
              selected: value.isCustom,
              onSelected: (_) => _pickCustomRange(context),
            ),
          ),
        ],
      ),
    );
  }
}
