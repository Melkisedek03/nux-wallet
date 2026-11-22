import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nux_wallet/services/fee_estimate.dart';

void main() {
  group('parseFeeEstimates', () {
    test('peta tarif sah', () {
      final rates = parseFeeEstimates({'1': 2.5, '6': 1.0, '12': 1});
      expect(rates, {1: 2.5, 6: 1.0, 12: 1.0});
    });

    test('bukan peta berarti null', () {
      expect(parseFeeEstimates('bukan json'), isNull);
      expect(parseFeeEstimates([1, 2]), isNull);
      expect(parseFeeEstimates(null), isNull);
    });

    test('entri tidak sah dilewati, yang sah tetap dipakai', () {
      final rates = parseFeeEstimates({
        '6': 1.0,
        'buruk': 2.0,
        '7': 'bukan angka',
        '8': -1.0,
        '9': 0,
      });
      expect(rates, {6: 1.0});
    });

    test('tidak ada entri sah berarti null', () {
      expect(parseFeeEstimates({}), isNull);
      expect(parseFeeEstimates({'x': 'y'}), isNull);
    });
  });

  group('pickFeeRate', () {
    test('target persis dipakai', () {
      expect(pickFeeRate({1: 3.0, 6: 1.0, 12: 0.5}), 1.0);
    });

    test('target hilang berarti target terdekat', () {
      expect(pickFeeRate({2: 2.0, 12: 0.5}), 2.0);
      expect(pickFeeRate({10: 0.8, 12: 0.5}), 0.8);
    });

    test('seri berarti target lebih kecil (konservatif)', () {
      expect(pickFeeRate({5: 1.5, 7: 0.9}), 1.5);
    });

    test('peta kosong berarti null', () {
      expect(pickFeeRate({}), isNull);
    });
  });

  group('estimateFundingFeeSats', () {
    test('1,0 sat/vB × 250 vB = 250 nusan', () {
      expect(estimateFundingFeeSats(1.0), BigInt.from(250));
    });

    test('pecahan dibulatkan ke atas', () {
      expect(estimateFundingFeeSats(1.001), BigInt.from(251));
      expect(estimateFundingFeeSats(2.124), BigInt.from(531));
    });

    test('tarif tidak sah berarti null', () {
      expect(estimateFundingFeeSats(0), isNull);
      expect(estimateFundingFeeSats(-1.0), isNull);
      expect(estimateFundingFeeSats(double.nan), isNull);
      expect(estimateFundingFeeSats(double.infinity), isNull);
    });
  });

  group('parseTxFee', () {
    test('field fee sah', () {
      expect(parseTxFee({'fee': 531, 'txid': 'aa'}), BigInt.from(531));
    });

    test('fee hilang atau bukan angka berarti null', () {
      expect(parseTxFee({'txid': 'aa'}), isNull);
      expect(parseTxFee({'fee': '531'}), isNull);
      expect(parseTxFee({'fee': -5}), isNull);
      expect(parseTxFee('bukan peta'), isNull);
    });
  });

  group('FeeEstimateService', () {
    test('perkiraan dari tarif live target 6', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/fee-estimates');
        return http.Response('{"1": 2.0, "6": 1.0, "12": 0.5}', 200);
      });
      final service = FeeEstimateService(client: client);
      expect(await service.estimateFundingFee(), BigInt.from(250));
    });

    test('HTTP gagal berarti null (cadangan tetap dipakai pemanggil)', () async {
      final client = MockClient((_) async => http.Response('error', 500));
      final service = FeeEstimateService(client: client);
      expect(await service.estimateFundingFee(), isNull);
    });

    test('JSON rusak berarti null', () async {
      final client = MockClient((_) async => http.Response('bukan json', 200));
      final service = FeeEstimateService(client: client);
      expect(await service.estimateFundingFee(), isNull);
    });

    test('biaya pasti dari /tx/{txid}', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/tx/${'aa' * 32}');
        return http.Response('{"fee": 724, "txid": "${'aa' * 32}"}', 200);
      });
      final service = FeeEstimateService(client: client);
      expect(
        await service.fetchFundingFee('aa' * 32),
        BigInt.from(724),
      );
    });

    test('biaya pasti gagal ambil berarti null', () async {
      final client = MockClient((_) async => http.Response('not found', 404));
      final service = FeeEstimateService(client: client);
      expect(await service.fetchFundingFee('aa' * 32), isNull);
    });

    test('tinggi ujung dari /blocks/tip/height', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/blocks/tip/height');
        return http.Response('1500', 200);
      });
      final service = FeeEstimateService(client: client);
      expect(await service.fetchTipHeight(), 1500);
    });

    test('tinggi ujung gagal ambil berarti null', () async {
      final client = MockClient((_) async => http.Response('error', 500));
      final service = FeeEstimateService(client: client);
      expect(await service.fetchTipHeight(), isNull);
    });

    test('tinggi ujung bukan angka berarti null', () async {
      final client = MockClient((_) async => http.Response('bukan angka', 200));
      final service = FeeEstimateService(client: client);
      expect(await service.fetchTipHeight(), isNull);
    });
  });
}
