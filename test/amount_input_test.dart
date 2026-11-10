import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/utils/amount_input.dart';
import 'package:nux_wallet/utils/format.dart';

/// Ketik satu karakter di akhir nilai saat ini, melewati
/// pemformat — meniru edit IME sungguhan.
TextEditingValue _type(
  AmountInputFormatter f,
  TextEditingValue current,
  String ch,
) {
  final raw = current.text + ch;
  return f.formatEditUpdate(
    current,
    TextEditingValue(
      text: raw,
      selection: TextSelection.collapsed(offset: raw.length),
    ),
  );
}

TextEditingValue _typeAll(AmountInputFormatter f, String chars) {
  var v = const TextEditingValue(text: '');
  for (final ch in chars.split('')) {
    v = _type(f, v, ch);
  }
  return v;
}

void main() {
  const idFmt = AmountInputFormatter(thousandsSep: '.', decimalSep: ',');
  const enFmt = AmountInputFormatter(thousandsSep: ',', decimalSep: '.');

  group('AmountInputFormatter — locale id', () {
    test('digit dikelompokkan ribuan saat mengetik', () {
      expect(_typeAll(idFmt, '1000').text, '1.000');
      expect(_typeAll(idFmt, '1000000').text, '1.000.000');
      expect(_typeAll(idFmt, '25000').text, '25.000');
    });

    test("mengetik '.' tidak pernah menghasilkan titik desimal", () {
      // '.' pada locale id adalah pemisah ribuan tampilan; sebagai
      // ketikan ia dibuang — "0.5" tidak bisa terbentuk, tempat
      // desimal adalah ','.
      expect(_typeAll(idFmt, '0.5').text, '5');
      expect(_typeAll(idFmt, '12.').text, '12');
      expect(_typeAll(idFmt, '.').text, '');
    });

    test('koma adalah desimal dan dipertahankan', () {
      expect(_typeAll(idFmt, '0,5').text, '0,5');
      expect(_typeAll(idFmt, '1000,25').text, '1.000,25');
      // Koma kedua dibuang.
      expect(_typeAll(idFmt, '0,5,').text, '0,5');
    });

    test('huruf dibuang saat diketik', () {
      expect(_typeAll(idFmt, '10a0').text, '100');
    });

    test('nol di depan berlebih dibuang', () {
      expect(_typeAll(idFmt, '05').text, '5');
      expect(_typeAll(idFmt, '00').text, '0');
    });

    test('hasil format selalu lolos parser bersama (atau kosong)', () {
      for (final typed in ['1', '1000', '1000000', '0,5', '25,25']) {
        final text = _typeAll(idFmt, typed).text;
        expect(
          parseAmountInputToMsat(text, DisplayUnit.nux, locale: 'id'),
          isNotNull,
          reason: 'teks terformat "$text" harus terbaca parser',
        );
      }
    });
  });

  group('AmountInputFormatter — locale en (cermin)', () {
    test('digit dikelompokkan dengan koma', () {
      expect(_typeAll(enFmt, '1000000').text, '1,000,000');
    });

    test("mengetik ',' tidak berpengaruh, '.' adalah desimal", () {
      expect(_typeAll(enFmt, '1,000').text, '1,000');
      expect(_typeAll(enFmt, '0.5').text, '0.5');
      expect(_typeAll(enFmt, '0,5').text, '5');
    });

    test('hasil format lolos parser locale en', () {
      final text = _typeAll(enFmt, '1000000').text;
      expect(
        parseAmountInputToMsat(text, DisplayUnit.nusan, locale: 'en'),
        BigInt.from(1000000 * 1000),
      );
    });
  });
}
