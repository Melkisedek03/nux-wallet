/// Format nominal Lightning untuk tampilan.
///
/// Nilai sumber selalu msat (millisatoshi versi Nusacoin). Satuan
/// tampilan utama adalah nusan (1 nusan = 1000 msat), dengan pemisah
/// ribuan gaya id_ID ('.') dan desimal ',' bila ada sisa msat.
String formatNusan(BigInt msat) {
  final negative = msat < BigInt.zero;
  final abs = msat.abs();
  final whole = abs ~/ BigInt.from(1000);
  final rem = (abs % BigInt.from(1000)).toInt();

  final digits = whole.toString();
  final buf = StringBuffer();
  if (negative) buf.write('-');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  if (rem != 0) {
    var frac = rem.toString().padLeft(3, '0');
    while (frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    buf.write(',$frac');
  }
  return buf.toString();
}

/// Format nominal rupiah bulat untuk Mode Toko v2: pemisah
/// ribuan gaya id_ID ('.'), tanpa desimal (rupiah di Mode Toko
/// selalu bulat — tidak ada sen). Dipakai semua permukaan kasir
/// (katalog, keypad, struk, laporan) supaya satu angka selalu
/// tampil dengan cara yang sama.
String formatRupiah(int rp) {
  final negative = rp < 0;
  final digits = rp.abs().toString();
  final buf = StringBuffer();
  if (negative) buf.write('-');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Satuan tampilan jumlah Lightning di dompet (saklar global di
/// Profil). Nilai yang disimpan & dihitung aplikasi TIDAK pernah
/// berubah — sumber kebenaran tetap msat; satuan ini murni lapisan
/// tampilan (keputusan tim 3 Nov 2026).
enum DisplayUnit { nusan, nux }

extension DisplayUnitProps on DisplayUnit {
  /// Label satuan yang tampil di samping angka.
  String get label => this == DisplayUnit.nusan ? 'nusan' : 'NUX';

  /// Satuan lawannya — untuk baris konversi di kolom kirim.
  DisplayUnit get other =>
      this == DisplayUnit.nusan ? DisplayUnit.nux : DisplayUnit.nusan;

  /// Presisi desimal maksimum yang diterima parser isian dalam
  /// satuan ini: nusan dihitung dari msat (3 desimal), NUX dari
  /// nusan (8 desimal).
  int get maxFractionDigits => this == DisplayUnit.nusan ? 3 : 8;
}

/// Pasangan (pemisah ribuan, pemisah desimal) per locale aplikasi:
/// id → '.' & ','; en → ',' & '.'.
(String, String) _separators(String locale) =>
    locale == 'en' ? (',', '.') : ('.', ',');

/// Kelompokkan digit bilangan bulat dengan [sep] tiap tiga digit.
String _groupDigits(String digits, String sep) {
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(sep);
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Format angka [msat] dalam [unit] TANPA label satuan.
///
/// - nusan: pemisah ribuan per locale; pecahan dari sisa msat
///   tampil sampai 3 desimal bila ada (nol di belakang dipangkas),
///   tanpa desimal bila bulat — sama seperti [formatNusan] tetapi
///   pemisahnya mengikuti [locale].
/// - NUX: 1 NUX = 100.000.000 nusan = 100.000.000.000 msat;
///   pecahan tampil eksak sampai presisi msat (nilai berpresisi
///   nusan tidak pernah melewati 8 desimal), nol di belakang
///   dipangkas.
///
/// Semua hitung bilangan bulat/BigInt — tanpa floating point.
String formatAmountNumber(BigInt msat, DisplayUnit unit,
    {String locale = 'id'}) {
  final (thousandsSep, decimalSep) = _separators(locale);
  final negative = msat < BigInt.zero;
  final abs = msat.abs();
  final BigInt whole;
  final String fracDigits;
  if (unit == DisplayUnit.nusan) {
    whole = abs ~/ BigInt.from(1000);
    fracDigits = (abs % BigInt.from(1000)).toString().padLeft(3, '0');
  } else {
    whole = abs ~/ BigInt.from(100000000000);
    fracDigits =
        (abs % BigInt.from(100000000000)).toString().padLeft(11, '0');
  }
  var frac = fracDigits;
  while (frac.endsWith('0')) {
    frac = frac.substring(0, frac.length - 1);
  }
  final buf = StringBuffer();
  if (negative) buf.write('-');
  buf.write(_groupDigits(whole.toString(), thousandsSep));
  if (frac.isNotEmpty) buf.write('$decimalSep$frac');
  return buf.toString();
}

/// Format angka [msat] dalam [unit] DENGAN label satuannya,
/// mis. "1.234,5 nusan" atau "0,001 NUX".
String formatAmountWithUnit(BigInt msat, DisplayUnit unit,
        {String locale = 'id'}) =>
    '${formatAmountNumber(msat, unit, locale: locale)} ${unit.label}';

/// Baris konversi ke satuan lawan untuk kolom kirim:
/// "≈ 0,001 NUX" bila satuan aktif nusan, dan sebaliknya.
String formatAmountConversion(BigInt msat, DisplayUnit activeUnit,
        {String locale = 'id'}) =>
    '≈ ${formatAmountWithUnit(msat, activeUnit.other, locale: locale)}';

/// Parse teks isian nominal dalam [unit] menjadi msat eksak.
///
/// Aturan ketat (tanpa floating point): pemisah mengikuti
/// [locale] (id: '.' ribuan & ',' desimal; en sebaliknya);
/// pengelompokan ribuan harus sah (kelompok pertama 1–3 digit,
/// berikutnya tepat 3); pecahan tidak boleh melewati
/// [DisplayUnit.maxFractionDigits]. Nilai nol, negatif, kosong,
/// atau berhuruf → null (pemanggil menampilkannya sebagai nominal
/// tidak sah, sama seperti perilaku parser lama).
BigInt? parseAmountInputToMsat(String text, DisplayUnit unit,
    {String locale = 'id'}) {
  final (thousandsSep, decimalSep) = _separators(locale);
  final t = text.trim().replaceAll(' ', '');
  if (t.isEmpty) return null;

  final decIdx = t.indexOf(decimalSep);
  final String intPart;
  var fracPart = '';
  if (decIdx >= 0) {
    if (t.indexOf(decimalSep, decIdx + 1) >= 0) return null;
    intPart = t.substring(0, decIdx);
    fracPart = t.substring(decIdx + 1);
    if (fracPart.contains(thousandsSep)) return null;
    if (!RegExp(r'^\d+$').hasMatch(fracPart)) return null;
    if (fracPart.length > unit.maxFractionDigits) return null;
  } else {
    intPart = t;
  }

  final groups = intPart.split(thousandsSep);
  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    if (!RegExp(r'^\d+$').hasMatch(g)) return null;
    if (groups.length > 1) {
      if (i == 0) {
        if (g.length > 3) return null;
      } else if (g.length != 3) {
        return null;
      }
    }
  }
  final whole = BigInt.parse(groups.join());
  final BigInt msat;
  if (unit == DisplayUnit.nusan) {
    final fracMsat =
        fracPart.isEmpty ? BigInt.zero : BigInt.parse(fracPart.padRight(3, '0'));
    msat = whole * BigInt.from(1000) + fracMsat;
  } else {
    final fracNusan = fracPart.isEmpty
        ? BigInt.zero
        : BigInt.parse(fracPart.padRight(8, '0'));
    msat = (whole * BigInt.from(100000000) + fracNusan) * BigInt.from(1000);
  }
  return msat == BigInt.zero ? null : msat;
}

/// Format waktu transaksi untuk daftar aktivitas/riwayat.
///
/// Hari ini → jam 'HH.mm'; kemarin → 'Kemarin'/'Yesterday';
/// lebih lama → 'd MMM' dengan singkatan bulan sesuai [locale]
/// ('id' atau 'en'). [now] bisa diisi untuk pengujian.
String formatTxTime(DateTime time, {DateTime? now, String locale = 'id'}) {
  final ref = now ?? DateTime.now();
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(ref.year, ref.month, ref.day);
  final diffDays = today.difference(day).inDays;
  if (diffDays == 0) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh.$mm';
  }
  if (diffDays == 1) return locale == 'en' ? 'Yesterday' : 'Kemarin';
  const monthsId = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  const monthsEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final months = locale == 'en' ? monthsEn : monthsId;
  return '${time.day} ${months[time.month - 1]}';
}
