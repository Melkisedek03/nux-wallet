import 'package:flutter/material.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/store_order_history.dart';
import '../utils/format.dart';
import '../utils/store_report.dart';

/// Periode Laporan Produk Terlaris.
enum _Period { today, last7Days, last30Days, all }

/// Laporan Produk Terlaris Mode Toko: produk terurut dari yang
/// paling banyak terjual pada periode terpilih, dari catatan
/// pesanan lunas toko ini (agregasi murni di
/// [aggregateProductSales] — pesanan VOID tidak dihitung).
/// Sampai di sini lewat Daftar Laporan yang bergarbang owner,
/// jadi layar ini tidak memeriksa peran lagi.
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
  _Period _period = _Period.last30Days;

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

  /// Jendela [from, to) untuk periode aktif. "Hari Ini" memakai
  /// hari kalender penuh; jendela berjalan memakai 7/30 × 24 jam
  /// ke belakang dari sekarang (ujung atas dilonggarkan ke besok
  /// supaya pesanan yang baru saja lunas tidak tersisih hanya
  /// karena perbedaan detik).
  ({DateTime from, DateTime to}) get _window {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    return switch (_period) {
      _Period.today => (
          from: DateTime(now.year, now.month, now.day),
          to: tomorrow,
        ),
      _Period.last7Days => (
          from: now.subtract(const Duration(days: 7)),
          to: tomorrow,
        ),
      _Period.last30Days => (
          from: now.subtract(const Duration(days: 30)),
          to: tomorrow,
        ),
      _Period.all => (from: DateTime(2000), to: tomorrow),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final window = _window;
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
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      _periodChip(
                        _Period.today,
                        l10n.storeFilterToday,
                      ),
                      _periodChip(_Period.last7Days, l10n.storePeriod7Days),
                      _periodChip(
                        _Period.last30Days,
                        l10n.storePeriod30Days,
                      ),
                      _periodChip(_Period.all, l10n.storePeriodAll),
                    ],
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

  Widget _periodChip(_Period period, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _period == period,
        onSelected: (_) => setState(() => _period = period),
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
