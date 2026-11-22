import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ldk_node/src/generated/api/types.dart';

import '../config.dart';
import '../l10n/app_localizations.dart';
import '../locale_controller.dart';
import '../services/fee_estimate.dart';
import '../services/lsp_service.dart';
import '../services/offline_bridge.dart';
import '../services/offline_mode_utils.dart';
import '../services/offline_spike_utils.dart';
import '../services/opening_paths_store.dart';
import '../services/path_ready_watcher.dart';
import '../theme.dart';
import '../unit_controller.dart';
import '../utils/amount_input.dart';
import '../utils/format.dart';
import '../utils/friendly_error.dart';
import 'onchain_screen.dart';

/// Layar Mode Offline produksi — tuas di Profil yang menyalakan
/// sesi jembatan mode gabung (mengiklankan + menemukan serentak)
/// tanpa pilihan peran dan tanpa tempel ID node: kedua HP menekan
/// saklar yang sama, saling menemukan, lalu pengguna mengetuk
/// Sambungkan pada perangkat yang kodenya cocok.
///
/// Berbeda dari layar Uji Offline (diagnostik testnet, tetap ada
/// apa adanya): permukaan ini tidak mengenal jargon — yang tampil
/// hanya kode perangkat, nama ELNUX-XXXX, dan keadaan jalur
/// (belum/disiapkan/siap). Pembukaan jalur ada di sini (PR C):
/// tombol Buat Jalur di kartu jalur, dengan lembar nominal,
/// dialog konfirmasi (biaya on-chain tampil sebagai perkiraan),
/// dan kartu "disiapkan" yang menampilkan kemajuan konfirmasi
/// sampai jalur siap — termasuk saat tidak tertaut (model dua
/// kunjungan: selama ±10 jam menunggu, kedua HP sudah pulang).
class OfflineModeScreen extends StatefulWidget {
  final LspService lspService;
  final OfflineBridgeService bridge;

  /// Pengambil perkiraan biaya — bisa disuntik (tes); bawaan
  /// memakai layanan nyata.
  final FeeEstimateService? feeEstimateService;

  const OfflineModeScreen({
    super.key,
    required this.lspService,
    required this.bridge,
    this.feeEstimateService,
  });

  @override
  State<OfflineModeScreen> createState() => _OfflineModeScreenState();
}

class _OfflineModeScreenState extends State<OfflineModeScreen> {
  String? _ownNodeId;
  bool _loadFailed = false;
  bool _busy = false;
  bool _pathReady = false;
  // Kapasitas kirim (msat) ke peer tertaut — plafon yang tampil
  // di kartu jalur saat jalur siap. Angka yang sama dipakai
  // pemeriksaan pra-bayar layar Kirim, supaya plafon yang
  // dilihat pengguna dan batas yang ditegakkan selalu cocok.
  BigInt? _pathSendableMsat;
  // Keadaan jalur tiga keadaan (PR C) + channel yang sedang
  // disiapkan (kemajuan konfirmasi + nilainya) + peer yang
  // dirujuk kartu (peer tertaut/diingat, atau lawan channel
  // disiapkan bila sesi sudah berakhir).
  PathState _pathState = PathState.none;
  ChannelDetails? _preparingChannel;
  String? _displayPeerId;
  // Biaya pasti pendanaan per txid (nusan utuh) — diambil sekali
  // per txid dari REST electrs begitu konfirmasi pertama tercatat;
  // txid yang gagal diambil tidak diulangi selama layar hidup.
  final Map<String, BigInt> _fundingFees = {};
  final Set<String> _fundingFeeTried = {};
  // Izin notifikasi (Android 13+): null = belum diperiksa / tidak
  // diketahui; false berarti kartu disiapkan menampilkan catatan
  // pengingat. Diperiksa sekali saat memasuki keadaan disiapkan.
  bool? _notifyGranted;
  bool _notifyChecked = false;
  // Himpunan dalam-pembukaan: menutup jendela negosiasi supaya
  // tombol Buat Jalur tidak muncul kembali sesudah pembukaan
  // terkirim (lihat OpeningPathsStore).
  final OpeningPathsStore _openingPaths = OpeningPathsStore();
  // Penjaga dalam-penerbangan pembukaan channel — tombol terkunci
  // selama panggilan openChannel berjalan.
  bool _openingChannel = false;
  // Kolom nominal lain di lembar nominal: dimiliki State, BUKAN
  // dibuat di _showAmountSheet — future lembar selesai saat pop
  // dipanggil, sementara animasi keluar + penutupan keyboard
  // masih bisa membangun ulang TextField sesudahnya; controller
  // yang di-dispose di finally lembar akan dipakai sesudah
  // dispose. Dibersihkan setiap kali lembar dibuka.
  final TextEditingController _customAmountController =
      TextEditingController();
  late final FeeEstimateService _feeEstimates;
  bool _wasLinked = false;
  String? _lastPeerId;
  Timer? _pathTimer;

  OfflineBridgeService get _bridge => widget.bridge;

  @override
  void initState() {
    super.initState();
    _feeEstimates = widget.feeEstimateService ?? FeeEstimateService();
    _bridge.addListener(_onBridgeChanged);
    _wasLinked = _bridge.isLinked;
    _lastPeerId = _bridge.peerNodeId;
    _loadOwnNodeId();
    _syncPathTimer();
    _refreshPath();
  }

  @override
  void dispose() {
    _pathTimer?.cancel();
    _customAmountController.dispose();
    _bridge.removeListener(_onBridgeChanged);
    super.dispose();
  }

  void _onBridgeChanged() {
    if (!mounted) return;
    // Muat keadaan jalur segera bila tautan ATAU peer berubah —
    // jangan tunggu putaran timer berikutnya. Notifikasi jembatan
    // juga datang untuk penemuan kandidat, yang tidak ada
    // hubungannya dengan jalur; tanpa penjaga ini keramaian
    // perangkat akan membanjiri node dengan panggilan listChannels.
    final linkChanged = _bridge.isLinked != _wasLinked;
    final peerChanged = _bridge.peerNodeId != _lastPeerId;
    setState(() {});
    _syncPathTimer();
    if (linkChanged || peerChanged) _refreshPath();
    _wasLinked = _bridge.isLinked;
    _lastPeerId = _bridge.peerNodeId;
  }

  /// Timer 5 detik selama tertaut ATAU selama ada jalur yang
  /// sedang disiapkan: jalur bisa menjadi siap (pendanaan
  /// terkonfirmasi) tanpa kejadian jembatan apa pun, dan layar
  /// ini sedang ditatap pengguna — 5 detik cukup hidup tanpa
  /// membebani node (layar uji memakai 3 detik untuk daftar peer
  /// + channel). Tanpa tautan dan tanpa penyiapan, timer mati
  /// supaya node tidak dibebani tanpa henti.
  void _syncPathTimer() {
    final shouldRun =
        _bridge.isLinked || _pathState == PathState.preparing;
    if (shouldRun && _pathTimer == null) {
      _pathTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refreshPath(),
      );
    } else if (!shouldRun) {
      _pathTimer?.cancel();
      _pathTimer = null;
    }
  }

  Future<void> _loadOwnNodeId() async {
    if (!widget.lspService.isRunning) {
      if (mounted) setState(() => _loadFailed = true);
      return;
    }
    try {
      final id = await widget.lspService.ownNodeId();
      if (mounted) setState(() => _ownNodeId = id);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  /// Muat ulang keadaan jalur dari daftar channel node (tiga
  /// keadaan, PR C): siap bila ada channel channel_ready dengan
  /// peer yang dikenal, disiapkan bila ada channel dengan peer
  /// itu yang masih dinegosiasikan/menunggu konfirmasi (atau
  /// pembukaan baru yang channel-nya belum muncul di daftar),
  /// belum ada bila tidak ada keduanya. Plafon kirim ke peer itu
  /// (kapasitas keluar channel usable-nya, sudah bersih dari
  /// cadangan) ikut dibaca untuk kartu siap.
  ///
  /// Kartu tampil juga saat TIDAK tertaut — model dua kunjungan
  /// menuntutnya: selama ±10 jam menunggu, kedua HP sudah pulang
  /// dan tidak tertaut lagi. Peer yang dirujuk kartu adalah peer
  /// yang diingat jembatan (masih tersimpan selama sesi aktif);
  /// bila sesi sudah berakhir dan ingatan peer dibersihkan,
  /// kartu memakai channel langsung manapun yang sedang disiapkan.
  /// Kegagalan baca membiarkan nilai terakhir tampil.
  Future<void> _refreshPath() async {
    if (!widget.lspService.isRunning) return;
    final linked = _bridge.isLinked;
    final rememberedPeer = _bridge.peerNodeId;
    // Muat hanya bila ada yang bisa ditampilkan: tertaut, peer
    // diingat, atau sedang memantau penyiapan (sesi sudah berakhir
    // tapi channel disiapkan pernah terlihat di siklus sebelumnya).
    final monitoring = _pathState == PathState.preparing;
    if (!linked && rememberedPeer == null && !monitoring) {
      if (_pathState != PathState.none ||
          _pathReady ||
          _pathSendableMsat != null) {
        if (mounted) {
          setState(() {
            _pathState = PathState.none;
            _preparingChannel = null;
            _displayPeerId = null;
            _pathReady = false;
            _pathSendableMsat = null;
          });
        }
      }
      _syncPathTimer();
      return;
    }
    try {
      final channels = await widget.lspService.listChannels();
      if (!mounted) return;
      // Pangkas himpunan dalam-pembukaan: channel yang sudah
      // muncul di daftar membawa sendiri keadaannya.
      await _openingPaths.prune(channels);
      PathState state;
      ChannelDetails? preparing;
      String? displayPeer;
      var ready = false;
      BigInt? sendable;
      if (rememberedPeer != null) {
        state = pathStateFor(
          channels,
          rememberedPeer,
          hasOpening: _openingPaths.hasOpeningFor(rememberedPeer),
        );
        preparing = preparingChannelForPeer(channels, rememberedPeer);
        displayPeer = rememberedPeer;
        ready = hasReadyPath(channels, rememberedPeer);
        sendable = usableOutboundCapacityToPeer(channels, rememberedPeer);
      } else {
        preparing = preparingDirectChannel(channels, AppConfig.lspNodeId);
        if (preparing != null) {
          state = PathState.preparing;
          displayPeer = preparing.counterpartyNodeId.hex;
        } else {
          state = PathState.none;
        }
      }
      // Biaya pasti pendanaan (best-effort): begitu konfirmasi
      // pertama tercatat, ambil field fee-nya dari REST electrs —
      // sekali per txid, gagal-diam.
      if (preparing != null && (preparing.confirmations ?? 0) >= 1) {
        _maybeFetchFundingFee(preparing);
      }
      // Izin notifikasi: periksa sekali saat memasuki keadaan
      // disiapkan — bila ditolak, kartu menampilkan catatan
      // pengingat.
      if (state == PathState.preparing && !_notifyChecked) {
        _notifyChecked = true;
        notificationPermissionGranted().then((granted) {
          if (mounted) setState(() => _notifyGranted = granted);
        });
      }
      final leavingPreparing =
          _pathState == PathState.preparing && state != PathState.preparing;
      if (state != _pathState ||
          preparing != _preparingChannel ||
          displayPeer != _displayPeerId ||
          ready != _pathReady ||
          sendable != _pathSendableMsat ||
          leavingPreparing) {
        setState(() {
          _pathState = state;
          _preparingChannel = preparing;
          _displayPeerId = displayPeer;
          _pathReady = ready;
          _pathSendableMsat = sendable;
          if (leavingPreparing) {
            // Episode penyiapan berakhir: episode berikutnya
            // memeriksa izin lagi (pengguna bisa saja sudah
            // memberikannya di antara dua episode).
            _notifyChecked = false;
            _notifyGranted = null;
          }
        });
      }
      _syncPathTimer();
    } catch (_) {
      // Nilai terakhir tetap tampil.
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
      if (fee == null || !mounted) return;
      setState(() => _fundingFees[txid] = fee);
    });
  }

  /// Saklar sesi / tombol Akhiri Sesi: menyalakan mode gabung
  /// (niat sesi tersimpan, iklan + pencarian serentak) atau
  /// mematikan sesi (stop: niat dan ingatan peer dibersihkan).
  /// Kegagalan memulai hanya diberitahukan lewat snackbar —
  /// saklar kembali ke keadaan semula lewat rebuild jembatan.
  Future<void> _setSession(bool on) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (on) {
        final id = _ownNodeId;
        if (id == null) return;
        await _bridge.startCombined(
          localName: localEndpointName(id),
          localNodeIdHex: id,
        );
      } else {
        await _bridge.stop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.offlineModeStartFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Alur Buat Jalur (§3 rancangan): izin notifikasi just-in-time
  /// → baca saldo on-chain → lembar nominal → perkiraan biaya →
  /// dialog konfirmasi → buka channel → muat ulang. Setiap
  /// langkah bisa membatalkan alur tanpa efek samping; dana hanya
  /// bergerak pada langkah terakhir.
  Future<void> _onMakePath() async {
    final peerId = _bridge.peerNodeId;
    if (peerId == null || !_bridge.isLinked || _openingChannel) return;
    // Pagar pembukaan dipakai ulang apa adanya (pola layar Uji):
    // peer tertaut lewat jembatan DAN sesi tidak di-boot offline.
    // Sambungan peer Lightning diperiksa ulang pada saat ketuk
    // di [_openPath] — tautan jembatan belum tentu berarti peer
    // Lightning sudah tersambung.
    if (!canOpenDirectChannel(
      peerConnected: _bridge.isLinked,
      sessionOffline: widget.lspService.isOfflineMode,
    )) {
      return;
    }
    // Izin notifikasi (Android 13+): gagal-terbuka — izin bukan
    // prasyarat membuat jalur; tanpa izin, kartu disiapkan
    // menampilkan catatan pengingat.
    await requestNotificationPermission();
    if (!mounted) return;
    BigInt spendable;
    try {
      spendable = await widget.lspService.spendableOnchainBalanceSats();
    } catch (_) {
      // Saldo tidak terbaca: hentikan alur — saldo adalah bahan
      // lembar nominal dan pemeriksaan daya beli.
      _showSnack(context.l10n.offlineModeOpenFailedGeneric);
      return;
    }
    // Momen (1) dialog saldo tidak cukup: tidak bisa membuka
    // jalur apa pun (bahkan minimum + cadangan biaya).
    if (spendable < minPathAmountSats + feeEstimateFallbackReserveSats) {
      await _showInsufficientBalanceDialog(
        amountSats: minPathAmountSats,
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
      peerName: localEndpointName(peerId),
      amountSats: amountSats,
      feeEstimateSats: feeEstimate,
    );
    if (confirmed != true || !mounted) return;
    await _openPath(
      peerId: peerId,
      amountSats: amountSats,
      spendableSats: spendable,
    );
  }

  /// Lembar nominal (§2.2 rancangan): pilihan bawaan 100.000
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
      minPathAmountSats * BigInt.from(1000),
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
                    l10n.offlineModeAmountTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _amountOption(
                    title: context.formatWalletAmount(
                      defaultPathAmountSats * BigInt.from(1000),
                    ),
                    subtitle: l10n.offlineModeAmountDefaultNote,
                    selected: !useCustom,
                    onTap: () => setSheetState(() {
                      useCustom = false;
                      error = null;
                    }),
                  ),
                  const SizedBox(height: 8),
                  _amountOption(
                    title: l10n.offlineModeAmountOther,
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
                        hintText: l10n.offlineModeAmountHint(
                          context.formatWalletAmount(
                            BigInt.from(25000) * BigInt.from(1000),
                          ),
                        ),
                        helperText: l10n.offlineModeAmountHelper(minAmountText),
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
                    l10n.offlineModeOnchainBalance(
                      context.formatWalletAmount(
                        spendableSats * BigInt.from(1000),
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: context.palette.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (!useCustom) {
                          Navigator.of(ctx).pop(defaultPathAmountSats);
                          return;
                        }
                        final msat = parseChannelAmountToMsat(
                          _customAmountController.text,
                          unit,
                          locale: locale,
                        );
                        if (msat == null || msat <= BigInt.zero) {
                          setSheetState(
                            () => error = l10n.offlineModeAmountInvalid(
                              unit.label,
                            ),
                          );
                          return;
                        }
                        final sats = msat ~/ BigInt.from(1000);
                        if (sats < minPathAmountSats) {
                          setSheetState(
                            () => error = l10n.offlineModeAmountTooSmall(
                              minAmountText,
                            ),
                          );
                          return;
                        }
                        Navigator.of(ctx).pop(sats);
                      },
                      child: Text(l10n.offlineModeAmountContinue),
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
            color: selected
                ? const Color(0xFF34D399)
                : context.palette.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? const Color(0xFF34D399)
                  : context.palette.muted,
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

  /// Dialog konfirmasi (§2.3 rancangan): nominal, biaya jaringan
  /// (PERKIRAAN — kata "(perkiraan)" dan tanda "±" wajib ada
  /// karena angka pastinya baru diketahui sesudah node merakit
  /// transaksi pendanaan), total dari dompet on-chain, arah
  /// pendanaan, dan waktu tunggu. Mengembalikan true bila
  /// pengguna menekan Buat Jalur.
  Future<bool?> _showConfirmDialog({
    required String peerName,
    required BigInt amountSats,
    required BigInt? feeEstimateSats,
  }) async {
    final l10n = context.l10n;
    final amountText =
        context.formatWalletAmount(amountSats * BigInt.from(1000));
    final feeText = feeEstimateSats == null
        ? l10n.offlineModeConfirmFeeUnknown
        : '±${context.formatWalletAmount(feeEstimateSats * BigInt.from(1000))}';
    final totalText = feeEstimateSats == null
        ? '±$amountText + ${l10n.offlineModeConfirmFeeWord}'
        : '±${context.formatWalletAmount((amountSats + feeEstimateSats) * BigInt.from(1000))}';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.offlineModeConfirmTitle(peerName)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _confirmRow(l10n.offlineModeConfirmAmount, amountText),
            const SizedBox(height: 8),
            _confirmRow(l10n.offlineModeConfirmFeeEstimate, feeText),
            const SizedBox(height: 8),
            _confirmRow(l10n.offlineModeConfirmTotal, totalText),
            const SizedBox(height: 14),
            Text(
              l10n.offlineModeConfirmDirection(amountText),
              style: TextStyle(fontSize: 13, color: ctx.palette.label),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.offlineModeConfirmWait,
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
            child: Text(l10n.offlineModeConfirmCreate),
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

  /// Dialog saldo tidak cukup (§2.4 rancangan): menginformasikan
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
        title: Text(l10n.offlineModeNoBalanceTitle),
        content: Text(
          l10n.offlineModeNoBalanceBody(
            context.formatWalletAmount(amountSats * BigInt.from(1000)),
            context.formatWalletAmount(balanceSats * BigInt.from(1000)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.offlineModeNoBalanceLater),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.offlineModeNoBalanceDeposit),
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

  /// Buka channel langsung ke [peerId] sebesar [amountSats] nusan
  /// (langkah 4–5 alur): periksa ulang peer tersambung saat itu
  /// juga, panggil openChannel, catat ID-nya di himpunan
  /// dalam-pembukaan, lalu muat ulang daftar channel.
  ///
  /// Aturan muat-ulang sesudah percobaan (§6 rancangan): muat
  /// ulang dilakukan apa pun hasilnya; bila channel yang
  /// disiapkan muncul, lanjut ke keadaan disiapkan dan error-nya
  /// diabaikan (panggilan bisa melempar sesudah channel tercipta).
  /// Hanya bila tidak ada channel yang muncul, pesan error per
  /// sebab ditampilkan.
  Future<void> _openPath({
    required String peerId,
    required BigInt amountSats,
    required BigInt spendableSats,
  }) async {
    if (_openingChannel) return;
    setState(() => _openingChannel = true);
    try {
      if (!await _peerConnected(peerId)) {
        _showSnack(context.l10n.offlineModeOpenFailedPeer);
        return;
      }
      UserChannelId? openedId;
      Object? openError;
      try {
        openedId = await widget.lspService.openChannelToPeer(
          peerId,
          '127.0.0.1',
          OfflineBridgeService.guestBridgePort,
          amountSats,
        );
      } catch (e) {
        openError = e;
      }
      if (openedId != null) {
        await _openingPaths.noteOpened(
          peerNodeIdHex: peerId,
          userChannelId: openedId,
        );
      }
      await _refreshPath();
      if (_pathState == PathState.preparing ||
          _pathState == PathState.ready) {
        return;
      }
      if (openError != null) {
        await _showOpenError(
          openError,
          peerId: peerId,
          amountSats: amountSats,
          spendableSats: spendableSats,
        );
      } else if (openedId == null) {
        _showSnack(context.l10n.offlineModeOpenFailedGeneric);
      }
    } finally {
      if (mounted) setState(() => _openingChannel = false);
    }
  }

  /// Pesan error per sebab (§6 rancangan, Q-C9) — tidak ada lagi
  /// error mentah ke log; layar produksi tidak punya permukaan
  /// log. Urutannya penting: saldo dulu (dialog deposit), lalu
  /// putus di tengah pembukaan (periksa ulang koneksi peer),
  /// lalu node belum siap, terakhir friendlyError dengan pesan
  /// umum sebagai fallback.
  Future<void> _showOpenError(
    Object error, {
    required String peerId,
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
    if (!await _peerConnected(peerId)) {
      _showSnack(context.l10n.offlineModeOpenFailedPeer);
      return;
    }
    if (!widget.lspService.isRunning ||
        s.contains('inisialisasi') ||
        s.contains('initialized')) {
      _showSnack(context.l10n.offlineModeOpenFailedNotReady);
      return;
    }
    _showSnack(
      friendlyError(
        error,
        fallback: context.l10n.offlineModeOpenFailedGeneric,
        l10n: context.l10n,
      ),
    );
  }

  /// Apakah peer Lightning [peerId] sedang tersambung ke node ini
  /// — pola `_peerConnected` layar Uji. Gagal baca berarti tidak
  /// tersambung (fail-closed: pembukaan ditunda, bukan dicoba
  /// buta).
  Future<bool> _peerConnected(String peerId) async {
    try {
      final peers = await widget.lspService.listPeerDetails();
      final id = peerId.toLowerCase();
      return peers.any(
        (p) => p.nodeId.hex.toLowerCase() == id && p.isConnected,
      );
    } catch (_) {
      return false;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.offlineModeTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _ownNodeId == null && !_loadFailed
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.offlineModeStartFailed),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      setState(() => _loadFailed = false);
                      _loadOwnNodeId();
                    },
                    child: Text(l10n.bootFailedRetry),
                  ),
                ],
              ),
            )
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = context.l10n;
    final bridge = _bridge;
    final ownId = _ownNodeId!;
    final state = offlineModeState(
      sessionActive: bridge.sessionActive,
      linked: bridge.isLinked,
      pathReady: _pathReady,
      pathPreparing: _pathState == PathState.preparing,
    );
    // Daftar kandidat hanya untuk mode gabung — sesi peran lama
    // (host/tamu dari layar uji) tidak mencari perangkat, jadi
    // tidak ada kandidat untuk ditampilkan; saklar tetap bisa
    // mematikannya lewat Akhiri Sesi.
    final showCandidates =
        bridge.sessionActive &&
        !bridge.isLinked &&
        bridge.role == OfflineBridgeRole.combined;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sessionCard(context, state),
          const SizedBox(height: 14),
          _myCodeCard(context, ownId),
          if (showCandidates) ...[
            const SizedBox(height: 14),
            if (bridge.discovered.isEmpty)
              _searchingCard(context)
            else
              ...bridge.discovered.map((host) => _candidateCard(context, host)),
          ],
          if (bridge.isLinked) ...[
            const SizedBox(height: 14),
            _connectedCard(context),
            const SizedBox(height: 8),
            _pathCard(context),
          ] else if (_showPathCard) ...[
            // Tidak tertaut tapi kartu tetap tampil: jalur sedang
            // disiapkan (model dua kunjungan — kemajuan dipantau
            // dari sini walau kedua HP sudah pulang) atau jalur
            // sudah siap dengan peer yang diingat (sambungkan lagi
            // untuk membayar).
            const SizedBox(height: 14),
            _pathCard(context),
          ],
          if (bridge.sessionActive) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _setSession(false),
                icon: const Icon(Icons.stop_rounded),
                label: Text(l10n.offlineModeEndSession),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF87171),
                  side: const BorderSide(color: Color(0xFFF87171)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Kartu saklar sesi — pola baris Profil (ubin ikon + judul +
  /// subjudul keadaan + saklar, seperti baris Tema). Subjudulnya
  /// sama persis dengan subjudul baris Mode Offline di Profil.
  Widget _sessionCard(BuildContext context, OfflineModeState state) {
    final l10n = context.l10n;
    final bridge = _bridge;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF10B981).withValues(alpha: 0.25),
                      const Color(0xFF10B981).withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.bluetooth_rounded,
                  color: Color(0xFF34D399),
                  size: 20,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.offlineModeTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitleForState(l10n, state, bridge.linkedEndpointName),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: bridge.sessionActive,
                onChanged: _busy ? null : _setSession,
              ),
            ],
          ),
          if (bridge.phase == OfflineBridgePhase.error)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 16,
                    color: Color(0xFFF87171),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.offlineModeStartFailed,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFF87171),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Kartu kode perangkat saya — kode tampil besar supaya bisa
  /// dicocokkan mata dengan daftar kandidat di HP seberang;
  /// nama endpoint kecil di bawahnya. Kartu ini tampil juga saat
  /// sesi mati: kode adalah identitas HP ini, bukan keadaan sesi.
  Widget _myCodeCard(BuildContext context, String ownId) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF0A5C42), Color(0xFF062A20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.offlineModeMyCode,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            formatDeviceCode(ownId),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            localEndpointName(ownId),
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  /// Kartu pencarian: sesi hidup, belum ada kandidat ditemukan.
  Widget _searchingCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.offlineModeSearching,
              style: TextStyle(fontSize: 14, color: context.palette.label),
            ),
          ),
        ],
      ),
    );
  }

  /// Satu kandidat dari daftar penemuan: nama endpoint + kode
  /// perangkatnya + tombol Sambungkan. Satu kandidat pun tetap
  /// butuh ketukan ini (prinsip 4 rancangan) — tidak ada sambung
  /// otomatis pada mulai segar.
  Widget _candidateCard(BuildContext context, DiscoveredHost host) {
    final l10n = context.l10n;
    final code = codeFromEndpointName(host.name);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  host.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.palette.label,
                  ),
                ),
                if (code != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    code,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _bridge.phase == OfflineBridgePhase.connecting
                ? null
                : () => _bridge.connectCombined(host),
            child: Text(l10n.offlineModeConnect),
          ),
        ],
      ),
    );
  }

  /// Kartu perangkat tertaut: nama endpoint + kodenya supaya
  /// pengguna yakin ini perangkat yang benar.
  Widget _connectedCard(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF34D399),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.offlineModeConnected,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.palette.label,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _linkedLabel(_bridge),
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Apakah kartu jalur tampil saat TIDAK tertaut: jalur sedang
  /// disiapkan (kemajuan dipantau dari sini), atau jalur sudah
  /// siap dengan peer yang diingat (sambungkan lagi untuk
  /// membayar). Saat tertaut kartu selalu tampil.
  bool get _showPathCard {
    if (_bridge.isLinked) return true;
    if (_pathState == PathState.preparing) return true;
    return _pathState == PathState.ready && _displayPeerId != null;
  }

  /// Kartu keadaan jalur tiga keadaan (PR C):
  /// - Belum ada (hanya saat tertaut): "Jalur pembayaran belum
  ///   ada" + tombol [Buat Jalur Pembayaran]. Pada sesi
  ///   boot-offline tombolnya tidak aktif + kalimat polos
  ///   (jalur baru butuh internet sekali saat disiapkan).
  /// - Disiapkan: "Jalur sedang disiapkan…" + kemajuan konfirmasi
  ///   ("Konfirmasi X/6" + batang, meniru pola layar Uji) + nilai
  ///   jalur + biaya pasti (begitu konfirmasi ≥ 1) + catatan
  ///   izin notifikasi bila ditolak. Tampil juga saat tidak
  ///   tertaut (model dua kunjungan).
  /// - Siap: kartu siap yang sudah ada ("Jalur siap — bisa bayar
  ///   tanpa internet" + "Bisa kirim sampai X"); bila peer tidak
  ///   tersambung, varian "sambungkan lagi ke ELNUX-XXXX".
  Widget _pathCard(BuildContext context) {
    final l10n = context.l10n;
    final state = _pathState;
    final IconData icon;
    final Color iconColor;
    if (state == PathState.ready) {
      icon = Icons.check_circle_rounded;
      iconColor = const Color(0xFF34D399);
    } else if (state == PathState.preparing) {
      icon = Icons.hourglass_top_rounded;
      iconColor = const Color(0xFFFBBF24);
    } else {
      icon = Icons.info_outline_rounded;
      iconColor = context.palette.muted;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pathCardTitle(l10n),
                      style: TextStyle(
                        fontSize: 14,
                        color: context.palette.label,
                      ),
                    ),
                    ..._pathCardLines(l10n),
                  ],
                ),
              ),
            ],
          ),
          if (state == PathState.preparing) ...[
            const SizedBox(height: 12),
            _preparingProgressBar(),
          ],
          if (state == PathState.none && _bridge.isLinked) ...[
            const SizedBox(height: 12),
            _makePathButton(),
          ],
        ],
      ),
    );
  }

  /// Judul kartu jalur per keadaan.
  String _pathCardTitle(AppLocalizations l10n) {
    switch (_pathState) {
      case PathState.ready:
        if (_bridge.isLinked && _pathReady) return l10n.offlineModeReady;
        final peerId = _displayPeerId;
        if (peerId == null) return l10n.offlineModeReady;
        return l10n.offlineModeReadyUnlinked(localEndpointName(peerId));
      case PathState.preparing:
        return l10n.offlineModePreparing;
      case PathState.none:
        return l10n.offlineModeNoPath;
    }
  }

  /// Baris-baris di bawah judul kartu jalur per keadaan.
  List<Widget> _pathCardLines(AppLocalizations l10n) {
    switch (_pathState) {
      case PathState.ready:
        if (_bridge.isLinked && _pathReady && _pathSendableMsat != null) {
          return [
            const SizedBox(height: 3),
            Text(
              l10n.offlineModeCanSendUpTo(
                context.formatWalletAmount(_pathSendableMsat!),
              ),
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          ];
        }
        return const [];
      case PathState.preparing:
        final lines = <Widget>[];
        final channel = _preparingChannel;
        final required = channel?.confirmationsRequired;
        final done = channel?.confirmations ?? 0;
        lines.add(const SizedBox(height: 3));
        if (channel == null || required == null) {
          // Jendela negosiasi (channel belum muncul di daftar)
          // atau jumlah wajib belum diketahui: tanpa angka,
          // gagal-terbuka.
          lines.add(
            Text(
              l10n.offlineModeWaitingConfirmations,
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          );
        } else if (done == 0) {
          // 0 konfirmasi (pendanaan tersiar, blok pertama belum
          // datang — di mainnet ini bisa berjam-jam, normal):
          // baris penenang tanpa angka jam.
          lines.add(
            Text(
              l10n.offlineModeWaitingFirst,
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          );
          lines.add(const SizedBox(height: 3));
          lines.add(
            Text(
              l10n.offlineModeWaitingFirstNote,
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          );
        } else {
          lines.add(
            Text(
              l10n.offlineModePreparingConfirmations(done, required),
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          );
          // Baris penjelas jumlah wajib + catatan jadwal
          // penambangan (sebelumnya hanya ada di cabang 0
          // konfirmasi): di mainnet jeda antar-blok bisa
          // berjam-jam, jadi pengguna perlu tahu bahwa menunggu
          // itu normal — dan bahwa mereka bisa menambang sendiri.
          lines.add(const SizedBox(height: 3));
          lines.add(
            Text(
              l10n.offlineModePreparingOfRequired(required),
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          );
          lines.add(const SizedBox(height: 3));
          lines.add(
            Text(
              l10n.offlineModeWaitingFirstNote,
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          );
        }
        if (channel != null) {
          lines.add(const SizedBox(height: 3));
          lines.add(
            Text(
              l10n.offlineModePreparingValue(
                context.formatWalletAmount(
                  channel.channelValueSats * BigInt.from(1000),
                ),
              ),
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          );
          final txid = channel.fundingTxo?.txid.hash;
          final fee = txid == null ? null : _fundingFees[txid];
          if (fee != null) {
            lines.add(const SizedBox(height: 3));
            lines.add(
              Text(
                l10n.offlineModePreparingFee(
                  context.formatWalletAmount(fee * BigInt.from(1000)),
                ),
                style: TextStyle(fontSize: 12, color: context.palette.muted),
              ),
            );
          }
        }
        if (_notifyGranted == false) {
          lines.add(const SizedBox(height: 3));
          lines.add(
            Text(
              l10n.offlineModeNotifyPermissionNote,
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          );
        }
        return lines;
      case PathState.none:
        return const [];
    }
  }

  /// Batang kemajuan konfirmasi kartu disiapkan: nilai X/6 bila
  /// jumlah wajib diketahui, tak tentu (indeterminate) bila tidak.
  Widget _preparingProgressBar() {
    final channel = _preparingChannel;
    final required = channel?.confirmationsRequired;
    final done = channel?.confirmations ?? 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: required == null ? null : done / required,
        minHeight: 6,
        backgroundColor: context.palette.border,
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
      ),
    );
  }

  /// Tombol Buat Jalur di kartu "belum ada": aktif bila pagar
  /// pembukaan terpenuhi (peer tertaut + sesi tidak di-boot
  /// offline), terkunci selama pembukaan berjalan. Pada sesi
  /// boot-offline tombolnya tidak aktif + kalimat polos —
  /// BUKAN string jargon (audit G4.4).
  Widget _makePathButton() {
    final l10n = context.l10n;
    final sessionOffline = widget.lspService.isOfflineMode;
    final canOpen = canOpenDirectChannel(
      peerConnected: _bridge.isLinked,
      sessionOffline: sessionOffline,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canOpen && !_openingChannel ? _onMakePath : null,
            child: Text(l10n.offlineModeMakePath),
          ),
        ),
        if (sessionOffline) ...[
          const SizedBox(height: 8),
          Text(
            l10n.offlineModePathNeedsInternet,
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
        ],
      ],
    );
  }

  /// Label perangkat tertaut: nama endpoint + kodenya
  /// ("ELNUX-039B7213 • 039B 7213").
  String _linkedLabel(OfflineBridgeService bridge) {
    final name = bridge.linkedEndpointName;
    if (name == null) return '';
    final code = codeFromEndpointName(name);
    return code == null ? name : '$name • $code';
  }
}

/// Subjudul keadaan tuas untuk [state] — dipakai kartu saklar
/// layar dan baris Profil, supaya keduanya selalu berkata sama.
/// [linkedName] hanya dipakai pada keadaan terhubung.
String _subtitleForState(
  AppLocalizations l10n,
  OfflineModeState state,
  String? linkedName,
) {
  switch (state) {
    case OfflineModeState.off:
      return l10n.offlineModeOff;
    case OfflineModeState.searching:
      return l10n.offlineModeSearching;
    case OfflineModeState.connected:
      final name = linkedName;
      return name == null
          ? l10n.offlineModeConnected
          : l10n.offlineModeConnectedTo(name);
    case OfflineModeState.preparing:
      return l10n.offlineModePreparing;
    case OfflineModeState.ready:
      return l10n.offlineModeReady;
  }
}

/// Baris Mode Offline di Profil — mengikuti pola baris Kelola
/// Channel (ubin ikon + judul + subjudul + chevron), dengan
/// subjudul yang memantulkan keadaan sesi secara langsung: mati
/// (deskripsi fitur), mencari, terhubung ke perangkat X, atau
/// jalur siap. Digebangi testnet oleh pemanggil, sama seperti
/// baris Uji Offline.
class OfflineModeRow extends StatefulWidget {
  final LspService lspService;
  final OfflineBridgeService bridge;

  const OfflineModeRow({
    super.key,
    required this.lspService,
    required this.bridge,
  });

  @override
  State<OfflineModeRow> createState() => _OfflineModeRowState();
}

class _OfflineModeRowState extends State<OfflineModeRow> {
  bool _pathReady = false;
  bool _pathPreparing = false;
  bool _lastLinked = false;
  String? _lastPeerId;
  Timer? _pathTimer;

  OfflineBridgeService get _bridge => widget.bridge;

  @override
  void initState() {
    super.initState();
    _bridge.addListener(_onBridgeChanged);
    _syncPathTimer();
    _refreshPath(force: true);
  }

  @override
  void dispose() {
    _pathTimer?.cancel();
    _bridge.removeListener(_onBridgeChanged);
    super.dispose();
  }

  void _onBridgeChanged() {
    if (!mounted) return;
    setState(() {});
    _syncPathTimer();
    _refreshPath(force: false);
  }

  /// Timer 15 detik hanya selama tertaut: jalur bisa menjadi siap
  /// tanpa kejadian jembatan apa pun. Baris ini hidup selama
  /// aplikasi berjalan (tab Profil dipertahankan IndexedStack),
  /// jadi timer yang tidak dibatasi tautan akan membebani node
  /// tanpa henti.
  void _syncPathTimer() {
    if (_bridge.isLinked && _pathTimer == null) {
      _pathTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _refreshPath(force: true),
      );
    } else if (!_bridge.isLinked) {
      _pathTimer?.cancel();
      _pathTimer = null;
    }
  }

  /// Muat ulang keadaan jalur. Jalur pemanggilan dari notifikasi
  /// jembatan ([force] false) hanya memuat bila tautan atau peer
  /// berubah — notifikasi juga datang untuk penemuan kandidat,
  /// yang tidak ada hubungannya dengan jalur; tanpa penjaga ini
  /// keramaian perangkat akan membanjiri node dengan panggilan
  /// listChannels.
  Future<void> _refreshPath({required bool force}) async {
    final linked = _bridge.isLinked;
    final peerId = _bridge.peerNodeId;
    if (!linked || peerId == null) {
      _lastLinked = linked;
      _lastPeerId = peerId;
      if ((_pathReady || _pathPreparing) && mounted) {
        setState(() {
          _pathReady = false;
          _pathPreparing = false;
        });
      }
      return;
    }
    if (!force && linked == _lastLinked && peerId == _lastPeerId) return;
    _lastLinked = linked;
    _lastPeerId = peerId;
    try {
      final channels = await widget.lspService.listChannels();
      if (!mounted) return;
      final ready = hasReadyPath(channels, peerId);
      final preparing =
          pathStateFor(channels, peerId) == PathState.preparing;
      if (ready != _pathReady || preparing != _pathPreparing) {
        setState(() {
          _pathReady = ready;
          _pathPreparing = preparing;
        });
      }
    } catch (_) {
      // Nilai terakhir tetap tampil.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = _bridge;
    final state = offlineModeState(
      sessionActive: bridge.sessionActive,
      linked: bridge.isLinked,
      pathReady: _pathReady,
      pathPreparing: _pathPreparing,
    );
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OfflineModeScreen(
            lspService: widget.lspService,
            bridge: widget.bridge,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF10B981).withValues(alpha: 0.25),
                    const Color(0xFF10B981).withValues(alpha: 0.08),
                  ],
                ),
              ),
              child: const Icon(
                Icons.bluetooth_rounded,
                color: Color(0xFF34D399),
                size: 20,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.offlineModeTitle,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _subtitleForState(
                      context.l10n,
                      state,
                      bridge.linkedEndpointName,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.palette.muted),
          ],
        ),
      ),
    );
  }
}
