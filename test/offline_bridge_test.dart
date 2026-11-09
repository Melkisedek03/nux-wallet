import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/offline_bridge.dart';

void main() {
  group('offlineResumeBackoff', () {
    test('tumbuh mengganda dari 2 detik', () {
      expect(offlineResumeBackoff(0), const Duration(seconds: 2));
      expect(offlineResumeBackoff(1), const Duration(seconds: 4));
      expect(offlineResumeBackoff(2), const Duration(seconds: 8));
      expect(offlineResumeBackoff(3), const Duration(seconds: 16));
    });

    test('mentok di 30 detik untuk percobaan besar', () {
      expect(offlineResumeBackoff(4), const Duration(seconds: 30));
      expect(offlineResumeBackoff(10), const Duration(seconds: 30));
    });
  });

  group('muatan HELLO mode gabung', () {
    const idA =
        '039b7213909b561a355832406bdbf18bf6e1ff56cd94c347890658cc02de408cc8';
    const idB =
        '035d4490410d765e327bd33bcaaa0db8bc1b0ea7ca0f8df7e9db8d9279b16683b0';

    test('encode lalu parse kembali ke ID yang sama', () {
      expect(parseHelloPayload(encodeHelloPayload(idA)), idA);
      expect(parseHelloPayload(encodeHelloPayload(idB)), idB);
    });

    test('huruf besar pada ID dinormalkan menjadi kecil', () {
      expect(parseHelloPayload(encodeHelloPayload(idA.toUpperCase())), idA);
    });

    test('byte acak (mirip jabat tangan Noise) ditolak', () {
      final noiseLike = Uint8List.fromList(
        List<int>.generate(helloMagic.length + 66, (i) => (i * 37) % 256),
      );
      expect(parseHelloPayload(noiseLike), isNull);
    });

    test('awalan benar tetapi isi bukan hex ditolak', () {
      final bad = Uint8List.fromList(
        utf8.encode('${helloMagic}zz${'a' * 64}'),
      );
      expect(parseHelloPayload(bad), isNull);
    });

    test('panjang salah ditolak (kurang maupun lebih)', () {
      final good = encodeHelloPayload(idA);
      expect(parseHelloPayload(good.sublist(0, good.length - 1)), isNull);
      final longer = Uint8List.fromList([...good, 0x41]);
      expect(parseHelloPayload(longer), isNull);
    });

    test('versi awalan lain ditolak', () {
      final v2 = Uint8List.fromList(
        utf8.encode('ELNUX-HELLO/2:$idA'),
      );
      expect(parseHelloPayload(v2), isNull);
    });
  });

  group('survivingInitiator', () {
    test('nama inisiator yang lebih kecil menang dari dua arah', () {
      expect(
        survivingInitiator('ELNUX-035d4490', 'ELNUX-039b7213'),
        'ELNUX-035d4490',
      );
      expect(
        survivingInitiator('ELNUX-039b7213', 'ELNUX-035d4490'),
        'ELNUX-035d4490',
      );
    });

    test('nama yang sama menghasilkan nama itu sendiri', () {
      expect(
        survivingInitiator('ELNUX-039b7213', 'ELNUX-039b7213'),
        'ELNUX-039b7213',
      );
    });
  });
}
