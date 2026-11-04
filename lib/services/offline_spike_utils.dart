import 'package:ldk_node/src/generated/api/types.dart';

/// Logika murni layar Uji Offline Lightning tahap 2 — dipisah
/// dari widget supaya bisa diuji tanpa perangkat: parsing nominal,
/// penyaringan channel langsung (bukan channel LSP), dan penentuan
/// peer seberang dari daftar peer node.

/// Parse nominal nusan bertulis tangan menjadi msat. Menerima
/// bilangan bulat ("25000") dan pecahan sampai 3 desimal dengan
/// pemisah '.' atau ',' ("1.5", "0,001" = 1 msat). Mengembalikan
/// null untuk teks yang tidak valid atau bernilai negatif; nol
/// dikembalikan apa adanya (kebijakan menolak nol ada di pemanggil).
BigInt? parseNusanToMsat(String raw) {
  final text = raw.trim().replaceAll(' ', '');
  if (text.isEmpty) return null;
  final match = RegExp(r'^(\d+)(?:[.,](\d{1,3}))?$').firstMatch(text);
  if (match == null) return null;
  final whole = BigInt.parse(match.group(1)!);
  final fracText = match.group(2);
  var msat = whole * BigInt.from(1000);
  if (fracText != null) {
    msat += BigInt.parse(fracText.padRight(3, '0'));
  }
  return msat;
}

/// Channel langsung antar-HP dari daftar semua channel node:
/// semua channel yang pihak seberangnya BUKAN node LSP
/// [lspNodeIdHex]. Channel LSP tidak pernah ditampilkan di layar
/// uji offline supaya bukti channel langsung tidak tercampur.
List<ChannelDetails> directChannels(
  List<ChannelDetails> channels,
  String lspNodeIdHex,
) {
  final lsp = lspNodeIdHex.toLowerCase();
  return channels
      .where((c) => c.counterpartyNodeId.hex.toLowerCase() != lsp)
      .toList();
}

/// ID node peer seberang lewat jembatan: satu-satunya peer yang
/// sedang tersambung dan bukan LSP. Mengembalikan null bila tidak
/// ada atau ada lebih dari satu calon (ambigu — pemanggil memakai
/// ID yang dimasukkan/diingat saja).
String? bridgeCounterpartId(
  List<PeerDetails> peers,
  String lspNodeIdHex,
) {
  final lsp = lspNodeIdHex.toLowerCase();
  final candidates = peers
      .where((p) => p.isConnected && p.nodeId.hex.toLowerCase() != lsp)
      .map((p) => p.nodeId.hex)
      .toList();
  if (candidates.length != 1) return null;
  return candidates.single;
}
