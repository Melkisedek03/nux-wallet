import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/market_info.dart';

/// Uji logika murni info pasar Jelajah: parse ticker CoinPaprika
/// (kuotasi langsung NUX/IDR + perubahan 24 jam), parse tinggi blok
/// electrs, dan bentuk data NuxMarketInfo.
void main() {
  group('parseCoinpaprikaTicker', () {
    test('respons ticker ter-parse harga + perubahan 24 jam', () {
      final ticker = parseCoinpaprikaTicker({
        'id': 'nux-nusacoin',
        'name': 'Nusacoin',
        'symbol': 'NUX',
        'rank': 7005,
        'quotes': {
          'IDR': {
            'price': 62.62496907349026,
            'volume_24h': 123456.0,
            'percent_change_24h': 0.99,
          },
        },
        'last_updated': '2026-11-25T01:09:07Z',
      });
      expect(ticker, isNotNull);
      expect(ticker!.priceIdr, closeTo(62.625, 0.001));
      expect(ticker.changePct, closeTo(0.99, 0.0001));
    });

    test('perubahan 24 jam negatif ikut ter-parse', () {
      final ticker = parseCoinpaprikaTicker({
        'quotes': {
          'IDR': {'price': 60.5, 'percent_change_24h': -3.25},
        },
      });
      expect(ticker, isNotNull);
      expect(ticker!.priceIdr, 60.5);
      expect(ticker.changePct, closeTo(-3.25, 0.0001));
    });

    test('tanpa percent_change_24h harga tetap ter-parse', () {
      final ticker = parseCoinpaprikaTicker({
        'quotes': {
          'IDR': {'price': 62.62},
        },
      });
      expect(ticker, isNotNull);
      expect(ticker!.priceIdr, 62.62);
      expect(ticker.changePct, isNull);
    });

    test('bentuk tak dikenal atau harga tidak positif → null', () {
      expect(parseCoinpaprikaTicker(null), isNull);
      expect(parseCoinpaprikaTicker('teks'), isNull);
      expect(parseCoinpaprikaTicker({'lain': 1}), isNull);
      expect(parseCoinpaprikaTicker({'quotes': {}}), isNull);
      expect(
        parseCoinpaprikaTicker({
          'quotes': {
            'USD': {'price': 0.0035},
          },
        }),
        isNull,
      );
      expect(
        parseCoinpaprikaTicker({
          'quotes': {
            'IDR': {'price': 0},
          },
        }),
        isNull,
      );
      expect(
        parseCoinpaprikaTicker({
          'quotes': {
            'IDR': {'price': -1.5},
          },
        }),
        isNull,
      );
      expect(
        parseCoinpaprikaTicker({
          'quotes': {'IDR': {}},
        }),
        isNull,
      );
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
    test('menyimpan harga IDR + perubahan 24 jam apa adanya', () {
      final info = NuxMarketInfo(
        priceIdr: 62.62,
        changePct: 0.99,
        blockHeight: 73675,
        fetchedAt: DateTime(2026, 11, 25),
      );
      expect(info.priceIdr, 62.62);
      expect(info.changePct, 0.99);
      expect(info.blockHeight, 73675);
    });

    test('tanpa perubahan 24 jam nilainya null', () {
      final info = NuxMarketInfo(
        priceIdr: 62.62,
        fetchedAt: DateTime(2026, 11, 25),
      );
      expect(info.priceIdr, 62.62);
      expect(info.changePct, isNull);
      expect(info.blockHeight, isNull);
    });
  });
}
