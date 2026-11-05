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
/// VOID penjualan lunas ada di detail penjualan (Fase A):
/// alasan wajib + persetujuan PIN admin lewat callback layar
/// Mode Toko; record ditandai VOID, bukan dihapus — fakta
/// penjualannya tetap bisa ditinjau di sini bertanda VOID.
class StoreSalesHistoryScreen extends StatefulWidget {
  const StoreSalesHistoryScreen({
    super.key,
    required this.receiptLabels,
    required this.receiptDataFor,
    this.onVoidApproval,
    this.onVoidSale,
    this.outletId = '',
  });

  /// ID outlet perangkat (prefix nota Fase B) untuk format
  /// nomor bill di daftar & detail.
  final String outletId;

  /// Label struk (bahasa aktif) dari layar Mode Toko.
  final StoreReceiptLabels receiptLabels;

  /// Pembangun data struk dari layar Mode Toko (kop toko,
  /// footer, ID outlet diputuskan di sana); argumen kedua =
  /// waktu cetak ulang (null untuk struk asli).
  final StoreReceiptData Function(
    CompletedOrder record,
    DateTime? reprintAt,
  ) receiptDataFor;

  /// Gerbang persetujuan VOID penjualan lunas (PIN admin di
  /// layar Mode Toko); null = VOID tidak ditawarkan.
  final Future<bool> Function()? onVoidApproval;

  /// Eksekusi VOID sesudah alasan terisi & persetujuan lolos:
  /// record ditandai VOID + audit ditulis pemanggil.
  final Future<void> Function(CompletedOrder record, String reason)?
      onVoidSale;

  @override
  State<StoreSalesHistoryScreen> createState() =>
      _StoreSalesHistoryScreenState();
}

class _StoreSalesHistoryScreenState extends State<StoreSalesHistoryScreen> {
  final _historyStore = StoreOrderHistoryStore();
  List<CompletedOrder> _orders = const [];
  bool _loading = true;

  /// Filter tanggal daftar (permintaan NUX 5 Nov 2026):
  /// bawaan HARI INI — data lama dilihat lewat chip Kemarin
  /// atau pemilih tanggal, bukan menumpuk di daftar utama.
  DateTime _filterDay = DateTime.now();

  List<CompletedOrder> get _visibleOrders => [
        for (final o in _orders)
          if (o.time.year == _filterDay.year &&
              o.time.month == _filterDay.month &&
              o.time.day == _filterDay.day)
            o,
      ];

  bool _isDay(DateTime day, DateTime other) =>
      day.year == other.year && day.month == other.month && day.day == other.day;

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
      ? formatBillNo(record.time, record.billNo, outletId: widget.outletId)
      : receiptTimestampText(record.time);

  String _methodLabel(CompletedOrder record) {
    final l10n = context.l10n;
    if (record.payMethod == payMethodCash) return l10n.storeCash;
    if (record.payMethod == payMethodQris) return l10n.storeQris;
    if (record.payMethod == payMethodSplit) return l10n.storeMethodSplit;
    if (record.payMethod != null) return record.payMethod!;
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
          onVoidApproval: widget.onVoidApproval,
          onVoidSale: widget.onVoidSale,
        ),
      ),
    );
    // Detail bisa mengubah record (VOID penjualan lunas) —
    // segarkan daftar saat kembali.
    if (mounted) _load();
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Bar filter tanggal: Hari Ini / Kemarin /
                // pilih tanggal bebas.
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.storeFilterToday),
                        selected: _isDay(_filterDay, DateTime.now()),
                        onSelected: (_) =>
                            setState(() => _filterDay = DateTime.now()),
                      ),
                      ChoiceChip(
                        label: Text(l10n.storeFilterYesterday),
                        selected: _isDay(
                          _filterDay,
                          DateTime.now().subtract(const Duration(days: 1)),
                        ),
                        onSelected: (_) => setState(
                          () => _filterDay =
                              DateTime.now().subtract(const Duration(days: 1)),
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.calendar_month_rounded,
                            size: 17),
                        label: Text(
                          '${_filterDay.day.toString().padLeft(2, '0')}/'
                          '${_filterDay.month.toString().padLeft(2, '0')}/'
                          '${_filterDay.year}',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _filterDay,
                            firstDate: DateTime(2025),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null && mounted) {
                            setState(() => _filterDay = picked);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _visibleOrders.isEmpty
                      ? Center(
                          child: Text(
                            l10n.storeSalesHistoryEmpty,
                            style: TextStyle(color: context.palette.muted),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                          itemCount: _visibleOrders.length,
                          itemBuilder: (context, i) =>
                              _saleRow(context, _visibleOrders[i]),
                        ),
                ),
              ],
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
    this.onVoidApproval,
    this.onVoidSale,
  });

  final CompletedOrder record;
  final String billTitle;
  final String methodLabel;
  final StoreReceiptLabels receiptLabels;
  final StoreReceiptData Function(
    CompletedOrder record,
    DateTime? reprintAt,
  ) receiptDataFor;
  final Future<bool> Function()? onVoidApproval;
  final Future<void> Function(CompletedOrder record, String reason)?
      onVoidSale;

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

  /// VOID penjualan lunas (Fase A): dialog alasan (wajib) →
  /// persetujuan PIN admin (callback layar Mode Toko) →
  /// eksekusi VOID oleh pemanggil → kembali ke daftar yang
  /// tersegar (record kini bertanda VOID).
  Future<void> _voidSale(BuildContext context) async {
    final approval = onVoidApproval;
    final execute = onVoidSale;
    if (approval == null || execute == null) return;
    final l10n = context.l10n;
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.storeVoidSaleTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.storeVoidSaleBody,
              style: TextStyle(fontSize: 13, color: ctx.palette.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: l10n.storeVoidReasonLabel,
                filled: true,
                fillColor: ctx.palette.cardAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final text = reasonController.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx, text);
            },
            child: Text(l10n.storeVoidSaleButton),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !context.mounted) return;
    if (!await approval()) return;
    if (!context.mounted) return;
    await execute(record, reason);
    if (!context.mounted) return;
    Navigator.pop(context);
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
                if (record.operatorName.isNotEmpty)
                  _row(context, l10n.storeReceiptCashier,
                      record.operatorName),
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
            if (onVoidApproval != null && onVoidSale != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _voidSale(context),
                icon: const Icon(Icons.block_rounded, size: 19),
                label: Text(l10n.storeVoidSaleButton),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
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
