import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/market_info.dart';

/// Uji logika murni info pasar Jelajah: parse candle UDF qutrade
/// (termasuk respons no_data), parse kurs USDT/IDR Indodax, parse
/// tinggi blok electrs, dan hitungan perubahan 24 jam + harga IDR.
void main() {
  group('parseUdfCloses', () {
    test('respons ok menghasilkan deret penutupan berurutan', () {
      final closes = parseUdfCloses({
        's': 'ok',
        't': [1794009600, 1794096000],
        'o': [0.005019, 0.005107],
        'c': [0.005107, 0.005107],
        'h': [0.005154, 0.005107],
        'l': [0.005016, 0.005107],
        'v': [27726.86, 0],
      });
      expect(closes, [0.005107, 0.005107]);
    });

    test('no_data dan error menghasilkan daftar kosong', () {
      expect(parseUdfCloses({'s': 'no_data', 'nextTime': 1}), isEmpty);
      expect(parseUdfCloses({'s': 'error', 'errmsg': 'unknown'}), isEmpty);
      expect(parseUdfCloses(null), isEmpty);
      expect(parseUdfCloses('exit'), isEmpty);
    });

    test('panjang t dan c berbeda: diambil yang terpendek', () {
      final closes = parseUdfCloses({
        's': 'ok',
        't': [1, 2, 3],
        'c': [0.5, 0.6],
      });
      expect(closes, [0.5, 0.6]);
    });
  });

  group('parseUsdtIdrRate', () {
    test('ticker Indodax ter-parse dari string angka', () {
      expect(
        parseUsdtIdrRate({
          'ticker': {'last': '18054', 'buy': '18054', 'sell': '18055'}
        }),
        18054.0,
      );
    });

    test('bentuk tak dikenal menghasilkan null', () {
      expect(parseUsdtIdrRate(null), isNull);
      expect(parseUsdtIdrRate({'ticker': {}}), isNull);
      expect(parseUsdtIdrRate({'ticker': {'last': '0'}}), isNull);
      expect(parseUsdtIdrRate({'lain': 1}), isNull);
    });
  });

  group('parseTipHeight', () {
    test('teks angka ter-parse, sisanya null', () {
      expect(parseTipHeight('73675'), 73675);
      expect(parseTipHeight(' 73675\n'), 73675);
      expect(parseTipHeight(''), isNull);
      expect(parseTipHeight('error'), isNull);
    });
  });

  group('NuxMarketInfo', () {
    test('perubahan 24 jam dari dua penutupan terakhir', () {
      final info = NuxMarketInfo(
        lastUsdt: 0.0055,
        prevCloseUsdt: 0.0050,
        fetchedAt: DateTime(2026, 11, 8),
      );
      expect(info.changePct, closeTo(10.0, 0.0001));
    });

    test('tanpa penutupan sebelumnya perubahan null', () {
      final info = NuxMarketInfo(
        lastUsdt: 0.005107,
        fetchedAt: DateTime(2026, 11, 8),
      );
      expect(info.changePct, isNull);
    });

    test('harga IDR = harga USDT kali kurs', () {
      final info = NuxMarketInfo(
        lastUsdt: 0.005107,
        usdtIdrRate: 18054,
        fetchedAt: DateTime(2026, 11, 8),
      );
      expect(info.priceIdr, closeTo(92.201838, 0.001));
    });

    test('tanpa kurs harga IDR null', () {
      final info = NuxMarketInfo(
        lastUsdt: 0.005107,
        fetchedAt: DateTime(2026, 11, 8),
      );
      expect(info.priceIdr, isNull);
    });
  });
}
