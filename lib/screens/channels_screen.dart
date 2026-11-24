import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ldk_node/src/generated/api/types.dart';

import '../config.dart';
import '../l10n/app_localizations.dart';
import '../locale_controller.dart';
import '../services/fee_estimate.dart';
import '../services/lsp_service.dart';
import '../services/offline_spike_utils.dart';
import '../services/opening_paths_store.dart';
import '../theme.dart';
import '../unit_controller.dart';
import '../utils/amount_input.dart';
import '../utils/format.dart';
import '../utils/friendly_error.dart';
import 'onchain_screen.dart';

/// Nominal bawaan pembukaan channel ke LSP (nusan utuh) —
/// sama seperti nominal bawaan Buat Jalur (PR C): cukup besar
/// untuk berguna, cukup kecil untuk percobaan pertama.
final BigInt defaultLspChannelAmountSats = BigInt.from(100000);

/// Nominal minimum pembukaan channel ke LSP (nusan utuh) —
/// sama seperti minimum Buat Jalur.
final BigInt minLspChannelAmountSats = BigInt.from(10000);

/// Jeda pengaman penutupan paksa dalam blok (CSV —
/// OP_CHECKSEQUENCEVERIFY, BIP 112): RELATIF terhadap
/// konfirmasi transaksi penutup, jadi jendela hukumannya selalu
/// penuh 144 blok kapan pun penutupan terjadi. Berlaku untuk
/// dana to_local si penutup pada tutup PAKSA saja; tutup kerja
/// sama tidak punya jeda.
const int forceCloseDelayBlocks = 144;

/// Perkiraan tinggi buka kunci dana tutup paksa dari tinggi
/// ujung [tipHeight] saat ini: transaksi penutup diasumsikan
/// terkonfirmasi di blok berikutnya, lalu jeda 144 blok. Label
/// "sekitar" di pemanggil menampung selisih ±1 blok dari
/// pembulatan ini. Murni supaya bisa diuji unit.
int forceCloseUnlockEstimate(int tipHeight) =>
    tipHeight + forceCloseDelayBlocks;

/// Konfirmasi yang DITAMPILKAN untuk channel menunggu: tidak
/// pernah melebihi jumlah wajib. Hitungan pendanaan basi bisa
/// jauh melampaui wajibnya (temuan lapangan: "Konfirmasi 69/6"
/// pada kartu yang sedang ditutup) dan hanya membingungkan.
/// Murni supaya bisa diuji unit.
int cappedConfirmations(int done, int required) {
  if (done < 0) return 0;
  if (done > required) return required;
  return done;
}

/// Layar Kelola Channel — daftar semua channel node (LSP dan
/// langsung) beserta penutupannya dari sisi pengguna.
///
/// Penutupan adalah mata rantai terakhir siklus hidup dana di
/// ELNUX: saldo Lightning kembali ke dompet on-chain internal
/// (alamat dari frasa yang sama) lewat transaksi penutup.
/// Alurnya selalu tutup KERJA SAMA lebih dulu; tutup paksa hanya
/// ditawarkan sesudah kerja sama gagal, dengan angka konkretnya
/// sendiri (144 blok + perkiraan tinggi buka kunci + biaya lebih
/// mahal) — keputusan sepihak ini harus diambil dengan tahu
/// akibatnya.
///
/// Batas v1 yang disengaja: tombol tutup hanya ada untuk
/// channel yang sudah siap (channel_ready). Channel yang masih
/// menunggu konfirmasi ditampilkan dengan kemajuannya tanpa
/// tombol — menutup channel yang dananya belum terkonfirmasi
/// adalah persoalan lain (pembatalan pendanaan), bukan
/// penutupan biasa.
///
/// Pembukaan channel ke LSP (PR 4 rancangan Kelola Channel)
/// tinggal di sini sebagai permukaan produksi, memakai jalur
/// `openChannelToLsp` yang sama dengan layar Uji — lembar
/// nominal, dialog konfirmasi (biaya tampil sebagai perkiraan),
/// lalu kartu "disiapkan" yang menampilkan txid pendanaan dan
/// kemajuan konfirmasi sampai channel siap. Layar Uji tetap
/// permukaan diagnostik testnet dan tidak disentuh.
class ChannelsScreen extends StatefulWidget {
  final LspService lspService;

  /// Pengambil perkiraan biaya — bisa disuntik (tes); bawaan
  /// memakai layanan nyata.
  final FeeEstimateService? feeEstimateService;

  const ChannelsScreen({
    super.key,
    required this.lspService,
    this.feeEstimateService,
  });

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<ChannelDetails> _channels = const [];
  bool _loading = true;
  bool _loadFailed = false;
  // Status menyegarkan muat-ulang (PR 1 rancangan Kelola
  // Channel): muat pertama memakai _loading (layar penuh);
  // muat ulang memakai _refreshing (ikon berputar di AppBar)
  // supaya daftar tetap terlihat selama data baru tiba.
  // Penghitung dalam-penerbangan menjaga dua pemuatan yang
  // tumpang-tindih (timer 5 detik + ketukan tombol) tidak
  // mematikan indikator terlalu dini.
  bool _refreshing = false;
  int _muatInFlight = 0;
  bool _closing = false;
  // Pembukaan channel ke LSP yang dilacak kunjungan ini
  // (hex userChannelId dari `openChannelToLsp`): selama channel
  // yang dilacak belum siap, kartu "disiapkan" tampil di atas
  // daftar dengan txid pendanaan + kemajuan konfirmasinya.
  // Sengaja hanya di memori kunjungan ini — tampilan txid yang
  // menetap di kartu channel adalah PR 2, bukan PR ini.
  final Set<String> _openingLspIds = {};
  // Penutupan yang dimulai dari layar ini (hex userChannelId):
  // selama channel yang ditutup masih terdaftar di node,
  // kartunya menampilkan "Menutup…" — bukan cabang menunggu
  // dengan hitungan pendanaan basi. Sengaja hanya di memori
  // kunjungan ini; mulai ulang aplikasi di tengah penutupan
  // mengembalikan kartu ke tampilan sebelum ditutup.
  final Set<String> _closingIds = {};
  // Biaya pasti pendanaan per txid (nusan utuh) — diambil sekali
  // per txid dari REST electrs begitu konfirmasi pertama tercatat;
  // txid yang gagal diambil tidak diulangi selama layar hidup.
  final Map<String, BigInt> _fundingFees = {};
  final Set<String> _fundingFeeTried = {};
  // Waktu blok transaksi pendanaan per txid (waktu setempat HP) —
  // "kapan channel dibuat" di kartu: diambil sekali per txid dari
  // REST electrs begitu konfirmasi pertama tercatat; txid yang
  // gagal diambil tidak diulangi selama layar hidup. Baris waktunya
  // disembunyikan bila waktunya belum diketahui (belum terkonfirmasi
  // atau pengambilan gagal) — fail-open seperti baris biaya.
  final Map<String, DateTime> _fundingBlockTimes = {};
  final Set<String> _fundingBlockTimeTried = {};
  // Penjaga dalam-penerbangan pembukaan channel — tombol terkunci
  // selama panggilan openChannel berjalan.
  bool _openingChannel = false;
  // Kolom nominal lain di lembar nominal: dimiliki State, BUKAN
  // dibuat di _showAmountSheet — future lembar selesai saat pop
  // dipanggil, sementara animasi keluar + penutupan keyboard
  // masih bisa membangun ulang TextField sesudahnya; controller
  // yang di-dispose di finally lembar akan dipakai sesudah
  // dispose. Dibersihkan setiap kali lembar dibuka.
  final TextEditingController _customAmountController = TextEditingController();

  late final FeeEstimateService _feeEstimates;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _feeEstimates = widget.feeEstimateService ?? FeeEstimateService();
    _muat();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _customAmountController.dispose();
    super.dispose();
  }

  bool _isLsp(ChannelDetails ch) =>
      ch.counterpartyNodeId.hex.toLowerCase() ==
      AppConfig.lspNodeId.toLowerCase();

  /// Label jenis channel (PR 1 rancangan Kelola Channel):
  /// lawan + is_outbound membedakan JIT (didanai LSP, lahir
  /// dari pembayaran masuk) dari Self-Funded (dibuka dan
  /// didanai pengguna sendiri ke LSP) secara eksak — tanpa
  /// tebak-tebakan. Perbandingan ID node tidak peka huruf
  /// (pola _isLsp yang sama).
  String _kindLabel(ChannelDetails ch) {
    final l10n = context.l10n;
    if (!_isLsp(ch)) return l10n.channelDirect;
    return ch.isOutbound ? l10n.channelLspSelfFunded : l10n.channelLspJit;
  }

  Future<void> _muat() async {
    // Umpan balik muat-ulang (PR 1): nyalakan status
    // menyegarkan di AWAL pemuatan ulang — bukan hanya
    // mematikannya di akhir. Sebelum PR ini _muat() tidak
    // pernah menyalakan status apa pun di awal, sehingga
    // ketukan tombol segarkan sesudah muatan pertama tidak
    // mengubah tampilan apa pun dan terasa seperti tombol
    // mati. Muat pertama dikecualikan: ia sudah ditutup
    // _loading (layar penuh).
    final isReload = !_loading;
    // Dihitung hanya bila benar-benar menaikkan penghitung —
    // finally di bawah memakai penanda yang sama supaya
    // penghitung tidak pernah turun tanpa naik.
    final counted = isReload && mounted;
    if (counted) {
      _muatInFlight++;
      if (_muatInFlight == 1) setState(() => _refreshing = true);
    }
    try {
      final all = await widget.lspService.listChannels();
      if (!mounted) return;
      final sorted = [...all]..sort((a, b) {
          // Channel LSP selalu paling atas — ia jalur utama
          // dompet; sisanya dari kapasitas terbesar.
          if (_isLsp(a) != _isLsp(b)) return _isLsp(a) ? -1 : 1;
          return b.channelValueSats.compareTo(a.channelValueSats);
        });
      // Pangkas pembukaan yang dilacak: channel yang sudah siap
      // tidak lagi butuh kartu "disiapkan" — barisnya sendiri
      // yang menampilkan "Siap".
      _openingLspIds.removeWhere((id) {
        final ch = _channelByOpeningId(sorted, id);
        return ch != null && ch.isChannelReady;
      });
      // Pangkas penutupan yang dilacak: channel yang sudah
      // meninggalkan daftar (handshake penutup selesai dan
      // transaksi penutup terakit) tidak butuh status
      // "Menutup…" lagi.
      _closingIds.removeWhere((id) => _channelByOpeningId(sorted, id) == null);
      // Biaya pasti pendanaan (best-effort): begitu konfirmasi
      // pertama tercatat, ambil field fee-nya dari REST electrs —
      // sekali per txid, gagal-diam.
      for (final id in _openingLspIds) {
        final ch = _channelByOpeningId(sorted, id);
        if (ch != null && (ch.confirmations ?? 0) >= 1) {
          _maybeFetchFundingFee(ch);
        }
      }
      // Waktu dibuat (best-effort): untuk SEMUA channel yang
      // pendanaannya sudah terkonfirmasi, ambil waktu blok
      // transaksi pendanaannya dari REST electrs — sekali per
      // txid, gagal-diam. Berbeda dari biaya di atas yang hanya
      // untuk pembukaan yang dilacak kunjungan ini, waktu dibuat
      // dibutuhkan setiap kartu (termasuk channel lama).
      for (final ch in sorted) {
        if (ch.fundingTxo?.txid.hash != null &&
            (ch.confirmations ?? 0) >= 1) {
          _maybeFetchFundingBlockTime(ch);
        }
      }
      setState(() {
        _channels = sorted;
        _loading = false;
        _loadFailed = false;
      });
      _syncRefreshTimer();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    } finally {
      if (counted) {
        _muatInFlight--;
        if (_muatInFlight == 0 && mounted) {
          setState(() => _refreshing = false);
        }
      }
    }
  }

  /// Channel dari [channels] yang userChannelId-nya cocok dengan
  /// [openingId] (hex) — null bila belum muncul di daftar
  /// (jendela negosiasi sesudah pembukaan terkirim).
  ChannelDetails? _channelByOpeningId(
    List<ChannelDetails> channels,
    String openingId,
  ) {
    for (final ch in channels) {
      if (userChannelIdHex(ch.userChannelId) == openingId) return ch;
    }
    return null;
  }

  /// Timer 5 detik selama ada pembukaan channel ke LSP yang
  /// dilacak: channel bisa menjadi siap (pendanaan terkonfirmasi)
  /// tanpa kejadian apa pun di layar ini, dan kemajuan x/6 harus
  /// bergerak hidup. Tanpa pembukaan yang dilacak, timer mati
  /// supaya node tidak dibebani tanpa henti.
  void _syncRefreshTimer() {
    final shouldRun = _openingLspIds.isNotEmpty;
    if (shouldRun && _refreshTimer == null) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _muat(),
      );
    } else if (!shouldRun) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  /// Ambil biaya pasti transaksi pendanaan [channel] dari REST
  /// electrs — sekali per txid; gagal-diam (baris biayanya tidak
  /// tampil). Dipanggil hanya bila konfirmasi pertama sudah
  /// tercatat, supaya angkanya adalah angka final transaksi itu.
  void _maybeFetchFundingFee(ChannelDetails channel) {
    final txid = channel.fundingTxo?.txid.hash;
    if (txid == null) return;
    if (_fundingFees.containsKey(txid) || _fundingFeeTried.contains(txid)) {
      return;
    }
    _fundingFeeTried.add(txid);
    _feeEstimates.fetchFundingFee(txid).then((fee) {
      if (fee != null && mounted) {
        setState(() => _fundingFees[txid] = fee);
      }
    });
  }

  /// Ambil waktu blok transaksi pendanaan [channel] dari REST
  /// electrs — sekali per txid; gagal-diam (baris waktunya tidak
  /// tampil). Pola yang sama dengan [_maybeFetchFundingFee].
  void _maybeFetchFundingBlockTime(ChannelDetails channel) {
    final txid = channel.fundingTxo?.txid.hash;
    if (txid == null) return;
    if (_fundingBlockTimes.containsKey(txid) ||
        _fundingBlockTimeTried.contains(txid)) {
      return;
    }
    _fundingBlockTimeTried.add(txid);
    _feeEstimates.fetchFundingBlockTime(txid).then((waktu) {
      if (waktu != null && mounted) {
        setState(() => _fundingBlockTimes[txid] = waktu);
      }
    });
  }

  static String _shortId(String hex) {
    if (hex.length <= 20) return hex;
    return '${hex.substring(0, 10)}…${hex.substring(hex.length - 6)}';
  }

  /// Channel masih menunggu konfirmasi: persis cabang menunggu
  /// [_status] — belum siap dan bukan sedang ditutup. Batang
  /// kemajuan kartu memakai predikat ini; bila cabang status
  /// berubah, predikat ini ikut berubah.
  bool _isConfirming(ChannelDetails ch) =>
      !_closingIds.contains(userChannelIdHex(ch.userChannelId)) &&
      !ch.isChannelReady;

  String _status(ChannelDetails ch) {
    final l10n = context.l10n;
    // Penutupan yang dimulai dari layar ini: channel masih
    // terdaftar tetapi sudah tidak channel_ready, jadi tanpa
    // cabang ini ia jatuh ke cabang menunggu dengan hitungan
    // pendanaan basi ("Konfirmasi 69/6", temuan lapangan).
    if (_closingIds.contains(userChannelIdHex(ch.userChannelId))) {
      return l10n.channelStatusClosing;
    }
    if (!ch.isChannelReady) {
      final conf = ch.confirmations;
      final req = ch.confirmationsRequired;
      if (conf != null && req != null) {
        final shown = cappedConfirmations(conf, req);
        return '${l10n.channelStatusPending} • ${l10n.offlineConfirmations} $shown/$req';
      }
      return l10n.channelStatusPending;
    }
    return ch.isUsable
        ? l10n.channelStatusReady
        : l10n.channelStatusPeerDown;
  }

  /// Dialog konfirmasi tutup kerja sama. Peringatan di dalamnya
  /// mengikuti jenis channel: channel LSP membawa peringatan
  /// berhentinya penerimaan lewat LSP sampai channel baru lahir
  /// (permintaan eksplisit pemilik produk — informasi ini wajib
  /// sampai SEBELUM keputusan, bukan sesudahnya); channel
  /// langsung membawa peringatan berakhirnya jalur offline
  /// dengan perangkat seberang.
  Future<void> _konfirmasiTutup(ChannelDetails ch) async {
    final isLsp = _isLsp(ch);
    final saldo =
        context.formatWalletAmount(countedChannelBalanceMsat(ch));
    final jadi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(ctx.l10n.closeChannelTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ctx.l10n.closeChannelBody(saldo)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color:
                        const Color(0xFFF59E0B).withValues(alpha: 0.45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isLsp
                          ? ctx.l10n.closeChannelLspWarning
                          : ctx.l10n.closeChannelDirectWarning,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: Text(ctx.l10n.closeChannelButton),
          ),
        ],
      ),
    );
    if (jadi != true || !mounted) return;
    await _tutupKerjaSama(ch);
  }

  Future<void> _tutupKerjaSama(ChannelDetails ch) async {
    setState(() => _closing = true);
    try {
      await widget.lspService.closeChannel(ch);
      if (!mounted) return;
      // Penutupan dimulai: kartu menampilkan "Menutup…"
      // sampai channel meninggalkan daftar (muat-ulang
      // sesudah ini memangkasnya bila handshake sudah selesai).
      _closingIds.add(userChannelIdHex(ch.userChannelId));
      setState(() => _closing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.closeChannelStarted)),
      );
      await _muat();
    } catch (e) {
      if (!mounted) return;
      setState(() => _closing = false);
      await _tawarkanTutupPaksa(ch, e);
    }
  }

  /// Tutup kerja sama gagal (lawan tidak terjangkau / menolak):
  /// tawarkan tutup paksa dengan penjelasan jujur — jeda
  /// pengaman dalam blok dan biaya on-chain yang lebih mahal —
  /// supaya keputusan sepihak ini diambil dengan tahu
  /// akibatnya, bukan karena panik.
  Future<void> _tawarkanTutupPaksa(ChannelDetails ch, Object sebab) async {
    final l10n = context.l10n;
    // Tinggi ujung untuk perkiraan tinggi buka kunci: gagal-
    // terbuka (null) berarti baris perkiraannya tidak tampil —
    // dialog tidak boleh menggantung menunggu jaringan.
    final tipHeight = await _feeEstimates.fetchTipHeight();
    if (!mounted) return;
    final unlockEstimate = tipHeight == null
        ? null
        : forceCloseUnlockEstimate(tipHeight);
    final jadi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(ctx.l10n.closeForceTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              friendlyError(sebab,
                  fallback: ctx.l10n.closeForceFallback,
                  l10n: ctx.l10n),
              style: TextStyle(
                  fontSize: 13, color: ctx.palette.secondary),
            ),
            const SizedBox(height: 10),
            Text(ctx.l10n.closeForceBody),
            if (unlockEstimate != null) ...[
              const SizedBox(height: 10),
              Text(ctx.l10n.closeForceUnlockEstimate(unlockEstimate)),
            ],
            // Catatan hari hanya di mainnet: penambangan
            // terjadwal ±98 menit/blok membuat 144 blok ≈ 10
            // hari; di testnet blok ditambang sesuai permintaan
            // sehingga angka hari tidak berarti.
            if (!AppConfig.isTestnet) ...[
              const SizedBox(height: 10),
              Text(ctx.l10n.closeForceDaysNote),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: Text(ctx.l10n.closeForceButton),
          ),
        ],
      ),
    );
    if (jadi != true || !mounted) return;
    setState(() => _closing = true);
    try {
      await widget.lspService.forceCloseChannel(ch);
      if (!mounted) return;
      // Sama seperti tutup kerja sama: kartu menampilkan
      // "Menutup…" sampai channel meninggalkan daftar.
      _closingIds.add(userChannelIdHex(ch.userChannelId));
      setState(() => _closing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.closeForceStarted)),
      );
      await _muat();
    } catch (e) {
      if (!mounted) return;
      setState(() => _closing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e,
              fallback: l10n.closeForceFallback, l10n: l10n)),
        ),
      );
    }
  }

  /// Alur Buka Channel ke LSP (§4.5 rancangan, mengikuti pola
  /// Buat Jalur): baca saldo on-chain → lembar nominal →
  /// perkiraan biaya → dialog konfirmasi → buka channel → muat
  /// ulang. Setiap langkah bisa membatalkan alur tanpa efek
  /// samping; dana hanya bergerak pada langkah terakhir.
  ///
  /// Pagar boot offline ditegakkan di layanan
  /// ([LspService.openChannelToLsp] menolak pada sesi boot
  /// offline); tombol di layar ini juga tidak aktif dalam sesi
  /// itu, dengan kalimat polos sebagai penjelasnya.
  Future<void> _onOpenToLsp() async {
    if (_openingChannel || widget.lspService.isOfflineMode) return;
    BigInt spendable;
    try {
      spendable = await widget.lspService.spendableOnchainBalanceSats();
    } catch (_) {
      // Saldo tidak terbaca: hentikan alur — saldo adalah bahan
      // lembar nominal dan pemeriksaan daya beli.
      _showSnack(context.l10n.kelolaLspOpenFailedGeneric);
      return;
    }
    // Momen (1) dialog saldo tidak cukup: tidak bisa membuka
    // channel apa pun (bahkan minimum + cadangan biaya).
    if (spendable < minLspChannelAmountSats + feeEstimateFallbackReserveSats) {
      await _showInsufficientBalanceDialog(
        amountSats: minLspChannelAmountSats,
        balanceSats: spendable,
      );
      return;
    }
    final amountSats = await _showAmountSheet(spendable);
    if (amountSats == null || !mounted) return;
    // Perkiraan biaya (timeout ±5 detik, gagal-terbuka): gagal
    // ambil berarti baris biaya "dihitung saat pengiriman" dan
    // pemeriksaan saldo memakai cadangan tetap.
    final feeEstimate = await _feeEstimates.estimateFundingFee();
    if (!mounted) return;
    final feeReserve = feeEstimate ?? feeEstimateFallbackReserveSats;
    if (amountSats + feeReserve > spendable) {
      await _showInsufficientBalanceDialog(
        amountSats: amountSats,
        balanceSats: spendable,
      );
      return;
    }
    final confirmed = await _showConfirmDialog(
      amountSats: amountSats,
      feeEstimateSats: feeEstimate,
    );
    if (confirmed != true || !mounted) return;
    await _openChannelToLsp(amountSats: amountSats, spendableSats: spendable);
  }

  /// Buka channel ke LSP sebesar [amountSats] nusan (langkah
  /// terakhir alur): panggil jalur PR #29, catat ID-nya di
  /// himpunan dalam-pembukaan, lalu muat ulang daftar channel.
  ///
  /// Aturan muat-ulang sesudah percobaan (pola Buat Jalur): muat
  /// ulang dilakukan apa pun hasilnya; bila channel yang
  /// disiapkan muncul, lanjut ke keadaan disiapkan dan error-nya
  /// diabaikan (panggilan bisa melempar sesudah channel tercipta).
  /// Hanya bila tidak ada channel yang muncul, pesan error per
  /// sebab ditampilkan.
  Future<void> _openChannelToLsp({
    required BigInt amountSats,
    required BigInt spendableSats,
  }) async {
    if (_openingChannel) return;
    setState(() => _openingChannel = true);
    try {
      UserChannelId? openedId;
      Object? openError;
      try {
        openedId = await widget.lspService.openChannelToLsp(amountSats);
      } catch (e) {
        openError = e;
      }
      if (openedId != null) {
        _openingLspIds.add(userChannelIdHex(openedId));
      }
      await _muat();
      // Channel yang dilacak muncul di daftar (disiapkan/siap)
      // atau masih dalam jendela negosiasi (kartu menunggu yang
      // tampil dari himpunan dalam-pembukaan): alur selesai,
      // error apa pun diabaikan.
      if (openedId != null) return;
      if (openError != null) {
        await _showOpenError(
          openError,
          amountSats: amountSats,
          spendableSats: spendableSats,
        );
      } else {
        _showSnack(context.l10n.kelolaLspOpenFailedGeneric);
      }
    } finally {
      if (mounted) setState(() => _openingChannel = false);
    }
  }

  /// Pesan error per sebab (pola Buat Jalur) — tidak ada lagi
  /// error mentah ke pengguna. Urutannya penting: saldo dulu
  /// (dialog deposit), lalu boot offline (kalimat polos — pagar
  /// layanan sebagai penahan terakhir bila tombolnya entah
  /// bagaimana ditekan), lalu node belum siap, terakhir
  /// friendlyError dengan pesan umum sebagai fallback.
  Future<void> _showOpenError(
    Object error, {
    required BigInt amountSats,
    required BigInt spendableSats,
  }) async {
    final s = error.toString().toLowerCase();
    if (s.contains('insufficient') || s.contains('balance')) {
      await _showInsufficientBalanceDialog(
        amountSats: amountSats,
        balanceSats: spendableSats,
      );
      return;
    }
    if (s.contains('boot offline')) {
      _showSnack(context.l10n.kelolaLspOfflineDisabled);
      return;
    }
    if (!widget.lspService.isRunning ||
        s.contains('inisialisasi') ||
        s.contains('initialized')) {
      _showSnack(context.l10n.kelolaLspOpenFailedNotReady);
      return;
    }
    _showSnack(
      friendlyError(
        error,
        fallback: context.l10n.kelolaLspOpenFailedGeneric,
        l10n: context.l10n,
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Lembar nominal (pola Buat Jalur): pilihan bawaan 100.000
  /// nusan (terpilih) atau "nominal lain" dengan kolom isian
  /// angka, beserta baris saldo on-chain supaya pengguna bisa
  /// menilai sendiri sebelum memilih. Mengembalikan nominal
  /// pilihan dalam nusan utuh, atau null bila lembar ditutup
  /// tanpa memilih.
  Future<BigInt?> _showAmountSheet(BigInt spendableSats) async {
    final l10n = context.l10n;
    // Satuan & locale dibaca sekali di sini: kolom nominal, hint,
    // helper, parser, dan pesan error semuanya memakai satuan
    // tampilan aktif yang sama — bukan nusan yang di-hardcode
    // (temuan lapangan 19 Nov 2026: pengguna satuan NUX mengetik
    // "0,001" lalu ditolak membingungkan).
    final unit = UnitController.unit.value;
    final locale = LocaleController.locale.value.languageCode;
    final minAmountText = context.formatWalletAmount(
      minLspChannelAmountSats * BigInt.from(1000),
    );
    _customAmountController.clear();
    var useCustom = false;
    String? error;
    return showModalBottomSheet<BigInt>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.kelolaLspAmountTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _amountOption(
                  title: context.formatWalletAmount(
                    defaultLspChannelAmountSats * BigInt.from(1000),
                  ),
                  subtitle: l10n.kelolaLspAmountDefaultNote,
                  selected: !useCustom,
                  onTap: () => setSheetState(() {
                    useCustom = false;
                    error = null;
                  }),
                ),
                const SizedBox(height: 8),
                _amountOption(
                  title: l10n.kelolaLspAmountOther,
                  selected: useCustom,
                  onTap: () => setSheetState(() {
                    useCustom = true;
                    error = null;
                  }),
                ),
                if (useCustom) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customAmountController,
                    // Pemformat nominal bersama (sama seperti
                    // kolom nominal Kirim & Terima): ribuan
                    // dikelompokkan on-the-fly mengikuti locale.
                    // Keyboard desimal wajib: satuan NUX mengetik
                    // pecahan ("0,001").
                    inputFormatters: [
                      AmountInputFormatter(
                        thousandsSep: locale == 'en' ? ',' : '.',
                        decimalSep: locale == 'en' ? '.' : ',',
                      ),
                    ],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      // Hint hanya contoh nilai (pendek, tidak
                      // terpotong); aturan minimum pindah ke
                      // helperText di bawah yang membungkus dan
                      // selalu terlihat.
                      hintText: l10n.kelolaLspAmountHint(
                        context.formatWalletAmount(
                          BigInt.from(25000) * BigInt.from(1000),
                        ),
                      ),
                      helperText: l10n.kelolaLspAmountHelper(minAmountText),
                      errorText: error,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (error != null) {
                        setSheetState(() => error = null);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  l10n.kelolaLspOnchainBalance(
                    context.formatWalletAmount(
                      spendableSats * BigInt.from(1000),
                    ),
                  ),
                  style: TextStyle(fontSize: 13, color: context.palette.muted),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (!useCustom) {
                        Navigator.of(ctx).pop(defaultLspChannelAmountSats);
                        return;
                      }
                      final msat = parseChannelAmountToMsat(
                        _customAmountController.text,
                        unit,
                        locale: locale,
                      );
                      if (msat == null || msat <= BigInt.zero) {
                        setSheetState(
                          () => error = l10n.kelolaLspAmountInvalid(unit.label),
                        );
                        return;
                      }
                      final sats = msat ~/ BigInt.from(1000);
                      if (sats < minLspChannelAmountSats) {
                        setSheetState(
                          () => error = l10n.kelolaLspAmountTooSmall(
                            minAmountText,
                          ),
                        );
                        return;
                      }
                      Navigator.of(ctx).pop(sats);
                    },
                    child: Text(l10n.kelolaLspAmountContinue),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Satu pilihan nominal di lembar: judul + subjudul opsional,
  /// bingkai hijau saat terpilih.
  Widget _amountOption({
    required String title,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF34D399) : context.palette.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? const Color(0xFF34D399) : context.palette.muted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.palette.label,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog konfirmasi (pola Buat Jalur): nominal, biaya jaringan
  /// (PERKIRAAN — kata "(perkiraan)" dan tanda "±" wajib ada
  /// karena angka pastinya baru diketahui sesudah node merakit
  /// transaksi pendanaan), total dari dompet on-chain, arah
  /// pendanaan, dan waktu tunggu. Mengembalikan true bila
  /// pengguna menekan Buka Channel.
  Future<bool?> _showConfirmDialog({
    required BigInt amountSats,
    required BigInt? feeEstimateSats,
  }) async {
    final l10n = context.l10n;
    final amountText = context.formatWalletAmount(
      amountSats * BigInt.from(1000),
    );
    final feeText = feeEstimateSats == null
        ? l10n.kelolaLspConfirmFeeUnknown
        : '±${context.formatWalletAmount(feeEstimateSats * BigInt.from(1000))}';
    final totalText = feeEstimateSats == null
        ? '±$amountText + ${l10n.kelolaLspConfirmFeeWord}'
        : '±${context.formatWalletAmount((amountSats + feeEstimateSats) * BigInt.from(1000))}';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.kelolaLspConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _confirmRow(l10n.kelolaLspConfirmAmount, amountText),
            const SizedBox(height: 8),
            _confirmRow(l10n.kelolaLspConfirmFeeEstimate, feeText),
            const SizedBox(height: 8),
            _confirmRow(l10n.kelolaLspConfirmTotal, totalText),
            const SizedBox(height: 14),
            Text(
              l10n.kelolaLspConfirmDirection(amountText),
              style: TextStyle(fontSize: 13, color: ctx.palette.label),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.kelolaLspConfirmWait,
              style: TextStyle(fontSize: 13, color: ctx.palette.muted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.kelolaLspConfirmCreate),
          ),
        ],
      ),
    );
  }

  /// Satu baris label-nilai di dialog konfirmasi.
  Widget _confirmRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: context.palette.muted),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  /// Dialog saldo tidak cukup (pola Buat Jalur): menginformasikan
  /// apa yang harus dilakukan dan keperluan on-chain seperti
  /// biasa — tombolnya membuka halaman Dompet On-chain (alamat
  /// deposit + tombol salin), bukan deposit di dalam alur.
  Future<void> _showInsufficientBalanceDialog({
    required BigInt amountSats,
    required BigInt balanceSats,
  }) async {
    final l10n = context.l10n;
    final goDeposit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.kelolaLspNoBalanceTitle),
        content: Text(
          l10n.kelolaLspNoBalanceBody(
            context.formatWalletAmount(amountSats * BigInt.from(1000)),
            context.formatWalletAmount(balanceSats * BigInt.from(1000)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.kelolaLspNoBalanceLater),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.kelolaLspNoBalanceDeposit),
          ),
        ],
      ),
    );
    if (goDeposit == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OnchainScreen(lspService: widget.lspService),
        ),
      );
    }
  }

  /// Tombol produksi Buka Channel ke LSP — selalu tampil di atas
  /// daftar (juga saat daftar kosong: membuka channel sendiri
  /// adalah alternatif dari menunggu channel JIT lahir). Tidak
  /// aktif selama pembukaan berjalan dan pada sesi boot offline
  /// (dengan kalimat polos sebagai penjelasnya — pola Buat Jalur
  /// langkah 9).
  Widget _openButton() {
    final l10n = context.l10n;
    final offlineBooted = widget.lspService.isOfflineMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: (_openingChannel || offlineBooted) ? null : _onOpenToLsp,
          icon: const Icon(Icons.add_link_rounded, size: 20),
          label: Text(l10n.channelOpenToLsp),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        if (offlineBooted) ...[
          const SizedBox(height: 8),
          Text(
            l10n.kelolaLspOfflineDisabled,
            style: TextStyle(fontSize: 13, color: context.palette.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Kartu "disiapkan" untuk tiap pembukaan channel ke LSP yang
  /// dilacak kunjungan ini — kosong bila tidak ada.
  List<Widget> _preparingCards() {
    return [for (final id in _openingLspIds) _preparingCard(id)];
  }

  /// Satu kartu "disiapkan" (pola kartu disiapkan Buat Jalur,
  /// diadaptasi ke konteks Kelola): judul + kemajuan konfirmasi
  /// (X/6 + batang) + nilai channel + biaya pasti (begitu
  /// konfirmasi ≥ 1) + txid pendanaan lengkap yang bisa diketuk
  /// untuk menyalin. Saat channel belum muncul di daftar
  /// (jendela negosiasi), kartu menampilkan "Menunggu
  /// konfirmasi…" tanpa angka.
  Widget _preparingCard(String openingId) {
    final l10n = context.l10n;
    final channel = _channelByOpeningId(_channels, openingId);
    final txid = channel?.fundingTxo?.txid.hash;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                color: Color(0xFFFBBF24),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.kelolaLspPreparing,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.palette.label,
                      ),
                    ),
                    ..._preparingCardLines(l10n, channel),
                  ],
                ),
              ),
            ],
          ),
          if (txid != null) ...[
            const SizedBox(height: 12),
            _fundingTxidRow(txid),
          ],
          if (channel != null && channel.confirmationsRequired != null) ...[
            const SizedBox(height: 12),
            _confirmationProgressBar(channel),
          ],
        ],
      ),
    );
  }

  /// Baris-baris di bawah judul kartu disiapkan.
  List<Widget> _preparingCardLines(
    AppLocalizations l10n,
    ChannelDetails? channel,
  ) {
    const lineStyle = TextStyle(fontSize: 12);
    final lines = <Widget>[];
    final required = channel?.confirmationsRequired;
    final done = channel?.confirmations ?? 0;
    lines.add(const SizedBox(height: 3));
    if (channel == null || required == null) {
      // Jendela negosiasi (channel belum muncul di daftar)
      // atau jumlah wajib belum diketahui: tanpa angka,
      // gagal-terbuka.
      lines.add(
        Text(
          l10n.kelolaLspWaitingConfirmations,
          style: lineStyle.copyWith(color: context.palette.muted),
        ),
      );
    } else if (done == 0) {
      // 0 konfirmasi (pendanaan tersiar, blok pertama belum
      // datang — di mainnet ini bisa berjam-jam, normal):
      // baris penenang tanpa angka jam.
      lines.add(
        Text(
          l10n.kelolaLspWaitingFirst,
          style: lineStyle.copyWith(color: context.palette.muted),
        ),
      );
      lines.add(const SizedBox(height: 3));
      lines.add(
        Text(
          l10n.kelolaLspWaitingFirstNote,
          style: lineStyle.copyWith(color: context.palette.muted),
        ),
      );
    } else {
      // Aturan yang sama seperti status kartu: hitungan yang
      // ditampilkan tidak pernah melebihi jumlah wajib.
      lines.add(
        Text(
          l10n.kelolaLspPreparingConfirmations(
            cappedConfirmations(done, required),
            required,
          ),
          style: lineStyle.copyWith(color: context.palette.muted),
        ),
      );
      // Baris penjelas jumlah wajib + catatan jadwal
      // penambangan: di mainnet jeda antar-blok bisa berjam-jam,
      // jadi pengguna perlu tahu bahwa menunggu itu normal — dan
      // bahwa mereka bisa menambang sendiri.
      lines.add(const SizedBox(height: 3));
      lines.add(
        Text(
          l10n.kelolaLspPreparingOfRequired(required),
          style: lineStyle.copyWith(color: context.palette.muted),
        ),
      );
      lines.add(const SizedBox(height: 3));
      lines.add(
        Text(
          l10n.kelolaLspWaitingFirstNote,
          style: lineStyle.copyWith(color: context.palette.muted),
        ),
      );
    }
    if (channel != null) {
      lines.add(const SizedBox(height: 3));
      lines.add(
        Text(
          l10n.kelolaLspPreparingValue(
            context.formatWalletAmount(
              channel.channelValueSats * BigInt.from(1000),
            ),
          ),
          style: lineStyle.copyWith(color: context.palette.muted),
        ),
      );
      final txid = channel.fundingTxo?.txid.hash;
      final fee = txid == null ? null : _fundingFees[txid];
      if (fee != null) {
        lines.add(const SizedBox(height: 3));
        lines.add(
          Text(
            l10n.kelolaLspPreparingFee(
              context.formatWalletAmount(fee * BigInt.from(1000)),
            ),
            style: lineStyle.copyWith(color: context.palette.muted),
          ),
        );
      }
    }
    return lines;
  }

  /// Baris txid pendanaan: label + txid lengkap (monospace, bisa
  /// membungkus) + tombol salin. Mengetuk teksnya juga menyalin.
  Widget _fundingTxidRow(String txid) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.channelFundingTxid,
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _copyTxid(txid),
                child: Text(
                  txid,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => _copyTxid(txid),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: context.palette.muted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _copyTxid(String txid) async {
    final copied = context.l10n.txCopied;
    await Clipboard.setData(ClipboardData(text: txid));
    _showSnack(copied);
  }

  /// Batang kemajuan konfirmasi channel: nilai X/6 bila jumlah
  /// wajib diketahui, tak tentu (indeterminate) bila tidak.
  /// Dipakai kartu disiapkan dan kartu channel yang masih
  /// menunggu — satu gaya batang untuk seluruh layar.
  Widget _confirmationProgressBar(ChannelDetails channel) {
    final required = channel.confirmationsRequired;
    final done = channel.confirmations ?? 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        // Nilai dibatasi 1,0: hitungan yang melampaui wajib
        // akan melempar assertion di mode debug.
        value: required == null
            ? null
            : cappedConfirmations(done, required) / required,
        minHeight: 6,
        backgroundColor: context.palette.border,
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.channelsTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Umpan balik muat-ulang (PR 1): selama data baru
          // tiba, ikon segarkan diganti indikator berputar —
          // ketukan tombol terasa dijawab, bukan mati.
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            )
          else
            IconButton(
              onPressed: _loading ? null : _muat,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _muat,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                children: [
                  _openButton(),
                  const SizedBox(height: 12),
                  ..._preparingCards(),
                  if (_loadFailed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Text(l10n.channelsLoadFailed,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _muat,
                            child: Text(l10n.updateRetry),
                          ),
                        ],
                      ),
                    )
                  else if (_channels.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Text(l10n.channelsEmpty,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 6),
                          Text(l10n.channelsEmptyHint,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: context.palette.muted),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    )
                  else
                    for (final ch in _channels) _barisChannel(ch),
                ],
              ),
            ),
    );
  }

  Widget _barisChannel(ChannelDetails ch) {
    final l10n = context.l10n;
    final isLsp = _isLsp(ch);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle,
                  size: 9,
                  color: ch.isUsable
                      ? const Color(0xFF34D399)
                      : const Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isLsp ? l10n.balanceViaLsp : l10n.balanceDirectChannel,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          // ID node lawan pada kartu LSP (NUX, 25 Nov 2026): kartu
          // direct sudah menampilkan id node (di bawah label jenis),
          // kartu LSP belum — tanpa ini pengguna tidak bisa melihat
          // channel ini terhubung ke node mana. Duduk di bawah judul
          // "Via LSP" dan di atas batang kemajuan (bila ada) — gaya
          // persis id node channel direct (11, monospace, redup).
          if (isLsp) ...[
            const SizedBox(height: 4),
            Text(
              _shortId(ch.counterpartyNodeId.hex),
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: context.palette.muted),
            ),
          ],
          // Status di barisnya sendiri (R3): sebelumnya status
          // duduk di Row judul tanpa batas lebar — teks status
          // mengambil lebar intrinsiknya duluan, mendesak label
          // sampai melipat huruf-per-huruf dan meluber 168 px
          // pada layar 360 px dengan channel menunggu. Di baris
          // sendiri, status memakai lebar penuh kartu dan hanya
          // terlipat di batas kata.
          const SizedBox(height: 4),
          Text(
            _status(ch),
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
          // Batang kemajuan konfirmasi: hanya selama channel
          // masih menunggu, duduk di antara baris status dan
          // label jenis — batang yang sama dengan kartu
          // disiapkan, satu gaya untuk seluruh layar.
          if (_isConfirming(ch)) ...[
            const SizedBox(height: 6),
            _confirmationProgressBar(ch),
          ],
          // Label jenis (PR 1): barisnya sendiri di bawah
          // judul — di baris sendiri, label selalu punya lebar
          // penuh kartu.
          const SizedBox(height: 4),
          Text(
            _kindLabel(ch),
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
          if (!isLsp) ...[
            const SizedBox(height: 4),
            Text(
              _shortId(ch.counterpartyNodeId.hex),
              style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: context.palette.muted),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '${l10n.channelCapacity} ${context.formatWalletAmount(ch.channelValueSats * BigInt.from(1000))} • ${l10n.channelYourBalance} ${context.formatWalletAmount(countedChannelBalanceMsat(ch))}',
            style:
                TextStyle(fontSize: 12.5, color: context.palette.muted),
          ),
          // Waktu dibuat (dari waktu blok transaksi pendanaan):
          // tampil bila sudah diambil; disembunyikan bila belum
          // diketahui — channel yang belum terkonfirmasi belum
          // punya waktu blok, dan pengambilan yang gagal tidak
          // menampilkan baris setengah jadi.
          if (_fundingBlockTimes[ch.fundingTxo?.txid.hash] != null) ...[
            const SizedBox(height: 4),
            Text(
              '${l10n.channelOpenedLabel} ${formatFullDateTime(_fundingBlockTimes[ch.fundingTxo?.txid.hash]!, locale: Localizations.localeOf(context).languageCode)}',
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          ],
          // Txid pendanaan (PR 2 rancangan Kelola Channel):
          // tampil lengkap di SETIAP kartu channel, bisa diketuk
          // untuk menyalin — catatan menetap dari fundingTxo
          // node, berbeda dari kartu "disiapkan" PR 4 yang hanya
          // melacak pembukaan kunjungan ini. Pada channel yang
          // masih menunggu, txid berdampingan dengan kemajuan
          // x/6 di baris status di atas. Tanpa fundingTxo
          // (jendela negosiasi) barisnya tidak tampil.
          if (ch.fundingTxo?.txid.hash != null) ...[
            const SizedBox(height: 10),
            _fundingTxidRow(ch.fundingTxo!.txid.hash),
          ],
          if (ch.isChannelReady) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _closing ? null : () => _konfirmasiTutup(ch),
                icon: const Icon(Icons.link_off_rounded, size: 17),
                label: Text(l10n.closeChannelButton),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: 0.55)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
