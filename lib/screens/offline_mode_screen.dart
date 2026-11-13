import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../locale_controller.dart';
import '../services/lsp_service.dart';
import '../services/offline_bridge.dart';
import '../services/offline_mode_utils.dart';
import '../theme.dart';

/// Layar Mode Offline produksi — tuas di Profil yang menyalakan
/// sesi jembatan mode gabung (mengiklankan + menemukan serentak)
/// tanpa pilihan peran dan tanpa tempel ID node: kedua HP menekan
/// saklar yang sama, saling menemukan, lalu pengguna mengetuk
/// Sambungkan pada perangkat yang kodenya cocok.
///
/// Berbeda dari layar Uji Offline (diagnostik testnet, tetap ada
/// apa adanya): permukaan ini tidak mengenal jargon — yang tampil
/// hanya kode perangkat, nama ELNUX-XXXX, dan keadaan jalur
/// siap/belum. Pembukaan jalur BUKAN di sini (PR C); layar ini
/// hanya menampilkan keadaan jalur dari data channel yang ada.
class OfflineModeScreen extends StatefulWidget {
  final LspService lspService;
  final OfflineBridgeService bridge;

  const OfflineModeScreen({
    super.key,
    required this.lspService,
    required this.bridge,
  });

  @override
  State<OfflineModeScreen> createState() => _OfflineModeScreenState();
}

class _OfflineModeScreenState extends State<OfflineModeScreen> {
  String? _ownNodeId;
  bool _loadFailed = false;
  bool _busy = false;
  bool _pathReady = false;
  bool _wasLinked = false;
  Timer? _pathTimer;

  OfflineBridgeService get _bridge => widget.bridge;

  @override
  void initState() {
    super.initState();
    _bridge.addListener(_onBridgeChanged);
    _wasLinked = _bridge.isLinked;
    _loadOwnNodeId();
    _syncPathTimer();
    _refreshPath();
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
    // Tautan baru terbentuk: muat keadaan jalur segera, jangan
    // tunggu putaran timer berikutnya.
    if (_bridge.isLinked && !_wasLinked) _refreshPath();
    _wasLinked = _bridge.isLinked;
  }

  /// Timer 5 detik hanya selama tertaut: jalur bisa menjadi siap
  /// (pendanaan terkonfirmasi) tanpa kejadian jembatan apa pun,
  /// dan layar ini sedang ditatap pengguna — 5 detik cukup hidup
  /// tanpa membebani node (layar uji memakai 3 detik untuk
  /// daftar peer + channel).
  void _syncPathTimer() {
    if (_bridge.isLinked && _pathTimer == null) {
      _pathTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refreshPath(),
      );
    } else if (!_bridge.isLinked) {
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

  /// Muat ulang keadaan jalur dari daftar channel node: siap bila
  /// ada channel usable dengan peer yang dikenal dari HELLO.
  /// Kegagalan baca membiarkan nilai terakhir tampil.
  Future<void> _refreshPath() async {
    final peerId = _bridge.peerNodeId;
    if (!_bridge.isLinked || peerId == null) {
      if (_pathReady && mounted) setState(() => _pathReady = false);
      return;
    }
    try {
      final channels = await widget.lspService.listChannels();
      if (!mounted) return;
      final ready = hasReadyPath(channels, peerId);
      if (ready != _pathReady) setState(() => _pathReady = ready);
    } catch (_) {
      // Nilai terakhir tetap tampil.
    }
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

  /// Kartu keadaan jalur — TAMPILAN SAJA (PR B): siap bila ada
  /// channel usable dengan peer tertaut, belum bila tidak ada.
  /// Tidak ada tombol di sini; pembukaan jalur adalah PR C.
  Widget _pathCard(BuildContext context) {
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
          Icon(
            _pathReady
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            color: _pathReady ? const Color(0xFF34D399) : context.palette.muted,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _pathReady ? l10n.offlineModeReady : l10n.offlineModeNoPath,
              style: TextStyle(fontSize: 14, color: context.palette.label),
            ),
          ),
        ],
      ),
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
      if (_pathReady && mounted) setState(() => _pathReady = false);
      return;
    }
    if (!force && linked == _lastLinked && peerId == _lastPeerId) return;
    _lastLinked = linked;
    _lastPeerId = peerId;
    try {
      final channels = await widget.lspService.listChannels();
      if (!mounted) return;
      final ready = hasReadyPath(channels, peerId);
      if (ready != _pathReady) setState(() => _pathReady = ready);
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
