import 'package:flutter/material.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/store_order_history.dart';
import '../services/store_report_export.dart';
import '../services/store_report_filter.dart';
import '../utils/format.dart';
import '../utils/store_report.dart';
import '../widgets/store_report_period_chips.dart';

/// Laporan Penjualan Produk Mode Toko: daftar LENGKAP penjualan
/// per produk pada periode terpilih — semua produk yang terjual,
/// urut abjad nama, masing-masing dengan jumlah terjual, bruto,
/// diskon baris, dan total bersih. Beda dari Produk Terlaris
/// yang sifatnya peringkat: laporan ini daftar pembukuannya.
///
/// Agregasinya sama dengan Produk Terlaris
/// ([aggregateProductSales]) — hanya beda urutan, di sini
/// [ProductSalesSort.byName]. Saringannya filter periode
/// bersama laporan Mode Toko, dan layarnya sampai lewat
/// Daftar Laporan yang bergarbang owner.
class StoreProductSalesScreen extends StatefulWidget {
  const StoreProductSalesScreen({super.key});

  @override
  State<StoreProductSalesScreen> createState() =>
      _StoreProductSalesScreenState();
}

class _StoreProductSalesScreenState extends State<StoreProductSalesScreen> {
  final _historyStore = StoreOrderHistoryStore();
  List<CompletedOrder> _orders = const [];
  bool _loading = true;
  bool _sharing = false;

  /// Bawaan sama dengan Produk Terlaris: 30 hari terakhir.
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

  /// Ekspor PDF laporan ini pada filter yang sedang aktif
  /// (pondasi ekspor bersama laporan Mode Toko).
  Future<void> _sharePdf() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final l10n = context.l10n;
      final window = storeReportWindowFor(_filter, now: DateTime.now());
      final entries = aggregateProductSales(
        _orders,
        from: window.from,
        to: window.to,
        sort: ProductSalesSort.byName,
      );
      final totalQty = entries.fold(0, (sum, e) => sum + e.qty);
      final totalNet = entries.fold(0, (sum, e) => sum + e.netRp);
      await shareReportPdf(
        text: buildProductSalesText(
          title: l10n.storeReportProductSalesTitle,
          periodLabel: storeReportFilterLabel(_filter, l10n),
          generatedStamp: formatGeneratedStamp(DateTime.now(), l10n.localeName),
          entries: entries,
          soldQtyLabel: l10n.storeBestsellersSoldQty,
          grossLabel: l10n.storeProductSalesGross,
          discountLabel: l10n.storeDiscount,
          totalLine: l10n.storeBestsellersTotalLine(
            totalQty,
            formatRupiah(totalNet),
          ),
          emptyLabel: l10n.storeBestsellersEmpty,
        ),
        fileStem: 'laporan-penjualan-produk',
      );
    } catch (_) {
      // Gagal menyusun/membagikan PDF — diamkan; layar tetap tampil.
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final window = storeReportWindowFor(_filter, now: DateTime.now());
    final entries = _loading
        ? const <ProductSalesEntry>[]
        : aggregateProductSales(
            _orders,
            from: window.from,
            to: window.to,
            sort: ProductSalesSort.byName,
          );
    final totalQty = entries.fold(0, (sum, e) => sum + e.qty);
    final totalNet = entries.fold(0, (sum, e) => sum + e.netRp);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storeReportProductSalesTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 21),
            tooltip: l10n.storeExportPdf,
            onPressed: _loading || _sharing ? null : _sharePdf,
          ),
        ],
      ),
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
                              _productRow(context, entries[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _productRow(BuildContext context, ProductSalesEntry entry) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    '${l10n.storeProductSalesGross} '
                        'Rp${formatRupiah(entry.grossRp)}',
                    if (entry.discountRp > 0)
                      '${l10n.storeDiscount} '
                          'Rp${formatRupiah(entry.discountRp)}',
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
            'Rp${formatRupiah(entry.netRp)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
