/// Simpanan persetujuan kebijakan privasi (sekali per pemasangan).
///
/// Dicentang user di layar persetujuan sesudah instalasi — centangan
/// itu sendiri baru aktif sesudah user menggulir kebijakan sampai bawah
/// (lihat lib/screens/privacy_policy_screen.dart). Sesudah tercatat,
/// gerbang persetujuan tidak tampil lagi.
///
/// Fail-open mengikuti konvensi simpanan lain di aplikasi: bila baca
/// gagal, dianggap belum menyetujui (gerbang tampil sekali — user tetap
/// bisa melanjutkan sesudah mencentang); bila tulis gagal, kegagalan
/// ditelan (gerbang mungkin tampil lagi saat buka berikutnya, bukan
/// macet).
library;

import 'package:shared_preferences/shared_preferences.dart';

class PrivacyConsentStore {
  /// Kunci SharedPreferences — berversi supaya revisi kebijakan besar
  /// di masa depan bisa meminta persetujuan ulang dengan kunci baru.
  static const key = 'privacy_policy_accepted_v1';

  static Future<bool> isAccepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAccepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, true);
    } catch (_) {
      // Ditelan — lihat catatan fail-open di atas.
    }
  }
}
