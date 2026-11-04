import 'dart:async';

import 'package:flutter/material.dart';
import '../locale_controller.dart';
import '../unit_controller.dart';
import '../theme.dart';
import 'package:flutter/services.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/bolt12_service.dart';
import '../services/lsp_service.dart';
import '../services/payment_notes.dart';
import '../services/saved_invoices.dart';
import '../utils/animated_checkmark.dart';
import '../utils/coin_alert.dart';
import '../utils/bolt11_info.dart';
import '../utils/format.dart';
import '../utils/friendly_error.dart';
import '../utils/receive_watch.dart';

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

  /// Kolom Catatan (opsional): teksnya menjadi deskripsi invoice
  /// (tag 'd' BOLT11) — dibaca pembayar sebelum membayar dan
  /// disimpan sebagai judul catatan pembayaran ini di riwayat.
  final _noteController = TextEditingController();
  String? _invoice;
  bool _loading = false;
  String? _error;

  /// Pengawasan event pembayaran masuk untuk invoice aktif.
  Timer? _eventTimer;
  int _watchGen = 0;
  bool _watching = false;

  /// Penanda layar sudah ditutup (dispose): pengawas event hanya
  /// boleh berjalan selama layar aktif — lihat receive_watch.dart.
  bool _disposed = false;
  bool _received = false;
  BigInt? _receivedMsat;

  /// Penggulir body: penerimaan mengantar layar ke atas supaya
  /// panel sukses terlihat tanpa scroll manual dari user.
  final _scrollController = ScrollController();

  /// Kunci blok perayaan penerimaan: sesudah perayaan terpicu,
  /// layar digulir sampai blok INI terlihat (ensureVisible) —
  /// bukan sekadar ke atas — supaya fokusnya tepat ke perayaan
  /// walau user sedang tergulir jauh ke bawah (mis. di panel
  /// Kode Bayar Statis) saat pembayaran masuk.
  final _celebrationKey = GlobalKey();

  /// Kunci blok QR invoice Bolt11 & blok QR Kode Bayar Statis:
  /// sasaran gulir sesudah invoice/offer selesai dibuat, supaya
  /// QR yang baru lahir langsung terlihat tanpa scroll manual
  /// (temuan NUX 4 Nov 2026: gulir momen pembuatan belum ada —
  /// yang ada hanya gulir perayaan penerimaan).
  final _invoiceKey = GlobalKey();
  final _staticKey = GlobalKey();

  /// Label/deskripsi offer statis pilihan user (kosong/null =
  /// teks bawaan bahasa aplikasi). Tersimpan di
  /// [Bolt12OfferStore]; menggantinya membuat offer dibuat
  /// ulang karena deskripsi adalah bagian dari offer.
  String? _customOfferDescription;

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
    // Pengawas event bersenjata sejak layar dibuka (bukan hanya
    // sesudah ada invoice/panel statis): pembayaran offer yang
    // tiba kapan pun selama user di layar ini harus terayakan.
    _syncWatcher();
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
  /// Deskripsi offer yang berlaku: label kustom user bila
  /// dipasang, selain itu teks bawaan bahasa aplikasi.
  String get _offerDescription =>
      _customOfferDescription ?? context.l10n.staticOfferDescription;

  Future<void> _prefetchStaticOffer() async {
    // Label kustom dibaca lebih dulu: offer yang dibuat/
    // dipakai harus yang berlabel berlaku, bukan bawaan.
    _customOfferDescription =
        await Bolt12OfferStore().loadCustomDescription();
    if (!mounted) return;
    final result = await _bolt12Service.ensureOffer(
        description: _offerDescription);
    if (result.outcome == StaticOfferOutcome.ready && mounted) {
      setState(() => _staticOffer = result.offer);
    }
  }

  /// Buka/tutup panel Kode Bayar Statis. Saat dibuka dan offer
  /// belum tersedia, pembuatan dicoba (lagi) — inilah titik coba
  /// ulang alami sesudah node tersambung ke LSP.
  ///
  /// Pembayaran offer masuk lewat Event_PaymentReceived yang sama
  /// seperti invoice Bolt11 (handler PaymentClaimed di ldk-node
  /// menerbitkan event itu untuk semua PaymentPurpose, termasuk
  /// Bolt12OfferPayment). Pengawas event layar ini bersenjata
  /// selama layar aktif — membuka/menutup panel tidak lagi
  /// menyalakan/mematikannya — jadi panel sukses tampil untuk
  /// pembayaran ke kode statis baik QR-nya sedang ditampilkan
  /// maupun tidak, bukan cuma suara + getar dari detektor
  /// dashboard (temuan lapangan NUX 3 Nov 2026).
  void _toggleStaticCode() {
    setState(() => _staticOpen = !_staticOpen);
    if (_staticOpen && _staticOffer == null && !_staticLoading) {
      _loadStaticOffer();
    } else if (_staticOpen && _staticOffer != null) {
      // Panel dibuka dengan offer sudah siap: gulir ke QR-nya.
      _scrollToKey(_staticKey);
    }
    _syncWatcher();
  }

  Future<void> _loadStaticOffer() async {
    setState(() {
      _staticLoading = true;
      _staticError = null;
    });
    final result = await _bolt12Service.ensureOffer(
        description: _offerDescription);
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
    // Offer baru tampil: gulir ke QR-nya (permintaan NUX —
    // sesudah Create Static layar mengantar ke kodenya).
    if (result.outcome == StaticOfferOutcome.ready) {
      _scrollToKey(_staticKey);
    }
  }

  /// Ubah label (deskripsi) offer statis: dialog teks; simpan
  /// memasang label kustom (kosong = kembali ke bawaan),
  /// membuang offer tersimpan, lalu offer dibuat ulang dengan
  /// label baru — kode bayar yang beredar berganti, jadi
  /// bagikan ulang kode barunya sesudah mengganti label.
  Future<void> _editOfferLabel() async {
    final controller = TextEditingController(
      text: _customOfferDescription ?? '',
    );
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(ctx.l10n.staticCodeLabelTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 100,
              decoration: InputDecoration(
                hintText: ctx.l10n.staticOfferDescription,
                filled: true,
                fillColor: ctx.palette.cardAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ctx.l10n.staticCodeLabelHint,
              style: TextStyle(fontSize: 12, color: ctx.palette.muted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(ctx.l10n.storeSettingsSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null || !mounted) return;
    final trimmed = saved.trim();
    final store = Bolt12OfferStore();
    await store.saveCustomDescription(trimmed.isEmpty ? null : trimmed);
    await store.clearOffer();
    if (!mounted) return;
    setState(() {
      _customOfferDescription = trimmed.isEmpty ? null : trimmed;
      _staticOffer = null;
      _staticError = null;
    });
    _loadStaticOffer();
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
      // Kolom nominal terisi dalam satuan tampilan aktif, dengan
      // format yang sama seperti yang dihasilkan pemformat isian.
      _amountController.text = formatAmountNumber(
          restored.amountMsat, UnitController.unit.value,
          locale: LocaleController.locale.value.languageCode);
    });
    _syncWatcher();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopWatching();
    _amountController.dispose();
    _noteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _createInvoice() async {
    // Kolom nominal diketik dalam satuan tampilan aktif (saklar
    // Profil): parse eksak ke msat oleh parser terpusat — tanpa
    // floating point, presisi melewati batas satuan ditolak.
    final unit = UnitController.unit.value;
    final locale = LocaleController.locale.value.languageCode;
    final amountMsat = parseAmountInputToMsat(
        _amountController.text, unit,
        locale: locale);
    if (amountMsat == null) {
      setState(() => _error = context.l10n.invalidAmount);
      return;
    }

    _stopWatching();
    setState(() {
      _loading = true;
      _error = null;
      _invoice = null;
      _received = false;
      _receivedMsat = null;
      _restored = false;
    });

    // Catatan user (bila diisi) menjadi deskripsi invoice;
    // kosong → teks bawaan "Terima {amount}" seperti sebelumnya.
    final note = _noteController.text.trim();
    final description = resolveInvoiceDescription(
        note: note,
        fallback: context.l10n.receiveInvoiceDesc(
            formatAmountWithUnit(amountMsat, unit, locale: locale)));

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
      // Invoice baru lahir: gulir ke blok QR-nya supaya user
      // langsung melihat kode yang harus dibagikan.
      _scrollToKey(_invoiceKey);
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
        // Catatan user ditautkan ke hash invoice ini: catatan
        // pembayaran node tidak membawa deskripsi, jadi tanpa
        // simpanan ini riwayat penerimaan tidak bisa berjudul
        // catatannya sendiri.
        if (note.isNotEmpty) {
          await PaymentNoteStore().save(info.paymentHashHex, note);
        }
      }
      _syncWatcher();
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
      // Pembuatan gagal dengan panel statis masih terbuka:
      // pengawas offer harus hidup lagi (di awal pembuatan ia
      // dimatikan supaya antrean bersih untuk invoice baru).
      _syncWatcher();
    }
  }

  /// Selaraskan pengawas event dengan keadaan layar: pengawas
  /// berjalan selama layar aktif dan berhenti sesudah layar
  /// ditutup — keputusan murninya di [receiveWatcherShouldRun].
  /// Aman dipanggil berulang: pengawas yang sudah sesuai keadaan
  /// tidak diutak-atik, jadi tidak ada timer ganda dan tidak ada
  /// kuras antrean berulang.
  void _syncWatcher() {
    final shouldRun = receiveWatcherShouldRun(screenActive: !_disposed);
    if (shouldRun && !_watching) {
      _startWatching();
    } else if (!shouldRun && _watching) {
      _stopWatching();
    }
  }

  void _stopWatching() {
    _eventTimer?.cancel();
    _eventTimer = null;
    _watchGen++;
    _watching = false;
  }

  /// Tunggu pembayaran lewat antrean event node
  /// (Event.paymentReceived dari binding LDK). Satu event yang
  /// sama melayani invoice Bolt11 dan offer Bolt12: di ldk-node,
  /// PaymentReceived diterbitkan dari handler PaymentClaimed untuk
  /// semua PaymentPurpose, termasuk Bolt12OfferPayment.
  ///
  /// Antrean event lebih dulu dikuras: event adalah antrean bersama
  /// satu node, jadi PaymentReceived milik pembayaran lama yang belum
  /// sempat dibaca tidak boleh memicu status sukses palsu di sini.
  Future<void> _startWatching() async {
    _eventTimer?.cancel();
    final gen = ++_watchGen;
    _watching = true;
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
    if (!mounted || gen != _watchGen) return;
    try {
      // Sekali tick, baca sampai 20 event: pembukaan channel JIT
      // menghasilkan beberapa event sebelum PaymentReceived.
      // Pengawas SENGAJA tetap membaca selama panel sukses tampil:
      // pembayaran berikutnya yang tiba di tengah perayaan harus
      // tertangkap dan menggantikan panel (lihat _handleReceived).
      for (var i = 0; i < 20; i++) {
        final e = await widget.lspService.pollNextEvent();
        if (e == null) break;
        if (e is Event_PaymentReceived) {
          _handleReceived(e, gen);
          return;
        }
      }
    } catch (_) {
      // Gagal baca sesaat — coba lagi di tick berikut.
    }
  }

  /// Satu pembayaran sungguhan tiba (invoice Bolt11 maupun offer
  /// Bolt12 — cabang ini buta-jenis; untuk offer [_invoice] memang
  /// null sehingga pembersihan simpanan terlewati dengan aman).
  ///
  /// Panel sukses tampil dengan nominal penerimaan INI dan layar
  /// digulir sampai panel terlihat. Panel TIDAK menutup sendiri:
  /// user menutupnya dengan tombol Selesai (keputusan NUX
  /// 4 Nov 2026 — perayaan yang menutup otomatis bisa hilang
  /// sebelum sempat dibaca). Penerimaan lain yang tiba selama
  /// panel tampil menggantikan nominal panel, jadi tidak ada
  /// penerimaan yang hilang diam-diam. Pengawas TIDAK dimatikan
  /// di sini — ia terus membaca selama layar aktif.
  void _handleReceived(Event_PaymentReceived e, int gen) {
    // Rayakan di sini juga (bunyi + getar), bersamaan dengan
    // tanda centang: pengawas event layar ini adalah pemicu
    // tercepat dan pasti untuk pembayaran yang sedang ditunggu,
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
    if (!mounted || gen != _watchGen) return;
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
      _noteController.clear();
    });
    _scrollToCelebration();
    _syncWatcher();
  }

  /// Tombol Selesai pada panel sukses: reset panel supaya layar
  /// siap menerima pembayaran berikutnya tanpa user keluar
  /// halaman, lalu selaraskan pengawas — ia tetap berjalan selama
  /// layar aktif (offer memang untuk dibayar berulang, dan
  /// pembayaran berikutnya bisa tiba kapan saja).
  void _finishCelebration() {
    if (!mounted) return;
    setState(() {
      _received = false;
      _receivedMsat = null;
    });
    _scrollToTop();
    _syncWatcher();
  }

  /// Gulir halus sampai blok perayaan terlihat di layar.
  /// Dipanggil sesudah perayaan terpicu & frame ter-render:
  /// ensureVisible mengantar tepat ke blok perayaan (fokusnya
  /// perayaan itu sendiri). Blok belum terpasang (sangat jarang)
  /// → jatuh ke gulir ke atas seperti perilaku lama.
  void _scrollToCelebration() => _scrollToKey(_celebrationKey,
      fallbackToTop: true);

  /// Gulir halus sampai blok berkunci [key] terlihat — dipakai
  /// perayaan (sesudah pembayaran tiba) dan blok QR invoice /
  /// offer statis (sesudah keduanya selesai dibuat).
  void _scrollToKey(GlobalKey key, {bool fallbackToTop = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = key.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      } else if (fallbackToTop) {
        _scrollToTop();
      }
    });
  }

  /// Gulir halus ke atas: panel sukses dirender dekat atas kolom,
  /// sedangkan pemicu penerimaan (panel offer) ada di bawah —
  /// tanpa ini user harus scroll manual untuk melihatnya.
  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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
        controller: _scrollController,
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
              inputFormatters: [
                _ThousandsSeparatorFormatter(
                  thousandsSep:
                      context.l10n.localeName == 'en' ? ',' : '.',
                  decimalSep: context.l10n.localeName == 'en' ? '.' : ',',
                ),
              ],
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
                suffixText: context.displayUnit.label,
                suffixStyle: TextStyle(
                    fontSize: 16,
                    color: context.palette.muted,
                    fontWeight: FontWeight.w600),
              ),
            ),
            // Konversi ke satuan lawan dari nominal yang diketik —
            // tampil hanya bila isian terbaca sebagai nominal sah.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _amountController,
              builder: (context, value, _) {
                final parsed = parseAmountInputToMsat(value.text,
                    UnitController.unit.value,
                    locale: LocaleController.locale.value.languageCode);
                if (parsed == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.formatWalletConversion(parsed),
                    style: TextStyle(
                        fontSize: 13, color: context.palette.muted),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // Kolom catatan (opsional): menjadi deskripsi invoice.
            Text(context.l10n.receiveNoteLabel,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLength: 140,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: context.l10n.receiveNoteHint,
                hintStyle: TextStyle(color: context.palette.hint),
                counterText: '',
                filled: true,
                fillColor: context.palette.cardAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
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
                key: _celebrationKey,
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
                        context.l10n.receivedAmount(context.formatWalletAmount(
                            _receivedMsat ?? BigInt.zero)),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.fundsArrived,
                      style:
                          TextStyle(fontSize: 12, color: context.palette.muted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    // Penutup manual (keputusan NUX 4 Nov 2026):
                    // perayaan tidak lagi hilang sendiri oleh
                    // timer — user yang menyelesaikannya.
                    ElevatedButton(
                      onPressed: _finishCelebration,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(context.l10n.done),
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
                key: _invoiceKey,
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
                    // Level H (bukan M): tengah QR tertutup logo
                    // ELNUX, koreksi kesalahan tertinggi menjaga
                    // QR tetap terpindai.
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                    embeddedImage: const AssetImage('assets/app_icon.png'),
                    embeddedImageStyle: const QrEmbeddedImageStyle(
                      size: Size(46, 46),
                    ),
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
                  key: _staticKey,
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
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                      embeddedImage:
                          const AssetImage('assets/app_icon.png'),
                      embeddedImageStyle: const QrEmbeddedImageStyle(
                        size: Size(46, 46),
                      ),
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
                const SizedBox(height: 6),
                // Label offer yang berlaku + jalan mengubahnya
                // (custom user; kosong = bawaan).
                Text(
                  '${context.l10n.staticCodeLabelTitle}: $_offerDescription',
                  style: TextStyle(
                      fontSize: 12, color: context.palette.muted),
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: _staticLoading ? null : _editOfferLabel,
                  child: Text(context.l10n.staticCodeLabelEdit),
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

/// Pemformat kolom nominal Terima: terapkan pemisah ribuan
/// secara langsung saat user mengetik, supaya tampilan selalu
/// rapi — bukan hanya saat nilai diisi program (mis. pulihan
/// invoice pending yang terisi "1.000", lalu rusak formatnya
/// begitu user mengedit). Pemisah mengikuti locale aplikasi
/// (id: '.' ribuan & ',' desimal; en sebaliknya) — pasangan
/// pemisah yang sama dengan parser terpusat
/// [parseAmountInputToMsat]. Format hanya tampilan: nilai angka
/// murninya dipulihkan saat parsing di
/// _ReceiveScreenState._createInvoice. Pecahan TIDAK dipotong di
/// sini: batas presisi satuan ditegakkan parser saat pembuatan
/// invoice, jadi pemformat tidak pernah diam-diam mengubah angka
/// yang diketik user.
class _ThousandsSeparatorFormatter extends TextInputFormatter {
  final String thousandsSep;
  final String decimalSep;

  const _ThousandsSeparatorFormatter({
    this.thousandsSep = '.',
    this.decimalSep = ',',
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.isEmpty) return newValue;

    // Pisah bagian bulat dan pecahan pada pemisah desimal
    // pertama; selain digit dibuang (termasuk pemisah ribuan
    // lama).
    final comma = raw.indexOf(decimalSep);
    var intDigits = (comma >= 0 ? raw.substring(0, comma) : raw)
        .replaceAll(RegExp(r'[^0-9]'), '');
    final fracDigits = comma >= 0
        ? raw.substring(comma + 1).replaceAll(RegExp(r'[^0-9]'), '')
        : null;

    // Buang nol di depan yang berlebih: "05" -> "5", "00" -> "0".
    intDigits = intDigits.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    // Kelompokkan ribuan dengan pemisah locale.
    final buf = StringBuffer();
    for (var i = 0; i < intDigits.length; i++) {
      if (i > 0 && (intDigits.length - i) % 3 == 0) buf.write(thousandsSep);
      buf.write(intDigits[i]);
    }
    var text = buf.toString();
    if (fracDigits != null) text = '$text$decimalSep$fracDigits';

    // Kursor selalu di akhir teks hasil format.
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
