import 'package:shared_preferences/shared_preferences.dart';

/// Alamat deposit on-chain yang sedang ditampilkan di layar Dompet
/// On-chain — tersimpan supaya TIDAK dibuat baru tiap kali layar
/// dibuka (keputusan NUX 15 Nov 2026: alamat baru hanya bila user
/// menekan tombol Refresh; keputusan di tangan user).
///
/// Disimpan bersama ID node pemiliknya: alamat diturunkan dari seed
/// dompet, jadi bila dompet dipulihkan dari frasa lain / profil
/// jaringan berganti (ID node berubah), simpanan lama TIDAK berlaku
/// lagi dan alamat baru dibuat sekali — dana yang telanjur dikirim
/// ke alamat dompet lain tidak akan masuk dompet ini.
class OnchainAddressStore {
  static const String addressKey = 'onchain_current_address';
  static const String nodeIdKey = 'onchain_current_address_node';

  /// Alamat tersimpan untuk dompet [nodeId]; null bila belum ada
  /// atau simpanan milik dompet lain.
  Future<String?> load({required String nodeId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedNode = prefs.getString(nodeIdKey);
      if (storedNode == null || storedNode != nodeId) return null;
      final address = prefs.getString(addressKey)?.trim();
      return (address == null || address.isEmpty) ? null : address;
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required String address,
    required String nodeId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(addressKey, address.trim());
      await prefs.setString(nodeIdKey, nodeId);
    } catch (_) {
      // Simpanan gagal — alamat tetap tampil di layar ini;
      // kunjungan berikutnya akan membuat yang baru (perilaku lama).
    }
  }
}
