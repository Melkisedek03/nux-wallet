import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/utils/bolt11_info.dart';

/// Invoice uji JIT testnet asli (nominal 5.000 nusan, deskripsi
/// "uji JIT NUX"). Nilai hash + kedaluwarsa yang diharapkan di bawah
/// diverifikasi dengan decoder Python independen, bukan dari kode
/// Dart yang diuji.
const _invoice =
    'lntn50u1p4dtvwydqjw44xjgz2f92zqnj4tqpp56e07u6ce6ryn9q094a8mlj2nv4ycaxl4fevez4wy48dvh2t5cjpqsp5pu2ya79p07tltuvnkfn6wszvcs5aqjqw8ptsaz0896q722632lfq9qyysgqcqzpvxqrrssrzjq2mf6clh7pmk2ftaw2d5zs2zd2llsz53pz8tgw0vduhfv6dkgg65jqqqqyqq2xsqqcqqqqqqqqqqqqqqfqgczp89wecast6hl4eymf8hlrt2zpw6x52qc4hgt0vsf2yh2h5j3xjcth7k8csyyvpanydw8v6xwxgkm74qtcw3aumxm8gkvcfhwf2ggq24yfp8';

void main() {
  group('parseBolt11Info', () {
    test('invoice asli: hash + kedaluwarsa terbaca benar', () {
      final info = parseBolt11Info(_invoice);
      expect(info, isNotNull);
      expect(info!.paymentHashHex,
          'd65fee6b19d0c93281e5af4fbfc95365498e9bf54e599155c4a9dacba974c482');
      // Deskripsi invoice uji ini memang "uji JIT NUX" (lihat
      // komentar di konstanta _invoice — diverifikasi decoder
      // independen).
      expect(info.description, 'uji JIT NUX');
      // timestamp invoice 1792389572 + expiry 3600 detik.
      expect(info.expiresAt.millisecondsSinceEpoch, 1792393172 * 1000);
      expect(
          info.isExpiredAt(
              DateTime.fromMillisecondsSinceEpoch(1792393171 * 1000)),
          isFalse);
      expect(
          info.isExpiredAt(
              DateTime.fromMillisecondsSinceEpoch(1792393172 * 1000)),
          isTrue);
    });

    test('satu karakter diubah: checksum rusak → null', () {
      final corrupted = '${_invoice.substring(0, 40)}q${_invoice.substring(41)}';
      expect(parseBolt11Info(corrupted), isNull);
    });

    test('masukan bukan invoice → null', () {
      expect(parseBolt11Info(''), isNull);
      expect(parseBolt11Info('bukan invoice'), isNull);
      expect(parseBolt11Info('ln'), isNull);
      expect(parseBolt11Info('lntn1qqqqqq'), isNull);
    });
  });

  group('parseBolt11AmountMsat', () {
    test('invoice asli 50u: 5.000.000 msat', () {
      // Invoice uji yang sama dengan grup di atas: awalan lntn50u
      // = 50 mikro-koin = 5.000 nusan = 5.000.000 msat.
      expect(parseBolt11AmountMsat(_invoice), BigInt.from(5000000));
    });

    // Invoice sisanya dirakit dari payload boneka + checksum
    // bech32 yang sah (dibuat & diverifikasi dengan encoder
    // independen): parser nominal hanya membaca awalan + checksum,
    // isi payload memang tidak dibacanya. Nilai harap dihitung
    // dari aritmetika BOLT11, bukan dari kode yang diuji.
    test('tanpa nominal (amountless) → null', () {
      expect(parseBolt11AmountMsat('lntn1pzry9x8qqqqqqqqqqaskaur'),
          isNull);
      expect(parseBolt11AmountMsat('lnnu1pzry9x8qqqqqqqqqqw6klqc'),
          isNull);
    });

    test('pengali m: 2m = 200.000.000 msat', () {
      expect(parseBolt11AmountMsat('lnnu2m1pzry9x8qqqqqqqqqqm853m8'),
          BigInt.from(200000000));
    });

    test('pengali n: 250n = 25.000 msat', () {
      expect(parseBolt11AmountMsat('lnnu250n1pzry9x8qqqqqqqqqqaazt28'),
          BigInt.from(25000));
    });

    test('pengali p bulat: 1000p = 100 msat', () {
      expect(parseBolt11AmountMsat('lnnu1000p1pzry9x8qqqqqqqqqqww2m8t'),
          BigInt.from(100));
    });

    test('pengali p tidak bulat ke msat → null', () {
      expect(parseBolt11AmountMsat('lnnu1005p1pzry9x8qqqqqqqqqqntje42'),
          isNull);
    });

    test('checksum rusak → null', () {
      final corrupted = '${_invoice.substring(0, 40)}q${_invoice.substring(41)}';
      expect(parseBolt11AmountMsat(corrupted), isNull);
    });

    test('masukan bukan invoice → null', () {
      expect(parseBolt11AmountMsat(''), isNull);
      expect(parseBolt11AmountMsat('bukan invoice'), isNull);
      expect(parseBolt11AmountMsat('ln'), isNull);
    });
  });
}
