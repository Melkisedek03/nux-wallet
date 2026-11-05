import 'package:flutter/services.dart';

/// Pemformat kolom nominal rupiah SAAT MENGETIK (on-the-fly):
/// digit yang diketik langsung dikelompokkan ribuan mengikuti
/// pemisah locale aplikasi (id '.' / en ','), supaya angka
/// besar terbaca jelas tanpa menunggu selesai (permintaan NUX
/// 5 Nov 2026 untuk kolom Uang Diterima & Modal). Format hanya
/// tampilan — nilai dibaca kembali dengan [parseRupiahAmount]
/// yang membuang semua non-digit.
class RupiahAmountFormatter extends TextInputFormatter {
  final String thousandsSep;

  const RupiahAmountFormatter({this.thousandsSep = '.'});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    // Buang nol di depan berlebih: "05000" → "5000", "0" tetap.
    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final buf = StringBuffer();
    for (var i = 0; i < trimmed.length; i++) {
      if (i > 0 && (trimmed.length - i) % 3 == 0) buf.write(thousandsSep);
      buf.write(trimmed[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Nilai rupiah dari teks kolom berformat ribuan (atau teks
/// angka polos): semua non-digit dibuang.
int parseRupiahAmount(String text) =>
    int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

/// Kelompokkan angka rupiah polos ke teks berformat ribuan —
/// pasangan tulis dari [parseRupiahAmount] untuk mengisi
/// kolom dari program (chip pecahan, tombol Uang Pas, Max).
String formatRupiahInput(int value, {String thousandsSep = '.'}) {
  final digits = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(thousandsSep);
    buf.write(digits[i]);
  }
  return buf.toString();
}
