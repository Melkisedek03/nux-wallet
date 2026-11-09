import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../l10n/app_localizations.dart';
import '../locale_controller.dart';
import '../services/lsp_service.dart';
import '../services/offline_bridge.dart';
import '../services/offline_spike_utils.dart';
import '../theme.dart';
import 'scan_screen.dart';
import 'send_screen.dart';
import '../utils/coin_alert.dart';
import '../utils/format.dart';

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
/// Tahap 2 menambah: penyambungan node dengan coba-ulang otomatis
/// dan ingatan peer seberang, kartu Channel (alamat + saldo
/// on-chain dompet internal untuk provisioning, buka channel
/// langsung ke peer seberang dari peran mana pun, daftar channel
/// langsung beserta konfirmasinya), dan kartu Pembayaran Uji
/// (invoice polos + bayar) untuk membuktikan pembayaran Lightning
/// saat kedua HP offline penuh.
///
/// Layar ini eksperimental dan hanya berguna di testnet; ia tidak
/// mengubah alur dompet normal sama sekali.
class OfflineSpikeScreen extends StatefulWidget {
  final LspService lspService;

  /// Jembatan offline milik aplikasi (singleton global dari
  /// main.dart): layar ini hanya menumpang memakai dan melihatnya.
  final OfflineBridgeService bridge;

  const OfflineSpikeScreen({
    super.key,
    required this.lspService,
    required this.bridge,
  });

  @override
  State<OfflineSpikeScreen> createState() => _OfflineSpikeScreenState();
}

class _OfflineSpikeScreenState extends State<OfflineSpikeScreen> {
  static const String _rememberedPeerKey = 'offline_spike_peer_id';
  static const String _celebratedFundingKey =
      'offline_spike_celebrated_funding_txids';

  OfflineBridgeService get _bridge => widget.bridge;
  final _hostNodeIdController = TextEditingController();
  final _channelAmountController = TextEditingController();
  final _invoiceAmountController = TextEditingController();
  final _payInvoiceController = TextEditingController();
  final List<String> _log = [];
  String? _ownNodeId;
  List<PeerDetails> _peers = const [];
  List<ChannelDetails> _channels = const [];
  String? _rememberedPeerId;
  String? _onchainAddress;
  BigInt? _onchainSats;
  String? _createdInvoice;
  Timer? _peerTimer;
  final Set<String> _celebratedFundingTxids = {};
  bool _celebratedFundingLoaded = false;
  bool _connectingNode = false;
  bool _openingChannel = false;
  bool _creatingInvoice = false;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    // Jembatan milik aplikasi: pasang callback selama layar tampil
    // dan tampilkan riwayat kejadian selama layar tidak tampil.
    _bridge.onChanged = () {
      if (mounted) setState(() {});
    };
    _bridge.onLog = _addLog;
    _log.addAll(_bridge.logHistory);
    _loadOwnNodeId();
    _loadRememberedPeer();
    _loadCelebratedFunding();
    _loadOnchain();
    _refreshPeers();
    _peerTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshPeers();
      _refreshChannels();
    });
  }

  @override
  void dispose() {
    _peerTimer?.cancel();
    // Jembatan TIDAK dihentikan: ia milik aplikasi dan sesinya
    // berjalan terus lintas layar. Hanya callback layar ini yang
    // dilepas. Menghentikan sesi adalah tombol berhenti eksplisit.
    _bridge.onChanged = null;
    _bridge.onLog = null;
    _hostNodeIdController.dispose();
    _channelAmountController.dispose();
    _invoiceAmountController.dispose();
    _payInvoiceController.dispose();
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
      // Sisi host tidak pernah menempel ID tamu; pelajari ID peer
      // seberang dari daftar peer (satu-satunya peer tersambung
      // yang bukan LSP) lalu ingat untuk sesi berikutnya.
      final detected = bridgeCounterpartId(peers, AppConfig.lspNodeId);
      if (detected != null && detected != _rememberedPeerId) {
        await _rememberPeer(detected);
      }
    } catch (_) {
      // Node bisa berhenti di tengah jalan; daftar terakhir
      // dibiarkan apa adanya.
    }
  }

  Future<void> _loadRememberedPeer() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_rememberedPeerKey);
    if (saved == null || !mounted) return;
    // Serahkan juga ke jembatan: sambung-ulang peer otomatis saat
    // tautan pulih memakai ingatan ini.
    _bridge.rememberPeerNodeId(saved);
    setState(() => _rememberedPeerId = saved);
    if (_hostNodeIdController.text.trim().isEmpty) {
      _hostNodeIdController.text = saved;
    }
  }

  Future<void> _loadCelebratedFunding() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_celebratedFundingKey);
    if (saved != null) _celebratedFundingTxids.addAll(saved);
    _celebratedFundingLoaded = true;
  }

  /// Perayaan sekali per transaksi pendanaan channel langsung yang
  /// baru terlihat di rantai. Pemicunya visibilitas di rantai
  /// (konfirmasi pertama tercatat), BUKAN event siaran internal node —
  /// event itu pernah terpicu untuk siaran yang hilang (channel
  /// zombie), jadi perayaan berdasar event akan merayakan kebohongan.
  /// TXID yang sudah dirayakan disimpan permanen supaya membuka ulang
  /// layar tidak merayakan lagi.
  Future<void> _celebrateNewlyVisibleFunding() async {
    if (!_celebratedFundingLoaded) return;
    final fresh = uncelebratedVisibleFundingTxids(
      _channels,
      _celebratedFundingTxids,
    );
    if (fresh.isEmpty) return;
    _celebratedFundingTxids.addAll(fresh);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _celebratedFundingKey,
      _celebratedFundingTxids.toList(),
    );
    _addLog('Siaran pendanaan channel terkonfirmasi terlihat di rantai.');
    await CoinAlert.play();
  }

  Future<void> _rememberPeer(String nodeIdHex) async {
    if (mounted) setState(() => _rememberedPeerId = nodeIdHex);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rememberedPeerKey, nodeIdHex);
  }

  /// Alamat + saldo on-chain dompet internal node untuk kartu
  /// Channel: alamat diambil sekali per kunjungan layar (setiap
  /// panggilan newAddress menurunkan alamat baru), saldo dibaca
  /// ulang di _refreshChannels.
  Future<void> _loadOnchain() async {
    if (!widget.lspService.isRunning) return;
    try {
      final address = await widget.lspService.onchainAddress();
      final sats = await widget.lspService.spendableOnchainBalanceSats();
      if (mounted) {
        setState(() {
          _onchainAddress = address;
          _onchainSats = sats;
        });
      }
    } catch (e) {
      _addLog('Gagal membaca dompet on-chain internal: $e');
    }
  }

  Future<void> _refreshChannels() async {
    if (!widget.lspService.isRunning) return;
    try {
      final all = await widget.lspService.listChannels();
      final sats = await widget.lspService.spendableOnchainBalanceSats();
      if (mounted) {
        setState(() {
          _channels = directChannels(all, AppConfig.lspNodeId);
          _onchainSats = sats;
        });
        await _celebrateNewlyVisibleFunding();
      }
    } catch (_) {
      // Sama seperti daftar peer: diamkan nilai terakhir.
    }
  }

  /// Peer tujuan untuk buka channel: ID yang diketik/diingat lebih
  /// dulu, lalu peer jembatan yang terdeteksi dari daftar peer.
  String? get _targetPeerId {
    final entered = _hostNodeIdController.text.trim();
    if (entered.length == 66) return entered;
    return _rememberedPeerId ??
        bridgeCounterpartId(_peers, AppConfig.lspNodeId);
  }

  bool _peerConnected(String nodeIdHex) {
    final id = nodeIdHex.toLowerCase();
    return _peers.any((p) => p.nodeId.hex.toLowerCase() == id && p.isConnected);
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
      // Notifikasi menetap layanan latar depan jembatan (tahap
      // produksi B) perlu izin ini di Android 13+; tanpa izin pun
      // layanan tetap berjalan, hanya notifikasinya tidak tampil.
      Permission.notification,
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

  /// Mode gabung (PR A tuas produksi): tanpa peran, ID node
  /// sendiri wajib ada karena ia isi muatan HELLO.
  Future<void> _startCombined() async {
    if (!await _ensurePermissions()) return;
    final id = _ownNodeId;
    if (id == null) {
      _addLog('ID node sendiri belum terbaca; mode gabung dibatalkan.');
      return;
    }
    await _bridge.startCombined(localName: _localName, localNodeIdHex: id);
  }

  /// Pindai QR ID node host dari HP seberang (kartu ID node di
  /// layarnya menampilkan QR-nya) dan isi kolom ID tujuan.
  Future<void> _scanHostNodeId() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (result == null || !mounted) return;
    final hex = result.trim();
    if (hex.length != 66) {
      _addLog('Hasil pindai bukan ID node (harus 66 karakter hex).');
      return;
    }
    setState(() => _hostNodeIdController.text = hex);
    _addLog('ID node host terisi dari pindaian QR.');
  }

  /// Pindai QR invoice dari HP seberang dan isi kolom bayar, sama
  /// seperti layar Kirim produksi: hasil pindai dinormalisasi dengan
  /// [normalizeInvoice] (buang awalan "lightning:", samakan huruf).
  Future<void> _scanInvoiceToPay() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (result == null || !mounted) return;
    setState(() => _payInvoiceController.text = normalizeInvoice(result));
    _addLog('Invoice terisi dari pindaian QR.');
  }

  /// Sambungkan node ke peer host dengan coba-ulang: kegagalan
  /// tahap 1 yang paling sering adalah connect ditekan sebelum
  /// tautan jembatan benar-benar siap, jadi percobaan diulang
  /// sampai peer tampil tersambung (maks. 10 kali, jeda 2 detik).
  Future<void> _connectNode() async {
    final hex = _hostNodeIdController.text.trim();
    if (hex.length != 66) {
      _addLog('ID node host tidak valid (harus 66 karakter hex).');
      return;
    }
    // Daftarkan ke jembatan agar tautan yang pulih menyambungkan
    // ulang peer ini otomatis, tanpa menekan tombol lagi.
    _bridge.rememberPeerNodeId(hex);
    setState(() => _connectingNode = true);
    try {
      for (var attempt = 1; attempt <= 10; attempt++) {
        try {
          await widget.lspService.connectToPeer(
            hex,
            '127.0.0.1',
            OfflineBridgeService.guestBridgePort,
          );
        } catch (e) {
          _addLog('Percobaan connect $attempt gagal: $e');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        await _refreshPeers();
        if (_peerConnected(hex)) {
          _addLog('Peer Lightning tersambung.');
          await _rememberPeer(hex);
          return;
        }
        _addLog('Percobaan connect $attempt: peer belum tersambung…');
      }
      _addLog('Connect node gagal setelah 10 percobaan.');
    } finally {
      if (mounted) setState(() => _connectingNode = false);
    }
  }

  Future<void> _openChannel() async {
    if (widget.lspService.isOfflineMode) {
      _addLog(
        'Buka channel ditolak: sesi ini dimulai tanpa internet, node tidak '
        'punya akses ke rantai sehingga siaran pendanaan tidak akan sampai '
        'ke jaringan. Mulai ulang aplikasi dengan internet untuk membuka '
        'channel.',
      );
      return;
    }
    final target = _targetPeerId;
    if (target == null || !_peerConnected(target)) {
      _addLog('Peer seberang belum tersambung; buka channel ditunda.');
      return;
    }
    final msat = parseChannelAmountToMsat(_channelAmountController.text);
    if (msat == null || msat <= BigInt.zero) {
      _addLog('Jumlah channel tidak valid (nusan bulat, tanpa pecahan).');
      return;
    }
    final sats = msat ~/ BigInt.from(1000);
    final spendable = _onchainSats;
    if (spendable != null && sats > spendable) {
      _addLog(
        'Saldo on-chain internal tidak cukup: butuh ${formatNusan(msat)} nusan, tersedia ${formatNusan(spendable * BigInt.from(1000))} nusan.',
      );
      return;
    }
    setState(() => _openingChannel = true);
    try {
      await widget.lspService.openChannelToPeer(
        target,
        '127.0.0.1',
        OfflineBridgeService.guestBridgePort,
        sats,
      );
      _addLog(
        'Pembukaan channel ${formatNusan(msat)} nusan terkirim; menunggu konfirmasi on-chain…',
      );
      await _refreshChannels();
    } catch (e) {
      _addLog('Buka channel gagal: $e');
    } finally {
      if (mounted) setState(() => _openingChannel = false);
    }
  }

  Future<void> _createInvoice() async {
    final msat = parseNusanToMsat(_invoiceAmountController.text);
    if (msat == null || msat <= BigInt.zero) {
      _addLog('Nominal invoice tidak valid.');
      return;
    }
    setState(() => _creatingInvoice = true);
    try {
      final invoice = await widget.lspService.createRegularInvoice(
        amountMsat: msat,
        description: 'ELNUX offline test',
      );
      if (mounted) setState(() => _createdInvoice = invoice);
      _addLog('Invoice uji ${formatNusan(msat)} nusan dibuat.');
    } catch (e) {
      _addLog('Buat invoice gagal: $e');
    } finally {
      if (mounted) setState(() => _creatingInvoice = false);
    }
  }

  Future<void> _payInvoice() async {
    final text = _payInvoiceController.text.trim();
    if (text.isEmpty) {
      _addLog('Tempel invoice dulu sebelum membayar.');
      return;
    }
    setState(() => _paying = true);
    try {
      final id = await widget.lspService.payInvoice(text);
      _addLog('Pembayaran terkirim; menunggu hasil akhir…');
      final status = await widget.lspService.waitForPaymentOutcome(
        id,
        timeout: const Duration(seconds: 45),
      );
      if (status == PaymentStatus.succeeded) {
        _addLog('Pembayaran uji SUKSES.');
      } else {
        _addLog('Pembayaran uji belum berhasil (status: $status).');
      }
      await _refreshChannels();
    } catch (e) {
      _addLog('Bayar invoice gagal: $e');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  bool get _canOpenChannel {
    final target = _targetPeerId;
    return canOpenDirectChannel(
      peerConnected: target != null && _peerConnected(target),
      sessionOffline: widget.lspService.isOfflineMode,
    );
  }

  static String _shortId(String hex) {
    if (hex.length <= 20) return hex;
    return '${hex.substring(0, 10)}…${hex.substring(hex.length - 6)}';
  }

  String _channelStatus(AppLocalizations l10n, ChannelDetails ch) {
    if (!ch.isChannelReady) {
      final conf = ch.confirmations;
      final req = ch.confirmationsRequired;
      if (conf != null && req != null) {
        return '${l10n.offlineChannelPending} • ${l10n.offlineConfirmations} $conf/$req';
      }
      return l10n.offlineChannelPending;
    }
    return ch.isUsable
        ? l10n.offlineChannelReady
        : l10n.offlineChannelReadyPeerDown;
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
                  const SizedBox(height: 8),
                  // QR ID node sendiri: HP seberang memindainya untuk
                  // mengisi kolom ID tujuan tanpa salin-tempel. ID
                  // node memang wajib diketahui sebelum connect —
                  // handshake Noise Lightning mengautentikasi peer
                  // dari ID ini, jadi datanya tidak bisa dibuang,
                  // hanya cara memindahkannya yang dipermudah.
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: _ownNodeId!,
                        version: QrVersions.auto,
                        size: 180,
                        backgroundColor: Colors.white,
                      ),
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
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _startCombined,
                      child: Text(l10n.offlineRoleCombined),
                    ),
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
                if ((bridge.role == OfflineBridgeRole.guest ||
                        bridge.role == OfflineBridgeRole.combined) &&
                    bridge.phase == OfflineBridgePhase.discovering) ...[
                  const SizedBox(height: 8),
                  Text(
                    bridge.role == OfflineBridgeRole.combined
                        ? l10n.offlineDiscoveredDevices
                        : l10n.offlineDiscoveredHosts,
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
                        onPressed: () =>
                            bridge.role == OfflineBridgeRole.combined
                                ? bridge.connectCombined(host)
                                : bridge.connectToHost(host, _localName),
                        child: Text(l10n.offlineConnect),
                      ),
                    ),
                ],
                if (bridge.role == OfflineBridgeRole.combined &&
                    bridge.isLinked) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.offlineHelloPeer,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    bridge.peerNodeId ?? '—',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
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
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        tooltip: l10n.offlineScan,
                        onPressed: _scanHostNodeId,
                      ),
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
                  l10n.offlineChannelTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${l10n.offlineTargetPeer}: ${_targetPeerId == null ? l10n.offlineNoTargetPeer : _shortId(_targetPeerId!)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.muted,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.offlineOnchainAddress,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _onchainAddress ?? '—',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${l10n.offlineOnchainBalance}: ${_onchainSats == null ? '—' : '${formatNusan(_onchainSats! * BigInt.from(1000))} nusan'}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                if (widget.lspService.isOfflineMode) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.cloud_off,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.offlineOpenBlockedOfflineSession,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _channelAmountController,
                  decoration: InputDecoration(
                    labelText: l10n.offlineChannelAmount,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_openingChannel || !_canOpenChannel)
                        ? null
                        : _openChannel,
                    child: Text(l10n.offlineOpenChannel),
                  ),
                ),
                const SizedBox(height: 12),
                if (_channels.isEmpty)
                  Text(
                    l10n.offlineNoDirectChannels,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.palette.muted,
                    ),
                  ),
                for (final ch in _channels)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 9,
                              color: ch.isUsable
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _shortId(ch.counterpartyNodeId.hex),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _channelStatus(l10n, ch),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${l10n.offlineChannelValue} ${formatNusan(ch.channelValueSats * BigInt.from(1000))} • ${l10n.offlineOutbound} ${formatNusan(ch.outboundCapacityMsat)} • ${l10n.offlineInbound} ${formatNusan(ch.inboundCapacityMsat)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
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
                  l10n.offlinePayTestTitle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _invoiceAmountController,
                  decoration: InputDecoration(
                    labelText: l10n.offlineInvoiceAmount,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _creatingInvoice ? null : _createInvoice,
                    child: Text(l10n.offlineCreateInvoice),
                  ),
                ),
                if (_createdInvoice != null) ...[
                  const SizedBox(height: 10),
                  // QR invoice: HP seberang memindainya untuk mengisi
                  // kolom bayar tanpa salin-tempel, sama seperti layar
                  // Terima produksi. Teks mentah tetap ditampilkan di
                  // bawahnya sebagai cadangan.
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: _createdInvoice!,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    _createdInvoice!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _createdInvoice!),
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
                const SizedBox(height: 12),
                TextField(
                  controller: _payInvoiceController,
                  decoration: InputDecoration(
                    labelText: l10n.offlineInvoiceToPay,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      tooltip: l10n.offlineScan,
                      onPressed: _scanInvoiceToPay,
                    ),
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
                    onPressed: _paying ? null : _payInvoice,
                    child: Text(l10n.offlinePayNow),
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
