import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../locale_controller.dart';
import '../services/lsp_service.dart';
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

  const OnchainScreen({super.key, required this.lspService});

  @override
  State<OnchainScreen> createState() => _OnchainScreenState();
}

class _OnchainScreenState extends State<OnchainScreen> {
  OnchainOverview? _overview;
  String? _address;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  /// Muat ringkasan saldo + alamat deposit sekali per kunjungan
  /// layar.
  Future<void> _muat() async {
    try {
      final overview = await widget.lspService.getOnchainOverview();
      final address = await widget.lspService.onchainAddress();
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

  /// Muat ulang saldo saja. Alamat TIDAK dimuat ulang: setiap
  /// panggilan onchainAddress menurunkan alamat BARU dari dompet,
  /// jadi memuat ulang alamat akan membakar alamat yang belum
  /// sempat dipakai.
  Future<void> _muatUlangSaldo() async {
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

  /// Kartu keterangan (rincian saldo): label di atas, nilai di
  /// bawah — Column, bukan Row. Bentuk Row sebelumnya membuat
  /// kolom nilai terjepit di antara label yang panjang
  /// ("Menunggu timelock") dan lebar kartu: nilai "jumlah • buka
  /// ~blok N" terlipat kata-per-kata menjadi kolom vertikal
  /// (temuan lapangan NUX, build 110). Dalam Column kedua teks
  /// memakai lebar penuh kartu dan hanya terlipat di batas kata.
  /// Bentuknya sengaja mengikuti kartu total di atas (label kecil
  /// di atas, angka di bawah) supaya satu bahasa visual.
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
