import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Jeda sambung-ulang jembatan untuk percobaan ke-[attempt]
/// (0-based): 2, 4, 8, 16 detik, lalu mentok 30 detik. Murni
/// supaya bisa diuji satuan.
Duration offlineResumeBackoff(int attempt) {
  final seconds = 2 << attempt;
  return Duration(seconds: seconds > 30 ? 30 : seconds);
}

/// Awalan ajaib muatan kendali HELLO mode gabung: begitu tautan
/// Nearby terbentuk, kedua sisi saling mengirim muatan ini —
/// di luar aliran berbingkai node — untuk bertukar ID node
/// penuh TANPA tempel manual. Versi melekat di awalan supaya
/// formatnya bisa berevolusi tanpa menebak-nebak.
const String helloMagic = 'ELNUX-HELLO/1:';

/// Bentuk muatan HELLO untuk [nodeIdHex] (66 karakter hex).
Uint8List encodeHelloPayload(String nodeIdHex) =>
    Uint8List.fromList(utf8.encode('$helloMagic${nodeIdHex.toLowerCase()}'));

/// Baca muatan HELLO; kembalikan ID node pengirim, atau null
/// bila muatan ini BUKAN HELLO yang sah (awalan salah, panjang
/// salah, atau isi bukan 66 hex). Ketat dengan sengaja: byte
/// pertama protokol Lightning yang menyerupai awalan ini secara
/// kriptografis tidak masuk akal, dan pemeriksaan panjang + hex
/// membuatnya mustahil lolos sebagai data.
String? parseHelloPayload(Uint8List bytes) {
  if (bytes.length != helloMagic.length + 66) return null;
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return null;
  }
  if (!text.startsWith(helloMagic)) return null;
  final id = text.substring(helloMagic.length);
  if (!RegExp(r'^[0-9a-fA-F]{66}$').hasMatch(id)) return null;
  return id.toLowerCase();
}

/// Inisiator tautan yang dipertahankan bila dua tautan ke
/// perangkat yang sama terbentuk nyaris bersamaan (kedua
/// pengguna mengetuk dalam saat yang berdekatan): nama endpoint
/// inisiator yang lebih kecil menang. Nama endpoint berbentuk
/// ELNUX-<8 hex pertama ID node>, jadi perbandingan leksikal ini
/// deterministik dan kedua sisi menghitung pemenang yang sama
/// dari data yang sama — tautan satunya dilepas.
String survivingInitiator(String a, String b) => a.compareTo(b) <= 0 ? a : b;

/// Pembingkaian aliran byte jembatan offline: potongan byte dari
/// socket TCP dipotong menjadi bingkai berukuran maks
/// [maxPayloadPerFrame] dengan awalan panjang 4 byte big-endian,
/// karena Nearby Connections hanya mengangkut payload byte yang
/// terpisah-pisah, bukan aliran. Kelas ini murni (tanpa IO) supaya
/// bisa diuji satuan.
class LengthPrefixFramer {
  static const int headerSize = 4;
  static const int maxPayloadPerFrame = 8192;

  /// Potong [data] menjadi daftar bingkai siap kirim. Data kosong
  /// menghasilkan daftar kosong.
  static List<Uint8List> encode(Uint8List data) {
    final frames = <Uint8List>[];
    var offset = 0;
    while (offset < data.length) {
      final end = min(offset + maxPayloadPerFrame, data.length);
      final payloadLength = end - offset;
      final frame = Uint8List(headerSize + payloadLength);
      ByteData.view(frame.buffer).setUint32(0, payloadLength, Endian.big);
      frame.setRange(headerSize, frame.length, data, offset);
      frames.add(frame);
      offset = end;
    }
    return frames;
  }
}

/// Pasangan [LengthPrefixFramer] di sisi penerima: menampung
/// potongan payload yang datang dalam urutan apa pun ukurannya,
/// lalu mengeluarkan muatan utuh setiap kali satu bingkai lengkap.
/// Urutan byte dijamin oleh Nearby Connections, jadi tidak ada
/// nomor urut di bingkai.
class LengthPrefixDeframer {
  /// Batas kewajaran satu bingkai; pesan protokol Lightning jauh
  /// di bawah ini. Melebihi batas berarti aliran rusak.
  static const int maxFramePayload = 1 << 22;

  Uint8List _pending = Uint8List(0);

  /// Umpan satu payload masuk; kembalikan daftar muatan bingkai
  /// yang menjadi lengkap karenanya (bisa kosong).
  List<Uint8List> feed(Uint8List chunk) {
    if (chunk.isNotEmpty) {
      final merged = Uint8List(_pending.length + chunk.length);
      merged.setRange(0, _pending.length, _pending);
      merged.setRange(_pending.length, merged.length, chunk);
      _pending = merged;
    }
    final out = <Uint8List>[];
    while (_pending.length >= LengthPrefixFramer.headerSize) {
      final length = ByteData.view(
        _pending.buffer,
        _pending.offsetInBytes,
      ).getUint32(0, Endian.big);
      if (length > maxFramePayload) {
        reset();
        throw const FormatException('Panjang bingkai jembatan tidak wajar');
      }
      if (_pending.length < LengthPrefixFramer.headerSize + length) break;
      out.add(
        _pending.sublist(
          LengthPrefixFramer.headerSize,
          LengthPrefixFramer.headerSize + length,
        ),
      );
      _pending = _pending.sublist(LengthPrefixFramer.headerSize + length);
    }
    return out;
  }

  void reset() => _pending = Uint8List(0);
}

/// Host Nearby yang ditemukan tamu saat pencarian.
class DiscoveredHost {
  final String endpointId;
  final String name;
  const DiscoveredHost(this.endpointId, this.name);
}

enum OfflineBridgeRole { none, host, guest, combined }

enum OfflineBridgePhase {
  idle,
  advertising,
  discovering,
  connecting,
  linked,
  error,
}

/// Jembatan offline tahap spike: meneruskan koneksi peer Lightning
/// (TCP di localhost) lewat Google Nearby Connections
/// (Bluetooth/Wi-Fi Direct) antar dua HP, tanpa internet.
///
/// Topologi:
/// - Node di HP host mendengarkan di 127.0.0.1:[nodeListenPort]
///   (diatur lewat Config.listeningAddresses saat node dibangun,
///   khusus testnet — lihat LspService.init). Saat tautan Nearby
///   terbentuk, jembatan host menyambung ke port itu.
/// - Node di HP tamu memanggil connect() ke 127.0.0.1:
///   [guestBridgePort]; jembatan tamu mendengarkan di port itu dan
///   meneruskan byte-nya ke host lewat Nearby.
///
/// Protokol Lightning sendiri tidak berubah dan tetap terenkripsi
/// ujung-ke-ujung (Noise BOLT #8); jembatan hanya mengangkut
/// ciphertext yang sudah dibingkai [LengthPrefixFramer].
class OfflineBridgeService {
  OfflineBridgeService({this.onChanged, this.onLog});

  /// Dipanggil setiap kali keadaan berubah (untuk setState UI).
  /// Bisa diganti-ganti: layanan ini sekarang milik aplikasi
  /// (singleton global), layar hanya menumpang memasang callback
  /// selama ia tampil dan melepasnya saat ditutup.
  void Function()? onChanged;

  /// Pendengar tambahan perubahan keadaan — [onChanged] hanya
  /// menampung satu callback, padahal baris Mode Offline di
  /// Profil dan layar Mode Offline harus hidup BERSAMAAN (baris
  /// tetap terpasang di balik layar yang terbuka di atasnya).
  /// Keduanya berlangganan di sini; [onChanged] tetap bekerja
  /// seperti sebelumnya untuk layar uji.
  final List<void Function()> _listeners = [];

  void addListener(void Function() listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// Catatan kejadian terbaca manusia untuk layar uji.
  void Function(String message)? onLog;

  /// Penyambung peer Lightning untuk peran tamu, dipasang oleh
  /// pemilik aplikasi (main.dart) karena hanya ia yang memegang
  /// LspService: menyambungkan node ke ID [nodeIdHex] lewat
  /// listener lokal jembatan. Dipakai tombol sambung manual dan
  /// sambung-ulang otomatis setiap kali tautan terbentuk kembali.
  Future<void> Function(String nodeIdHex)? peerConnector;

  /// Riwayat catatan kejadian (terbaru di akhir, maks 200 baris)
  /// supaya layar yang baru dibuka bisa menampilkan kejadian
  /// selama ia tidak tampil — jembatan tidak lagi mati bersamanya.
  final List<String> logHistory = [];

  static const String serviceId = 'org.nusacoin.elnux.offline';

  /// Port listener node Lightning di localhost (peran host).
  static const int nodeListenPort = 19735;

  /// Port listener jembatan di localhost HP tamu; node tamu
  /// connect() ke sini.
  static const int guestBridgePort = 19736;

  final Nearby _nearby = Nearby();

  OfflineBridgeRole role = OfflineBridgeRole.none;
  OfflineBridgePhase phase = OfflineBridgePhase.idle;
  String? lastError;
  String? linkedEndpointId;
  String? linkedEndpointName;
  final List<DiscoveredHost> discovered = [];

  /// Niat sesi: true sejak peran dimulai sampai pengguna secara
  /// eksplisit mengakhiri sesi (stop). Selama niat hidup, tautan
  /// yang putus disambung ulang otomatis dan niat disimpan supaya
  /// sesi bisa dilanjutkan setelah aplikasi dimulai ulang.
  bool sessionActive = false;
  String? _localName;
  String? _peerNodeId;
  String? _rememberedHostName;
  Timer? _resumeTimer;
  int _resumeAttempt = 0;

  // --- Keadaan khusus mode gabung (combined) ---
  /// ID node lokal penuh, untuk muatan HELLO dan pemulihan sesi.
  String? _localNodeIdHex;

  /// ID node peer yang dipelajari dari HELLO tautan ini.
  String? _helloPeerNodeId;

  /// Endpoint yang DIMULAI sisi ini (requestConnection) dan nama
  /// inisiator tiap endpoint yang dikenal — bahan aturan
  /// dedupe tautan ganda (lihat [survivingInitiator]).
  final Set<String> _outboundEndpoints = {};
  final Map<String, String> _initiatorByEndpoint = {};

  /// Endpoint yang kalah dedupe: pemutusannya diabaikan, bukan
  /// dianggap sesi putus.
  final Set<String> _droppedEndpoints = {};

  /// Tautan gabung yang sudah menetap (pemenang dedupe).
  String? _survivorEndpointId;

  /// Sisi ini penelpon Lightning pada tautan menetap (yang
  /// memulai tautan Nearby yang menang); lawannya pendengar.
  bool _combinedDialer = false;

  /// Tugas tautan (sambung socket node / telepon peer) sudah
  /// dijalankan untuk tautan menetap saat ini.
  bool _dutiesDone = false;

  /// Sambung otomatis ke peer yang diingat DIPERBOLEHKAN:
  /// hanya pada jalur pulih (tautan pernah terbentuk lalu putus,
  /// atau sesi dipulihkan) — mulai segar selalu lewat ketukan
  /// pengguna pada daftar kandidat.
  bool _resumeArmed = false;

  /// ID node peer yang saat ini dikenal sesi (diingat manual pada
  /// mode lama, dipelajari dari HELLO pada mode gabung).
  String? get peerNodeId => _peerNodeId;

  static const _kActive = 'offline_bridge_session_active';
  static const _kRole = 'offline_bridge_role';
  static const _kLocalName = 'offline_bridge_local_name';
  static const _kPeerNodeId = 'offline_bridge_peer_node_id';
  static const _kHostName = 'offline_bridge_host_name';
  static const _kLocalNodeId = 'offline_bridge_local_node_id';

  Socket? _nodeSocket;
  StreamSubscription<Uint8List>? _nodeSocketSub;
  ServerSocket? _guestServer;
  StreamSubscription<Socket>? _guestServerSub;
  final LengthPrefixDeframer _deframer = LengthPrefixDeframer();

  bool get isLinked =>
      phase == OfflineBridgePhase.linked && linkedEndpointId != null;

  void _notify() {
    onChanged?.call();
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  void _log(String message) {
    logHistory.add(message);
    if (logHistory.length > 200) {
      logHistory.removeRange(0, logHistory.length - 200);
    }
    onLog?.call(message);
  }

  /// Simpan niat sesi saat ini (kebal mulai-ulang aplikasi).
  Future<void> _persistIntent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kActive, sessionActive);
    await prefs.setString(_kRole, role.name);
    if (_localName != null) await prefs.setString(_kLocalName, _localName!);
    if (_peerNodeId != null) {
      await prefs.setString(_kPeerNodeId, _peerNodeId!);
    }
    if (_rememberedHostName != null) {
      await prefs.setString(_kHostName, _rememberedHostName!);
    }
    if (_localNodeIdHex != null) {
      await prefs.setString(_kLocalNodeId, _localNodeIdHex!);
    }
  }

  Future<void> _clearPersistedIntent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kActive);
    await prefs.remove(_kRole);
    await prefs.remove(_kLocalName);
    await prefs.remove(_kPeerNodeId);
    await prefs.remove(_kHostName);
    await prefs.remove(_kLocalNodeId);
  }

  /// Lanjutkan niat sesi dari penyimpanan setelah aplikasi dimulai
  /// ulang: peran host kembali mengiklankan diri, peran tamu
  /// kembali mencari (dan menyambung otomatis ke host yang
  /// diingat). Mengembalikan false bila tidak ada sesi tersimpan.
  /// Upaya terbaik: kegagalan (mis. izin belum diberikan) tercatat
  /// di log dan fase, bukan melempar.
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kActive) != true) return false;
    final savedRole = prefs.getString(_kRole);
    final savedName = prefs.getString(_kLocalName);
    if (savedRole == null || savedName == null) return false;
    _peerNodeId = prefs.getString(_kPeerNodeId);
    _rememberedHostName = prefs.getString(_kHostName);
    _log('Melanjutkan sesi offline tersimpan…');
    if (savedRole == OfflineBridgeRole.host.name) {
      await startHost(savedName);
    } else if (savedRole == OfflineBridgeRole.guest.name) {
      await startDiscovery(savedName);
    } else if (savedRole == OfflineBridgeRole.combined.name) {
      final savedLocalId = prefs.getString(_kLocalNodeId);
      if (savedLocalId == null) return false;
      // Sesi gabung yang dipulihkan adalah jalur pulih: peer yang
      // diingat boleh disambung otomatis saat ditemukan kembali.
      await startCombined(
        localName: savedName,
        localNodeIdHex: savedLocalId,
        resumeArmed: true,
      );
    } else {
      return false;
    }
    return true;
  }

  /// Ingat ID node peer (tamu: ID node host) untuk sambung-ulang
  /// peer otomatis setiap kali tautan terbentuk kembali.
  void rememberPeerNodeId(String nodeIdHex) {
    _peerNodeId = nodeIdHex;
    _persistIntent();
  }

  /// Sambungkan node tamu ke peer yang diingat lewat
  /// [peerConnector]; dipakai tombol manual di layar dan jalur
  /// otomatis saat tautan pulih. Kesalahan diteruskan ke pemanggil
  /// manual; jalur otomatis menangkap dan mencatatnya sendiri.
  Future<void> connectGuestNode(String nodeIdHex) async {
    rememberPeerNodeId(nodeIdHex);
    final connector = peerConnector;
    if (connector == null) {
      throw StateError('Penyambung peer belum terpasang');
    }
    await connector(nodeIdHex);
  }

  /// Mulai peran host: iklankan diri dan terima satu tamu.
  /// Menghidupkan niat sesi: tautan yang putus disambung ulang
  /// otomatis dan sesi bisa dilanjutkan setelah mulai ulang.
  Future<void> startHost(String localName) async {
    await _teardown();
    sessionActive = true;
    _localName = localName;
    _resumeAttempt = 0;
    role = OfflineBridgeRole.host;
    await _persistIntent();
    await _advertise();
    await _sinkronLayananLatar();
  }

  Future<void> _advertise() async {
    phase = OfflineBridgePhase.advertising;
    lastError = null;
    _notify();
    _log('Mengiklankan sebagai host ($_localName)…');
    final ok = await _nearby.startAdvertising(
      _localName ?? '',
      Strategy.P2P_POINT_TO_POINT,
      serviceId: serviceId,
      onConnectionInitiated: (endpointId, info) {
        linkedEndpointName = info.endpointName;
        _log('Permintaan dari ${info.endpointName}; menerima…');
        _nearby.acceptConnection(
          endpointId,
          onPayLoadRecieved: _onPayloadReceived,
        );
      },
      onConnectionResult: (endpointId, status) {
        if (status == Status.CONNECTED) {
          _onLinked(endpointId);
        } else {
          lastError = 'Koneksi host gagal: $status';
          phase = OfflineBridgePhase.error;
          _log(lastError!);
          _notify();
        }
      },
      onDisconnected: (endpointId) => _onUnlinked(endpointId),
    );
    if (!ok) {
      phase = OfflineBridgePhase.error;
      lastError = 'startAdvertising gagal';
      _log(lastError!);
      _notify();
      _scheduleResume();
    }
  }

  /// Mulai peran tamu: cari host yang sedang mengiklankan diri.
  /// Menghidupkan niat sesi, sama seperti [startHost].
  Future<void> startDiscovery(String localName) async {
    await _teardown();
    sessionActive = true;
    _localName = localName;
    _resumeAttempt = 0;
    role = OfflineBridgeRole.guest;
    await _persistIntent();
    await _discover();
    await _sinkronLayananLatar();
  }

  Future<void> _discover() async {
    phase = OfflineBridgePhase.discovering;
    lastError = null;
    discovered.clear();
    _notify();
    _log('Mencari host di sekitar…');
    final ok = await _nearby.startDiscovery(
      _localName ?? '',
      Strategy.P2P_POINT_TO_POINT,
      serviceId: serviceId,
      onEndpointFound: (endpointId, endpointName, _) {
        discovered.removeWhere((h) => h.endpointId == endpointId);
        final host = DiscoveredHost(endpointId, endpointName);
        discovered.add(host);
        _log('Host ditemukan: $endpointName');
        _notify();
        // Sambung otomatis ke host yang diingat dari sesi ini:
        // inilah jalur pulih utama peran tamu setelah putus.
        if (sessionActive &&
            phase == OfflineBridgePhase.discovering &&
            _rememberedHostName != null &&
            endpointName == _rememberedHostName) {
          _log('Host sesi ini; menyambung otomatis…');
          connectToHost(host, _localName ?? '').catchError((Object e) {
            _log('Sambung otomatis gagal: $e');
          });
        }
      },
      onEndpointLost: (endpointId) {
        discovered.removeWhere((h) => h.endpointId == endpointId);
        _notify();
      },
    );
    if (!ok) {
      phase = OfflineBridgePhase.error;
      lastError = 'startDiscovery gagal';
      _log(lastError!);
      _notify();
      _scheduleResume();
    }
  }

  /// Tamu menyambung ke [host] terpilih. Listener TCP lokal
  /// diikat lebih dulu supaya node tamu bisa langsung connect()
  /// begitu tautan Nearby terbentuk.
  Future<void> connectToHost(DiscoveredHost host, String localName) async {
    if (role != OfflineBridgeRole.guest) return;
    // Ingat host ini: penemuan ulang nama yang sama di sesi ini
    // disambung otomatis (lihat onEndpointFound).
    _rememberedHostName = host.name;
    _persistIntent();
    await _closeGuestServer();
    _guestServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      guestBridgePort,
    );
    _guestServerSub = _guestServer!.listen(
      _onGuestTcpAccepted,
      onError: (Object e) => _log('Listener jembatan tamu error: $e'),
    );
    linkedEndpointName = host.name;
    phase = OfflineBridgePhase.connecting;
    _notify();
    _log('Menyambung ke ${host.name}…');
    final ok = await _nearby.requestConnection(
      localName,
      host.endpointId,
      onConnectionInitiated: (endpointId, info) {
        _nearby.acceptConnection(
          endpointId,
          onPayLoadRecieved: _onPayloadReceived,
        );
      },
      onConnectionResult: (endpointId, status) {
        if (status == Status.CONNECTED) {
          _onLinked(endpointId);
        } else {
          lastError = 'Koneksi ke host gagal: $status';
          phase = OfflineBridgePhase.discovering;
          _log(lastError!);
          _notify();
        }
      },
      onDisconnected: (endpointId) => _onUnlinked(endpointId),
    );
    if (!ok) {
      phase = OfflineBridgePhase.discovering;
      lastError = 'requestConnection gagal';
      _log(lastError!);
      _notify();
    }
  }

  /// Mulai mode GABUNG: mengiklankan diri DAN mencari perangkat
  /// lain pada saat yang sama (strategi P2P_CLUSTER), tanpa
  /// peran induk/tamu yang dipilih manusia. Kedua sisi menekan
  /// tombol yang sama; siapa menelepon Lightning diputuskan dari
  /// siapa yang memulai tautan yang menang (lihat
  /// [_settleSurvivor]). Menghidupkan niat sesi seperti peran
  /// lain. [resumeArmed] hanya untuk pemulihan sesi: penemuan
  /// peer yang diingat langsung disambung; mulai segar selalu
  /// lewat ketukan pengguna pada daftar kandidat.
  Future<void> startCombined({
    required String localName,
    required String localNodeIdHex,
    bool resumeArmed = false,
  }) async {
    await _teardown();
    sessionActive = true;
    _localName = localName;
    _localNodeIdHex = localNodeIdHex;
    _resumeAttempt = 0;
    _resumeArmed = resumeArmed;
    role = OfflineBridgeRole.combined;
    await _persistIntent();
    await _advertiseAndDiscover();
    await _sinkronLayananLatar();
  }

  Future<void> _advertiseAndDiscover() async {
    phase = OfflineBridgePhase.discovering;
    lastError = null;
    discovered.clear();
    _notify();
    _log('Mode gabung: mengiklankan + mencari perangkat ($_localName)…');
    final okIklan = await _nearby.startAdvertising(
      _localName ?? '',
      Strategy.P2P_CLUSTER,
      serviceId: serviceId,
      onConnectionInitiated: (endpointId, info) {
        // Tautan masuk: inisiatornya adalah perangkat seberang.
        _initiatorByEndpoint[endpointId] = info.endpointName;
        linkedEndpointName = info.endpointName;
        _log('Permintaan gabung dari ${info.endpointName}; menerima…');
        _nearby.acceptConnection(
          endpointId,
          onPayLoadRecieved: _onPayloadReceived,
        );
      },
      onConnectionResult: (endpointId, status) {
        if (status == Status.CONNECTED) {
          _onLinked(endpointId);
        } else {
          _log('Tautan masuk gabung gagal: $status');
          _notify();
        }
      },
      onDisconnected: (endpointId) => _onUnlinked(endpointId),
    );
    final okCari = await _nearby.startDiscovery(
      _localName ?? '',
      Strategy.P2P_CLUSTER,
      serviceId: serviceId,
      onEndpointFound: (endpointId, endpointName, _) {
        discovered.removeWhere((h) => h.endpointId == endpointId);
        final host = DiscoveredHost(endpointId, endpointName);
        discovered.add(host);
        _log('Perangkat ditemukan: $endpointName');
        _notify();
        // Sambung otomatis HANYA pada jalur pulih (sesi pernah
        // tertaut / dipulihkan) ke peer yang diingat — mulai
        // segar tidak pernah menyambung tanpa ketukan pengguna.
        if (sessionActive &&
            _resumeArmed &&
            _survivorEndpointId == null &&
            _rememberedHostName != null &&
            endpointName == _rememberedHostName) {
          _log('Peer sesi ini ditemukan lagi; menyambung otomatis…');
          connectCombined(host).catchError((Object e) {
            _log('Sambung otomatis gabung gagal: $e');
          });
        }
      },
      onEndpointLost: (endpointId) {
        discovered.removeWhere((h) => h.endpointId == endpointId);
        _notify();
      },
    );
    if (!okIklan || !okCari) {
      phase = OfflineBridgePhase.error;
      lastError =
          'Mode gabung gagal dimulai (iklan: $okIklan, cari: $okCari)';
      _log(lastError!);
      _notify();
      _scheduleResume();
    }
  }

  /// Pengguna mengetuk satu kandidat: sisi ini menjadi pemulai
  /// tautan. Listener TCP lokal diikat lebih dulu (pola
  /// [connectToHost]) supaya node sisi ini bisa langsung
  /// menelepon begitu tautan menetap dan HELLO tiba; bila
  /// dedupe menjadikan sisi ini pendengar, listener itu ditutup
  /// lagi di [_teardownLinkDuties].
  Future<void> connectCombined(DiscoveredHost host) async {
    if (role != OfflineBridgeRole.combined) return;
    if (_survivorEndpointId != null) return;
    _rememberedHostName = host.name;
    _persistIntent();
    await _ensureGuestServer();
    linkedEndpointName = host.name;
    phase = OfflineBridgePhase.connecting;
    _notify();
    _log('Menyambung gabung ke ${host.name}…');
    _outboundEndpoints.add(host.endpointId);
    _initiatorByEndpoint[host.endpointId] = _localName ?? '';
    final ok = await _nearby.requestConnection(
      _localName ?? '',
      host.endpointId,
      onConnectionInitiated: (endpointId, info) {
        _nearby.acceptConnection(
          endpointId,
          onPayLoadRecieved: _onPayloadReceived,
        );
      },
      onConnectionResult: (endpointId, status) {
        if (status == Status.CONNECTED) {
          _onLinked(endpointId);
        } else {
          _outboundEndpoints.remove(endpointId);
          lastError = 'Sambung gabung ke ${host.name} gagal: $status';
          phase = OfflineBridgePhase.discovering;
          _log(lastError!);
          _notify();
        }
      },
      onDisconnected: (endpointId) => _onUnlinked(endpointId),
    );
    if (!ok) {
      _outboundEndpoints.remove(host.endpointId);
      phase = OfflineBridgePhase.discovering;
      lastError = 'requestConnection gabung gagal';
      _log(lastError!);
      _notify();
    }
  }

  /// Tautan gabung terbentuk: kirim HELLO, lalu menangkan
  /// dedupe. Bila dua tautan ke perangkat yang sama hidup
  /// bersamaan, yang dipertahankan adalah tautan yang
  /// inisiatornya menang menurut [survivingInitiator]; yang
  /// kalah diputus dan pemutusannya ditandai supaya tidak
  /// dibaca sebagai sesi putus.
  void _onLinkedCombined(String endpointId) {
    _sendHello(endpointId);
    if (_survivorEndpointId == null) {
      _settleSurvivor(endpointId);
      return;
    }
    if (_survivorEndpointId == endpointId) return;
    final existingInitiator = _initiatorByEndpoint[_survivorEndpointId!] ?? '';
    final newInitiator = _initiatorByEndpoint[endpointId] ?? '';
    if (existingInitiator == newInitiator ||
        survivingInitiator(existingInitiator, newInitiator) ==
            existingInitiator) {
      _log('Tautan ganda ke peer yang sama; yang baru dilepas.');
      _droppedEndpoints.add(endpointId);
      _nearby.disconnectFromEndpoint(endpointId);
      return;
    }
    _log('Tautan ganda: tautan lama dilepas, yang baru menang.');
    _droppedEndpoints.add(_survivorEndpointId!);
    _nearby.disconnectFromEndpoint(_survivorEndpointId!);
    _teardownLinkDuties();
    _settleSurvivor(endpointId);
  }

  /// Tetapkan tautan yang menang: penelpon Lightning adalah
  /// sisi yang memulai tautan ini; lawannya pendengar. Tugas
  /// tautan dijalankan lewat [_maybeRunDuties] (penelpon masih
  /// menunggu HELLO peer sebelum bisa menelepon).
  void _settleSurvivor(String endpointId) {
    _survivorEndpointId = endpointId;
    linkedEndpointId = endpointId;
    phase = OfflineBridgePhase.linked;
    _resumeAttempt = 0;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _combinedDialer = _outboundEndpoints.contains(endpointId);
    _log(
      'Jembatan gabung terhubung ke $linkedEndpointName '
      '(${_combinedDialer ? 'sisi ini menelepon' : 'sisi ini mendengarkan'})',
    );
    _notify();
    _maybeRunDuties();
  }

  /// Ikat listener telepon lokal bila belum terikat (pola
  /// [connectToHost]): node penelpon connect() ke port ini.
  /// Idempoten — dedupe yang membalik peran menutup listener
  /// lewat [_teardownLinkDuties], dan tugas penelpon mengikat
  /// ulang lewat sini sebelum menelepon.
  Future<void> _ensureGuestServer() async {
    if (_guestServer != null) return;
    await _closeGuestServer();
    _guestServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      guestBridgePort,
    );
    _guestServerSub = _guestServer!.listen(
      _onGuestTcpAccepted,
      onError: (Object e) => _log('Listener jembatan gabung error: $e'),
    );
  }

  /// Jalankan tugas tautan menetap sekali saja: pendengar
  /// menyambungkan jembatan ke listener node lokalnya (pola
  /// host lama); penelpon menelepon peer lewat [peerConnector]
  /// begitu ID node peer diketahui dari HELLO.
  void _maybeRunDuties() {
    if (role != OfflineBridgeRole.combined) return;
    if (_survivorEndpointId == null || _dutiesDone) return;
    if (_combinedDialer) {
      final peerId = _helloPeerNodeId;
      if (peerId == null) return; // HELLO belum tiba; dipanggil lagi nanti.
      _dutiesDone = true;
      () async {
        try {
          await _ensureGuestServer();
          _log('HELLO lengkap; menelepon peer Lightning…');
          await connectGuestNode(peerId);
        } catch (e) {
          _log('Telepon peer gabung gagal: $e');
        }
      }();
    } else {
      _dutiesDone = true;
      Socket.connect(InternetAddress.loopbackIPv4, nodeListenPort).then(
        (socket) {
          _log('Socket ke node pendengar tersambung');
          _attachNodeSocket(socket);
        },
        onError: (Object e) {
          lastError = 'Gagal menyambung ke node pendengar: $e';
          _log(lastError!);
          _notify();
        },
      );
    }
  }

  /// Lepas tugas tautan (tautan menetap digantikan / putus):
  /// socket node dan listener telepon lokal ditutup, penanda
  /// tugas direset. Niat sesi tidak disentuh.
  void _teardownLinkDuties() {
    _detachNodeSocket();
    _closeGuestServer();
    _dutiesDone = false;
    _combinedDialer = false;
  }

  /// Kirim HELLO ke satu endpoint: ID node lokal penuh, di luar
  /// aliran node. Kegagalan kirim hanya tercatat — HELLO peer
  /// yang tidak tiba membuat penelpon menunggu, bukan rusak.
  void _sendHello(String endpointId) {
    final id = _localNodeIdHex;
    if (id == null) return;
    _nearby
        .sendBytesPayload(endpointId, encodeHelloPayload(id))
        .catchError((Object e) => _log('Kirim HELLO gagal: $e'));
  }

  /// Akhiri sesi secara eksplisit: niat sesi dimatikan, ingatan
  /// peer/host dilupakan, simpanan niat dihapus, lalu semua peran
  /// dan socket dihentikan. Inilah satu-satunya jalan mematikan
  /// jembatan — menutup layar tidak lagi memanggil ini.
  Future<void> stop() async {
    sessionActive = false;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _peerNodeId = null;
    _rememberedHostName = null;
    await _clearPersistedIntent();
    await _teardown();
    await _sinkronLayananLatar();
  }

  /// Saluran ke JembatanLatarService (layanan latar depan Android,
  /// tahap produksi B) lewat MainActivity.
  static const _saluranLayanan = MethodChannel('nux_wallet/jembatan');

  /// Samakan keadaan layanan latar depan dengan niat sesi: sesi
  /// aktif → layanan berjalan (proses dijaga hidup, notifikasi
  /// menetap tampil); sesi berakhir → layanan berhenti. Upaya
  /// terbaik: bukan Android atau saluran gagal tidak menggagalkan
  /// jembatan, hanya tercatat di log.
  Future<void> _sinkronLayananLatar() async {
    if (!Platform.isAndroid) return;
    try {
      await _saluranLayanan.invokeMethod(
        sessionActive ? 'mulaiLayanan' : 'berhentiLayanan',
      );
    } catch (e) {
      _log('Layanan latar tidak tersedia: $e');
    }
  }

  /// Hentikan semua peran dan tutup semua socket, tanpa menyentuh
  /// niat sesi (dipakai saat berganti peran dan mulai peran baru).
  Future<void> _teardown() async {
    await _detachNodeSocket();
    await _closeGuestServer();
    if (role == OfflineBridgeRole.host ||
        role == OfflineBridgeRole.combined) {
      await _nearby.stopAdvertising();
    }
    if (role == OfflineBridgeRole.guest ||
        role == OfflineBridgeRole.combined) {
      await _nearby.stopDiscovery();
    }
    await _nearby.stopAllEndpoints();
    role = OfflineBridgeRole.none;
    phase = OfflineBridgePhase.idle;
    linkedEndpointId = null;
    linkedEndpointName = null;
    discovered.clear();
    _survivorEndpointId = null;
    _helloPeerNodeId = null;
    _outboundEndpoints.clear();
    _initiatorByEndpoint.clear();
    _droppedEndpoints.clear();
    _combinedDialer = false;
    _dutiesDone = false;
    _resumeArmed = false;
    _deframer.reset();
    _notify();
  }

  /// Jadwalkan satu percobaan sambung-ulang dengan jeda mundur.
  /// Hanya dipanggil dari jalur kegagalan/putus; selama tautan
  /// sehat atau peran berjalan normal, tidak ada timer yang hidup
  /// (hemat baterai — radio Nearby sendiri biaya utamanya, dan
  /// itu hanya menyala selama sesi aktif).
  void _scheduleResume() {
    if (!sessionActive) return;
    _resumeTimer?.cancel();
    final delay = offlineResumeBackoff(_resumeAttempt);
    _resumeAttempt++;
    _log('Sambung ulang otomatis dalam ${delay.inSeconds} detik…');
    _resumeTimer = Timer(delay, _resume);
  }

  Future<void> _resume() async {
    if (!sessionActive || isLinked) return;
    if (role == OfflineBridgeRole.combined) {
      if (phase == OfflineBridgePhase.idle ||
          phase == OfflineBridgePhase.error) {
        _log('Memulai ulang iklan + pencarian gabung…');
        await _advertiseAndDiscover();
      } else if (phase == OfflineBridgePhase.discovering) {
        // Pencarian masih hidup; penemuan peer yang diingat
        // menyambung sendiri. Periksa lagi nanti selama belum
        // tertaut.
        _scheduleResume();
      }
      return;
    }
    if (role == OfflineBridgeRole.host) {
      if (phase == OfflineBridgePhase.idle ||
          phase == OfflineBridgePhase.error) {
        _log('Memasang ulang iklan host…');
        await _advertise();
      }
    } else if (role == OfflineBridgeRole.guest) {
      final remembered = _rememberedHostName;
      if (remembered != null) {
        for (final host in discovered) {
          if (host.name == remembered) {
            _log('Host ditemukan lagi; menyambung otomatis…');
            await connectToHost(host, _localName ?? '');
            return;
          }
        }
      }
      if (phase == OfflineBridgePhase.idle ||
          phase == OfflineBridgePhase.error) {
        _log('Memulai ulang pencarian host…');
        await _discover();
      } else if (phase == OfflineBridgePhase.discovering) {
        // Pencarian masih berjalan; penemuan host yang diingat
        // menyambung sendiri lewat onEndpointFound. Tetap
        // jadwalkan pemeriksaan berikutnya selama belum tertaut.
        _scheduleResume();
      }
    }
  }

  void _onLinked(String endpointId) {
    if (role == OfflineBridgeRole.combined) {
      _onLinkedCombined(endpointId);
      return;
    }
    linkedEndpointId = endpointId;
    phase = OfflineBridgePhase.linked;
    _resumeAttempt = 0;
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _log('Jembatan terhubung ke $linkedEndpointName');
    _notify();
    if (role == OfflineBridgeRole.guest && _peerNodeId != null) {
      // Tautan terbentuk kembali: sambungkan ulang peer Lightning
      // secara otomatis (dulu harus menekan tombol sambung lagi).
      _log('Menyambung ulang peer Lightning otomatis…');
      connectGuestNode(_peerNodeId!).catchError((Object e) {
        _log('Sambung ulang peer gagal: $e');
        _scheduleResume();
      });
    }
    if (role == OfflineBridgeRole.host) {
      // Node host mendengarkan di localhost; jembatan yang
      // menyambung masuk ke sana.
      Socket.connect(InternetAddress.loopbackIPv4, nodeListenPort).then(
        (socket) {
          _log('Socket ke node host tersambung');
          _attachNodeSocket(socket);
        },
        onError: (Object e) {
          lastError = 'Gagal menyambung ke node host: $e';
          _log(lastError!);
          _notify();
        },
      );
    }
    // Peran tamu: socket node datang lewat listener saat aplikasi
    // memanggil connect() pada node (lihat _onGuestTcpAccepted).
  }

  void _onUnlinked(String endpointId) {
    // Endpoint yang kalah dedupe gabung: pemutusannya disengaja,
    // bukan sesi putus — bersihkan catatan lalu selesai.
    if (_droppedEndpoints.remove(endpointId)) {
      _initiatorByEndpoint.remove(endpointId);
      _outboundEndpoints.remove(endpointId);
      return;
    }
    if (endpointId != linkedEndpointId) return;
    _log('Jembatan putus dari $linkedEndpointName');
    linkedEndpointId = null;
    linkedEndpointName = null;
    _detachNodeSocket();
    _closeGuestServer();
    _deframer.reset();
    if (role == OfflineBridgeRole.combined) {
      // Tautan menetap berakhir: bersihkan keadaan gabung dan
      // persenjatai sambung otomatis — penemuan kembali peer yang
      // diingat sekarang boleh menyambung sendiri (jalur pulih).
      _survivorEndpointId = null;
      _helloPeerNodeId = null;
      _dutiesDone = false;
      _combinedDialer = false;
      _resumeArmed = true;
    }
    phase = role == OfflineBridgeRole.host
        ? OfflineBridgePhase.advertising
        : OfflineBridgePhase.discovering;
    _notify();
    // Selama niat sesi hidup, putus bukan akhir: jadwalkan
    // penyembuhan (host memastikan iklannya hidup, tamu mencari
    // dan menyambung ulang ke host yang diingat).
    _scheduleResume();
  }

  void _onGuestTcpAccepted(Socket socket) {
    if (_nodeSocket != null) {
      // Satu tautan peer saja untuk spike; tolak sisanya.
      socket.destroy();
      return;
    }
    _log('Node tamu menyambung ke jembatan');
    _attachNodeSocket(socket);
  }

  void _attachNodeSocket(Socket socket) {
    _nodeSocket = socket;
    _nodeSocketSub = socket.listen(
      (data) {
        for (final frame in LengthPrefixFramer.encode(data)) {
          _sendToNearby(frame);
        }
      },
      onError: (Object e) => _log('Socket node error: $e'),
      onDone: () {
        _log('Socket node ditutup');
        _detachNodeSocket();
      },
    );
    _notify();
  }

  Future<void> _detachNodeSocket() async {
    await _nodeSocketSub?.cancel();
    _nodeSocketSub = null;
    _nodeSocket?.destroy();
    _nodeSocket = null;
  }

  Future<void> _closeGuestServer() async {
    await _guestServerSub?.cancel();
    _guestServerSub = null;
    await _guestServer?.close();
    _guestServer = null;
  }

  void _sendToNearby(Uint8List frame) {
    final endpointId = linkedEndpointId;
    if (endpointId == null) {
      _log('Byte node dibuang: jembatan belum terhubung');
      return;
    }
    _nearby
        .sendBytesPayload(endpointId, frame)
        .catchError((Object e) => _log('Kirim payload gagal: $e'));
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;
    // Mode gabung: muatan HELLO adalah kendali, bukan data node —
    // pelajari ID pengirimnya, ingat sebagai peer sesi, lalu
    // jalankan tugas tautan yang menunggunya. Muatan ini tidak
    // pernah diteruskan ke socket node.
    if (role == OfflineBridgeRole.combined) {
      final helloId = parseHelloPayload(payload.bytes!);
      if (helloId != null) {
        if (helloId != _helloPeerNodeId) {
          _helloPeerNodeId = helloId;
          rememberPeerNodeId(helloId);
          _log('HELLO diterima: ID node peer $helloId');
          _notify();
        }
        _maybeRunDuties();
        return;
      }
    }
    final List<Uint8List> messages;
    try {
      messages = _deframer.feed(payload.bytes!);
    } on FormatException catch (e) {
      _log('Aliran jembatan rusak: ${e.message}');
      return;
    }
    final socket = _nodeSocket;
    if (socket == null) {
      if (messages.isNotEmpty) {
        _log('Byte peer tiba sebelum socket node siap; dibuang');
      }
      return;
    }
    for (final message in messages) {
      socket.add(message);
    }
  }
}
