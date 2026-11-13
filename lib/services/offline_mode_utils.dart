import 'package:ldk_node/src/generated/api/types.dart';

/// Logika murni tuas Mode Offline produksi — dipisah dari widget
/// supaya bisa diuji tanpa perangkat: kode perangkat yang dilihat
/// pengguna, nama endpoint jembatan, keadaan jalur pembayaran
/// dengan peer tertaut, dan keadaan tuas itu sendiri.
///
/// Permukaan tuas tidak mengenal jargon: yang tampil hanya kode
/// perangkat (8 hex pertama ID node, dikelompokkan 4+4), nama
/// endpoint ELNUX-XXXX, dan keadaan siap/belum — kata "channel",
/// "konfirmasi 6/6", dan "node ID" tidak pernah sampai ke layar.

/// Nama endpoint jembatan untuk ID node [nodeIdHex]: awalan ELNUX-
/// ditambah 8 hex pertamanya. Bentuk yang sama dipakai layar uji
/// (lihat _localName di OfflineSpikeScreen) dan aturan dedupe
/// tautan ganda di layanan jembatan.
String localEndpointName(String nodeIdHex) {
  final id = nodeIdHex.toLowerCase();
  final head = id.length >= 8 ? id.substring(0, 8) : id;
  return 'ELNUX-$head';
}

/// Kode perangkat yang dicocokkan mata pengguna: 8 hex pertama
/// ID node [nodeIdHex], huruf besar, dikelompokkan 4+4
/// ("039B 7213"). ID yang lebih pendek dari 8 karakter
/// dikembalikan apa adanya dalam huruf besar.
String formatDeviceCode(String nodeIdHex) {
  final head = nodeIdHex.length >= 8 ? nodeIdHex.substring(0, 8) : nodeIdHex;
  final upper = head.toUpperCase();
  if (upper.length <= 4) return upper;
  return '${upper.substring(0, 4)} ${upper.substring(4)}';
}

/// Kode perangkat dari nama endpoint jembatan ("ELNUX-039b7213"
/// menjadi "039B 7213"). Mengembalikan null bila nama tidak
/// mengikuti pola itu — nama endpoint asing tidak pernah
/// diterjemahkan menjadi kode.
String? codeFromEndpointName(String name) {
  final match = RegExp(r'^ELNUX-([0-9a-fA-F]{8})$').firstMatch(name);
  if (match == null) return null;
  return formatDeviceCode(match.group(1)!);
}

/// Apakah sudah ada jalur pembayaran yang SIAP dengan peer
/// [peerNodeIdHex]: sekurang-kurangnya satu channel yang pihak
/// seberangnya peer itu DAN sudah usable (channel_ready).
/// Channel yang masih menunggu konfirmasi bukan jalur siap —
/// di PR B ia tampil sebagai "belum ada" (keadaan "disiapkan"
/// adalah PR C). Perbandingan ID tidak peka huruf besar/kecil.
bool hasReadyPath(List<ChannelDetails> channels, String? peerNodeIdHex) {
  if (peerNodeIdHex == null) return false;
  final peer = peerNodeIdHex.toLowerCase();
  return channels.any(
    (c) => c.isUsable && c.counterpartyNodeId.hex.toLowerCase() == peer,
  );
}

/// Keadaan tuas Mode Offline yang dilihat pengguna (bagian 4.2
/// rancangan): mati, mencari perangkat, terhubung ke perangkat,
/// atau jalur pembayaran sudah siap.
enum OfflineModeState { off, searching, connected, ready }

/// Hitung [OfflineModeState] dari keadaan jembatan dan jalur:
/// niat sesi mati berarti mati; sesi hidup tapi belum tertaut
/// berarti mencari; tertaut dengan jalur siap berarti siap,
/// tertaut tanpa jalur siap berarti terhubung.
OfflineModeState offlineModeState({
  required bool sessionActive,
  required bool linked,
  required bool pathReady,
}) {
  if (!sessionActive) return OfflineModeState.off;
  if (!linked) return OfflineModeState.searching;
  return pathReady ? OfflineModeState.ready : OfflineModeState.connected;
}
