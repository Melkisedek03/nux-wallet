import 'package:flutter/material.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/print_service.dart';
import '../services/store_order_history.dart';
import '../utils/format.dart';
import '../utils/store_receipt.dart';
import 'store_receipt_preview.dart';

/// Riwayat Penjualan Mode Toko: daftar transaksi yang sudah
/// selesai (terbaru di depan) untuk ditinjau satu per satu —
/// bahan review owner sampai level nota.
///
/// Dari detail satu penjualan, struknya bisa dicetak ulang
/// atau dibagikan ulang (pelanggan kehilangan nota, dsb.).
/// Setiap salinan yang keluar dari layar ini SELALU bertanda
/// REPRINT: banner + waktu cetak ulang tercetak di struk dan
/// watermark diagonal menempel di pratinjau/gambar yang
/// dibagikan — salinan tidak boleh bisa berlagak nota asli
/// (permintaan NUX 4 Nov 2026).
///
/// VOID penjualan lunas SENGAJA belum ada di sini: aksi itu
/// mengubah data penjualan dan menunggu gerbang otentikasi
/// PIN owner (Fase peran Mode Toko).
class StoreSalesHistoryScreen extends StatefulWidget {
  const StoreSalesHistoryScreen({
    super.key,
    required this.receiptLabels,
    required this.receiptDataFor,
  });

  /// Label struk (bahasa aktif) dari layar Mode Toko.
  final StoreReceiptLabels receiptLabels;

  /// Pembangun data struk dari layar Mode Toko (kop toko,
  /// footer, ID outlet diputuskan di sana); argumen kedua =
  /// waktu cetak ulang (null untuk struk asli).
  final StoreReceiptData Function(
    CompletedOrder record,
    DateTime? reprintAt,
  ) receiptDataFor;

  @override
  State<StoreSalesHistoryScreen> createState() =>
      _StoreSalesHistoryScreenState();
}

class _StoreSalesHistoryScreenState extends State<StoreSalesHistoryScreen> {
  final _historyStore = StoreOrderHistoryStore();
  List<CompletedOrder> _orders = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Simpanan terbaca kronologis (tertua dulu); daftar review
    // menampilkan yang terbaru di depan.
    final orders = await _historyStore.load();
    if (!mounted) return;
    setState(() {
      _orders = orders.reversed.toList();
      _loading = false;
    });
  }

  String _billTitle(CompletedOrder record) => record.billNo > 0
      ? formatBillNo(record.time, record.billNo)
      : receiptTimestampText(record.time);

  String _methodLabel(CompletedOrder record) {
    final l10n = context.l10n;
    if (record.payMethod == payMethodCash) return l10n.storeCash;
    if (record.payMethod == payMethodQris) return l10n.storeQris;
    return record.grandTotalRp == 0 ? l10n.storeReceiptPromo : '—';
  }

  Future<void> _openDetail(CompletedOrder record) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StoreSaleDetailScreen(
          record: record,
          billTitle: _billTitle(record),
          methodLabel: _methodLabel(record),
          receiptLabels: widget.receiptLabels,
          receiptDataFor: widget.receiptDataFor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storeSalesHistory),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF34D399)),
            )
          : _orders.isEmpty
              ? Center(
                  child: Text(
                    l10n.storeSalesHistoryEmpty,
                    style: TextStyle(color: context.palette.muted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  itemCount: _orders.length,
                  itemBuilder: (context, i) {
                    final record = _orders[i];
                    return _saleRow(context, record);
                  },
                ),
    );
  }

  Widget _saleRow(BuildContext context, CompletedOrder record) {
    final muted = TextStyle(fontSize: 12, color: context.palette.muted);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetail(record),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.palette.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _billTitle(record),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    receiptTimestampText(record.time),
                    style: muted,
                  ),
                  if (record.customerName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(record.customerName, style: muted),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rp${formatRupiah(record.grandTotalRp)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(_methodLabel(record), style: muted),
                if (record.isVoid) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'VOID',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.palette.dangerSoft,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.palette.muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Detail satu penjualan selesai: ringkasan + rincian item +
/// aksi salinan struk (cetak ulang / pratinjau & bagikan),
/// selalu bertanda REPRINT.
class _StoreSaleDetailScreen extends StatelessWidget {
  const _StoreSaleDetailScreen({
    required this.record,
    required this.billTitle,
    required this.methodLabel,
    required this.receiptLabels,
    required this.receiptDataFor,
  });

  final CompletedOrder record;
  final String billTitle;
  final String methodLabel;
  final StoreReceiptLabels receiptLabels;
  final StoreReceiptData Function(
    CompletedOrder record,
    DateTime? reprintAt,
  ) receiptDataFor;

  /// Salinan hanya untuk penjualan rupiah yang LUNAS: record
  /// VOID tidak pernah menjadi nota pelanggan, dan record era
  /// nusan lama tidak punya struk rupiah.
  bool get _canReprint => record.isRupiahEra && !record.isVoid;

  List<StoreReceiptElement> _reprintElements() => buildStoreReceiptElements(
        receiptDataFor(record, DateTime.now()),
        receiptLabels,
      );

  Future<void> _reprint(BuildContext context) async {
    final settings = await PrintService.loadSettings();
    final outcome = await PrintService.printStoreReceipt(
      settings: settings,
      elements: _reprintElements(),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(printOutcomeMessage(context.l10n, outcome))),
    );
  }

  Future<void> _previewShare(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => StoreReceiptPreviewDialog(
        elements: _reprintElements(),
        watermark: 'REPRINT',
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storeSaleDetailTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.palette.border),
            ),
            child: Column(
              children: [
                _row(context, l10n.storeReceiptBillNo, billTitle),
                _row(
                  context,
                  l10n.storeReceiptDate,
                  receiptTimestampText(record.time),
                ),
                if (record.customerName.isNotEmpty)
                  _row(context, l10n.storeReceiptCustomer,
                      record.customerName),
                _row(context, l10n.storeSalePaymentLabel, methodLabel),
                _row(
                  context,
                  l10n.storeReceiptGrandTotal,
                  'Rp${formatRupiah(record.grandTotalRp)}',
                ),
                if (record.isVoid) _row(context, 'Status', 'VOID'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.palette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in record.lines) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${line.qty} × ${line.label}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        'Rp${formatRupiah(line.lineGrossRp)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (line.lineDiscountRp > 0)
                    Text(
                      '${l10n.storeDiscount} -Rp${formatRupiah(line.lineDiscountRp)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_canReprint) ...[
            ElevatedButton.icon(
              onPressed: () => _reprint(context),
              icon: const Icon(Icons.print_rounded, size: 19),
              label: Text(l10n.storeReprintReceipt),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _previewShare(context),
              icon: const Icon(Icons.share_rounded, size: 19),
              label: Text(l10n.storePreviewShareReceipt),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ] else
            Text(
              l10n.storeSaleReceiptUnavailable,
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
        ],
      ),
    );
  }
}
