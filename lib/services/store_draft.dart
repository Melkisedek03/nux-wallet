import 'dart:convert';

import '../utils/store_mode_logic.dart';
import 'store_database.dart';
import 'store_hold.dart';

/// Draf pesanan Mode Toko — jaring pengaman background
/// (temuan NUX 4 Nov 2026).
///
/// Bila aplikasi masuk background (tombol Home tertekan tak
/// sengaja) atau prosesnya dibunuh sistem selagi kasir menyusun
/// pesanan, pesanan berjalan tidak boleh hilang: layar Mode
/// Toko menyalinnya ke slot draf TUNGGAL ini. Saat Mode Toko
/// dibuka lagi dengan pesanan berjalan kosong, draf dipulihkan
/// persis seperti semula (baris + qty + diskon baris + catatan
/// + diskon order) lalu slotnya dikosongkan.
///
/// Draf TERPISAH dari daftar Ditahan (store_hold.dart): Ditahan
/// adalah parkir yang disengaja kasir untuk tamu yang bayar
/// belakangan; draf adalah salinan darurat otomatis yang tidak
/// pernah tampil sebagai entri Ditahan.
///
/// Serialisasinya memakai bentuk yang sama persis dengan entri
/// tahan ([HeldOrder.toJson] / [HeldOrder.fromJson]) — satu
/// format pesanan terparkir untuk seluruh Mode Toko.
String encodeDraftOrder(HeldOrder draft) => jsonEncode(draft.toJson());

/// Baca draf dari string simpanan; null bila slot kosong atau
/// isinya tidak sah (fail-closed: draf rusak tidak dipulihkan
/// menjadi pesanan yang salah).
HeldOrder? decodeDraftOrder(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  return HeldOrder.fromJson(parsed);
}

/// Penyimpanan slot draf di SQLite (store_pos.db, tabel
/// store_kv — draf adalah snapshot JSON murni, bentuk
/// simpanannya tidak berubah dari era SharedPreferences).
/// Semua operasi fail-open seperti penyimpanan lokal Mode Toko
/// lain: draf adalah jaring pengaman, kegagalannya tidak boleh
/// menjatuhkan layar kasir.
class StoreDraftStore {
  static const String storageKey = 'store_draft_order_v1';

  StoreDraftStore({StoreDatabase? database})
    : _database = database ?? StoreDatabase.instance;

  final StoreDatabase _database;

  /// Simpan [lines] + [orderDiscount] sebagai draf (menimpa
  /// draf sebelumnya — hanya draf terakhir yang berlaku).
  /// Pesanan kosong tidak pernah menjadi draf.
  Future<void> save({
    required List<OrderLine> lines,
    required Discount? orderDiscount,
  }) async {
    if (lines.isEmpty) return;
    try {
      final draft = buildHeldOrder(
        now: DateTime.now(),
        lines: lines,
        orderDiscount: orderDiscount,
      );
      final db = await _database.database;
      await storeKvSet(db, storageKey, encodeDraftOrder(draft));
    } catch (_) {
      // Abaikan — jaring pengaman tidak boleh mengganggu kasir.
    }
  }

  /// Muat draf tersimpan; null bila tidak ada / tidak sah.
  Future<HeldOrder?> load() async {
    try {
      final db = await _database.database;
      return decodeDraftOrder(await storeKvGet(db, storageKey));
    } catch (_) {
      return null;
    }
  }

  /// Kosongkan slot draf — dipanggil sesudah draf dipulihkan,
  /// dan setiap kali pesanan berjalan berakhir dengan disengaja
  /// (lunas, dibatalkan, ditahan) supaya tidak ada pemulihan
  /// hantu di kunjungan berikutnya.
  Future<void> clear() async {
    try {
      final db = await _database.database;
      await storeKvDelete(db, storageKey);
    } catch (_) {
      // Abaikan — sama seperti di atas.
    }
  }
}
