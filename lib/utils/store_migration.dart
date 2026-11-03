/// Keputusan migrasi Mode Toko v1 (kasir nusan) → v2 (kasir
/// rupiah), dijalankan SATU KALI pada jalan pertama v2.
///
/// Rancangan §7 yang diputuskan: era tidak dicampur. Shift v1
/// yang masih terbuka ditutup paksa (bertanda era lama di
/// simpanannya); pesanan ditahan v1 GUGUR (harganya nusan —
/// melanjutkannya ke kasir rupiah akan mengarang nilai); katalog
/// v1 tidak dipakai (store v2 mulai kosong, kasir mengisi ulang
/// dengan harga rupiah). Riwayat penjualan v1 TIDAK disentuh:
/// ia tetap arsip dan hanya tidak dibaca agregasi v2.
///
/// Fungsi perencanaan di sini MURNI supaya keputusannya teruji;
/// layar yang mengeksekusi (menutup shift, mengosongkan daftar
/// tahan v1, menampilkan satu dialog pemberitahuan).
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Rencana migrasi satu kali: apa yang harus dilakukan layar
/// pada jalan pertama v2.
class StoreMigrationPlan {
  /// Ada shift era nusan yang masih terbuka → tutup paksa.
  final bool closeOpenLegacyShift;

  /// Jumlah pesanan ditahan v1 yang gugur (disebut jujur di
  /// dialog pemberitahuan; 0 = tidak ada yang gugur).
  final int droppedHeldOrders;

  /// Katalog v1 tidak kosong → kasir perlu tahu katalog v2
  /// mulai kosong dan harga harus diisi ulang dalam rupiah.
  final bool catalogNeedsRefill;

  const StoreMigrationPlan({
    this.closeOpenLegacyShift = false,
    this.droppedHeldOrders = 0,
    this.catalogNeedsRefill = false,
  });

  static const none = StoreMigrationPlan();

  /// Apakah ada tindakan/pemberitahuan yang perlu ditampilkan?
  /// (Penutupan shift sendiri senyap — yang diberitahukan ke
  /// kasir adalah yang berdampak ke pekerjaannya: pesanan
  /// ditahan yang gugur dan katalog yang perlu diisi ulang.
  /// Tetapi dialog hanya pantas tampil bila migrasi sungguh
  /// melakukan sesuatu.)
  bool get hasActions =>
      closeOpenLegacyShift || droppedHeldOrders > 0 || catalogNeedsRefill;

  bool get hasNotices => droppedHeldOrders > 0 || catalogNeedsRefill;

  @override
  bool operator ==(Object other) =>
      other is StoreMigrationPlan &&
      other.closeOpenLegacyShift == closeOpenLegacyShift &&
      other.droppedHeldOrders == droppedHeldOrders &&
      other.catalogNeedsRefill == catalogNeedsRefill;

  @override
  int get hashCode =>
      Object.hash(closeOpenLegacyShift, droppedHeldOrders, catalogNeedsRefill);
}

/// Susun rencana migrasi dari keadaan simpanan v1. Migrasi yang
/// sudah pernah jalan ([alreadyDone]) tidak pernah mengulang —
/// rencana kosong apa pun keadaan v1 yang tertinggal.
StoreMigrationPlan planStoreMigration({
  required bool alreadyDone,
  required bool hasOpenLegacyShift,
  required int legacyHeldCount,
  required bool legacyCatalogNonEmpty,
}) {
  if (alreadyDone) return StoreMigrationPlan.none;
  return StoreMigrationPlan(
    closeOpenLegacyShift: hasOpenLegacyShift,
    droppedHeldOrders: legacyHeldCount < 0 ? 0 : legacyHeldCount,
    catalogNeedsRefill: legacyCatalogNonEmpty,
  );
}

/// Penanda "migrasi v2 sudah jalan" di SharedPreferences —
/// terpisah dari store data mana pun supaya eksekusi migrasi
/// idempoten walau aplikasi mati di tengah jalan pertama.
class StoreMigrationFlagStore {
  static const String storageKey = 'store_v2_migration_done';

  Future<bool> isDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(storageKey) ?? false;
    } catch (_) {
      // Gagal baca = anggap SUDAH jalan: lebih aman tidak
      // menjalankan migrasi destruktif dua kali daripada
      // mengulanginya karena kegagalan baca sesaat.
      return true;
    }
  }

  Future<void> markDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(storageKey, true);
    } catch (_) {
      // Abaikan — jalan berikut akan merencanakan ulang dari
      // keadaan simpanan yang sudah termigrasi (yang secara
      // alami menghasilkan rencana yang lebih kecil/kosong).
    }
  }
}
