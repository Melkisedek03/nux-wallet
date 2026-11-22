import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../locale_controller.dart';
import '../services/deposit_progress.dart';
import '../services/lsp_service.dart';
import '../services/onchain_address_store.dart';
import '../theme.dart';
import '../unit_controller.dart';
import '../utils/format.dart';

/// Layar Dompet On-chain — saldo dompet on-chain internal node
/// beserta alamat depositnya. Dibuka dari baris Dompet On-chain
/// di Profil.
///
/// Dana hasil penutupan channel kembali ke dompet ini; sebelum
/// halaman ini ada, angkanya hanya terlihat di layar uji — dan
/// baris on-chain di kartu saldo Beranda terbukti membuat kartu
/// membengkak (QA visual build 109), jadi rumahnya pindah ke sini.
/// Angka utama kartu Beranda tetap khusus Lightning.
class OnchainScreen extends StatefulWidget {
  final LspService lspService;
  final DepositProgressService? depositProgressService;

  const OnchainScreen({
    super.key,
    required this.lspService,
    this.depositProgressService,
  });

  @override
  State<OnchainScreen> createState() => _OnchainScreenState();
}

class _OnchainScreenState extends State<OnchainScreen> {
  final _addressStore = OnchainAddressStore();
  late final DepositProgressService _depositProgress;
  OnchainOverview? _overview;
  String? _address;
  bool _loading = true;
  bool _refreshingAddress = false;
  List<PendingDeposit> _pendingDeposits = const [];
  Timer? _depositTimer;

  @override
  void initState() {
    super.initState();
    _depositProgress =
        widget.depositProgressService ?? DepositProgressService();
    _muat();
    _muatDeposit();
  }

  @override
  void dispose() {
    _depositTimer?.cancel();
    super.dispose();
  }

  /// Muat deposit yang masih menunggu konfirmasi: riwayat dari
  /// node + tinggi ujung dari electrs. Gagal-terbuka penuh —
  /// kegagalan di sini tidak boleh merusak layar saldo: daftar
  /// terakhir tetap tampil (atau kosong bila belum pernah ada).
  Future<void> _muatDeposit() async {
    try {
      final payments = await widget.lspService.listPayments();
      final tip = await _depositProgress.fetchTipHeight();
      if (!mounted) return;
      setState(() {
        _pendingDeposits = pendingDeposits(payments, tip);
      });
      _syncDepositTimer();
    } catch (_) {
      // Daftar terakhir tetap tampil; percobaan berikutnya dari
      // timer atau refresh manual.
      if (mounted) _syncDepositTimer();
    }
  }

  /// Timer 5 detik HANYA selama ada deposit tertunda (pola yang
  /// sama dengan timer kartu "disiapkan" Kelola Channel) — tanpa
  /// deposit tertunda tidak ada polling yang berjalan.
  void _syncDepositTimer() {
    if (_pendingDeposits.isNotEmpty && _depositTimer == null) {
      _depositTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _muatDeposit(),
      );
    } else if (_pendingDeposits.isEmpty) {
      _depositTimer?.cancel();
      _depositTimer = null;
    }
  }

  /// Muat ringkasan saldo + alamat deposit sekali per kunjungan
  /// layar. Alamatnya dari simpanan (lihat
  /// [_alamatTersimpanAtauBaru]) — TIDAK dibuat baru di tiap
  /// kunjungan.
  Future<void> _muat() async {
    try {
      final overview = await widget.lspService.getOnchainOverview();
      final address = await _alamatTersimpanAtauBaru();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _address = address;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Alamat yang ditampilkan: simpanan untuk dompet ini bila ada;
  /// bila belum ada, buat SEKALI lewat node lalu simpan. Setiap
  /// panggilan onchainAddress menurunkan alamat BARU dari dompet,
  /// jadi memanggilnya di tiap kunjungan layar membakar alamat
  /// yang belum sempat dipakai — itu yang dihentikan keputusan
  /// NUX 15 Nov 2026. Alamat baru sesudah ini hanya dari tombol
  /// Refresh manual ([_segarkanAlamat]).
  Future<String> _alamatTersimpanAtauBaru() async {
    try {
      final nodeId = await widget.lspService.ownNodeId();
      final stored = await _addressStore.load(nodeId: nodeId);
      if (stored != null) return stored;
      final fresh = await widget.lspService.onchainAddress();
      await _addressStore.save(address: fresh, nodeId: nodeId);
      return fresh;
    } catch (_) {
      // ID node tidak terbaca (node belum jalan dsb.): buat alamat
      // segar untuk tampilan ini tanpa menyimpan — kunjungan
      // berikutnya mengulang dari simpanan lama / baru lagi.
      return widget.lspService.onchainAddress();
    }
  }

  /// Tombol Refresh manual di kartu alamat: buat alamat BARU atas
  /// permintaan user, simpan sebagai alamat tampil, dan tampilkan.
  /// Alamat lama tetap milik dompet yang sama (dana yang telanjur
  /// dikirim ke sana tetap masuk) — yang berganti hanya alamat
  /// yang ditampilkan.
  Future<void> _segarkanAlamat() async {
    if (_refreshingAddress) return;
    setState(() => _refreshingAddress = true);
    try {
      final nodeId = await widget.lspService.ownNodeId();
      final address = await widget.lspService.onchainAddress();
      await _addressStore.save(address: address, nodeId: nodeId);
      if (!mounted) return;
      setState(() => _address = address);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.onchainLoadFailed)),
      );
    } finally {
      if (mounted) setState(() => _refreshingAddress = false);
    }
  }

  /// Muat ulang saldo + deposit tertunda. Alamat TIDAK dimuat
  /// ulang: setiap panggilan onchainAddress menurunkan alamat
  /// BARU dari dompet, jadi memuat ulang alamat akan membakar
  /// alamat yang belum sempat dipakai.
  Future<void> _muatUlangSaldo() async {
    _muatDeposit();
    try {
      final overview = await widget.lspService.getOnchainOverview();
      if (!mounted) return;
      setState(() => _overview = overview);
    } catch (_) {
      // Nilai terakhir tetap tampil; kegagalan refresh hanya
      // diberitahukan lewat snackbar.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.onchainLoadFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.onchainTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loading ? null : _muatUlangSaldo,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _overview == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.onchainLoadFailed),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          setState(() => _loading = true);
                          _muat();
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
    final overview = _overview!;
    final unit = context.displayUnit.label;
    String amount(BigInt sats) =>
        context.formatWalletAmountNumber(sats * BigInt.from(1000));
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kartu total: angka besar, sama seperti angka utama
          // kartu saldo Beranda.
          Container(
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
                  l10n.onchainTotal,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  '${amount(overview.totalSats)} $unit',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Baris turunan: hanya yang menambah informasi — porsi
          // yang belum bisa dipakai, dan dana yang masih terkunci
          // jeda pengaman penutupan paksa.
          if (overview.spendableSats != overview.totalSats)
            _row(
              context,
              l10n.balanceSpendable,
              '${amount(overview.spendableSats)} $unit',
            ),
          if (overview.timelockSats > BigInt.zero)
            _row(
              context,
              l10n.balanceTimelock,
              '${amount(overview.timelockSats)} $unit'
                  '${overview.timelockHeight == null ? '' : ' • ${l10n.balanceTimelockUnlocks(overview.timelockHeight!)}'}',
            ),
          // Deposit yang masih menunggu konfirmasi — satu baris
          // per deposit, dengan progres x/6. Bagian ini HILANG
          // seluruhnya bila tidak ada deposit tertunda (tanpa
          // pesan keadaan kosong): deposit yang mencapai 6/6
          // berstatus Succeeded dan catatan riwayatnya yang
          // tersisa.
          if (_pendingDeposits.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l10n.onchainPendingTitle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.palette.label,
              ),
            ),
            const SizedBox(height: 8),
            for (final deposit in _pendingDeposits)
              _depositCard(context, deposit, amount),
            const SizedBox(height: 6),
          ],
          if (_address != null) ...[
            const SizedBox(height: 14),
            Text(
              l10n.onchainAddress,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.palette.label),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _address!,
                      style: TextStyle(
                          fontSize: 12, color: context.palette.label),
                    ),
                  ),
                  // Refresh manual: satu-satunya jalan membuat alamat
                  // baru — keputusan di tangan user, bukan otomatis
                  // tiap buka menu (keputusan NUX 15 Nov 2026).
                  // Tombol refresh di AppBar hanya memuat ulang
                  // SALDO dan sengaja tidak menyentuh alamat.
                  IconButton(
                    tooltip: l10n.onchainNewAddress,
                    icon: const Icon(Icons.refresh_rounded,
                        color: Color(0xFF34D399)),
                    onPressed:
                        _refreshingAddress ? null : _segarkanAlamat,
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Color(0xFF34D399)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _address!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.onchainCopied)),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.onchainAddressHint,
              style:
                  TextStyle(fontSize: 12, color: context.palette.muted),
            ),
          ],
        ],
      ),
    );
  }

  /// Salin txid deposit (pola yang sama dengan baris txid kartu
  /// channel): teks maupun ikon bisa diketuk.
  void _copyTxid(String txid) {
    Clipboard.setData(ClipboardData(text: txid));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.txCopied)),
    );
  }

  /// Kartu satu deposit tertunda: jumlah, progres konfirmasi
  /// x/6 + batang progres, dan txid (ketuk untuk salin).
  ///
  /// Seluruhnya Column mengikuti [_row]: jumlah dan teks
  /// progres masing-masing di barisnya sendiri — teks progres
  /// terpanjang ("0/6 — menunggu blok pertama") berdampingan
  /// dengan jumlah dalam satu Row meluber 49dp pada lebar 360
  /// (ditemukan tes widget). txid 64 karakter juga tidak pernah
  /// masuk satu baris Row tanpa meluber.
  Widget _depositCard(
    BuildContext context,
    PendingDeposit deposit,
    String Function(BigInt) amount,
  ) {
    final l10n = context.l10n;
    final confirmations = deposit.confirmations;
    final progressText = confirmations == null
        ? l10n.onchainDepositConfirmationsUnknown
        : confirmations == 0
        ? l10n.onchainDepositWaitingFirst(depositConfirmationsRequired)
        : l10n.onchainDepositConfirmations(
            confirmations,
            depositConfirmationsRequired,
          );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '+${amount(deposit.amountSats)} ${context.displayUnit.label}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.palette.label,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            progressText,
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
          if (confirmations != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: confirmations / depositConfirmationsRequired,
              backgroundColor: context.palette.border,
              color: const Color(0xFF34D399),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _copyTxid(deposit.txid),
                  child: Text(
                    deposit.txid,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _copyTxid(deposit.txid),
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
      ),
    );
  }

  /// Kartu keterangan (rincian saldo): label di atas, nilai di
  /// bawah — Column, bukan Row. Bentuk Row sebelumnya membuat
  /// LABEL yang menumpuk vertikal, bukan nilai: nilai (tanpa
  /// flex) diukur duluan dengan lebar intrinsik penuhnya
  /// (~484dp untuk "jumlah • terbuka ~blok N"), sehingga label
  /// Expanded hanya kebagian lebar 0 dan menumpuk kata-per-kata
  /// setinggi 320dp, sementara nilai tetap satu baris horizontal
  /// dan meluber 247dp ke kanan kartu (diukur dari bentuk Row
  /// lama pada HP 320; koreksi NUX 13 Nov — laporan pertama
  /// Strider sempat tertukar menyebut nilai yang menumpuk).
  /// Dalam Column kedua teks memakai lebar penuh kartu dan hanya
  /// terlipat di batas kata. Bentuknya sengaja mengikuti kartu
  /// total di atas (label kecil di atas, angka di bawah) supaya
  /// satu bahasa visual.
  Widget _row(BuildContext context, String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: context.palette.muted)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.palette.label)),
        ],
      ),
    );
  }
}
