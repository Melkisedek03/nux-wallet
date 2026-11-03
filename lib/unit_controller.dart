import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/format.dart';

/// Pengatur satuan tampilan jumlah dompet: NUX atau nusan.
///
/// Satu saklar global di Profil, berlaku di seluruh aplikasi
/// dompet (saldo, kirim, terima, riwayat) — pola yang sama
/// persis dengan [LocaleController] & ThemeController: nilai
/// static ValueNotifier, dimuat sebelum aplikasi jalan, disimpan
/// di SharedPreferences.
///
/// Bawaan = nusan (perilaku aplikasi selama ini; pengguna yang
/// tidak menyentuh saklar tidak melihat perubahan apa pun).
/// Nilai yang disimpan & dihitung aplikasi tetap msat — satuan
/// ini murni lapisan tampilan. Mode Toko TIDAK membaca pengatur
/// ini: jumlah poin di sana selalu nusan.
class UnitController {
  static const _prefsKey = 'display_unit';

  static final ValueNotifier<DisplayUnit> unit =
      ValueNotifier(DisplayUnit.nusan);

  /// Baca pilihan tersimpan sebelum aplikasi jalan (dipanggil di main).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      unit.value = prefs.getString(_prefsKey) == 'nux'
          ? DisplayUnit.nux
          : DisplayUnit.nusan;
    } catch (_) {
      unit.value = DisplayUnit.nusan;
    }
  }

  static Future<void> setUnit(DisplayUnit next) async {
    unit.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, next.name);
    } catch (_) {
      // Pilihan tetap berlaku sesi ini; gagal simpan bukan fatal.
    }
  }
}

/// Akses cepat pemformat jumlah dompet dari BuildContext mana
/// pun: membaca satuan aktif + locale aplikasi saat build.
/// MaterialApp dibangun ulang saat satuan berubah (UnitController
/// ikut di Listenable.merge akar aplikasi), jadi semua permukaan
/// menyegarkan tampilannya sendiri.
extension WalletAmountContext on BuildContext {
  DisplayUnit get displayUnit => UnitController.unit.value;

  String get _amountLocale => Localizations.localeOf(this).languageCode;

  /// Angka + label satuan aktif, mis. "1.234,5 nusan".
  String formatWalletAmount(BigInt msat) =>
      formatAmountWithUnit(msat, displayUnit, locale: _amountLocale);

  /// Angka saja dalam satuan aktif (label digambar terpisah).
  String formatWalletAmountNumber(BigInt msat) =>
      formatAmountNumber(msat, displayUnit, locale: _amountLocale);

  /// Baris konversi "≈ …" dalam satuan lawan dari satuan aktif.
  String formatWalletConversion(BigInt msat) =>
      formatAmountConversion(msat, displayUnit, locale: _amountLocale);
}
