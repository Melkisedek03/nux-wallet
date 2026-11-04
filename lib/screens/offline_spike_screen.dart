import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_localizations.dart';
import '../locale_controller.dart';
import '../services/lsp_service.dart';
import '../services/offline_bridge.dart';
import '../theme.dart';

/// Layar Uji Offline Lightning (spike tahap 1) — membuktikan dua
/// node ELNUX bisa tersambung sebagai peer lewat jembatan
/// Bluetooth (Nearby Connections → localhost), tanpa internet.
///
/// Alur uji dua HP:
/// 1. HP host menekan "Host" — jembatan mengiklankan diri dan
///    node host sudah mendengarkan di localhost (khusus testnet).
/// 2. HP tamu menekan "Tamu", memilih host yang ditemukan, lalu
///    jembatan terhubung.
/// 3. HP tamu menempel ID node host dan menekan "Sambungkan Node
///    Lightning" — node tamu connect() ke jembatan lokalnya.
/// 4. Bukti keberhasilan: daftar Peer Lightning di kedua HP
///    menampilkan pihak seberang berstatus Terhubung.
///
/// Layar ini eksperimental dan hanya berguna di testnet; ia tidak
/// mengubah alur dompet normal sama sekali.
class OfflineSpikeScreen extends StatefulWidget {
  final LspService lspService;

  const OfflineSpikeScreen({super.key, required this.lspService});

  @override
  State<OfflineSpikeScreen> createState() => _OfflineSpikeScreenState();
}

class _OfflineSpikeScreenState extends State<OfflineSpikeScreen> {
  late final OfflineBridgeService _bridge;
  final _hostNodeIdController = TextEditingController();
  final List<String> _log = [];
  String? _ownNodeId;
  List<PeerDetails> _peers = const [];
  Timer? _peerTimer;
  bool _connectingNode = false;

  @override
  void initState() {
    super.initState();
    _bridge = OfflineBridgeService(
      onChanged: () {
        if (mounted) setState(() {});
      },
      onLog: _addLog,
    );
    _loadOwnNodeId();
    _refreshPeers();
    _peerTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshPeers(),
    );
  }

  @override
  void dispose() {
    _peerTimer?.cancel();
    _bridge.stop();
    _hostNodeIdController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    if (!mounted) return;
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _log.insert(0, '$stamp  $message');
      if (_log.length > 40) _log.removeRange(40, _log.length);
    });
  }

  Future<void> _loadOwnNodeId() async {
    if (!widget.lspService.isRunning) return;
    try {
      final id = await widget.lspService.ownNodeId();
      if (mounted) setState(() => _ownNodeId = id);
    } catch (e) {
      _addLog('Gagal membaca ID node: $e');
    }
  }

  Future<void> _refreshPeers() async {
    if (!widget.lspService.isRunning) return;
    try {
      final peers = await widget.lspService.listPeerDetails();
      if (mounted) setState(() => _peers = peers);
    } catch (_) {
      // Node bisa berhenti di tengah jalan; daftar terakhir
      // dibiarkan apa adanya.
    }
  }

  /// Nama yang diiklankan/dicari lewat Nearby: cukup pendek untuk
  /// daftar penemuan, tetap bisa dicocokkan ke ID node pemiliknya.
  String get _localName {
    final id = _ownNodeId;
    if (id == null || id.length < 8) return 'ELNUX';
    return 'ELNUX-${id.substring(0, 8)}';
  }

  /// Izin runtime untuk Nearby di Android 12+: pindai/iklankan/
  /// sambung Bluetooth + lokasi. Nearby di banyak perangkat juga
  /// menuntut layanan Lokasi (saklar sistem) menyala; itu tidak
  /// bisa dinyalakan dari aplikasi, jadi dicatat di log saja.
  Future<bool> _ensurePermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.nearbyWifiDevices,
    ].request();
    results.forEach((permission, status) {
      _addLog('Izin $permission: $status');
    });
    final coreGranted =
        (results[Permission.bluetoothScan]?.isGranted ?? false) &&
        (results[Permission.bluetoothConnect]?.isGranted ?? false);
    if (!coreGranted) {
      _addLog('Izin Bluetooth inti belum diberikan; hentikan uji.');
    }
    return coreGranted;
  }

  Future<void> _startHost() async {
    if (!await _ensurePermissions()) return;
    await _bridge.startHost(_localName);
  }

  Future<void> _startGuest() async {
    if (!await _ensurePermissions()) return;
    await _bridge.startDiscovery(_localName);
  }

  Future<void> _connectNode() async {
    final hex = _hostNodeIdController.text.trim();
    if (hex.length != 66) {
      _addLog('ID node host tidak valid (harus 66 karakter hex).');
      return;
    }
    setState(() => _connectingNode = true);
    try {
      await widget.lspService.connectToPeer(
        hex,
        '127.0.0.1',
        OfflineBridgeService.guestBridgePort,
      );
      _addLog('Perintah connect terkirim; menunggu handshake peer…');
    } catch (e) {
      _addLog('Connect node gagal: $e');
    } finally {
      if (mounted) setState(() => _connectingNode = false);
    }
  }

  String _phaseLabel(AppLocalizations l10n) {
    switch (_bridge.phase) {
      case OfflineBridgePhase.idle:
        return l10n.offlineStatusIdle;
      case OfflineBridgePhase.advertising:
        return l10n.offlineStatusAdvertising;
      case OfflineBridgePhase.discovering:
        return l10n.offlineStatusDiscovering;
      case OfflineBridgePhase.connecting:
        return l10n.offlineStatusConnecting;
      case OfflineBridgePhase.linked:
        return l10n.offlineStatusLinked;
      case OfflineBridgePhase.error:
        return '${l10n.offlineStatusError}: ${_bridge.lastError ?? ''}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bridge = _bridge;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.offlineSpike),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          _card(
            child: Text(
              l10n.offlineIntro,
              style: TextStyle(
                fontSize: 12.5,
                color: context.palette.muted,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.offlineOwnNodeId,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _ownNodeId ?? l10n.offlineNodeNotRunning,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                  ),
                ),
                if (_ownNodeId != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _ownNodeId!),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.offlineCopied)),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: Text(l10n.offlineCopy),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.offlineChooseRole,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _phaseLabel(l10n),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.muted,
                  ),
                ),
                const SizedBox(height: 12),
                if (bridge.phase == OfflineBridgePhase.idle ||
                    bridge.phase == OfflineBridgePhase.error) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _startHost,
                          child: Text(l10n.offlineRoleHost),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _startGuest,
                          child: Text(l10n.offlineRoleGuest),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton(
                      onPressed: () => bridge.stop(),
                      child: Text(l10n.offlineStop),
                    ),
                  ),
                ],
                if (bridge.role == OfflineBridgeRole.guest &&
                    bridge.phase == OfflineBridgePhase.discovering) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.offlineDiscoveredHosts,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (bridge.discovered.isEmpty)
                    Text('—', style: TextStyle(color: context.palette.muted)),
                  for (final host in bridge.discovered)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        host.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: TextButton(
                        onPressed: () => bridge.connectToHost(host, _localName),
                        child: Text(l10n.offlineConnect),
                      ),
                    ),
                ],
                if (bridge.role == OfflineBridgeRole.guest &&
                    bridge.isLinked) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _hostNodeIdController,
                    decoration: InputDecoration(
                      labelText: l10n.offlineHostNodeIdLabel,
                      hintText: l10n.offlineHostNodeIdHint,
                      border: const OutlineInputBorder(),
                    ),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _connectingNode ? null : _connectNode,
                      child: Text(l10n.offlineConnectNode),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.offlinePeersTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                if (_peers.isEmpty)
                  Text(
                    l10n.offlineNoPeers,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.palette.muted,
                    ),
                  ),
                for (final peer in _peers)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 9,
                          color: peer.isConnected
                              ? const Color(0xFF34D399)
                              : const Color(0xFF9CA3AF),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            peer.nodeId.hex,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          peer.isConnected
                              ? l10n.offlinePeerConnected
                              : l10n.offlinePeerDisconnected,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.offlineLogTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                if (_log.isEmpty)
                  Text('—', style: TextStyle(color: context.palette.muted)),
                for (final line in _log)
                  Text(
                    line,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.border),
      ),
      child: child,
    );
  }
}
