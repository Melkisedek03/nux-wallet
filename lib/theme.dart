import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Palet semantik ELNUX — satu sumber warna untuk tema gelap & terang.
///
/// Nilai gelap = tampilan lama aplikasi persis (tidak diubah), nilai
/// terang = padanannya di latar terang. Aksen hijau, merah, dan kuning
/// pekat sengaja TIDAK masuk palet: warnanya sama di kedua tema.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  /// Latar scaffold.
  final Color background;

  /// Permukaan kartu utama (dialog, kartu daftar, baris pengaturan).
  final Color card;

  /// Permukaan kartu sekunder (kotak input, kotak ikon, chip).
  final Color cardAlt;

  /// Teks utama yang sebelumnya hardcode (label, isi).
  final Color label;

  /// Teks sekunder (sapaan header, keterangan).
  final Color secondary;

  /// Teks redup (sublabel, keterangan kecil).
  final Color muted;

  /// Teks paling redup (tab non-aktif).
  final Color faint;

  /// Teks redup lain (status non-aktif).
  final Color dim;

  /// Garis batas tipis kartu.
  final Color border;

  /// Latar lembut (kotak ikon transaksi keluar, pil tab non-aktif).
  final Color softBg;

  /// Warna placeholder input.
  final Color hint;

  /// Teks peringatan di atas latar kuning (judul kartu legacy).
  final Color warningText;

  /// Ikon peringatan (kuning).
  final Color warningIcon;

  /// Teks bahaya yang lembut (status gagal).
  final Color dangerSoft;

  const AppPalette({
    required this.background,
    required this.card,
    required this.cardAlt,
    required this.label,
    required this.secondary,
    required this.muted,
    required this.faint,
    required this.dim,
    required this.border,
    required this.softBg,
    required this.hint,
    required this.warningText,
    required this.warningIcon,
    required this.dangerSoft,
  });

  /// Tema gelap — warna lama aplikasi, tidak diubah.
  static const dark = AppPalette(
    background: Color(0xFF0B0E0C),
    card: Color(0xFF101412),
    cardAlt: Color(0xFF121715),
    label: Color(0xFFB8C8BF),
    secondary: Color(0xFF8A9A90),
    muted: Color(0xFF7D8F86),
    faint: Color(0xFF6B7D73),
    dim: Color(0xFF9AA8A0),
    border: Color(0x0FFFFFFF),
    softBg: Color(0x14FFFFFF),
    hint: Color(0x33FFFFFF),
    warningText: Color(0xFFFDE68A),
    warningIcon: Color(0xFFFBBF24),
    dangerSoft: Color(0xFFF87171),
  );

  /// Tema terang — padanan terang dari setiap peran di atas.
  static const light = AppPalette(
    background: Color(0xFFF4F7F5),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFEDF1EE),
    label: Color(0xFF2E3B33),
    secondary: Color(0xFF5B6B61),
    muted: Color(0xFF75857B),
    faint: Color(0xFF8A9890),
    dim: Color(0xFF9AA89F),
    border: Color(0x14000000),
    softBg: Color(0x0D000000),
    hint: Color(0x40000000),
    warningText: Color(0xFF92400E),
    warningIcon: Color(0xFFD97706),
    dangerSoft: Color(0xFFDC2626),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? card,
    Color? cardAlt,
    Color? label,
    Color? secondary,
    Color? muted,
    Color? faint,
    Color? dim,
    Color? border,
    Color? softBg,
    Color? hint,
    Color? warningText,
    Color? warningIcon,
    Color? dangerSoft,
  }) {
    return AppPalette(
      background: background ?? this.background,
      card: card ?? this.card,
      cardAlt: cardAlt ?? this.cardAlt,
      label: label ?? this.label,
      secondary: secondary ?? this.secondary,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      dim: dim ?? this.dim,
      border: border ?? this.border,
      softBg: softBg ?? this.softBg,
      hint: hint ?? this.hint,
      warningText: warningText ?? this.warningText,
      warningIcon: warningIcon ?? this.warningIcon,
      dangerSoft: dangerSoft ?? this.dangerSoft,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardAlt: Color.lerp(cardAlt, other.cardAlt, t)!,
      label: Color.lerp(label, other.label, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
      border: Color.lerp(border, other.border, t)!,
      softBg: Color.lerp(softBg, other.softBg, t)!,
      hint: Color.lerp(hint, other.hint, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      warningIcon: Color.lerp(warningIcon, other.warningIcon, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
    );
  }
}

/// Akses palet dari BuildContext mana pun di bawah MaterialApp:
/// `context.palette.card`.
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// Dua ThemeData aplikasi — aksen hijau emerald dipertahankan di
/// kedua tema; yang berubah hanya permukaan & teks lewat [AppPalette].
class AppTheme {
  /// Keluarga font aplikasi: Momo Trust Display (Google Fonts).
  /// Satu-satunya sumber nama keluarga — dipakai ThemeData dan
  /// teks brand splash screen.
  static const String fontFamily = 'Momo Trust Display';

  // Konstruktor ThemeData langsung (bukan ThemeData.dark()/light()
  // + copyWith): fontFamily hanya ada di konstruktor, dan kedua
  // factory itu sendiri hanyalah ThemeData(brightness: ...) —
  // jadi perilaku identik, font tinggal ditambahkan.
  static final darkTheme = ThemeData(
    brightness: Brightness.dark,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: AppPalette.dark.background,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF10B981),
      surface: Color(0xFF101412),
    ),
    appBarTheme: const AppBarTheme(elevation: 0),
    extensions: const [AppPalette.dark],
  );

  static final lightTheme = ThemeData(
    brightness: Brightness.light,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: AppPalette.light.background,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF10B981),
      surface: Color(0xFFFFFFFF),
    ),
    appBarTheme: const AppBarTheme(elevation: 0),
    extensions: const [AppPalette.light],
  );
}

/// Pengatur tema aplikasi: gelap default (sesuai selera NUX),
/// pilihan user disimpan di SharedPreferences dan bertahan
/// antar-buka aplikasi.
class ThemeController {
  static const _prefsKey = 'theme_mode';

  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier(ThemeMode.dark);

  /// Baca pilihan tersimpan sebelum aplikasi jalan (dipanggil di main).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      mode.value = raw == 'light' ? ThemeMode.light : ThemeMode.dark;
    } catch (_) {
      mode.value = ThemeMode.dark;
    }
  }

  static Future<void> setMode(ThemeMode next) async {
    mode.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, next == ThemeMode.light ? 'light' : 'dark');
    } catch (_) {
      // Pilihan tetap berlaku sesi ini; gagal simpan bukan fatal.
    }
  }

  static Future<void> toggle() => setMode(
      mode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}
