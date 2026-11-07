import 'package:ldk_node/src/generated/api/types.dart';

import '../utils/format.dart';

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

/// Parse nominal kolom buka channel menjadi msat. Berbeda dari
/// [parseNusanToMsat] (yang membaca '.' sebagai pemisah desimal),
/// nominal channel mengikuti aturan isian nominal bersama aplikasi
/// ([parseAmountInputToMsat], locale id: '.' pemisah ribuan, ','
/// desimal) — persis seperti tampilan nominal di aplikasi sendiri,
/// jadi "25.000" terbaca dua puluh lima ribu nusan, bukan 25, dan
/// "1.000.000" sah. Channel hanya boleh bernilai nusan bulat, jadi
/// hasil berpecahan (sisa msat di luar kelipatan 1.000, mis. "25,5")
/// ditolak sebagai null; nol juga null (bawaan parser bersama).
BigInt? parseChannelAmountToMsat(String raw) {
  final msat = parseAmountInputToMsat(raw, DisplayUnit.nusan);
  if (msat == null) return null;
  if (msat % BigInt.from(1000) != BigInt.zero) return null;
  return msat;
}

/// Apakah transaksi pendanaan channel ini sudah terlihat di rantai:
/// keluaran pendanaannya dikenal DAN sekurang-kurangnya satu
/// konfirmasi tercatat (atau channel sudah siap, yang berarti jumlah
/// konfirmasi wajibnya tercapai). Sengaja BUKAN berdasar event siaran
/// internal node: event itu pernah terpicu untuk siaran yang hilang di
/// tengah jalan (channel zombie, Nov 2026), jadi satu-satunya bukti
/// yang dipercaya adalah visibilitas di rantai itu sendiri.
bool fundingVisibleOnChain(ChannelDetails channel) {
  if (channel.fundingTxo == null) return false;
  return channel.isChannelReady || (channel.confirmations ?? 0) >= 1;
}

/// TXID pendanaan dari [channels] yang sudah terlihat di rantai dan
/// belum ada di [celebratedTxids] — calon perayaan "pendanaan akhirnya
/// tersiar", sekali per transaksi pendanaan.
List<String> uncelebratedVisibleFundingTxids(
  List<ChannelDetails> channels,
  Set<String> celebratedTxids,
) {
  return channels
      .where(fundingVisibleOnChain)
      .map((c) => c.fundingTxo!.txid.hash)
      .where((txid) => !celebratedTxids.contains(txid))
      .toList();
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
String? bridgeCounterpartId(List<PeerDetails> peers, String lspNodeIdHex) {
  final lsp = lspNodeIdHex.toLowerCase();
  final candidates = peers
      .where((p) => p.isConnected && p.nodeId.hex.toLowerCase() != lsp)
      .map((p) => p.nodeId.hex)
      .toList();
  if (candidates.length != 1) return null;
  return candidates.single;
}

/// Apakah channel langsung boleh dibuka: peer seberang harus tersambung
/// DAN sesi tidak boleh dimulai dalam mode offline. Pada sesi offline node
/// tidak punya akses ke rantai, sehingga siaran transaksi pendanaan tidak
/// akan sampai ke jaringan dan channel menggantung menunggu konfirmasi
/// yang tidak akan pernah datang; membuka channel dalam keadaan itu
/// ditolak sejak awal.
bool canOpenDirectChannel({
  required bool peerConnected,
  required bool sessionOffline,
}) {
  return peerConnected && !sessionOffline;
}
