import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/store_order_history.dart';
import '../services/store_report_filter.dart';
import '../services/store_shift.dart';
import '../utils/format.dart';
import '../utils/store_report.dart';
import '../widgets/store_report_period_chips.dart';

/// Laporan Pembayaran Mode Toko: penerimaan per tanggal,
/// dirinci per shift (permintaan NUX 8 Nov 2026). Tanggal
/// sebuah shift ditentukan jam BUKA-nya, bukan jam tutupnya —
/// shift yang melewati tengah malam tetap tercatat di tanggal
/// bukanya (agregasi murni di [aggregatePaymentsByDay]).
///
/// Filter khusus laporan ini: saklar Rincian per Shift.
/// MATI = hanya subtotal per tanggal; HIDUP = baris tiap shift
/// (jam buka–tutup, operator, jumlah nota, penerimaannya)
/// tampil di bawah tanggalnya. Saringan periode memakai
/// filter bersama laporan Mode Toko, dan layarnya sampai
/// lewat Daftar Laporan yang bergarbang owner.
class StorePaymentReportScreen extends StatefulWidget {
  const StorePaymentReportScreen({super.key});

  @override
  State<StorePaymentReportScreen> createState() =>
      _StorePaymentReportScreenState();
}

class _StorePaymentReportScreenState extends State<StorePaymentReportScreen> {
  final _historyStore = StoreOrderHistoryStore();
  final _shiftStore = StoreShiftStore();
  List<CompletedOrder> _orders = const [];
  List<StoreShift> _shifts = const [];
  bool _loading = true;

  /// Bawaan sama dengan laporan lain: 30 hari terakhir.
  StoreReportFilter _filter =
      const StoreReportFilter.preset(StoreReportPeriod.last30Days);

  /// Saklar khusus laporan ini: rincian per shift tampil.
  bool _breakdown = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final orders = await _historyStore.load();
    final shifts = await _shiftStore.load();
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _shifts = shifts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final window = storeReportWindowFor(_filter, now: DateTime.now());
    final days = _loading
        ? const <DayPaymentEntry>[]
        : aggregatePaymentsByDay(
            _orders,
            _shifts,
            from: window.from,
            to: window.to,
          );
    final totalCount = days.fold(0, (sum, d) => sum + d.invoiceCount);
    final totalRp = days.fold(0, (sum, d) => sum + d.totalRp);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.storeReportPaymentsTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: StoreReportPeriodChips(
                    value: _filter,
                    onChanged: (filter) => setState(() => _filter = filter),
                  ),
                ),
                SwitchListTile(
                  title: Text(
                    l10n.storePaymentReportBreakdown,
                    style: const TextStyle(fontSize: 14),
                  ),
                  value: _breakdown,
                  onChanged: (v) => setState(() => _breakdown = v),
                ),
                if (days.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 2),
                    child: Text(
                      l10n.storePaymentReportTotalLine(
                        totalCount,
                        formatRupiah(totalRp),
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                Expanded(
                  child: days.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              l10n.storeBestsellersEmpty,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: context.palette.muted,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: days.length,
                          itemBuilder: (context, i) =>
                              _dayCard(context, days[i]),
                        ),
                ),
              ],
            ),
    );
  }

  /// Satu tanggal: kepala berisi tanggal + subtotal hari;
  /// di bawahnya baris shift-shiftnya bila saklar rincian
  /// hidup.
  Widget _dayCard(BuildContext context, DayPaymentEntry entry) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatDayPeriod(day: entry.day, locale: l10n.localeName),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'Rp${formatRupiah(entry.totalRp)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (_breakdown)
            for (final shiftEntry in entry.shifts) ...[
              const Divider(height: 18),
              _shiftRow(context, shiftEntry),
            ],
        ],
      ),
    );
  }

  Widget _shiftRow(BuildContext context, ShiftPaymentEntry entry) {
    final l10n = context.l10n;
    final shift = entry.shift;
    final timeFmt = DateFormat.Hm(l10n.localeName);
    final hours = shift.closedAt != null
        ? '${timeFmt.format(shift.openedAt)} – '
              '${timeFmt.format(shift.closedAt!)}'
        : '${timeFmt.format(shift.openedAt)} – '
              '${l10n.storeShiftStillOpen}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hours,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (shift.operatorName.isNotEmpty) shift.operatorName,
                  l10n.storePaymentReportInvoices(entry.invoiceCount),
                ].join(' • '),
                style: TextStyle(
                  fontSize: 12,
                  color: context.palette.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Rp${formatRupiah(entry.totalRp)}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
