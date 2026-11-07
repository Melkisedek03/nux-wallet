import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Jeda sambung-ulang jembatan untuk percobaan ke-[attempt]
/// (0-based): 2, 4, 8, 16 detik, lalu mentok 30 detik. Murni
/// supaya bisa diuji satuan.
Duration offlineResumeBackoff(int attempt) {
  final seconds = 2 << attempt;
  return Duration(seconds: seconds > 30 ? 30 : seconds);
}

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

enum OfflineBridgeRole { none, host, guest }

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

  static const _kActive = 'offline_bridge_session_active';
  static const _kRole = 'offline_bridge_role';
  static const _kLocalName = 'offline_bridge_local_name';
  static const _kPeerNodeId = 'offline_bridge_peer_node_id';
  static const _kHostName = 'offline_bridge_host_name';

  Socket? _nodeSocket;
  StreamSubscription<Uint8List>? _nodeSocketSub;
  ServerSocket? _guestServer;
  StreamSubscription<Socket>? _guestServerSub;
  final LengthPrefixDeframer _deframer = LengthPrefixDeframer();

  bool get isLinked =>
      phase == OfflineBridgePhase.linked && linkedEndpointId != null;

  void _notify() => onChanged?.call();

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
  }

  Future<void> _clearPersistedIntent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kActive);
    await prefs.remove(_kRole);
    await prefs.remove(_kLocalName);
    await prefs.remove(_kPeerNodeId);
    await prefs.remove(_kHostName);
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
  }

  /// Hentikan semua peran dan tutup semua socket, tanpa menyentuh
  /// niat sesi (dipakai saat berganti peran dan mulai peran baru).
  Future<void> _teardown() async {
    await _detachNodeSocket();
    await _closeGuestServer();
    if (role == OfflineBridgeRole.host) {
      await _nearby.stopAdvertising();
    } else if (role == OfflineBridgeRole.guest) {
      await _nearby.stopDiscovery();
    }
    await _nearby.stopAllEndpoints();
    role = OfflineBridgeRole.none;
    phase = OfflineBridgePhase.idle;
    linkedEndpointId = null;
    linkedEndpointName = null;
    discovered.clear();
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
    if (endpointId != linkedEndpointId) return;
    _log('Jembatan putus dari $linkedEndpointName');
    linkedEndpointId = null;
    linkedEndpointName = null;
    _detachNodeSocket();
    _closeGuestServer();
    _deframer.reset();
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
