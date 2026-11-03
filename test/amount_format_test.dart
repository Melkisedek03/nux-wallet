import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/unit_controller.dart';
import 'package:nux_wallet/utils/format.dart';
import 'package:shared_preferences/shared_preferences.dart';

BigInt msat(int v) => BigInt.from(v);

void main() {
  group('formatAmountNumber — mode nusan', () {
    test('bulat tanpa desimal, pemisah ribuan id', () {
      expect(formatAmountNumber(msat(5000000), DisplayUnit.nusan), '5.000');
      expect(formatAmountNumber(msat(1000), DisplayUnit.nusan), '1');
      expect(formatAmountNumber(BigInt.zero, DisplayUnit.nusan), '0');
    });

    test('pecahan msat sampai 3 desimal, nol belakang dipangkas', () {
      // 1.234 nusan = 1234 msat.
      expect(formatAmountNumber(msat(1234), DisplayUnit.nusan), '1,234');
      // 1.250 nusan -> "1,25".
      expect(formatAmountNumber(msat(1250), DisplayUnit.nusan), '1,25');
      // 0.001 nusan = 1 msat.
      expect(formatAmountNumber(msat(1), DisplayUnit.nusan), '0,001');
      // 999.999 nusan.
      expect(formatAmountNumber(msat(999999), DisplayUnit.nusan), '999,999');
    });

    test('pemisah mengikuti locale en', () {
      expect(formatAmountNumber(msat(1234567), DisplayUnit.nusan,
          locale: 'en'), '1,234.567');
      expect(formatAmountNumber(msat(5000000), DisplayUnit.nusan,
          locale: 'en'), '5,000');
    });

    test('nilai besar & negatif', () {
      expect(formatAmountNumber(msat(1234567890123), DisplayUnit.nusan),
          '1.234.567.890,123');
      expect(formatAmountNumber(msat(-1500), DisplayUnit.nusan), '-1,5');
    });
  });

  group('formatAmountNumber — mode NUX', () {
    test('1 NUX penuh = 100.000.000 nusan', () {
      expect(formatAmountNumber(msat(100000000000), DisplayUnit.nux), '1');
      expect(formatAmountNumber(msat(200000000000), DisplayUnit.nux), '2');
    });

    test('pecahan nusan menjadi desimal NUX (<= 8 desimal)', () {
      // 1 nusan = 0,00000001 NUX.
      expect(formatAmountNumber(msat(1000), DisplayUnit.nux), '0,00000001');
      // 150.000 nusan = 0,0015 NUX.
      expect(formatAmountNumber(msat(150000000), DisplayUnit.nux), '0,0015');
      // 1.234.567 nusan = 0,01234567 NUX.
      expect(
          formatAmountNumber(msat(1234567000), DisplayUnit.nux), '0,01234567');
    });

    test('presisi msat tetap eksak di bawah 1 nusan', () {
      // 1 msat = 0,00000000001 NUX (11 desimal) — tidak dibulatkan.
      expect(formatAmountNumber(msat(1), DisplayUnit.nux), '0,00000000001');
      // 500 msat = 0,5 nusan.
      expect(formatAmountNumber(msat(500), DisplayUnit.nux), '0,000000005');
    });

    test('pemisah ribuan bagian bulat + locale en', () {
      // 1.234,5 NUX.
      expect(formatAmountNumber(msat(123450000000000), DisplayUnit.nux),
          '1.234,5');
      expect(formatAmountNumber(msat(123450000000000), DisplayUnit.nux,
          locale: 'en'), '1,234.5');
    });
  });

  group('formatAmountWithUnit & konversi', () {
    test('label satuan menempel', () {
      expect(formatAmountWithUnit(msat(5000000), DisplayUnit.nusan),
          '5.000 nusan');
      expect(formatAmountWithUnit(msat(100000000000), DisplayUnit.nux),
          '1 NUX');
    });

    test('konversi selalu ke satuan lawan', () {
      expect(formatAmountConversion(msat(100000000), DisplayUnit.nusan),
          '≈ 0,001 NUX');
      expect(formatAmountConversion(msat(100000000000), DisplayUnit.nux),
          '≈ 100.000.000 nusan');
    });
  });

  group('parseAmountInputToMsat — nusan', () {
    test('bulat & berkelompok', () {
      expect(parseAmountInputToMsat('5000', DisplayUnit.nusan),
          msat(5000000));
      expect(parseAmountInputToMsat('5.000', DisplayUnit.nusan),
          msat(5000000));
      expect(parseAmountInputToMsat(' 250 ', DisplayUnit.nusan), msat(250000));
      expect(parseAmountInputToMsat('1.234.567', DisplayUnit.nusan),
          msat(1234567000));
    });

    test('desimal koma sampai 3 tempat', () {
      expect(parseAmountInputToMsat('1,5', DisplayUnit.nusan), msat(1500));
      expect(parseAmountInputToMsat('1,234', DisplayUnit.nusan), msat(1234));
      expect(parseAmountInputToMsat('0,001', DisplayUnit.nusan), msat(1));
    });

    test('locale en: koma ribuan, titik desimal', () {
      expect(parseAmountInputToMsat('5,000', DisplayUnit.nusan, locale: 'en'),
          msat(5000000));
      expect(parseAmountInputToMsat('1.5', DisplayUnit.nusan, locale: 'en'),
          msat(1500));
      expect(
          parseAmountInputToMsat('1,234.567', DisplayUnit.nusan, locale: 'en'),
          msat(1234567));
    });

    test('menolak nilai tak sah', () {
      for (final bad in [
        '',
        '0',
        '0,0',
        '-5',
        'abc',
        '1,2345', // 4 desimal nusan
        '12.34', // kelompok ribuan tak sah di locale id
        '1.5', // '.' bukan desimal di locale id; kelompok tak sah
        '1..000',
        '1,2,3',
        ',5',
        '5,',
      ]) {
        expect(parseAmountInputToMsat(bad, DisplayUnit.nusan), isNull,
            reason: bad);
      }
    });
  });

  group('parseAmountInputToMsat — NUX', () {
    test('bulat & pecahan sampai 8 desimal', () {
      expect(parseAmountInputToMsat('1', DisplayUnit.nux),
          msat(100000000000));
      expect(parseAmountInputToMsat('0,001', DisplayUnit.nux),
          msat(100000000));
      expect(parseAmountInputToMsat('0,00000001', DisplayUnit.nux),
          msat(1000));
      expect(parseAmountInputToMsat('1,5', DisplayUnit.nux),
          msat(150000000000));
      expect(parseAmountInputToMsat('2.500,25', DisplayUnit.nux),
          msat(250025000000000));
    });

    test('locale en', () {
      expect(parseAmountInputToMsat('1.5', DisplayUnit.nux, locale: 'en'),
          msat(150000000000));
      expect(
          parseAmountInputToMsat('2,500.25', DisplayUnit.nux, locale: 'en'),
          msat(250025000000000));
    });

    test('menolak lebih dari 8 desimal & nilai tak sah', () {
      expect(parseAmountInputToMsat('0,000000001', DisplayUnit.nux), isNull);
      expect(parseAmountInputToMsat('0', DisplayUnit.nux), isNull);
      expect(parseAmountInputToMsat('-1', DisplayUnit.nux), isNull);
      expect(parseAmountInputToMsat('satu', DisplayUnit.nux), isNull);
    });
  });

  group('dwiarah format <-> parse', () {
    test('mode nusan: semua nilai msat pulang-pergi di kedua locale', () {
      final samples = [
        msat(1000),
        msat(1234),
        msat(5000000),
        msat(999999),
        msat(1234567000),
        msat(100000000000),
        msat(250025000000000),
      ];
      for (final v in samples) {
        for (final locale in ['id', 'en']) {
          final text = formatAmountNumber(v, DisplayUnit.nusan, locale: locale);
          expect(
              parseAmountInputToMsat(text, DisplayUnit.nusan, locale: locale),
              v,
              reason: '$text (nusan, $locale)');
        }
      }
    });

    test('mode NUX: nilai bulat-nusan pulang-pergi; sub-nusan tidak '
        '(parser NUX dibatasi 8 desimal sesuai spesifikasi)', () {
      final wholeNusan = [
        msat(1000),
        msat(5000000),
        msat(1234567000),
        msat(100000000000),
        msat(250025000000000),
      ];
      for (final v in wholeNusan) {
        for (final locale in ['id', 'en']) {
          final text = formatAmountNumber(v, DisplayUnit.nux, locale: locale);
          expect(parseAmountInputToMsat(text, DisplayUnit.nux, locale: locale),
              v,
              reason: '$text (NUX, $locale)');
        }
      }
      // 1.234 nusan tampil eksak 11 desimal di NUX, tetapi parser
      // menolaknya — presisi isian NUX memang dibatasi di nusan.
      final sub = formatAmountNumber(msat(1234), DisplayUnit.nux);
      expect(parseAmountInputToMsat(sub, DisplayUnit.nux), isNull);
    });
  });

  group('UnitController', () {
    test('bawaan nusan; tersimpan nux terbaca kembali', () async {
      SharedPreferences.setMockInitialValues({});
      await UnitController.load();
      expect(UnitController.unit.value, DisplayUnit.nusan);

      await UnitController.setUnit(DisplayUnit.nux);
      expect(UnitController.unit.value, DisplayUnit.nux);

      // Nilai benar-benar tersimpan: muat ulang dari prefs yang sama.
      UnitController.unit.value = DisplayUnit.nusan;
      await UnitController.load();
      expect(UnitController.unit.value, DisplayUnit.nux);

      // Kembalikan ke bawaan supaya test lain tak terpengaruh.
      await UnitController.setUnit(DisplayUnit.nusan);
    });

    test('nilai simpanan tak dikenal jatuh ke nusan', () async {
      SharedPreferences.setMockInitialValues({'display_unit': 'aneh'});
      await UnitController.load();
      expect(UnitController.unit.value, DisplayUnit.nusan);
    });
  });
}
