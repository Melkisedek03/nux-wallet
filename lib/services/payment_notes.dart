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
