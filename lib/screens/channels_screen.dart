import 'package:flutter/material.dart';
import 'package:ldk_node/src/generated/api/types.dart';

import '../config.dart';
import '../locale_controller.dart';
import '../services/lsp_service.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/friendly_error.dart';

/// Layar Kelola Channel — daftar semua channel node (LSP dan
/// langsung) beserta penutupannya dari sisi pengguna.
///
/// Penutupan adalah mata rantai terakhir siklus hidup dana di
/// ELNUX: saldo Lightning kembali ke dompet on-chain internal
/// (alamat dari frasa yang sama) lewat transaksi penutup.
/// Alurnya selalu tutup KERJA SAMA lebih dulu; tutup paksa hanya
/// ditawarkan sesudah kerja sama gagal, dengan penjelasannya
/// sendiri (jeda pengaman dalam blok + biaya lebih mahal).
///
/// Batas v1 yang disengaja: tombol tutup hanya ada untuk
/// channel yang sudah siap (channel_ready). Channel yang masih
/// menunggu konfirmasi ditampilkan dengan kemajuannya tanpa
/// tombol — menutup channel yang dananya belum terkonfirmasi
/// adalah persoalan lain (pembatalan pendanaan), bukan
/// penutupan biasa.
class ChannelsScreen extends StatefulWidget {
  final LspService lspService;

  const ChannelsScreen({super.key, required this.lspService});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<ChannelDetails> _channels = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  bool _isLsp(ChannelDetails ch) =>
      ch.counterpartyNodeId.hex.toLowerCase() ==
      AppConfig.lspNodeId.toLowerCase();

  Future<void> _muat() async {
    try {
      final all = await widget.lspService.listChannels();
      if (!mounted) return;
      final sorted = [...all]..sort((a, b) {
          // Channel LSP selalu paling atas — ia jalur utama
          // dompet; sisanya dari kapasitas terbesar.
          if (_isLsp(a) != _isLsp(b)) return _isLsp(a) ? -1 : 1;
          return b.channelValueSats.compareTo(a.channelValueSats);
        });
      setState(() {
        _channels = sorted;
        _loading = false;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  static String _shortId(String hex) {
    if (hex.length <= 20) return hex;
    return '${hex.substring(0, 10)}…${hex.substring(hex.length - 6)}';
  }

  String _status(ChannelDetails ch) {
    final l10n = context.l10n;
    if (!ch.isChannelReady) {
      final conf = ch.confirmations;
      final req = ch.confirmationsRequired;
      if (conf != null && req != null) {
        return '${l10n.channelStatusPending} • ${l10n.offlineConfirmations} $conf/$req';
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
        formatNusan(countedChannelBalanceMsat(ch));
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.channelsTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
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
              Text(_status(ch),
                  style: TextStyle(
                      fontSize: 12, color: context.palette.muted)),
            ],
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
            '${l10n.channelCapacity} ${formatNusan(ch.channelValueSats * BigInt.from(1000))} • ${l10n.channelYourBalance} ${formatNusan(countedChannelBalanceMsat(ch))}',
            style:
                TextStyle(fontSize: 12.5, color: context.palette.muted),
          ),
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
