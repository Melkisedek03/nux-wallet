import 'package:flutter/services.dart';

/// Pemformat kolom nominal bersama (Terima & kolom nominal
/// Bolt12 di Kirim): terapkan pemisah ribuan secara langsung
/// saat user mengetik, supaya tampilan selalu rapi — bukan
/// hanya saat nilai diisi program. Pemisah mengikuti locale
/// aplikasi (id: '.' ribuan & ',' desimal; en sebaliknya) —
/// pasangan pemisah yang sama dengan parser terpusat
/// `parseAmountInputToMsat`. Format hanya tampilan: nilai
/// angka murninya dipulihkan saat parsing oleh pemanggil.
///
/// Konsekuensi on-the-fly yang disengaja (permintaan NUX
/// 10 Nov 2026 untuk kolom nominal Bolt12 di Kirim, menyamai
/// perilaku kolom Terima yang lebih dulu ada): karakter selain
/// digit dan pemisah desimal dibuang saat itu juga — jadi pada
/// locale id tanda '.' tidak pernah bisa diketik sebagai
/// desimal (tempatnya ','), dan mengetik pemisah ribuan dengan
/// tangan tidak berpengaruh karena pengelompokan digambar
/// ulang dari digitnya. Pecahan TIDAK dipotong di sini: batas
/// presisi satuan ditegakkan parser saat pembayaran/pembuatan
/// invoice, jadi pemformat tidak pernah diam-diam mengubah
/// angka yang diketik user.
///
/// Diekstrak dari pemformat privat layar Terima
/// (_ThousandsSeparatorFormatter) supaya kedua kolom nominal
/// berperilaku identik dan tidak saling menyimpang.
class AmountInputFormatter extends TextInputFormatter {
  final String thousandsSep;
  final String decimalSep;

  const AmountInputFormatter({
    this.thousandsSep = '.',
    this.decimalSep = ',',
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.isEmpty) return newValue;

    // Pisah bagian bulat dan pecahan pada pemisah desimal
    // pertama; selain digit dibuang (termasuk pemisah ribuan
    // lama).
    final comma = raw.indexOf(decimalSep);
    var intDigits = (comma >= 0 ? raw.substring(0, comma) : raw)
        .replaceAll(RegExp(r'[^0-9]'), '');
    final fracDigits = comma >= 0
        ? raw.substring(comma + 1).replaceAll(RegExp(r'[^0-9]'), '')
        : null;

    // Buang nol di depan yang berlebih: "05" -> "5", "00" -> "0".
    intDigits = intDigits.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    // Kelompokkan ribuan dengan pemisah locale.
    final buf = StringBuffer();
    for (var i = 0; i < intDigits.length; i++) {
      if (i > 0 && (intDigits.length - i) % 3 == 0) buf.write(thousandsSep);
      buf.write(intDigits[i]);
    }
    var text = buf.toString();
    if (fracDigits != null) text = '$text$decimalSep$fracDigits';

    // Kursor selalu di akhir teks hasil format.
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
