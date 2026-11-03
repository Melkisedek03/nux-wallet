import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/print_service.dart';
import '../services/store_order_history.dart';
import '../services/store_report_export.dart';
import '../services/store_shift.dart';
import '../utils/store_report.dart';

/// Layar Laporan Penjualan Mode Toko: pratinjau dua dokumen
/// (ringkasan + rincian per item) untuk satu jendela — satu
/// shift (berjalan atau lampau) atau satu hari kalender lokal —
/// dengan aksi Cetak (58mm) dan Bagikan PDF.
///
/// Dokumen disusun murni dari record tersimpan oleh fungsi di
/// `store_report.dart`; layar ini hanya memilih jendelanya dan
/// menyambungkan aksi cetak/bagikan.
class StoreShiftReportScreen extends StatefulWidget {
  final StoreShift? shift;
  final DateTime? day;

  const StoreShiftReportScreen.forShift(StoreShift this.shift) : day = null;
  const StoreShiftReportScreen.forDay(DateTime this.day) : shift = null;

  @override
  State<StoreShiftReportScreen> createState() => _StoreShiftReportScreenState();
}

class _StoreShiftReportScreenState extends State<StoreShiftReportScreen> {
  final _historyStore = StoreOrderHistoryStore();
  final _shiftStore = StoreShiftStore();

  bool _loading = true;
  bool _sharing = false;
  String _periodLine = '';
  bool _stillOpen = false;
  bool _isEmpty = true;
  String _summaryText = '';
  String _detailsText = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _locale =>
      context.l10n.localeName.startsWith('en') ? 'en' : 'id';

  ShiftReportLabels _labels() {
    final l10n = context.l10n;
    return ShiftReportLabels(
      summaryTitle: l10n.storeReportSummaryTitle,
      detailsTitle: l10n.storeReportDetailsTitle,
      itemQty: l10n.storeReportItemQty,
      subTotal: l10n.storeSubtotal,
      discount: l10n.storeDiscount,
      orderDiscount: l10n.storeOrderDiscount,
      pointsDiscount: l10n.storeReportPointsDiscount,
      totalOrder: l10n.storeReportTotalOrder,
      totalOrderInfo: l10n.storeReportTotalOrderInfo,
      invoicesLabel: l10n.storeReportInvoices,
      invUnit: l10n.storeReportInvUnit,
      cashLabel: l10n.storeReportCash,
      qrisLabel: l10n.storeReportQris,
      pointsIssued: l10n.storeReportPointsIssued,
      pointsPending: l10n.storeReportPointsPending,
      pointsRedeemed: l10n.storeReportPointsRedeemed,
      voidInfo: l10n.storeReportVoidInfo,
      voidItemQty: l10n.storeReportVoidItemQty,
      voidSubTotal: l10n.storeReportVoidSubTotal,
      voidDiscount: l10n.storeReportVoidDiscount,
      voidTotalOrder: l10n.storeReportVoidTotalOrder,
      qtyLabel: l10n.storeReportQty,
      otherCategory: l10n.storeReportOther,
      generatedOn: l10n.storeReportGeneratedOn,
      menusText: l10n.storeReportMenus,
    );
  }

  Future<void> _load() async {
    final orders = await _historyStore.load();
    if (!mounted) return;
    final l10n = context.l10n;
    final now = DateTime.now();
    late final DateTime from;
    late final DateTime to;
    String? periodNote;

    final shift = widget.shift;
    if (shift != null) {
      from = shift.openedAt;
      to = shift.windowEnd(now);
      _stillOpen = shift.isOpen;
      _periodLine = formatShiftPeriod(
        openedAt: shift.openedAt,
        closedAt: shift.closedAt,
        locale: _locale,
        stillOpenWord: l10n.storeShiftStillOpen,
      );
    } else {
      final day = widget.day!;
      from = DateTime(day.year, day.month, day.day);
      to = from.add(const Duration(days: 1));
      _stillOpen = false;
      _periodLine = formatDayPeriod(day: from, locale: _locale);
      final shifts = await _shiftStore.load();
      if (!mounted) return;
      final count = countShiftsInWindow(shifts, from: from, to: to, now: now);
      // Catatan jumlah shift hanya bila hari itu memang memuat
      // beberapa shift — jujur, tanpa mengarang nomor shift.
      if (count > 1) periodNote = l10n.storeReportShiftsNote(count);
    }

    final summary = aggregateShiftSales(orders, from: from, to: to);
    final details = aggregateMenuDetails(orders, from: from, to: to);
    final docs = buildShiftReportDocuments(
      labels: _labels(),
      periodLine: _periodLine,
      periodNote: periodNote,
      summary: summary,
      details: details,
      generatedAt: now,
      locale: _locale,
    );
    setState(() {
      _summaryText = docs.summary;
      _detailsText = docs.details;
      _isEmpty = summary.invoiceCount == 0 && summary.voids.count == 0;
      _loading = false;
    });
  }

  String get _fileStem {
    final shift = widget.shift;
    String stamp(DateTime t) =>
        '${t.year}${t.month.toString().padLeft(2, '0')}'
        '${t.day.toString().padLeft(2, '0')}';
    return shift != null
        ? 'laporan-shift-${stamp(shift.openedAt)}'
        : 'laporan-tanggal-${stamp(widget.day!)}';
  }

  Future<void> _print() async {
    final l10n = context.l10n;
    final settings = await PrintService.loadSettings();
    final lines = [
      ..._summaryText.split('\n'),
      '',
      '',
      ..._detailsText.split('\n'),
    ];
    final outcome = await PrintService.printTextLines(
      settings: settings,
      lines: lines,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(printOutcomeMessage(l10n, outcome))));
  }

  Future<void> _sharePdf() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final file = await writeShiftReportPdf(
        summaryText: _summaryText,
        detailsText: _detailsText,
        fileStem: _fileStem,
      );
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      // Gagal menyusun/membagikan PDF — diamkan; pratinjau tetap
      // tampil dan jalur cetak tidak terpengaruh.
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storeSalesReport),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF34D399)),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.receipt_long_rounded,
                            size: 19,
                            color: Color(0xFF34D399),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _periodLine,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_stillOpen)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x2610B981),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                l10n.storeShiftStillOpen,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF34D399),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_isEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          l10n.storeReportEmpty,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _DocPreview(title: l10n.storeReportSummaryTitle, text: _summaryText),
                      const SizedBox(height: 16),
                      _DocPreview(title: l10n.storeReportDetailsTitle, text: _detailsText),
                    ],
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _print,
                            icon: const Icon(Icons.print_rounded, size: 19),
                            label: Text(l10n.storeReportPrint),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _sharing ? null : _sharePdf,
                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 19),
                            label: Text(l10n.storeReportSharePdf),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Satu dokumen laporan sebagai teks monospace dalam kartu —
/// persis teks yang dicetak/dibagikan (layar adalah kebenaran).
class _DocPreview extends StatelessWidget {
  final String title;
  final String text;

  const _DocPreview({required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.border),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
