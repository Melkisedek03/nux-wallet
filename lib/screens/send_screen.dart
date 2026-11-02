import 'package:flutter/material.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:vibration/vibration.dart';
import '../config.dart';
import '../locale_controller.dart';
import '../theme.dart';
import 'package:flutter/services.dart';
import '../services/lsp_service.dart';
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
class SendScreen extends StatefulWidget {
  final LspService lspService;

  const SendScreen({super.key, required this.lspService});

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

  bool _loading = false;
  String? _error;
  bool _paid = false;

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

  /// Kapasitas kirim (msat) dari channel yang usable — batas
  /// kirim sesungguhnya sesudah cadangan pengaman dikeluarkan
  /// node. Null selama belum terbaca.
  BigInt? _sendableMsat;

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
    super.dispose();
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
    if (info != _offerInfo && mounted) {
      setState(() => _offerInfo = info);
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
      if (!mounted) return;
      setState(() {
        _balanceMsat = balance;
        _sendableMsat = totalUsableOutboundCapacityMsat(channels);
        _hasUsableChannel = channels.any((c) => c.isUsable);
      });
    } catch (_) {
      // Abaikan — lihat keterangan di atas.
    }
  }

  /// Keadaan "saldo ada tetapi yang bisa dikirim nol karena
  /// cadangan" — satu-satunya keadaan yang selalu menampilkan
  /// penjelasan cadangan tanpa menunggu percobaan bayar.
  bool get _zeroSendable =>
      _hasUsableChannel &&
      _sendableMsat != null &&
      _sendableMsat == BigInt.zero &&
      _balanceMsat != null &&
      _balanceMsat! > BigInt.zero;

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
      if (!await _checkSendable(amountMsat)) return;
    }
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
      await _pay(() => widget.lspService.payInvoice(invoice));
    }
  }

  /// Pemeriksaan pra-bayar bersama untuk invoice Bolt11 dan
  /// offer Bolt12: nilai [amountMsat] terhadap saldo & kapasitas
  /// kirim terbaru. Mengembalikan true bila pembayaran boleh
  /// lanjut ke dialog konfirmasi; false berarti layar sudah
  /// menyatakan alasannya (saldo tidak cukup / tertahan cadangan)
  /// atau layar sudah tidak aktif. Bila angka saldo/kapasitas
  /// belum terbaca, pemeriksaan tidak bisa dinilai — pembayaran
  /// dilanjutkan dan node menjadi penentu, seperti perilaku lama.
  Future<bool> _checkSendable(BigInt amountMsat) async {
    await _refreshSendable();
    if (!mounted) return false;
    final balance = _balanceMsat;
    final sendable = _sendableMsat;
    if (balance == null || sendable == null) return true;
    final check = evaluateSend(
      amountMsat: amountMsat,
      balanceMsat: balance,
      usableOutboundMsat: sendable,
      hasUsableChannel: _hasUsableChannel,
    );
    if (check == SendCheck.insufficientBalance) {
      setState(() {
        _error = context.l10n.sendInsufficientBalance;
        _reserveHeldMsat = null;
        _reserveSendableMsat = null;
      });
      return false;
    }
    if (check == SendCheck.reserveHeld) {
      // Bila kotak nol-bisa-kirim sudah tampil, penjelasan
      // yang sama sudah ada di layar — cukup jangan lanjut.
      if (!_zeroSendable) {
        setState(() {
          _error = null;
          _reserveHeldMsat = balance - sendable;
          _reserveSendableMsat = sendable;
        });
      }
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
      final parsed = parseNusanInputToMsat(_offerAmountController.text);
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
              context.l10n.sendOfferAmountLine(formatNusan(amountMsat)),
              style: const TextStyle(fontWeight: FontWeight.w700),
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
      await _pay(() => fixedAmount
          ? widget.lspService.payOffer(offer)
          : widget.lspService.payOfferUsingAmount(offer, amountMsat));
    }
  }

  /// Jalankan perintah kirim [sendPayment] (invoice Bolt11 atau
  /// offer Bolt12 — keduanya mengembalikan ID pembayaran node)
  /// lalu tunggu hasil akhirnya. Validasi bentuk & nominal sudah
  /// dikerjakan pemanggil sebelum konfirmasi.
  Future<void> _pay(Future<PaymentId> Function() sendPayment) async {
    setState(() {
      _loading = true;
      _error = null;
      _paid = false;
      _stillPending = false;
      _waitingOutcome = false;
      _reserveHeldMsat = null;
      _reserveSendableMsat = null;
    });

    try {
      final paymentId = await sendPayment();
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
      } else if (outcome == PaymentStatus.failed) {
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
                formatNusan(reserveMsat), formatNusan(sendableMsat)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.sendTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
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
                context.l10n.sendableLine(formatNusan(_sendableMsat!)),
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
              onChanged: (_) {
                // Kotak cadangan menunjuk invoice sebelumnya —
                // invoice berubah, kotaknya gugur.
                if (_reserveHeldMsat != null) {
                  setState(() {
                    _reserveHeldMsat = null;
                    _reserveSendableMsat = null;
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
            // Panel offer Bolt12 — hanya tampil bila isi kolom
            // kode terbaca sebagai offer. Nominal tetap cukup
            // ditampilkan; nominal variable butuh kolom isian
            // pembayar (pola kolom nominal layar Terima).
            if (_offerInfo != null) ...[
              const SizedBox(height: 20),
              if (_offerInfo!.isFixedAmount)
                Text(
                  context.l10n
                      .sendOfferAmountLine(formatNusan(_offerInfo!.amountMsat!)),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.palette.label),
                )
              else ...[
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
                    suffixText: 'nusan',
                    suffixStyle: TextStyle(
                        fontSize: 16,
                        color: context.palette.muted,
                        fontWeight: FontWeight.w600),
                  ),
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
            if (_paid) ...[
              const SizedBox(height: 20),
              Container(
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
