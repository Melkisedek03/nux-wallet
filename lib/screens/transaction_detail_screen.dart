import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../locale_controller.dart';
import '../unit_controller.dart';
import '../services/print_service.dart';
import '../services/saved_invoices.dart';
import '../theme.dart';

/// Layar Detail Transaksi — dibuka dengan mengetuk baris di daftar
/// Aktivitas/Riwayat.
///
/// Menampilkan rincian satu catatan pembayaran node: jenis, status,
/// nominal, waktu, ID pembayaran utuh, dan hash pembayaran (atau
/// txid untuk on-chain) yang bisa disalin.
///
/// Khusus pembayaran MASUK yang masih pending dan invoice-nya
/// tersimpan lokal (lihat SavedInvoiceStore): invoice ditampilkan
/// lagi lengkap dengan QR + tombol Salin selama belum kedaluwarsa,
/// supaya user yang aplikasinya sempat tertutup tetap bisa
/// membagikan invoice yang sama. Invoice kedaluwarsa hanya diberi
/// lencana + penjelasan, tanpa QR — invoice mati tidak bisa dibayar.
///
/// Khusus pembayaran KELUAR yang masih pending — satu-satunya
/// keadaan "uang menggantung" yang sungguhan, karena dananya
/// terkunci di jalan: statusnya berlabel "Sedang diproses" dan
/// layar menampilkan kalimat penenang bahwa uangnya aman dan
/// akan selesai sendiri (keputusan NUX 30 Okt 2026).
///
/// Khusus pembayaran JIT yang SUDAH lunas — pembayaran inilah
/// yang melahirkan channel penerima dan dikenai potongan biaya
/// pembuatan 0,5%: layar menampilkan kalimat penjelasan supaya
/// user paham kenapa jumlah yang diterimanya berkurang, dan
/// bahwa potongan itu hanya sekali (keputusan NUX 30 Okt 2026).
/// Pembayaran berikutnya lewat channel yang sama tercatat
/// sebagai Bolt11 biasa, jadi catatan ini tidak muncul lagi.
class TransactionDetailScreen extends StatelessWidget {
  final PaymentDetails payment;

  /// Invoice tersimpan yang hash-nya cocok dengan pembayaran ini;
  /// null bila tidak ada simpanan (mis. dibuat sebelum fitur simpan
  /// invoice ada, atau pembayaran keluar/on-chain).
  final SavedInvoice? savedInvoice;

  const TransactionDetailScreen({
    super.key,
    required this.payment,
    this.savedInvoice,
  });

  String _hex(Iterable<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Hash pembayaran dari jenis pembayaran Lightning; null untuk
  /// on-chain (yang punya txid, bukan hash pembayaran).
  String? get _paymentHashHex {
    final kind = payment.kind;
    if (kind is PaymentKind_Bolt11) return _hex(kind.hash.data);
    if (kind is PaymentKind_Bolt11Jit) return _hex(kind.hash.data);
    if (kind is PaymentKind_Spontaneous) return _hex(kind.hash.data);
    // Pembayaran offer/refund Bolt12: hash boleh kosong selama
    // catatan belum tuntas — tampilkan bila ada, sama seperti
    // pemetaan ekspor CSV.
    if (kind is PaymentKind_Bolt12Offer) {
      return kind.hash == null ? null : _hex(kind.hash!.data);
    }
    if (kind is PaymentKind_Bolt12Refund) {
      return kind.hash == null ? null : _hex(kind.hash!.data);
    }
    return null;
  }

  String? get _txid {
    final kind = payment.kind;
    if (kind is PaymentKind_Onchain) return kind.txid.hash;
    return null;
  }

  bool get _isJit => payment.kind is PaymentKind_Bolt11Jit;
  bool get _isOnchain => payment.kind is PaymentKind_Onchain;

  String _fullTime(BuildContext context) {
    final t = DateTime.fromMillisecondsSinceEpoch(
        payment.latestUpdateTimestamp.toInt() * 1000);
    final en = context.l10n.localeName.startsWith('en');
    const monthsId = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    const monthsEn = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final months = en ? monthsEn : monthsId;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]} ${t.year}, $hh.$mm';
  }

  /// Cetak struk transaksi ini ke printer 58mm yang dipilih di
  /// Pengaturan Printer. Teks struk hanya ASCII (printer thermal
  /// tidak mengenal glif layar seperti lambang petir/rantai dan
  /// tanda minus tipografi), jadi jenis ditulis polos dan jumlah
  /// memakai '-'.
  Future<void> _printReceipt(BuildContext context) async {
    final l10n = context.l10n;
    final isIn = payment.direction == PaymentDirection.inbound;
    final statusText = switch (payment.status) {
      PaymentStatus.pending => isIn ? l10n.pending : l10n.processing,
      PaymentStatus.failed => l10n.failed,
      PaymentStatus.succeeded => l10n.txSucceeded,
    };
    final amountText = payment.amountMsat == null
        ? '-'
        : '${isIn ? '+' : '-'}${context.formatWalletAmount(payment.amountMsat!)}';
    final typeText =
        _isJit ? 'Lightning JIT' : _isOnchain ? 'On-chain' : 'Lightning';
    final txid = _txid;
    final hashHex = _paymentHashHex;
    final printableInvoice = savedInvoice != null &&
            isIn &&
            payment.status == PaymentStatus.pending &&
            !savedInvoice!.isExpiredAt(DateTime.now())
        ? savedInvoice!.invoice
        : null;
    final settings = await PrintService.loadSettings();
    final outcome = await PrintService.printReceipt(
      settings: settings,
      receipt: ReceiptData(
        typeText: typeText,
        statusText: statusText,
        amountText: amountText,
        timeText: _fullTime(context),
        hashLabel: txid != null ? 'TxID' : (hashHex != null ? 'Hash' : null),
        hashValue: txid ?? hashHex,
        invoice: printableInvoice,
      ),
      typeLabel: l10n.txType,
      statusLabel: l10n.txStatus,
      timeLabel: l10n.txTime,
      defaultFooter: l10n.receiptDefaultFooter,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(printOutcomeMessage(l10n, outcome))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIn = payment.direction == PaymentDirection.inbound;
    final statusText = switch (payment.status) {
      PaymentStatus.pending =>
        isIn ? context.l10n.pending : context.l10n.processing,
      PaymentStatus.failed => context.l10n.failed,
      PaymentStatus.succeeded => context.l10n.txSucceeded,
    };
    final amountText = payment.amountMsat == null
        ? '—'
        : '${isIn ? '+' : '−'}${context.formatWalletAmount(payment.amountMsat!)}';
    final typeText = _isJit
        ? '⚡ JIT'
        : _isOnchain
            ? '⛓ on-chain'
            : '⚡ Lightning';
    final hashHex = _paymentHashHex;
    final txid = _txid;

    final showSaved = savedInvoice != null &&
        isIn &&
        payment.status == PaymentStatus.pending;
    final savedExpired =
        showSaved && savedInvoice!.isExpiredAt(DateTime.now());
    final showNotSavedNote = savedInvoice == null &&
        isIn &&
        payment.status == PaymentStatus.pending &&
        !_isOnchain;
    final showProcessingNote =
        !isIn && payment.status == PaymentStatus.pending;
    final showJitNote =
        _isJit && payment.status == PaymentStatus.succeeded;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.txDetailTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: context.l10n.print,
            onPressed: () => _printReceipt(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  _row(context, context.l10n.txType, typeText),
                  _row(context, context.l10n.txStatus, statusText),
                  _row(context, context.l10n.amountLabel, amountText),
                  _row(context, context.l10n.txTime, _fullTime(context)),
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
                children: [
                  _copyRow(context, context.l10n.txPaymentId,
                      _hex(payment.id.data)),
                  if (hashHex != null)
                    _copyRow(context, context.l10n.txPaymentHash, hashHex),
                  if (txid != null)
                    _copyRow(context, 'TxID', txid),
                ],
              ),
            ),
            if (showProcessingNote) ...[
              const SizedBox(height: 20),
              Text(
                context.l10n.txProcessingNote,
                style:
                    TextStyle(fontSize: 13, color: context.palette.muted),
              ),
            ],
            if (showJitNote) ...[
              const SizedBox(height: 20),
              Text(
                context.l10n.txJitNote,
                style:
                    TextStyle(fontSize: 13, color: context.palette.muted),
              ),
            ],
            if (showSaved && !savedExpired) ...[
              const SizedBox(height: 20),
              Text(context.l10n.invoiceTitle,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: QrImageView(
                    data: savedInvoice!.invoice,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.palette.cardAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        savedInvoice!.invoice,
                        style: TextStyle(
                            fontSize: 12, color: context.palette.label),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy,
                          color: Color(0xFF34D399)),
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: savedInvoice!.invoice));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(context.l10n.invoiceCopied)),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.shareInvoiceHint,
                style:
                    TextStyle(fontSize: 12, color: context.palette.muted),
                textAlign: TextAlign.center,
              ),
            ],
            if (showSaved && savedExpired) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(context.l10n.txExpiredBadge,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.palette.dangerSoft)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                context.l10n.txInvoiceExpiredNote,
                style:
                    TextStyle(fontSize: 13, color: context.palette.muted),
              ),
            ],
            if (showNotSavedNote) ...[
              const SizedBox(height: 20),
              Text(
                context.l10n.txInvoiceNotSavedNote,
                style:
                    TextStyle(fontSize: 13, color: context.palette.muted),
              ),
            ],
          ],
        ),
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
            child: Text(label,
                style:
                    TextStyle(fontSize: 13, color: context.palette.muted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _copyRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style:
                    TextStyle(fontSize: 13, color: context.palette.muted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            color: const Color(0xFF34D399),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.txCopied)),
              );
            },
          ),
        ],
      ),
    );
  }
}
