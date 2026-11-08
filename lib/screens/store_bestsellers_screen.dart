import 'package:flutter/material.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/store_order_history.dart';
import '../services/store_report_filter.dart';
import '../utils/format.dart';
import '../utils/store_report.dart';
import '../widgets/store_report_period_chips.dart';

/// Laporan Produk Terlaris Mode Toko: produk terurut dari yang
/// paling banyak terjual pada periode terpilih, dari catatan
/// pesanan lunas toko ini (agregasi murni di
/// [aggregateProductSales] — pesanan VOID tidak dihitung).
/// Sampai di sini lewat Daftar Laporan yang bergarbang owner,
/// jadi layar ini tidak memeriksa peran lagi.
///
/// Saringannya memakai filter periode bersama laporan Mode
/// Toko (StoreReportFilter + StoreReportPeriodChips) — pola
/// yang sama akan dipakai laporan-laporan berikutnya.
class StoreBestsellersScreen extends StatefulWidget {
  const StoreBestsellersScreen({super.key});

  @override
  State<StoreBestsellersScreen> createState() =>
      _StoreBestsellersScreenState();
}

class _StoreBestsellersScreenState extends State<StoreBestsellersScreen> {
  final _historyStore = StoreOrderHistoryStore();
  List<CompletedOrder> _orders = const [];
  bool _loading = true;

  /// Bawaan 30 hari: jendela yang cukup berarti untuk peringkat
  /// (hari ini saja sering hampir kosong di toko kecil).
  StoreReportFilter _filter =
      const StoreReportFilter.preset(StoreReportPeriod.last30Days);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final orders = await _historyStore.load();
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final window = storeReportWindowFor(_filter, now: DateTime.now());
    final entries = _loading
        ? const <ProductSalesEntry>[]
        : aggregateProductSales(_orders, from: window.from, to: window.to);
    final totalQty = entries.fold(0, (sum, e) => sum + e.qty);
    final totalNet = entries.fold(0, (sum, e) => sum + e.netRp);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.storeReportBestsellersTitle)),
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
                if (entries.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 2),
                    child: Text(
                      l10n.storeBestsellersTotalLine(
                        totalQty,
                        formatRupiah(totalNet),
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                Expanded(
                  child: entries.isEmpty
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
                          itemCount: entries.length,
                          itemBuilder: (context, i) =>
                              _rankRow(context, i + 1, entries[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _rankRow(BuildContext context, int rank, ProductSalesEntry entry) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: rank <= 3
                    ? const Color(0xFF10B981)
                    : context.palette.muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (entry.code.isNotEmpty) entry.code,
                    l10n.storeBestsellersSoldQty(entry.qty),
                  ].join(' • '),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Rp${formatRupiah(entry.netRp)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
