import 'dart:convert';

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

/// Tag baris riwayat dari jenis pembayaran + tag rute tercatat.
///
/// JIT dan on-chain dibaca dari jenis pembayaran node (persis);
/// tag rute lokal hanya mengisi sisanya — pembayaran Lightning
/// biasa yang tercatat berjalan lewat channel langsung. Urutan
/// ini penting: pembayaran JIT menurut definisinya lahir dari
/// LSP, tidak pernah langsung; on-chain bukan Lightning.
String historyRowTag({
  required bool isJit,
  required bool isOnchain,
  required String? routeTag,
}) {
  if (isJit) return '⚡ JIT';
  if (isOnchain) return '⛓ on-chain';
  if (routeTag == paymentTagDirect) return '⚡ direct';
  return '⚡';
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
