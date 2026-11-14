import 'package:flutter/material.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:vibration/vibration.dart';
import '../config.dart';
import '../locale_controller.dart';
import '../unit_controller.dart';
import '../theme.dart';
import 'package:flutter/services.dart';
import '../services/lsp_service.dart';
import '../services/offline_bridge.dart';
import '../services/payment_notes.dart';
import '../utils/amount_input.dart';
import '../utils/animated_checkmark.dart';
import '../utils/bolt11_info.dart';
import '../utils/bolt12_info.dart';
import '../utils/coin_alert.dart';
import '../utils/format.dart';
import '../utils/friendly_error.dart';
import 'scan_screen.dart';

/// Normalisasi hasil scan QR menjadi teks invoice siap pakai:
/// buang awalan "lightning:" (beberapa QR memakainya), dan samakan
/// huruf menjadi kecil — invoice bech32 sah dalam huruf besar semua,
/// diseragamkan agar lolos pemeriksaan awalan di layar Kirim.
String normalizeInvoice(String raw) {
  var text = raw.trim();
  if (text.toLowerCase().startsWith('lightning:')) {
    text = text.substring('lightning:'.length).trim();
  }
  if (text.toLowerCase().startsWith('ln')) {
    text = text.toLowerCase();
  }
  return text;
}

/// Layar Kirim — bayar invoice Lightning.
///
/// Alur: tempel/scan invoice → konfirmasi (dialog + getar) → bayar →
/// TUNGGU hasil akhir. Tombol Bayar TIDAK langsung membayar: user
/// harus menekan Bayar sekali lagi di dialog konfirmasi. Ini
/// sengaja, karena pembayaran Lightning bersifat instan dan tidak
/// bisa dibatalkan — ketukan Bayar yang tidak sengaja sebelumnya
/// langsung mengirim dana.
///
/// Centang berhasil hanya tampil setelah pembayaran benar-benar
/// berstatus sukses di catatan node (lihat
/// LspService.waitForPaymentOutcome): perintah kirim yang diterima
/// node bukan bukti pembayaran sampai — pembayaran bisa gagal di
/// jalan, misalnya penerima sedang tidak terhubung. Bila hasil
/// akhir tidak kunjung jelas sampai batas tunggu, layar menyatakan
/// "masih diproses" apa adanya dan mengarahkan ke Riwayat, bukan
/// mengklaim sukses atau gagal.
///
/// Layar juga menampilkan angka yang benar-benar bisa dikirim
/// (kapasitas keluar channel menurut node — sudah bersih dari
/// cadangan pengaman channel) dan memeriksanya SEBELUM dialog
/// konfirmasi: nominal yang melewati saldo ditolak sebagai saldo
/// tidak cukup; nominal yang muat di saldo tetapi tidak di
/// kapasitas kirim ditolak dengan penjelasan cadangan, bukan
/// dibiarkan gagal di node sesudah dicoba (keputusan NUX
/// 31 Okt 2026, turunan temuan RouteNotFound: saldo 995 yang
/// batas kirimnya 0 gagal berulang tanpa penjelasan).
///
/// Saat sesi jembatan offline aktif dan peer tertaut adalah
/// satu-satunya peer yang tersambung, angka "bisa dikirim" dan
/// pemeriksaan pra-bayar invoice Bolt11 dibatasi ke channel
/// peer itu saja — channel LSP yang tidak terjangkau tidak lagi
/// ikut menjanjikan saldo yang tidak bisa bergerak (temuan
/// lapangan 13 Nov 2026). Offer Bolt12 memakai angka gabungan
/// seperti sebelumnya.
class SendScreen extends StatefulWidget {
  final LspService lspService;

  /// Jembatan offline (diterima sama seperti di ReceiveScreen);
  /// sesi jembatannya yang aktif ikut menandai konteks langsung.
  final OfflineBridgeService? bridge;

  const SendScreen({super.key, required this.lspService, this.bridge});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _invoiceController = TextEditingController();

  /// Kolom nominal untuk offer Bolt12 variable-amount: hanya
  /// tampil bila isi kolom kode terbaca sebagai offer tanpa
  /// nominal tetap (lihat [_offerInfo]).
  final _offerAmountController = TextEditingController();

  /// Info offer dari isi kolom kode saat ini; null bila isinya
  /// bukan offer atau strukturnya tidak terbaca. Diperbarui oleh
  /// [_syncOfferInfo] setiap isi kolom berubah (ketik, tempel,
  /// scan) — murni bahan tampilan panel offer; keputusan bayar
  /// selalu membaca ulang dari teks saat tombol ditekan.
  Bolt12OfferInfo? _offerInfo;

  /// Isi kolom kode yang terakhir disinkronkan ke [_offerInfo],
  /// supaya pendengar perubahan tidak memarse ulang string yang
  /// sama berulang kali.
  String _offerInfoText = '';

  /// Nominal invoice Bolt11 yang terbaca dari isi kolom kode saat
  /// ini (null bila bukan invoice bernominal / isinya offer).
  /// Bahan baris nominal + konversi satuan di formulir — jumlah
  /// yang sama yang dinilai pemeriksaan pra-bayar & dialog.
  BigInt? _bolt11AmountMsat;

  bool _loading = false;
  String? _error;
  bool _paid = false;

  /// Penggulir badan + kunci panel sukses: sesudah pembayaran
  /// berhasil, layar digulir sampai panel perayaan terlihat —
  /// panel tinggal di bawah formulir, tanpa gulir ia sering
  /// terlewat user (temuan NUX 4 Nov 2026). Panel ditutup
  /// manual dengan tombol Selesai, sama seperti layar Terima.
  final _scrollController = ScrollController();
  final _successKey = GlobalKey();

  /// True selama perintah kirim sudah diterima node dan aplikasi
  /// sedang menunggu status final pembayaran.
  bool _waitingOutcome = false;

  /// True bila batas tunggu habis dan status masih pending:
  /// pembayaran belum jelas hasil akhirnya (bukan sukses, bukan
  /// gagal) — user diarahkan memeriksa Riwayat dan dilarang
  /// membayar ulang invoice yang sama.
  bool _stillPending = false;

  /// Saldo Lightning total (msat) menurut node — angka yang sama
  /// dengan yang tampil di Beranda. Null selama belum terbaca.
  BigInt? _balanceMsat;

  /// Kapasitas kirim EFEKTIF (msat) yang tampil di baris "Bisa
  /// dikirim": angka lingkup peer saat pembatasan offline aktif
  /// ([_linkedSendableMsat] tidak null), angka gabungan bila
  /// tidak. Null selama belum terbaca.
  BigInt? _sendableMsat;

  /// Kapasitas kirim gabungan (msat) dari SEMUA channel usable —
  /// angka yang dinilai pemeriksaan pra-bayar sebagai batas
  /// cadangan, dan bahan keadaan nol-bisa-kirim. Disimpan
  /// terpisah dari [_sendableMsat] supaya penilaian cadangan
  /// tidak tertukar dengan angka lingkup peer.
  BigInt? _meltedSendableMsat;

  /// Kapasitas kirim (msat) hanya dari channel usable ke peer
  /// yang tertaut dalam sesi jembatan offline — null bila
  /// pembatasan tidak aktif (tidak ada sesi, tidak tertaut, peer
  /// tertaut belum tersambung di node, atau ada peer lain yang
  /// tersambung sehingga jalur LSP tetap bisa dipakai). Bila
  /// tidak null, inilah batas yang dipakai pemeriksaan pra-bayar
  /// invoice Bolt11 dan yang tampil di baris "Bisa dikirim".
  BigInt? _linkedSendableMsat;

  /// True bila ada channel usable; tanpa itu kapasitas kirim
  /// tidak bisa dinilai (bisa jadi sebabnya koneksi, bukan
  /// cadangan) dan penjelasan cadangan tidak ditampilkan.
  bool _hasUsableChannel = false;

  /// Selisih saldo − kapasitas kirim (msat) saat sebuah percobaan
  /// bayar tertahan cadangan; mengisi kotak penjelasan cadangan.
  /// Null = kotak tidak tampil.
  BigInt? _reserveHeldMsat;

  /// Kapasitas kirim (msat) pada saat yang sama dengan
  /// [_reserveHeldMsat] — pasangan angkanya di kotak yang sama,
  /// ditangkap bersama supaya kotaknya konsisten walau angka
  /// layar disegarkan sesudahnya.
  BigInt? _reserveSendableMsat;

  /// Kapasitas kirim lingkup peer (msat) pada saat sebuah
  /// percobaan bayar tertahan batas peer; mengisi kotak
  /// penjelasan batas peer. Null = kotak tidak tampil.
  BigInt? _peerLimitSendableMsat;

  @override
  void initState() {
    super.initState();
    _invoiceController.addListener(_syncOfferInfo);
    _refreshSendable();
  }

  @override
  void dispose() {
    _invoiceController.removeListener(_syncOfferInfo);
    _invoiceController.dispose();
    _offerAmountController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Gulir halus sampai panel sukses terlihat (sesudah frame
  /// panel ter-render). Panel tak terpasang → gulir ke bawah
  /// sekali sebagai cadangan.
  void _scrollToSuccess() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = _successKey.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      } else if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Sinkronkan [_offerInfo] dengan isi kolom kode terbaru.
  /// Dipanggil pendengar pengontrol — mencakup ketikan, tempel
  /// dari tombol Tempel, dan hasil scan, karena ketiganya mengubah
  /// teks pengontrol yang sama.
  void _syncOfferInfo() {
    final text = _invoiceController.text.trim();
    if (text == _offerInfoText) return;
    _offerInfoText = text;
    final info = isBolt12Offer(text) ? parseOfferInfo(text) : null;
    final bolt11Amount =
        info == null ? parseBolt11AmountMsat(text) : null;
    if ((info != _offerInfo || bolt11Amount != _bolt11AmountMsat) &&
        mounted) {
      setState(() {
        _offerInfo = info;
        _bolt11AmountMsat = bolt11Amount;
      });
    }
  }

  /// Muat/segarkan saldo + kapasitas kirim dari node.
  ///
  /// Kegagalan baca ditelan diam-diam: angka kirim hanya tambahan
  /// kejujuran tampilan & bahan pemeriksaan pra-bayar — layar
  /// Kirim harus tetap berfungsi persis seperti sebelumnya bila
  /// angka ini tidak tersedia.
  Future<void> _refreshSendable() async {
    try {
      final channels = await widget.lspService.listChannels();
      final balance = await widget.lspService.getLightningBalance();
      final linkedSendable = await _linkedPeerSendable(channels);
      if (!mounted) return;
      final melted = totalUsableOutboundCapacityMsat(channels);
      setState(() {
        _balanceMsat = balance;
        _meltedSendableMsat = melted;
        _linkedSendableMsat = linkedSendable;
        _sendableMsat = linkedSendable ?? melted;
        _hasUsableChannel = channels.any((c) => c.isUsable);
      });
    } catch (_) {
      // Abaikan — lihat keterangan di atas.
    }
  }

  /// Kapasitas kirim lingkup peer untuk [channels]: jumlah
  /// kapasitas keluar channel usable ke peer yang tertaut dalam
  /// sesi jembatan offline — ATAU null bila pembatasan tidak
  /// berlaku, dan pemanggil memakai angka gabungan seperti biasa.
  ///
  /// Pembatasan berlaku bila sesi jembatan aktif, perangkat
  /// tertaut, DAN peer tertaut itu satu-satunya peer yang
  /// tersambung ke node. Syarat terakhir inilah yang menjaga
  /// perilaku online: selama peer LSP (atau peer lain) masih
  /// tersambung, pembayaran bisa menempuh jalur itu, jadi angka
  /// gabungan tetap benar. Saat offline hanya peer tertaut yang
  /// tersambung, sehingga channel ke dialah satu-satunya jalur
  /// yang bisa dipakai — angka gabungan yang ikut menghitung
  /// channel LSP menjadi janji kosong (temuan lapangan 13 Nov
  /// 2026: saldo kirim tampil besar, pembayaran gagal tanpa rute
  /// karena channel langsung tinggal 679.000 nusan yang bisa
  /// dikirim).
  ///
  /// Kegagalan membaca daftar peer mematikan pembatasan
  /// (fail-open): node tetap penentu akhir seperti sebelumnya.
  Future<BigInt?> _linkedPeerSendable(List<ChannelDetails> channels) async {
    final bridge = widget.bridge;
    final linkedId = bridge?.peerNodeId;
    if (bridge == null ||
        !bridge.sessionActive ||
        !bridge.isLinked ||
        linkedId == null) {
      return null;
    }
    List<PeerDetails> peers;
    try {
      peers = await widget.lspService.listPeerDetails();
    } catch (_) {
      return null;
    }
    final peer = linkedId.toLowerCase();
    var linkedConnected = false;
    var othersConnected = false;
    for (final p in peers) {
      if (!p.isConnected) continue;
      if (p.nodeId.hex.toLowerCase() == peer) {
        linkedConnected = true;
      } else {
        othersConnected = true;
      }
    }
    if (!linkedConnected || othersConnected) return null;
    return usableOutboundCapacityToPeer(channels, linkedId);
  }

  /// Sesi jembatan offline sedang aktif DAN perangkat tertaut —
  /// konteks tempat pesan kegagalan tanpa-rute berlaku dan tempat
  /// pemeriksaan pra-bayar bisa dibatasi ke peer tertaut. Tanpa
  /// tautan, tidak ada "perangkat ini" yang bisa disebut di
  /// pesan mana pun.
  bool get _offlineLinked =>
      widget.bridge?.sessionActive == true && widget.bridge?.isLinked == true;

  /// Keadaan "saldo ada tetapi yang bisa dikirim nol karena
  /// cadangan" — satu-satunya keadaan yang selalu menampilkan
  /// penjelasan cadangan tanpa menunggu percobaan bayar.
  /// Dinilai dari angka GABUNGAN: cadangan adalah soal saldo
  /// menyeluruh, bukan soal peer.
  bool get _zeroSendable =>
      _hasUsableChannel &&
      _meltedSendableMsat != null &&
      _meltedSendableMsat == BigInt.zero &&
      _balanceMsat != null &&
      _balanceMsat! > BigInt.zero;

  /// Keadaan "saldo kirim gabungan ada, tetapi yang bisa dikirim
  /// ke perangkat tertaut nol": channel langsung sudah habis
  /// terpakai (atau belum ada jalurnya) sementara channel lain
  /// masih bersaldo — formulir jalan buntu tanpa penjelasan,
  /// sama seperti keadaan nol-bisa-kirim karena cadangan.
  bool get _zeroLinkedSendable =>
      _linkedSendableMsat != null &&
      _linkedSendableMsat == BigInt.zero &&
      _meltedSendableMsat != null &&
      _meltedSendableMsat! > BigInt.zero;

  /// Getar singkat saat dialog konfirmasi muncul — penanda fisik
  /// bahwa ketukan Bayar belum mengirim apa-apa, masih bisa dibatalkan.
  /// Kegagalan getar (perangkat tanpa vibrator, izin, dll.) ditelan
  /// diam-diam, sama seperti CoinAlert: tidak boleh mengganggu alur.
  Future<void> _vibrateConfirm() async {
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(duration: 150);
      }
    } catch (_) {
      // Tanpa getar pun konfirmasi tetap jalan.
    }
  }

  /// Potongan invoice untuk dialog konfirmasi: cukup untuk
  /// membedakan invoice ini dari invoice lain, tanpa memenuhi dialog.
  String _invoicePreview(String invoice) {
    if (invoice.length <= 40) return invoice;
    return '${invoice.substring(0, 24)}…${invoice.substring(invoice.length - 12)}';
  }

  /// Ketukan Bayar pertama: validasi, getar, lalu minta konfirmasi.
  /// Pembayaran baru jalan bila user menekan Bayar di dialog.
  Future<void> _onPayPressed() async {
    final invoice = _invoiceController.text.trim();
    if (invoice.isEmpty) {
      setState(() => _error = context.l10n.pasteInvoiceFirst);
      return;
    }
    // Offer Bolt12 (kode bayar lno1…) jalurnya sendiri SEBELUM
    // jalur Bolt11: parser Bolt11 node menolak string offer dan
    // pengguna membaca pesan "tidak valid / kedaluwarsa" yang
    // menyesatkan — offer-nya sendiri sah dan tanpa kedaluwarsa.
    if (isBolt12Offer(invoice)) {
      await _onPayOfferPressed(invoice);
      return;
    }
    if (!invoice.startsWith('ln')) {
      setState(() => _error = context.l10n.invalidInvoice);
      return;
    }
    // Pemeriksaan pra-bayar: nominal dibaca dari awalan invoice,
    // lalu dinilai terhadap saldo & kapasitas kirim terbaru.
    // Nominal yang memang tidak bisa dikirim ditolak DI SINI
    // dengan alasannya — bukan dibiarkan gagal di node sesudah
    // dicoba. Invoice tanpa nominal terbaca (amountless / tidak
    // terurai) melewati pemeriksaan ini dan mengalir seperti
    // sebelumnya; node tetap penentu akhirnya.
    final amountMsat = parseBolt11AmountMsat(invoice);
    if (amountMsat != null) {
      // Invoice Bolt11 dinilai dengan pembatasan lingkup peer
      // bila berlaku (sesi offline, hanya peer tertaut yang
      // tersambung): nominal yang muat di angka gabungan tetapi
      // melewati kapasitas channel ke perangkat itu ditolak di
      // sini, bukan dibiarkan gagal tanpa rute di node.
      if (!await _checkSendable(amountMsat, scopeToLinkedPeer: true)) {
        return;
      }
    }
    // Deskripsi/catatan invoice (tag 'd') — ditampilkan di dialog
    // konfirmasi dan disimpan sebagai judul pembayaran ini di
    // riwayat. Gagal baca (invoice tak terurai) = tanpa catatan,
    // alur bayar tidak terganggu.
    final bolt11Info = parseBolt11Info(invoice);
    final invoiceDescription = bolt11Info?.description;
    await _vibrateConfirm();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.confirmPayTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.confirmPayBody),
            // Nominal yang akan dikirim, di samping pratinjau
            // invoice — jumlahnya dibaca dari invoice itu sendiri
            // (permintaan lapangan NUX 3 Nov 2026). Invoice tanpa
            // nominal terbaca tidak punya angka jujur untuk
            // ditampilkan di sini; node tetap penentu akhirnya.
            if (amountMsat != null) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.confirmPayAmountLine(
                    context.formatWalletAmount(amountMsat)),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                context.formatWalletConversion(amountMsat),
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
            if (invoiceDescription != null) ...[
              const SizedBox(height: 6),
              Text(invoiceDescription,
                  style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Text(
              _invoicePreview(invoice),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: Text(context.l10n.pay),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _pay(
        () => widget.lspService.payInvoice(invoice),
        // Konteks pesan tanpa-rute: sesi offline tertaut DAN
        // invoice belum kedaluwarsa — invoice kedaluwarsa gagal
        // karena waktunya, bukan karena rutenya, jadi pesannya
        // tidak boleh menyalahkan jalur.
        offlineRouteContext:
            _offlineLinked &&
            !(bolt11Info?.isExpiredAt(DateTime.now()) ?? false),
        onSent: () async {
          // Pembayaran sudah diterima node: tautkan deskripsi
          // invoice ke hash-nya supaya riwayat berjudul catatan
          // ini. Catatan pembayaran node tidak membawa deskripsi.
          final hash = bolt11Info?.paymentHashHex;
          if (hash != null && invoiceDescription != null) {
            await PaymentNoteStore().save(hash, invoiceDescription);
          }
          if (hash != null && _directContext) {
            await PaymentTagStore().saveDirect(hash);
          }
        },
      );
    }
  }

  /// Konteks langsung saat ini: node boot offline atau sesi
  /// jembatan offline aktif. Pembayaran yang dikirim dari
  /// konteks ini pasti berjalan lewat channel langsung (LSP
  /// tidak terjangkau), jadi hash-nya dicatat bertag direct
  /// untuk Riwayat (lihat PaymentTagStore) — node sendiri tidak
  /// mencatat channel jalur pembayaran. Predikat konteksnya sama
  /// dengan yang dipakai layar Terima.
  bool get _directContext => receiveIsOfflineContext(
        bootedOffline: widget.lspService.isOfflineMode,
        bridgeSessionActive: widget.bridge?.sessionActive ?? false,
      );

  /// Pemeriksaan pra-bayar bersama untuk invoice Bolt11 dan
  /// offer Bolt12: nilai [amountMsat] terhadap saldo & kapasitas
  /// kirim terbaru. Mengembalikan true bila pembayaran boleh
  /// lanjut ke dialog konfirmasi; false berarti layar sudah
  /// menyatakan alasannya (saldo tidak cukup / tertahan cadangan
  /// / melewati batas peer) atau layar sudah tidak aktif. Bila
  /// angka saldo/kapasitas belum terbaca, pemeriksaan tidak bisa
  /// dinilai — pembayaran dilanjutkan dan node menjadi penentu,
  /// seperti perilaku lama.
  ///
  /// [scopeToLinkedPeer] (hanya jalur Bolt11) mengaktifkan
  /// penilaian tambahan terhadap kapasitas kirim lingkup peer
  /// bila pembatasan offline berlaku: nominal yang muat di angka
  /// gabungan tetapi melewati angka lingkup ditolak sebagai
  /// batas peer, bukan dibiarkan gagal tanpa rute di node.
  /// Offer Bolt12 memakai perilaku lama (angka gabungan) —
  /// penerima offline sudah dipaksa Bolt11 oleh layar Terima,
  /// jadi kasus bayar-ke-peer-tertaut praktis selalu Bolt11.
  Future<bool> _checkSendable(
    BigInt amountMsat, {
    bool scopeToLinkedPeer = false,
  }) async {
    await _refreshSendable();
    if (!mounted) return false;
    final balance = _balanceMsat;
    final sendable = _meltedSendableMsat;
    if (balance == null || sendable == null) return true;
    final check = evaluateSend(
      amountMsat: amountMsat,
      balanceMsat: balance,
      usableOutboundMsat: sendable,
      hasUsableChannel: _hasUsableChannel,
      scopedUsableOutboundMsat: scopeToLinkedPeer ? _linkedSendableMsat : null,
    );
    if (check == SendCheck.insufficientBalance) {
      setState(() {
        _error = context.l10n.sendInsufficientBalance;
        _reserveHeldMsat = null;
        _reserveSendableMsat = null;
        _peerLimitSendableMsat = null;
      });
      return false;
    }
    if (check == SendCheck.reserveHeld) {
      // Bila kotak nol-bisa-kirim sudah tampil, penjelasan
      // yang sama sudah ada di layar — cukup jangan lanjut.
      setState(() {
        _peerLimitSendableMsat = null;
        if (!_zeroSendable) {
          _error = null;
          _reserveHeldMsat = balance - sendable;
          _reserveSendableMsat = sendable;
        }
      });
      return false;
    }
    if (check == SendCheck.peerLimit) {
      setState(() {
        _error = null;
        _reserveHeldMsat = null;
        _reserveSendableMsat = null;
        _peerLimitSendableMsat = _linkedSendableMsat;
      });
      return false;
    }
    return true;
  }

  /// Ketukan Bayar untuk offer Bolt12: baca info offer, tentukan
  /// nominal (tetap dari offer, atau isian pembayar untuk offer
  /// variable), jalankan pemeriksaan pra-bayar yang sama dengan
  /// invoice, minta konfirmasi, lalu bayar lewat jalur Bolt12.
  Future<void> _onPayOfferPressed(String raw) async {
    final offer = raw.trim().toLowerCase();
    final info = parseOfferInfo(offer);
    if (info == null || info.hasForeignCurrency) {
      setState(() => _error = context.l10n.sendOfferInvalid);
      return;
    }
    if (info.isExpiredAt(DateTime.now())) {
      setState(() => _error = context.l10n.sendOfferExpired);
      return;
    }
    final bool fixedAmount = info.isFixedAmount;
    final BigInt amountMsat;
    if (fixedAmount) {
      amountMsat = info.amountMsat!;
    } else {
      // Isian nominal offer variable diketik dalam satuan
      // tampilan aktif — parse eksak ke msat oleh parser
      // terpusat (tanpa floating point).
      final parsed = parseAmountInputToMsat(
          _offerAmountController.text, UnitController.unit.value,
          locale: LocaleController.locale.value.languageCode);
      if (parsed == null) {
        setState(() => _error = context.l10n.invalidAmount);
        return;
      }
      amountMsat = parsed;
    }
    if (!await _checkSendable(amountMsat)) return;
    await _vibrateConfirm();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.confirmPayOfferTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.confirmPayBody),
            const SizedBox(height: 12),
            Text(
              context.l10n.sendOfferAmountLine(
                  context.formatWalletAmount(amountMsat)),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              context.formatWalletConversion(amountMsat),
              style: const TextStyle(fontSize: 12.5),
            ),
            if (info.description != null) ...[
              const SizedBox(height: 6),
              Text(info.description!, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Text(
              _invoicePreview(offer),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: Text(context.l10n.pay),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final description = info.description;
      PaymentId? sentId;
      await _pay(() async {
        final id = await (fixedAmount
            ? widget.lspService.payOffer(offer)
            : widget.lspService.payOfferUsingAmount(offer, amountMsat));
        sentId = id;
        return id;
      });
      // Tautkan deskripsi offer sebagai catatan riwayat (judul
      // baris di Riwayat pengirim), meniru jalur Bolt11. Bedanya:
      // hash pembayaran offer tidak diketahui sebelum membayar —
      // ia baru muncul di catatan node sesudah invoice penerbit
      // diambil — jadi penautan dilakukan di sini, sesudah _pay
      // menunggu hasil akhir. Gagal taut tidak masalah: riwayat
      // jatuh ke judul baku, pembayaran tidak terpengaruh.
      if (description != null && sentId != null) {
        try {
          final payments = await widget.lspService.listPayments();
          final hashHex =
              findBolt12PaymentHashHex(payments, paymentIdHex(sentId!));
          if (hashHex != null) {
            await PaymentNoteStore().save(hashHex, description);
            if (_directContext) {
              await PaymentTagStore().saveDirect(hashHex);
            }
          }
        } catch (_) {
          // Abaikan — catatan tambahan, bukan bagian pembayaran.
        }
      }
    }
  }

  /// Jalankan perintah kirim [sendPayment] (invoice Bolt11 atau
  /// offer Bolt12 — keduanya mengembalikan ID pembayaran node)
  /// lalu tunggu hasil akhirnya. Validasi bentuk & nominal sudah
  /// dikerjakan pemanggil sebelum konfirmasi.
  ///
  /// [onSent] (bila ada) dijalankan tepat sesudah perintah kirim
  /// diterima node, sebelum hasil akhir ditunggu — tempat pemanggil
  /// menautkan catatan pembayaran. Kegagalannya ditelan: catatan
  /// tidak boleh menggagalkan pembayaran yang sudah berjalan.
  ///
  /// [offlineRouteContext] (hanya jalur Bolt11) menandai bahwa
  /// kegagalan kirim boleh dijelaskan sebagai kegagalan
  /// tanpa-rute ke perangkat tertaut: pemanggil sudah memastikan
  /// sesi offline tertaut dan invoice belum kedaluwarsa.
  Future<void> _pay(
    Future<PaymentId> Function() sendPayment, {
    Future<void> Function()? onSent,
    bool offlineRouteContext = false,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
      _paid = false;
      _stillPending = false;
      _waitingOutcome = false;
      _reserveHeldMsat = null;
      _reserveSendableMsat = null;
      _peerLimitSendableMsat = null;
    });

    try {
      PaymentId paymentId;
      try {
        paymentId = await sendPayment();
      } catch (e) {
        // Gagal kirim sinkron (node menolak perintah sebelum
        // pembayaran tercatat — di lapangan selalu tanpa rute
        // bila nominal melewati channel langsung). Error binding
        // tidak membawa alasan (semua kegagalan kirim diringkas
        // ke satu varian), jadi pesannya dipilih dari konteks
        // yang sudah dipastikan pemanggil, bukan dari teks
        // error. Di luar konteks itu, lempar lagi ke penanganan
        // umum di bawah.
        if (!mounted) return;
        if (offlineRouteContext) {
          setState(() => _error = context.l10n.sendOfflineRouteFailed);
          return;
        }
        rethrow;
      }
      if (onSent != null) {
        try {
          await onSent();
        } catch (_) {
          // Abaikan — lihat dokumentasi [onSent].
        }
      }
      if (!mounted) return;
      // Perintah kirim diterima node — mulai tunggu hasil AKHIR.
      // Tanpa penungguan ini centang berhasil tampil prematur dan
      // kegagalan susulan (mis. penerima offline) tidak pernah
      // diperlihatkan ke pengirim.
      setState(() => _waitingOutcome = true);
      final outcome =
          await widget.lspService.waitForPaymentOutcome(paymentId);
      if (!mounted) return;
      if (outcome == PaymentStatus.succeeded) {
        // Getar sukses — penanda fisik hasil akhir, sama seperti
        // peringatan koin masuk di sisi penerima.
        CoinAlert.vibrateSuccess();
        setState(() => _paid = true);
        _scrollToSuccess();
      } else if (outcome == PaymentStatus.failed) {
        // Hasil akhir gagal sesudah perintah diterima: alasannya
        // hanya hidup di antrean event node (Event.paymentFailed),
        // dan layar ini tidak boleh merebut event yang dibutuhkan
        // layar Terima — jadi pesannya tetap umum. Pesan
        // tanpa-rute hanya untuk gagal sinkron di atas, yang
        // alasannya dipastikan dari konteks.
        setState(() => _error = context.l10n.payFailedFinal);
      } else {
        // Lewat batas tunggu dan masih pending: nyatakan apa
        // adanya, jangan klaim sukses maupun gagal.
        setState(() => _stillPending = true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e,
          fallback: context.l10n.payFailed, l10n: context.l10n));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _waitingOutcome = false;
        });
        // Saldo & kapasitas kirim berubah sesudah pembayaran —
        // segarkan angkanya supaya baris "Bisa dikirim" tidak basi.
        _refreshSendable();
      }
    }
  }

  /// Kotak penjelasan cadangan pengaman channel (amber, pola yang
  /// sama dengan kotak "masih diproses"): dipakai kotak
  /// nol-bisa-kirim yang selalu tampil dan kotak tertahan-cadangan
  /// sesudah percobaan bayar. [hint] + tombol Beranda hanya untuk
  /// keadaan nol-bisa-kirim.
  Widget _reserveBox({
    required BigInt reserveMsat,
    required BigInt sendableMsat,
    bool zeroState = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Text(
            context.l10n.sendReserveNote(
                context.formatWalletAmount(reserveMsat),
                context.formatWalletAmount(sendableMsat)),
            style:
                TextStyle(fontSize: 13, color: context.palette.label),
            textAlign: TextAlign.center,
          ),
          if (zeroState) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.sendZeroSendableHint,
              style:
                  TextStyle(fontSize: 13, color: context.palette.label),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.backToHome,
                  style: const TextStyle(
                      color: Color(0xFF34D399),
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }

  /// Kotak penjelasan batas kirim ke perangkat tertaut (amber,
  /// pola yang sama dengan kotak cadangan): nominal yang diminta
  /// melewati kapasitas kirim channel ke perangkat itu — bukan
  /// soal cadangan, melainkan soal jangkauan saat offline.
  Widget _peerLimitBox({required BigInt sendableMsat}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        context.l10n.sendOfflinePeerLimit(
          context.formatWalletAmount(sendableMsat),
        ),
        style: TextStyle(fontSize: 13, color: context.palette.label),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.sendTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info
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
                      context.l10n.sendInfo,
                      style: TextStyle(fontSize: 13, color: context.palette.label),
                    ),
                  ),
                ],
              ),
            ),
            // Angka yang benar-benar bisa dikirim saat ini —
            // kapasitas keluar menurut node, bukan saldo penuh.
            if (_sendableMsat != null) ...[
              const SizedBox(height: 14),
              Text(
                context.l10n
                    .sendableLine(context.formatWalletAmount(_sendableMsat!)),
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: context.palette.label),
              ),
            ],
            // Saldo ada tetapi nol yang bisa dikirim (seluruhnya
            // tertahan cadangan): jelaskan + beri jalan keluar,
            // jangan biarkan formulir jadi jalan buntu.
            if (_zeroSendable) ...[
              const SizedBox(height: 14),
              _reserveBox(
                reserveMsat: _balanceMsat!,
                sendableMsat: BigInt.zero,
                zeroState: true,
              ),
            ],
            const SizedBox(height: 20),
            // Invoice input
            Text(context.l10n.invoiceTitle,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _invoiceController,
              // Readonly (keputusan NUX 10 Nov 2026): invoice adalah
              // data ber-checksum — mengetik/mengeditnya manual hanya
              // bisa merusak, tidak pernah memperbaiki. Dua jalur
              // masuk yang sah (tombol Tempel & Pindai di bawah)
              // mengisi field ini secara program sehingga tidak
              // terpengaruh; keyboard pun tidak lagi muncul saat
              // field disentuh. Pengganti edit manual adalah tombol
              // hapus (x) di ujung field (suffixIcon di bawah).
              readOnly: true,
              onChanged: (_) {
                // Kotak cadangan / batas peer menunjuk invoice
                // sebelumnya — invoice berubah, kotaknya gugur.
                if (_reserveHeldMsat != null ||
                    _peerLimitSendableMsat != null) {
                  setState(() {
                    _reserveHeldMsat = null;
                    _reserveSendableMsat = null;
                    _peerLimitSendableMsat = null;
                  });
                }
              },
              maxLines: 4,
              minLines: 3,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                // Hint hanya menampilkan SATU format: prefix HRP jaringan
                // yang sedang dipakai (lntn di testnet, lnnu di mainnet).
                // Sebelumnya hardcode 'lnnu1... atau lntn1...' sehingga
                // user mainnet melihat format testnet dan bingung.
                // Diambil dari AppConfig.isTestnet (sudah benar per branch
                // lewat config kulit masing-masing) — tanpa mengubah
                // config.dart, jadi sync ke mainnet aman.
                hintText: AppConfig.isTestnet ? 'lntn1...' : 'lnnu1...',
                hintStyle:
                    TextStyle(color: context.palette.hint),
                filled: true,
                fillColor: context.palette.cardAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                // Tombol hapus: hanya tampil bila field terisi.
                // Mengosongkan field + mereset keadaan yang menunjuk
                // invoice lama (pesan error & kotak cadangan) —
                // meniru reset pada jalur Pindai.
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _invoiceController,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return IconButton(
                      icon: Icon(Icons.close_rounded,
                          size: 19, color: context.palette.muted),
                      onPressed: () {
                        _invoiceController.clear();
                        setState(() {
                          _error = null;
                          _reserveHeldMsat = null;
                          _reserveSendableMsat = null;
                          _peerLimitSendableMsat = null;
                        });
                      },
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null) {
                        _invoiceController.text = data!.text!;
                      }
                    },
                    icon: const Icon(Icons.paste,
                        color: Color(0xFF34D399), size: 18),
                    label: Text(context.l10n.paste,
                        style: TextStyle(color: Color(0xFF34D399))),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final scanned = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ScanScreen(),
                        ),
                      );
                      if (!mounted) return;
                      if (scanned != null) {
                        _invoiceController.text =
                            normalizeInvoice(scanned);
                        setState(() {
                          _error = null;
                          _reserveHeldMsat = null;
                          _reserveSendableMsat = null;
                          _peerLimitSendableMsat = null;
                        });
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner,
                        color: Color(0xFF34D399), size: 18),
                    label: Text(context.l10n.scanQr,
                        style: TextStyle(color: Color(0xFF34D399))),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: const Color(0xFF34D399).withValues(alpha: 0.3)),
                      padding:
                          const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Panel nominal invoice Bolt11 — tampil bila nominal
            // terbaca dari invoice di kolom kode: jumlah yang akan
            // dikirim dalam satuan aktif + konversi ke satuan
            // lawan (baris konversi selalu tampil di kolom kirim).
            if (_offerInfo == null && _bolt11AmountMsat != null) ...[
              const SizedBox(height: 20),
              Text(
                context.l10n.sendOfferAmountLine(
                    context.formatWalletAmount(_bolt11AmountMsat!)),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.palette.label),
              ),
              const SizedBox(height: 2),
              Text(
                context.formatWalletConversion(_bolt11AmountMsat!),
                style:
                    TextStyle(fontSize: 12.5, color: context.palette.muted),
              ),
            ],
            // Panel offer Bolt12 — hanya tampil bila isi kolom
            // kode terbaca sebagai offer. Nominal tetap cukup
            // ditampilkan; nominal variable butuh kolom isian
            // pembayar (pola kolom nominal layar Terima).
            if (_offerInfo != null) ...[
              const SizedBox(height: 20),
              if (_offerInfo!.isFixedAmount) ...[
                Text(
                  context.l10n.sendOfferAmountLine(
                      context.formatWalletAmount(_offerInfo!.amountMsat!)),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.palette.label),
                ),
                const SizedBox(height: 2),
                Text(
                  context.formatWalletConversion(_offerInfo!.amountMsat!),
                  style:
                      TextStyle(fontSize: 12.5, color: context.palette.muted),
                ),
              ] else ...[
                Text(context.l10n.sendOfferVariableHint,
                    style: TextStyle(
                        fontSize: 13, color: context.palette.muted)),
                const SizedBox(height: 10),
                Text(context.l10n.amountLabel,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _offerAmountController,
                  // Pemformat nominal bersama (sama seperti kolom
                  // nominal Terima): ribuan dikelompokkan on-the-fly
                  // mengikuti locale, dan karakter asing — termasuk
                  // '.' sebagai desimal pada locale id — dibuang
                  // saat diketik, bukan baru ditolak di pagar akhir
                  // (permintaan NUX 10 Nov 2026).
                  inputFormatters: [
                    AmountInputFormatter(
                      thousandsSep:
                          LocaleController.locale.value.languageCode ==
                                  'en'
                              ? ','
                              : '.',
                      decimalSep:
                          LocaleController.locale.value.languageCode ==
                                  'en'
                              ? '.'
                              : ',',
                    ),
                  ],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(color: context.palette.hint),
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
                // Konversi ke satuan lawan dari nominal yang
                // diketik — tampil hanya bila isian terbaca sah.
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _offerAmountController,
                  builder: (context, value, _) {
                    final parsed = parseAmountInputToMsat(value.text,
                        UnitController.unit.value,
                        locale:
                            LocaleController.locale.value.languageCode);
                    if (parsed == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        context.formatWalletConversion(parsed),
                        style: TextStyle(
                            fontSize: 12.5, color: context.palette.muted),
                      ),
                    );
                  },
                ),
              ],
            ],
            const SizedBox(height: 20),
            // Pay button
            ElevatedButton(
              onPressed: _loading ? null : _onPayPressed,
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
                  : Text(context.l10n.pay,
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 13),
                  textAlign: TextAlign.center),
            ],
            if (_waitingOutcome) ...[
              const SizedBox(height: 12),
              Text(context.l10n.payWaitingOutcome,
                  style:
                      TextStyle(fontSize: 13, color: context.palette.muted),
                  textAlign: TextAlign.center),
            ],
            if (_stillPending) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  context.l10n.payStillPending,
                  style: TextStyle(
                      fontSize: 13, color: context.palette.label),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (_reserveHeldMsat != null && _reserveSendableMsat != null) ...[
              const SizedBox(height: 20),
              _reserveBox(
                reserveMsat: _reserveHeldMsat!,
                sendableMsat: _reserveSendableMsat!,
              ),
            ],
            // Batas kirim ke perangkat tertaut: kotak sesudah
            // percobaan bayar yang tertahan, atau kotak tetap bila
            // yang bisa dikirim ke perangkat itu nol sementara
            // saldo kirim gabungan masih ada.
            if (_peerLimitSendableMsat != null) ...[
              const SizedBox(height: 20),
              _peerLimitBox(sendableMsat: _peerLimitSendableMsat!),
            ] else if (_zeroLinkedSendable) ...[
              const SizedBox(height: 20),
              _peerLimitBox(sendableMsat: BigInt.zero),
            ],
            if (_paid) ...[
              const SizedBox(height: 20),
              Container(
                key: _successKey,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  children: [
                    const AnimatedCheckmark(),
                    SizedBox(height: 8),
                    Text(context.l10n.paymentSuccess,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF34D399))),
                    const SizedBox(height: 12),
                    // Penutup manual, sama seperti perayaan
                    // layar Terima (keputusan NUX 4 Nov 2026).
                    ElevatedButton(
                      onPressed: () => setState(() => _paid = false),
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
            ],
          ],
        ),
      ),
    );
  }
}
