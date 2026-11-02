import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/utils/bolt12_info.dart';

/// Offer variable-amount ASLI dari node fork (spike Bolt12
/// 2 Nov 2026, dibuat receive_variable_amount dengan deskripsi
/// "Spike Bolt12 ELNUX", tanpa kedaluwarsa).
const _offerVariable = 'lno1qgsxn3j3r9xwswu6tx4j0aw89gq3sgjskk97ts5mtzt0n43rwyqsqqq2zffhq6ttv5syymmvwscnygz9f3892kqsl5qhzq69kgvyfpa0zm5r0rf6ygt79jm838ttyckz6r56m8t5pp7h20hwkgpa4y0ykzqeml5zd3n5dhwdaxkq4df5mgrglu0wqw0hzemxrv3ahhqzqwqu2ncajzcmfvnpjuxzk97g6zmska74cxyvlagn47f36hy6n33scqr5q3jsd9kyea7qy0y59n4er3lyl5ex9qj9shwvsqu3hkzvj2tyvmeztlqmkygxhs7rypjj8yq5m6ch5rxk2nq205lvk50rjag22kln90zgskdqq7hzqfk4dm3s5fu24mrtymju4ehn4qkrfu6h2wnjt40kd2aprad2kp8r5nnnshgjeg23ztkmnv4hf5pe6k8z8e6etmhk075xj2a9pp4gpucruu5eluerhnsvmr8lqeh6tyqqw3uw7zrfhapsthaue0tgckx4v0v6l6qnk7gc6zjfgux8mpxlljgrjnyjs8curnjwlr8m6pxn29jz84vvf7qyh5tctxwh7krfz77t7duyr58098qrct0wl9d78rsldwr0xar2427qsefvwtynt4nyqmfj6njj4e6m6ssel98jrdgafjapu22waldef4u3vggzjuj920fkmwjwy0jqk38msmerthtyr5udalpwaz634g6hcyyht3gq';

/// Offer nominal tetap ASLI dari node fork yang sama:
/// 5.000.000 msat, deskripsi "Spike Bolt12 fixed", tanpa
/// kedaluwarsa.
const _offerFixed = 'lno1qgsxn3j3r9xwswu6tx4j0aw89gq3sgjskk97ts5mtzt0n43rwyqsqqqgqdxyksq2zffhq6ttv5syymmvwscnygrxd9ux2eqsl5qhzq69kgvyfpa0zm5r0rf6ygt79jm838ttyckz6r56m8t5pp7h20hwkgp72adae5hluze3hvw22p46e45qcq4upyrc7aly2l9r26uwkc8425czqtk3tx4fyln3msymfzdr07wq9xr79lmxhrgjlldlx8ntqth7h2yxkqr5xjnwypnsfdms0phtuukdsg29vcxuety0fcydgtn8pmzjp3j50f3mcru5r4wwnhljqh0rucak3xxfgtuv46lnlmdxt5f8p5wjptvztwtc5uvggz24khxg7f8h8ezhr52cgp3cvmm9t5y9plpv5hc2vasmrvw5t03x5ph3zppuen9lmspq3wxy06vtuqpsnvnavqt4p6cavejk84j5v2kf4jtjmpqraamrflgdgvpgyzfa2qcqwnh5qpqdyvhgpnxgx0c9n8euxgafv075qs2n6c4dy2pm7fj3uf73m63j0sau4rcnju3a4watnzxhdcj8yswgl5j0j8kurw3w5u68f7z3s2kphxj8e429c6fnakqp0qd9jpkzcakkyd256twzkvqw9pjhrpmck3av60acjxn49972hrfluz6gf9x8mrm3vggzecs4fa3zs35d7aeczps83fhfeckzh8zsjhwnyahkwfpglwcm4cgq';

/// Offer contoh berkedaluwarsa lampau (rekaman absolute_expiry
/// 1000000000 = 9 Sep 2001) — disusun mengikuti pengkodean TLV
/// BOLT12 yang sama, BUKAN keluaran node.
const _offerExpired = 'lno1qgsqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq2zf9k2erpd36hwctjwdsjqcm0de6x76qwqsae4jsqzcssyqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq';

/// Offer contoh berdenominasi mata uang asing (offer_currency
/// "USD", nominal 2500) — node menolak membayarnya.
const _offerCurrency = 'lno1qcp4256ypqpqn3q2p3zx7mrpwgsxxmmww3hks93pqgqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq';

/// Offer contoh nominal tetap 250.000 msat dengan kedaluwarsa
/// jauh di masa depan (4102444800 = 1 Jan 2100).
const _offerFutureFixed = 'lno1pqps85yspgg5uctww35jq6m9v3skcathv9e8xcgwqn6gv4cqzcssyqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq';

void main() {
  group('isBolt12Offer', () {
    test('awalan lno1 dikenali, tidak peka huruf & spasi pinggir', () {
      expect(isBolt12Offer(_offerVariable), isTrue);
      expect(isBolt12Offer(_offerFixed.toUpperCase()), isTrue);
      expect(isBolt12Offer('  $_offerFixed  '), isTrue);
    });

    test('yang bukan offer ditolak', () {
      expect(isBolt12Offer(''), isFalse);
      expect(isBolt12Offer('lntn1invoicebolt11biasa'), isFalse);
      expect(isBolt12Offer('lno'), isFalse);
      expect(isBolt12Offer('halo'), isFalse);
    });
  });

  group('parseOfferInfo', () {
    test('offer variable asli: tanpa nominal, tanpa kedaluwarsa', () {
      final info = parseOfferInfo(_offerVariable);
      expect(info, isNotNull);
      expect(info!.amountMsat, isNull);
      expect(info.isFixedAmount, isFalse);
      expect(info.description, 'Spike Bolt12 ELNUX');
      expect(info.absoluteExpirySecs, isNull);
      expect(info.hasForeignCurrency, isFalse);
      expect(info.isExpiredAt(DateTime.now()), isFalse);
    });

    test('offer tetap asli: nominal 5.000.000 msat terbaca', () {
      final info = parseOfferInfo(_offerFixed);
      expect(info, isNotNull);
      expect(info!.amountMsat, BigInt.from(5000000));
      expect(info.isFixedAmount, isTrue);
      expect(info.description, 'Spike Bolt12 fixed');
      expect(info.absoluteExpirySecs, isNull);
      expect(info.hasForeignCurrency, isFalse);
    });

    test('huruf besar semua terbaca sama', () {
      final info = parseOfferInfo(_offerFixed.toUpperCase());
      expect(info, isNotNull);
      expect(info!.amountMsat, BigInt.from(5000000));
      expect(info.description, 'Spike Bolt12 fixed');
    });

    test('kedaluwarsa lampau terdeteksi', () {
      final info = parseOfferInfo(_offerExpired);
      expect(info, isNotNull);
      expect(info!.absoluteExpirySecs, BigInt.from(1000000000));
      expect(info.isExpiredAt(DateTime.now()), isTrue);
      expect(
        info.isExpiredAt(DateTime.utc(2000, 1, 1)),
        isFalse,
      );
    });

    test('nominal tetap + kedaluwarsa masa depan belum lewat', () {
      final info = parseOfferInfo(_offerFutureFixed);
      expect(info, isNotNull);
      expect(info!.amountMsat, BigInt.from(250000));
      expect(info.isExpiredAt(DateTime.now()), isFalse);
    });

    test('denominasi mata uang asing ditandai', () {
      final info = parseOfferInfo(_offerCurrency);
      expect(info, isNotNull);
      expect(info!.hasForeignCurrency, isTrue);
    });

    test('string rusak / bukan offer menghasilkan null', () {
      expect(parseOfferInfo(''), isNull);
      expect(parseOfferInfo('lno1'), isNull);
      expect(parseOfferInfo('lntn1invoicebolt11biasa'), isNull);
      expect(parseOfferInfo('lno1bbbiii'), isNull);
      // Terpotong: jalan TLV tidak berakhir utuh.
      expect(
        parseOfferInfo(_offerFixed.substring(0, _offerFixed.length - 40)),
        isNull,
      );
      // Terpotong pendek: payload tidak utuh sejak awal.
      expect(parseOfferInfo(_offerVariable.substring(0, 60)), isNull);
    });
  });

  group('parseNusanInputToMsat', () {
    test('angka polos dikali 1000', () {
      expect(parseNusanInputToMsat('5000'), BigInt.from(5000000));
      expect(parseNusanInputToMsat(' 250 '), BigInt.from(250000));
      expect(parseNusanInputToMsat('1'), BigInt.from(1000));
    });

    test('pemisah ribuan titik & desimal koma ala layar Terima', () {
      expect(parseNusanInputToMsat('5.000'), BigInt.from(5000000));
      expect(parseNusanInputToMsat('1,5'), BigInt.from(1500));
    });

    test('isian tidak sah menghasilkan null', () {
      expect(parseNusanInputToMsat(''), isNull);
      expect(parseNusanInputToMsat('0'), isNull);
      expect(parseNusanInputToMsat('-5'), isNull);
      expect(parseNusanInputToMsat('abc'), isNull);
    });
  });
}
