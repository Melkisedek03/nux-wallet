import 'dart:async';

import 'package:flutter/material.dart';
import '../locale_controller.dart';
import '../theme.dart';
import 'package:flutter/services.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/bolt12_service.dart';
import '../services/lsp_service.dart';
import '../services/saved_invoices.dart';
import '../utils/animated_checkmark.dart';
import '../utils/coin_alert.dart';
import '../utils/bolt11_info.dart';
import '../utils/format.dart';
import '../utils/friendly_error.dart';

/// Layar Terima — buat invoice Lightning.
///
/// Alur: user isi nominal → tekan Buat Invoice → QR + invoice muncul →
/// pembayar scan → dana masuk.
///
/// Jalur pembuatan invoice dipilih dari kapasitas terima yang
/// sudah ada ("Jalur 1", keputusan NUX 30 Okt 2026): bila total
/// kapasitas terima channel yang usable mencukupi nominal, invoice
/// yang dibuat adalah invoice Bolt11 biasa lewat channel itu —
/// tanpa potongan kelahiran dan tanpa minimum JIT, jadi penerimaan
/// kecil pun bisa. Invoice JIT (pembayaran pertama sekaligus
/// melahirkan channel 0-conf dari LSP) hanya dipakai bila
/// kapasitas belum cukup, yaitu saat jalur memang harus lahir.
///
/// Invoice yang melahirkan channel punya jumlah minimum dari
/// parameter LSP (min_payment_size_msat = 1.000.000, yaitu 1.000
/// nusan), yang ditegakkan sisi klien SEBELUM invoice dibuat —
/// error node untuk pelanggaran ini generik (LiquidityRequestFailed,
/// sama seperti kegagalan likuiditas lain), jadi layar membedakan
/// kasusnya dari nominal yang diminta: pembuatan gagal + nominal
/// di bawah minimum → pesan khusus yang menjelaskan minimumnya,
/// bukan error umum "Gagal membuat invoice" (keputusan NUX
/// 30 Okt 2026 — info minimum ini wajib sampai ke pengguna).
class ReceiveScreen extends StatefulWidget {
  final LspService lspService;

  const ReceiveScreen({super.key, required this.lspService});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final _amountController = TextEditingController();
  String? _invoice;
  bool _loading = false;
  String? _error;

  /// Pengawasan event pembayaran masuk untuk invoice aktif.
  Timer? _eventTimer;
  int _watchGen = 0;
  bool _received = false;
  BigInt? _receivedMsat;

  /// True bila [_invoice] berasal dari simpanan lokal (invoice
  /// pending terakhir dipulihkan saat layar dibuka), bukan baru
  /// dibuat di sesi ini — ditandai dengan petunjuk di bawah QR.
  bool _restored = false;

  /// Keadaan panel Kode Bayar Statis (offer Bolt12).
  late final Bolt12OfferService _bolt12Service =
      Bolt12OfferService(widget.lspService);
  bool _staticOpen = false;
  bool _staticLoading = false;
  String? _staticOffer;
  String? _staticError;

  @override
  void initState() {
    super.initState();
    _restoreLastInvoice();
    // Sesudah frame pertama: context.l10n belum boleh dibaca di
    // initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetchStaticOffer();
    });
  }

  /// Panaskan offer statis tanpa memblokir layar: bila simpanan
  /// ada (atau node sudah tersambung dan offer bisa dibuat), panel
  /// Kode Bayar Statis langsung siap saat dibuka. Hasil "belum ada
  /// peer" dan kegagalan ditelan diam-diam di sini — usaha yang
  /// sesungguhnya (dengan pesan ke user) terjadi saat panel dibuka,
  /// dan saat itu node mungkin sudah tersambung.
  Future<void> _prefetchStaticOffer() async {
    final result = await _bolt12Service.ensureOffer(
        description: context.l10n.staticOfferDescription);
    if (result.outcome == StaticOfferOutcome.ready && mounted) {
      setState(() => _staticOffer = result.offer);
    }
  }

  /// Buka/tutup panel Kode Bayar Statis. Saat dibuka dan offer
  /// belum tersedia, pembuatan dicoba (lagi) — inilah titik coba
  /// ulang alami sesudah node tersambung ke LSP.
  void _toggleStaticCode() {
    setState(() => _staticOpen = !_staticOpen);
    if (_staticOpen && _staticOffer == null && !_staticLoading) {
      _loadStaticOffer();
    }
  }

  Future<void> _loadStaticOffer() async {
    setState(() {
      _staticLoading = true;
      _staticError = null;
    });
    final result = await _bolt12Service.ensureOffer(
        description: context.l10n.staticOfferDescription);
    if (!mounted) return;
    setState(() {
      _staticLoading = false;
      switch (result.outcome) {
        case StaticOfferOutcome.ready:
          _staticOffer = result.offer;
          _staticError = null;
        case StaticOfferOutcome.needsPeer:
          _staticError = context.l10n.staticCodeNeedsConnection;
        case StaticOfferOutcome.failed:
          _staticError = context.l10n.staticCodeFailed;
      }
    });
  }

  /// Pulihkan invoice pending terakhir yang belum kedaluwarsa dari
  /// simpanan lokal, supaya user yang aplikasinya sempat tertutup
  /// tidak kehilangan invoice yang sudah ia bagikan. Invoice yang
  /// dipulihkan diawasi event pembayarannya sama seperti invoice
  /// yang baru dibuat.
  ///
  /// Sebelum dipulihkan, simpanan direkonsiliasi dulu dengan
  /// catatan pembayaran node: pembayaran invoice ini bisa saja
  /// tiba saat pengguna berada di layar lain, sehingga penghapusan
  /// simpanan oleh pengawas event di layar ini (satu-satunya pemicu
  /// penghapusan) tidak sempat berjalan. Bila node sudah
  /// mencatatnya lunas, simpanan itu basi — buang dan lanjut ke
  /// simpanan berikutnya, jangan pulihkan sebagai "belum dibayar"
  /// (Riwayat, yang membaca catatan yang sama, sudah menampilkan
  /// pembayaran itu sebagai diterima). Gagal membaca catatan (node
  /// sesaat tidak siap) TIDAK membuang apa pun: jatuh ke perilaku
  /// lama, supaya simpanan yang sah tidak hilang hanya karena
  /// baca status gagal sesaat.
  Future<void> _restoreLastInvoice() async {
    final store = SavedInvoiceStore();
    var saved = await store.latestUnexpired();
    if (saved == null || !mounted || _invoice != null) return;
    try {
      final payments = await widget.lspService.listPayments();
      while (saved != null &&
          invoiceAlreadyPaid(payments, saved.paymentHashHex)) {
        await store.removeByHash(saved.paymentHashHex);
        saved = await store.latestUnexpired();
      }
    } catch (_) {
      // Abaikan — pulihkan apa adanya seperti perilaku lama.
    }
    if (saved == null || !mounted || _invoice != null) return;
    final restored = saved;
    setState(() {
      _invoice = restored.invoice;
      _restored = true;
      _amountController.text = formatNusan(restored.amountMsat);
    });
    _startWatching();
  }

  @override
  void dispose() {
    _eventTimer?.cancel();
    _watchGen++;
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _createInvoice() async {
    // Kolom nominal menampilkan pemisah gaya id ('.' ribuan, ','
    // desimal — lihat _ThousandsSeparatorFormatter): buang pemisah
    // tampilan supaya yang terbaca tetap angka murninya.
    final text = _amountController.text
        .trim()
        .replaceAll('.', '')
        .replaceAll(',', '.');
    final nusan = double.tryParse(text);
    if (nusan == null || nusan <= 0) {
      setState(() => _error = context.l10n.invalidAmount);
      return;
    }

    _eventTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _invoice = null;
      _received = false;
      _receivedMsat = null;
      _restored = false;
    });

    // 1 nusan = 1000 msat
    final amountMsat = BigInt.from((nusan * 1000).round());
    final description =
        context.l10n.receiveInvoiceDesc(nusan.toString());

    // Pilih jalur dari kapasitas terima yang sudah ada. Gagal
    // membaca kapasitas (node sesaat tidak siap) tidak boleh
    // menggagalkan pembuatan invoice: pilihannya jatuh ke JIT —
    // perilaku lama yang sudah terbukti.
    var route = ReceiveInvoiceRoute.jit;
    try {
      final inbound = await widget.lspService.usableInboundCapacityMsat();
      route = chooseReceiveInvoiceRoute(
        amountMsat: amountMsat,
        usableInboundCapacityMsat: inbound,
      );
    } catch (_) {
      route = ReceiveInvoiceRoute.jit;
    }

    try {
      final invoice = route == ReceiveInvoiceRoute.regular
          ? await widget.lspService.createRegularInvoice(
              amountMsat: amountMsat,
              description: description,
            )
          : await widget.lspService.createJitInvoice(
              amountMsat: amountMsat,
              description: description,
            );
      setState(() => _invoice = invoice);
      // Simpan invoice di HP (string + hash + kedaluwarsa) supaya
      // tetap bisa dilihat/disalin kembali dari Riwayat atau saat
      // aplikasi dibuka lagi, selama belum kedaluwarsa. Catatan
      // node sendiri tidak menyimpan string invoice. Kegagalan
      // parse/simpan tidak menggagalkan invoice yang sudah jadi.
      final info = parseBolt11Info(invoice);
      if (info != null) {
        await SavedInvoiceStore().save(SavedInvoice(
          invoice: invoice,
          paymentHashHex: info.paymentHashHex,
          amountMsat: amountMsat,
          createdAt: DateTime.now(),
          expiresAt: info.expiresAt.toLocal(),
        ));
      }
      _startWatching();
    } catch (e) {
      // Di bawah minimum kelahiran (1.000 nusan = 1.000.000 msat,
      // parameter LSP) invoice JIT memang tidak bisa dibuat —
      // sampaikan alasannya dengan jelas, bukan error umum. Pesan
      // minimum ini khusus kegagalan di jalur JIT: kegagalan jalur
      // biasa (kapasitas sebenarnya cukup) sebabnya lain, jadi
      // tetap pesan umum walau nominalnya di bawah 1.000.
      // Kegagalan lain pada nominal berapa pun tetap pesan biasa.
      setState(() => _error = route == ReceiveInvoiceRoute.jit &&
              amountMsat < BigInt.from(1000000)
          ? context.l10n.receiveJitMinimumNote
          : friendlyError(e,
              fallback: context.l10n.createInvoiceFailed,
              l10n: context.l10n));
    } finally {
      setState(() => _loading = false);
    }
  }

  /// Tunggu pembayaran invoice ini lewat antrean event node
  /// (Event.paymentReceived dari binding LDK).
  ///
  /// Antrean event lebih dulu dikuras: event adalah antrean bersama
  /// satu node, jadi PaymentReceived milik pembayaran lama yang belum
  /// sempat dibaca tidak boleh memicu status sukses palsu di sini.
  Future<void> _startWatching() async {
    _eventTimer?.cancel();
    final gen = ++_watchGen;
    await _drainEvents();
    if (!mounted || gen != _watchGen) return;
    _eventTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollEvents(gen),
    );
  }

  Future<void> _drainEvents() async {
    try {
      for (var i = 0; i < 100; i++) {
        final e = await widget.lspService.pollNextEvent();
        if (e == null) break;
      }
    } catch (_) {
      // Node belum siap — abaikan, polling berikutnya yang bekerja.
    }
  }

  Future<void> _pollEvents(int gen) async {
    if (!mounted || gen != _watchGen || _received) return;
    try {
      // Sekali tick, baca sampai 20 event: pembukaan channel JIT
      // menghasilkan beberapa event sebelum PaymentReceived.
      for (var i = 0; i < 20; i++) {
        final e = await widget.lspService.pollNextEvent();
        if (e == null) break;
        if (e is Event_PaymentReceived) {
          _eventTimer?.cancel();
          // Rayakan di sini juga (bunyi + getar), bersamaan dengan
          // tanda centang: pengawas event layar ini adalah pemicu
          // tercepat dan pasti untuk invoice yang sedang ditunggu,
          // sedangkan deteksi polling dashboard bisa datang beberapa
          // detik sesudahnya. CoinAlert menahan perayaan ganda untuk
          // penerimaan yang sama.
          CoinAlert.play();
          // Invoice ini sudah lunas: hapus dari simpanan supaya
          // tidak dipulihkan lagi sebagai pending di sesi berikut.
          final currentInvoice = _invoice;
          if (currentInvoice != null) {
            final info = parseBolt11Info(currentInvoice);
            if (info != null) {
              SavedInvoiceStore().removeByHash(info.paymentHashHex);
            }
          }
          if (mounted && gen == _watchGen) {
            setState(() {
              _received = true;
              _receivedMsat = e.amountMsat;
              // Layar kembali bersih untuk penerimaan berikutnya
              // (keputusan NUX 2 Nov 2026): invoice yang sudah
              // lunas dibersihkan — panel sukses di bawah sudah
              // menggantikannya — dan kolom jumlah dikosongkan;
              // sebelumnya nominal invoice yang lunas tetap
              // tertinggal di kolom.
              _invoice = null;
              _restored = false;
              _amountController.clear();
            });
          }
          return;
        }
      }
    } catch (_) {
      // Gagal baca sesaat — coba lagi di tick berikut.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.receiveTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info JIT
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Text('\u26A1', style: TextStyle(fontSize: 24)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.jitInfo,
                      style: TextStyle(fontSize: 13, color: context.palette.label),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Amount input
            Text(context.l10n.amountLabel,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              inputFormatters: [_ThousandsSeparatorFormatter()],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                  fontSize: 32, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(
                    color: context.palette.hint),
                filled: true,
                fillColor: context.palette.cardAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                suffixText: 'nusan',
                suffixStyle: TextStyle(
                    fontSize: 16,
                    color: context.palette.muted,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            // Create button
            ElevatedButton(
              onPressed: _loading ? null : _createInvoice,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.l10n.createInvoice,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
            if (_received) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0x2610B981),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0x6610B981),
                  ),
                ),
                child: Column(
                  children: [
                    const AnimatedCheckmark(),
                    const SizedBox(height: 12),
                    Text(context.l10n.paymentReceived,
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF34D399))),
                    const SizedBox(height: 6),
                    Text(
                        context.l10n.receivedAmount(
                            formatNusan(_receivedMsat ?? BigInt.zero)),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.fundsArrived,
                      style:
                          TextStyle(fontSize: 12, color: context.palette.muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ] else if (_invoice != null) ...[
              const SizedBox(height: 24),
              if (_restored) ...[
                Text(
                  context.l10n.receiveRestoredHint,
                  style: TextStyle(
                      fontSize: 12, color: context.palette.warningIcon),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
              ],
              Text(context.l10n.invoiceTitle,
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: QrImageView(
                    data: _invoice!,
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
                        _invoice!,
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
                            ClipboardData(text: _invoice!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.l10n.invoiceCopied)),
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
            // Kode Bayar Statis (offer Bolt12) — fondasi Mode
            // Toko: satu kode untuk semua pembayaran masuk,
            // pembayar yang menentukan jumlahnya.
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: _toggleStaticCode,
              icon: const Icon(Icons.qr_code_2_rounded, size: 20),
              label: Text(context.l10n.staticCodeTitle,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF34D399),
                side: BorderSide(
                    color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            if (_staticOpen) ...[
              const SizedBox(height: 16),
              if (_staticLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF34D399)),
                  ),
                )
              else if (_staticOffer != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: QrImageView(
                      data: _staticOffer!,
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
                          _staticOffer!,
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
                              ClipboardData(text: _staticOffer!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text(context.l10n.staticCodeCopied)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.staticCodeHint,
                  style: TextStyle(
                      fontSize: 12, color: context.palette.muted),
                  textAlign: TextAlign.center,
                ),
              ] else if (_staticError != null) ...[
                Text(_staticError!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _staticLoading ? null : _loadStaticOffer,
                  child: Text(context.l10n.updateRetry),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Pemformat kolom nominal Terima: terapkan pemisah ribuan '.'
/// gaya id secara langsung saat user mengetik, supaya tampilan
/// selalu rapi — bukan hanya saat nilai diisi program (mis. pulihan
/// invoice pending yang terisi "1.000", lalu rusak formatnya begitu
/// user mengedit). Pecahan memakai koma desimal, sama seperti
/// [formatNusan]. Format hanya tampilan: nilai angka murninya
/// dipulihkan saat parsing di _ReceiveScreenState._createInvoice.
class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.isEmpty) return newValue;

    // Pisah bagian bulat dan pecahan pada koma desimal pertama;
    // selain digit dibuang (termasuk '.' pemisah ribuan lama).
    final comma = raw.indexOf(',');
    var intDigits = (comma >= 0 ? raw.substring(0, comma) : raw)
        .replaceAll(RegExp(r'[^0-9]'), '');
    final fracDigits = comma >= 0
        ? raw.substring(comma + 1).replaceAll(RegExp(r'[^0-9]'), '')
        : null;

    // Buang nol di depan yang berlebih: "05" -> "5", "00" -> "0".
    intDigits = intDigits.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    // Kelompokkan ribuan dengan '.', pola yang sama seperti
    // formatNusan di utils/format.dart.
    final buf = StringBuffer();
    for (var i = 0; i < intDigits.length; i++) {
      if (i > 0 && (intDigits.length - i) % 3 == 0) buf.write('.');
      buf.write(intDigits[i]);
    }
    var text = buf.toString();
    if (fracDigits != null) text = '$text,$fracDigits';

    // Kursor selalu di akhir teks hasil format.
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
