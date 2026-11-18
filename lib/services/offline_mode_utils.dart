import 'package:ldk_node/src/generated/api/types.dart';

/// Logika murni tuas Mode Offline produksi — dipisah dari widget
/// supaya bisa diuji tanpa perangkat: kode perangkat yang dilihat
/// pengguna, nama endpoint jembatan, keadaan jalur pembayaran
/// dengan peer tertaut, dan keadaan tuas itu sendiri.
///
/// Permukaan tuas tidak mengenal jargon: yang tampil hanya kode
/// perangkat (8 hex pertama ID node, dikelompokkan 4+4), nama
/// endpoint ELNUX-XXXX, dan keadaan jalur (belum/disiapkan/siap) —
/// kata "channel" dan "node ID" tidak pernah sampai ke layar;
/// konfirmasi tampil sebagai "Konfirmasi X/6", bukan angka blok.

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

/// Nominal bawaan pembukaan jalur (PR C, keputusan pemilik produk
/// 18 Nov 2026): 100.000 nusan — cukup besar untuk belanja
/// lapangan, cukup kecil untuk percobaan pertama.
final BigInt defaultPathAmountSats = BigInt.from(100000);

/// Nominal minimum pembukaan jalur (PR C): 10.000 nusan. Lawan
/// menetapkan cadangan max(1% × kapasitas, min 1.000 nusan) —
/// pada channel 1.000 nusan seluruh nilainya menjadi cadangan dan
/// tidak ada yang bisa dikirim; pada 10.000 nusan, cadangannya
/// 1.000 dan 9.000 tetap bisa dikirim.
final BigInt minPathAmountSats = BigInt.from(10000);

/// Apakah sudah ada jalur pembayaran yang SIAP dengan peer
/// [peerNodeIdHex]: sekurang-kurangnya satu channel yang pihak
/// seberangnya peer itu DAN sudah usable (channel_ready + peer
/// tersambung). Channel yang masih menunggu konfirmasi bukan
/// jalur siap — ia tampil sebagai "disiapkan" (lihat
/// [pathStateFor]). Perbandingan ID tidak peka huruf besar/kecil.
bool hasReadyPath(List<ChannelDetails> channels, String? peerNodeIdHex) {
  if (peerNodeIdHex == null) return false;
  final peer = peerNodeIdHex.toLowerCase();
  return channels.any(
    (c) => c.isUsable && c.counterpartyNodeId.hex.toLowerCase() == peer,
  );
}

/// Keadaan jalur pembayaran dengan satu peer (PR C): belum ada,
/// sedang disiapkan (pendanaan dinegosiasikan atau menunggu
/// konfirmasi), atau sudah siap (channel_ready sudah dipertukarkan
/// — bisa dipakai membayar begitu peer tersambung).
enum PathState { none, preparing, ready }

/// Apakah channel [channel] sedang DISIAPKAN: belum channel_ready
/// DAN konfirmasinya belum mencapai jumlah wajib. Ini mencakup
/// jendela negosiasi (fundingTxo masih null, konfirmasi belum
/// tercatat — keduanya null berarti 0/6) dan masa tunggu
/// konfirmasi (0–5/6).
///
/// Channel yang sedang DITUTUP sengaja tidak terhitung: ia juga
/// tidak channel_ready, tetapi konfirmasinya sudah ≥ jumlah wajib
/// — jalurnya sudah berakhir, bukan sedang disiapkan.
bool isPreparingChannel(ChannelDetails channel) {
  if (channel.isChannelReady) return false;
  final done = channel.confirmations ?? 0;
  final required = channel.confirmationsRequired ?? 6;
  return done < required;
}

/// Keadaan jalur dengan peer [peerNodeIdHex] dari daftar
/// [channels]: siap bila ada satu channel dengan peer itu yang
/// sudah channel_ready; disiapkan bila ada satu channel dengan
/// peer itu yang sedang disiapkan ([isPreparingChannel]) atau
/// [hasOpening] (pembukaan baru yang channel-nya belum muncul di
/// daftar — jendela negosiasi, lihat OpeningPathsStore); belum
/// ada bila tidak ada keduanya.
///
/// Siap mengalahkan disiapkan: bila dua channel dengan peer yang
/// sama lahir bersamaan (balapan ketuk kedua sisi, Q-C7), yang
/// satu sudah siap dan yang satu masih disiapkan, pengguna bisa
/// membayar — kartu menampilkan keadaan siap. Perbandingan ID
/// tidak peka huruf besar/kecil; peer null berarti belum ada.
PathState pathStateFor(
  List<ChannelDetails> channels,
  String? peerNodeIdHex, {
  bool hasOpening = false,
}) {
  if (peerNodeIdHex == null) return PathState.none;
  final peer = peerNodeIdHex.toLowerCase();
  var preparing = hasOpening;
  for (final c in channels) {
    if (c.counterpartyNodeId.hex.toLowerCase() != peer) continue;
    if (c.isChannelReady) return PathState.ready;
    if (isPreparingChannel(c)) preparing = true;
  }
  return preparing ? PathState.preparing : PathState.none;
}

/// Channel yang sedang disiapkan dengan peer [peerNodeIdHex],
/// atau null bila tidak ada. Bila ada lebih dari satu (balapan
/// ketuk kedua sisi), yang konfirmasinya paling banyak yang
/// dipilih — yang paling dekat dengan siap adalah yang paling
/// informatif untuk ditampilkan. Perbandingan ID tidak peka huruf.
ChannelDetails? preparingChannelForPeer(
  List<ChannelDetails> channels,
  String? peerNodeIdHex,
) {
  if (peerNodeIdHex == null) return null;
  final peer = peerNodeIdHex.toLowerCase();
  ChannelDetails? best;
  var bestConfirmations = -1;
  for (final c in channels) {
    if (c.counterpartyNodeId.hex.toLowerCase() != peer) continue;
    if (!isPreparingChannel(c)) continue;
    final done = c.confirmations ?? 0;
    if (done > bestConfirmations) {
      best = c;
      bestConfirmations = done;
    }
  }
  return best;
}

/// Channel langsung manapun yang sedang disiapkan (lawan bukan
/// node LSP [lspNodeIdHex]) — dipakai kartu jalur saat sesi sudah
/// berakhir dan ingatan peer dibersihkan: pasangan yang pulang
/// tetap bisa memantau kemajuan penyiapan dari layar ini.
/// Bila ada lebih dari satu, yang konfirmasinya paling banyak
/// yang dipilih. Channel LSP dan channel siap diabaikan.
ChannelDetails? preparingDirectChannel(
  List<ChannelDetails> channels,
  String lspNodeIdHex,
) {
  final lsp = lspNodeIdHex.toLowerCase();
  ChannelDetails? best;
  var bestConfirmations = -1;
  for (final c in channels) {
    if (c.counterpartyNodeId.hex.toLowerCase() == lsp) continue;
    if (!isPreparingChannel(c)) continue;
    final done = c.confirmations ?? 0;
    if (done > bestConfirmations) {
      best = c;
      bestConfirmations = done;
    }
  }
  return best;
}

/// Keadaan tuas Mode Offline yang dilihat pengguna (bagian 4.2
/// rancangan): mati, mencari perangkat, terhubung ke perangkat,
/// jalur sedang disiapkan, atau jalur pembayaran sudah siap.
enum OfflineModeState { off, searching, connected, preparing, ready }

/// Hitung [OfflineModeState] dari keadaan jembatan dan jalur:
/// niat sesi mati berarti mati; sesi hidup tapi belum tertaut
/// berarti mencari; tertaut dengan jalur siap berarti siap,
/// tertaut dengan jalur disiapkan berarti disiapkan, tertaut
/// tanpa keduanya berarti terhubung.
OfflineModeState offlineModeState({
  required bool sessionActive,
  required bool linked,
  required bool pathReady,
  bool pathPreparing = false,
}) {
  if (!sessionActive) return OfflineModeState.off;
  if (!linked) return OfflineModeState.searching;
  if (pathReady) return OfflineModeState.ready;
  if (pathPreparing) return OfflineModeState.preparing;
  return OfflineModeState.connected;
}
