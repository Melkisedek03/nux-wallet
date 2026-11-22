import 'dart:convert';

import 'package:ldk_node/src/generated/api/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Catatan pembayaran ELNUX — teks deskripsi invoice yang ditautkan
/// ke payment hash, disimpan lokal di HP.
///
/// Kenapa harus disimpan sendiri: catatan pembayaran node
/// (PaymentDetails) TIDAK membawa deskripsi invoice — hanya hash,
/// nominal, arah, dan status. Tanpa simpanan ini, riwayat hanya
/// bisa berjudul "Diterima"/"Dikirim" selamanya, walau invoice-nya
/// sendiri membawa catatan ("untuk SPP November").
///
/// Dua arah menulis:
/// - MASUK: catatan yang diketik user di kolom Catatan layar
///   Terima menjadi deskripsi invoice-nya; saat invoice dibuat,
///   pasangan hash → catatan disimpan di sini.
/// - KELUAR: deskripsi invoice orang lain yang dibayar user
///   disimpan saat pembayaran dikirim, supaya riwayat pembayaran
///   keluar pun berjudul catatannya, bukan sekadar "Dikirim".
///
/// Deskripsi OTOMATIS aplikasi ("Terima 5.000 nusan") tidak pernah
/// disimpan dari sisi terima — itu bukan catatan user. Dari sisi
/// kirim, deskripsi invoice yang dibayar disimpan apa adanya:
/// itulah teks yang disetujui user di dialog konfirmasi.

/// Teks yang menjadi deskripsi invoice: catatan user bila terisi,
/// kalau tidak teks bawaan aplikasi (perilaku lama).
String resolveInvoiceDescription({
  required String note,
  required String fallback,
}) {
  final trimmed = note.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

/// Encode peta hash → catatan menjadi string JSON simpanan.
String encodePaymentNotes(Map<String, String> notes) => jsonEncode(notes);

/// Decode string simpanan menjadi peta hash → catatan.
///
/// Fail-open total: masukan rusak/bukan peta → peta kosong; entri
/// yang kuncinya bukan hash hex 64 karakter atau nilainya bukan
/// teks terisi dibuang satu per satu, bukan menggagalkan sisanya.
Map<String, String> decodePaymentNotes(String? raw) {
  if (raw == null || raw.isEmpty) return <String, String>{};
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return <String, String>{};
  }
  if (decoded is! Map) return <String, String>{};
  final out = <String, String>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is String &&
        key.length == 64 &&
        value is String &&
        value.trim().isNotEmpty) {
      out[key] = value;
    }
  }
  return out;
}

/// Penyimpanan [PaymentNoteStore] di SharedPreferences.
///
/// Pola sama seperti SavedInvoiceStore: semua kegagalan baca
/// dianggap "tidak ada catatan" (fail-open), kegagalan tulis
/// ditelan — catatan adalah lapisan kenyamanan, tidak boleh
/// menggagalkan pembuatan invoice atau pembayaran.
class PaymentNoteStore {
  static const String storageKey = 'payment_notes_v1';

  /// Batas simpanan: catatan terlama terbuang lebih dulu.
  /// 500 jauh di atas pola pakai dompet pribadi dan menjaga
  /// ukuran simpanan tetap kecil.
  static const int maxKeep = 500;

  /// Muat seluruh catatan (peta hash hex → catatan).
  Future<Map<String, String>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodePaymentNotes(prefs.getString(storageKey));
    } catch (_) {
      return <String, String>{};
    }
  }

  /// Simpan (atau perbarui) catatan untuk [paymentHashHex].
  ///
  /// Catatan kosong tidak disimpan. Entri yang diperbarui pindah
  /// ke posisi terbaru supaya pemotongan [maxKeep] membuang yang
  /// benar-benar paling lama tidak tersentuh.
  Future<void> save(String paymentHashHex, String note) async {
    final trimmed = note.trim();
    if (paymentHashHex.length != 64 || trimmed.isEmpty) return;
    try {
      final notes = await loadAll();
      notes.remove(paymentHashHex);
      notes[paymentHashHex] = trimmed;
      while (notes.length > maxKeep) {
        notes.remove(notes.keys.first);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encodePaymentNotes(notes));
    } catch (_) {
      // Gagal simpan = riwayat baris ini tetap berjudul arah
      // pembayaran, seperti sebelum fitur ini ada.
    }
  }
}

/// Nilai tag rute yang dikenal untuk [PaymentTagStore]: pembayaran
/// berjalan lewat channel langsung antar-HP, bukan lewat LSP.
const String paymentTagDirect = 'direct';

/// Panjang maksimum label offer Bolt12 yang tampil sebagai tag
/// baris riwayat (dalam rune, aman untuk emoji). Label lebih
/// panjang dipangkas dengan '…' — baris ke-2 TransactionRow
/// memang dilindungi FittedBox scaleDown sehingga tidak bisa
/// meluap, tapi tanpa pangkasan satu label panjang akan
/// menyusutkan seluruh baris ke ukuran tak terbaca.
const int maxOfferLabelTagRunes = 20;

/// Tag baris riwayat untuk pembayaran Lightning biasa tanpa
/// penanda khusus: petir polos.
const String historyRowTagBare = '⚡';

/// Tag baris riwayat untuk pembayaran Bolt12 MASUK lewat offer
/// statis berlabel kustom: '⚡ ' + label (dipangkas bila perlu).
/// Label adalah teks pilihan user sendiri, ditampilkan apa adanya.
String bolt12OfferLabelTag(String label) {
  final trimmed = label.trim();
  final runes = trimmed.runes.toList();
  if (runes.length <= maxOfferLabelTagRunes) return '⚡ $trimmed';
  return '⚡ ${String.fromCharCodes(runes.take(maxOfferLabelTagRunes))}…';
}

/// Tag baris riwayat dari jenis pembayaran + tag rute tercatat
/// + label offer Bolt12.
///
/// JIT dan on-chain dibaca dari jenis pembayaran node (persis);
/// label offer dibaca dari simpanan lokal (catatan pembayaran
/// node tidak membawa deskripsi — lihat Bolt12OfferStore);
/// tag rute lokal hanya mengisi sisanya — pembayaran Lightning
/// biasa yang tercatat berjalan lewat channel langsung.
///
/// Urutan penting: pembayaran JIT menurut definisinya lahir
/// dari LSP, tidak pernah langsung; on-chain bukan Lightning;
/// keduanya tidak pernah berjenis Bolt12Offer, jadi tidak
/// pernah berebut dengan label. Label menang atas tag direct:
/// pembayaran Bolt12 masuk lewat channel langsung tetap
/// pembayaran lewat offer berlabel itu — label itulah yang
/// dikenali user. Tanpa label, Bolt12 masuk tetap '⚡' polos
/// seperti sebelum fitur ini ada (tidak ada tag 'Bolt12':
/// permukaan awam tidak butuh jargon baru).
///
/// [fundingLabel] hanya dipakai layar DETAIL (bukan baris):
/// kiriman on-chain yang mendanai channel membawa label
/// jenisnya ("Pembukaan Channel …⚡") sebagai ganti '⛓
/// on-chain' polos. Baris riwayat tidak mengopernya, jadi
/// baris tidak berubah — label pendanaan memang dicakup
/// rancangan hanya untuk detail Aktivitas. Label pendanaan
/// tidak pernah berebut dengan JIT: pendanaan adalah on-chain,
/// JIT adalah Bolt11.
String historyRowTag({
  required bool isJit,
  required bool isOnchain,
  required String? routeTag,
  bool isBolt12Inbound = false,
  String? bolt12Label,
  String? fundingLabel,
}) {
  if (isJit) return '⚡ JIT';
  if (isOnchain && fundingLabel != null && fundingLabel.trim().isNotEmpty) {
    return fundingLabel;
  }
  if (isOnchain) return '⛓ on-chain';
  if (isBolt12Inbound && bolt12Label != null && bolt12Label.trim().isNotEmpty) {
    return bolt12OfferLabelTag(bolt12Label);
  }
  if (routeTag == paymentTagDirect) return '⚡ direct';
  return historyRowTagBare;
}

/// Penyimpanan tag rute pembayaran di SharedPreferences
/// (hash hex → tag). Pola sama seperti [PaymentNoteStore]:
/// fail-open, kegagalan tulis ditelan — tag adalah lapisan
/// tampilan riwayat, bukan data dana.
///
/// Mengapa dicatat, bukan dibaca dari node: catatan pembayaran
/// LDK tidak memuat channel yang dilalui pembayaran, jadi rute
/// hanya bisa dibuktikan pada saat transaksi terjadi — konteks
/// offline (boot offline / sesi jembatan aktif) saat kirim atau
/// terima. Sekali tercatat, tag melekat pada hash pembayaran itu.
class PaymentTagStore {
  static const String storageKey = 'payment_route_tags_v1';

  /// Batas simpanan: tag terlama terbuang lebih dulu (pola sama
  /// seperti PaymentNoteStore.maxKeep).
  static const int maxKeep = 500;

  /// Muat seluruh tag (peta hash hex → tag).
  Future<Map<String, String>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodePaymentNotes(prefs.getString(storageKey));
    } catch (_) {
      return <String, String>{};
    }
  }

  /// Simpan (atau perbarui) tag untuk [paymentHashHex].
  Future<void> save(String paymentHashHex, String tag) async {
    final trimmed = tag.trim();
    if (paymentHashHex.length != 64 || trimmed.isEmpty) return;
    try {
      final tags = await loadAll();
      tags.remove(paymentHashHex);
      tags[paymentHashHex] = trimmed;
      while (tags.length > maxKeep) {
        tags.remove(tags.keys.first);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encodePaymentNotes(tags));
    } catch (_) {
      // Gagal simpan = baris ini tampil tanpa tag rute, seperti
      // sebelum fitur ini ada.
    }
  }

  /// Catat pembayaran ini berjalan lewat channel langsung.
  Future<void> saveDirect(String paymentHashHex) =>
      save(paymentHashHex, paymentTagDirect);
}

/// Label pendanaan channel (PR 2 rancangan Kelola Channel):
/// kiriman on-chain yang sebenarnya pendanaan channel membawa
/// keterangan jenisnya di detail Aktivitas, dibedakan dari
/// lawan channel-nya (keputusan 4 rancangan).
///
/// Teksnya TETAP persis seperti diputuskan, termasuk ⚡, dan
/// sama di kedua bahasa — ini label tetap, bukan kalimat yang
/// diterjemahkan. Karena itu tidak ada kunci l10n untuknya.

/// Jenis pendanaan yang disimpan [ChannelFundingLabelStore]:
/// txid mendanai channel ke LSP atau channel langsung.
const String fundingKindLsp = 'lsp';
const String fundingKindDirect = 'direct';

/// Label detail untuk pendanaan channel ke LSP.
const String fundingLabelLsp = 'Pembukaan Channel ke LSP⚡';

/// Label detail untuk pendanaan channel langsung.
const String fundingLabelDirect = 'Pembukaan Channel Langsung⚡';

/// Teks label detail dari jenis pendanaan tersimpan [kind];
/// null bila jenisnya tidak dikenal (termasuk null) — pemanggil
/// menampilkan jenis on-chain polos seperti sebelumnya.
String? fundingLabelTextForKind(String? kind) {
  if (kind == fundingKindLsp) return fundingLabelLsp;
  if (kind == fundingKindDirect) return fundingLabelDirect;
  return null;
}

/// Jenis pendanaan [txid] dari daftar channel [channels] yang
/// masih dikenal node: [fundingKindLsp] bila txid adalah
/// pendanaan channel ke LSP, [fundingKindDirect] bila channel
/// langsung, null bila tidak ada channel yang txid
/// pendanaannya cocok. Perbandingan ID node tidak peka huruf
/// besar/kecil — hex node bisa berbeda kapitalisasi antar
/// sumber.
///
/// Korelasi ini hidup hanya selama channel-nya masih dikenal
/// node; pemanggil menyimpannya ke [ChannelFundingLabelStore]
/// pada kecocokan pertama, supaya labelnya bertahan sesudah
/// channel ditutup dan hilang dari daftar (§4.4 rancangan).
String? matchChannelFundingKind({
  required String txid,
  required List<ChannelDetails> channels,
  required String lspNodeIdHex,
}) {
  final lsp = lspNodeIdHex.toLowerCase();
  for (final ch in channels) {
    if (ch.fundingTxo?.txid.hash == txid) {
      return ch.counterpartyNodeId.hex.toLowerCase() == lsp
          ? fundingKindLsp
          : fundingKindDirect;
    }
  }
  return null;
}

/// Penyimpanan label pendanaan channel di SharedPreferences
/// (txid hex → jenis pendanaan). Pola sama seperti
/// [PaymentNoteStore]: fail-open, kegagalan tulis ditelan —
/// label adalah lapisan tampilan detail, bukan data dana.
///
/// Mengapa dicatat, bukan dibaca dari node setiap kali:
/// korelasi txid ↔ channel hanya bisa dibuktikan selama
/// channel-nya masih terdaftar di node. Begitu channel ditutup
/// dan hilang dari daftar, kiriman pendanaannya di riwayat
/// tidak lagi bisa dicocokkan — kecuali pasangannya sudah
/// disimpan saat pertama kali terlihat.
class ChannelFundingLabelStore {
  static const String storageKey = 'channel_funding_labels_v1';

  /// Batas simpanan: label terlama terbuang lebih dulu (pola
  /// sama seperti PaymentNoteStore.maxKeep). Satu entri per
  /// channel yang pernah didanai node ini — 500 jauh di atas
  /// pola pakai dompet pribadi.
  static const int maxKeep = 500;

  /// Muat seluruh label (peta txid hex → jenis pendanaan).
  Future<Map<String, String>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodePaymentNotes(prefs.getString(storageKey));
    } catch (_) {
      return <String, String>{};
    }
  }

  /// Simpan (atau perbarui) jenis pendanaan untuk [txid].
  ///
  /// Txid bukan 64 karakter atau jenis di luar yang dikenal
  /// tidak disimpan. Entri yang diperbarui pindah ke posisi
  /// terbaru supaya pemotongan [maxKeep] membuang yang
  /// benar-benar paling lama tidak tersentuh.
  Future<void> save(String txid, String kind) async {
    if (txid.length != 64) return;
    if (kind != fundingKindLsp && kind != fundingKindDirect) return;
    try {
      final labels = await loadAll();
      labels.remove(txid);
      labels[txid] = kind;
      while (labels.length > maxKeep) {
        labels.remove(labels.keys.first);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encodePaymentNotes(labels));
    } catch (_) {
      // Gagal simpan = detail kiriman ini tampil on-chain
      // polos, seperti sebelum fitur ini ada.
    }
  }

  /// Simpan sekumpulan pasangan txid → jenis dalam satu kali
  /// baca-tulis (dipakai penyegaran riwayat yang mencocokkan
  /// banyak kiriman sekaligus). Entri yang tidak sah (txid
  /// bukan 64 karakter / jenis tidak dikenal) dibuang satu per
  /// satu, bukan menggagalkan sisanya.
  Future<void> saveAll(Map<String, String> entries) async {
    final valid = <String, String>{};
    for (final entry in entries.entries) {
      if (entry.key.length != 64) continue;
      if (entry.value != fundingKindLsp && entry.value != fundingKindDirect) {
        continue;
      }
      valid[entry.key] = entry.value;
    }
    if (valid.isEmpty) return;
    try {
      final labels = await loadAll();
      for (final entry in valid.entries) {
        labels.remove(entry.key);
        labels[entry.key] = entry.value;
      }
      while (labels.length > maxKeep) {
        labels.remove(labels.keys.first);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encodePaymentNotes(labels));
    } catch (_) {
      // Sama seperti save: gagal simpan hanya menghilangkan
      // label detail, bukan dana.
    }
  }
}
