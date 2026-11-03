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
