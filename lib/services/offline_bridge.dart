import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';

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
  final void Function()? onChanged;

  /// Catatan kejadian terbaca manusia untuk layar uji.
  final void Function(String message)? onLog;

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

  Socket? _nodeSocket;
  StreamSubscription<Uint8List>? _nodeSocketSub;
  ServerSocket? _guestServer;
  StreamSubscription<Socket>? _guestServerSub;
  final LengthPrefixDeframer _deframer = LengthPrefixDeframer();

  bool get isLinked =>
      phase == OfflineBridgePhase.linked && linkedEndpointId != null;

  void _notify() => onChanged?.call();

  void _log(String message) => onLog?.call(message);

  /// Mulai peran host: iklankan diri dan terima satu tamu.
  Future<void> startHost(String localName) async {
    await stop();
    role = OfflineBridgeRole.host;
    phase = OfflineBridgePhase.advertising;
    lastError = null;
    _notify();
    _log('Mengiklankan sebagai host ($localName)…');
    final ok = await _nearby.startAdvertising(
      localName,
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
    }
  }

  /// Mulai peran tamu: cari host yang sedang mengiklankan diri.
  Future<void> startDiscovery(String localName) async {
    await stop();
    role = OfflineBridgeRole.guest;
    phase = OfflineBridgePhase.discovering;
    lastError = null;
    discovered.clear();
    _notify();
    _log('Mencari host di sekitar…');
    final ok = await _nearby.startDiscovery(
      localName,
      Strategy.P2P_POINT_TO_POINT,
      serviceId: serviceId,
      onEndpointFound: (endpointId, endpointName, _) {
        discovered.removeWhere((h) => h.endpointId == endpointId);
        discovered.add(DiscoveredHost(endpointId, endpointName));
        _log('Host ditemukan: $endpointName');
        _notify();
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
    }
  }

  /// Tamu menyambung ke [host] terpilih. Listener TCP lokal
  /// diikat lebih dulu supaya node tamu bisa langsung connect()
  /// begitu tautan Nearby terbentuk.
  Future<void> connectToHost(DiscoveredHost host, String localName) async {
    if (role != OfflineBridgeRole.guest) return;
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

  /// Hentikan semua peran dan tutup semua socket.
  Future<void> stop() async {
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

  void _onLinked(String endpointId) {
    linkedEndpointId = endpointId;
    phase = OfflineBridgePhase.linked;
    _log('Jembatan terhubung ke $linkedEndpointName');
    _notify();
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
