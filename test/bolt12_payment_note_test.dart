import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/lsp_service.dart';

/// Pembayaran keluar Bolt12 contoh: [idByte] membedakan catatan,
/// [withHash] menentukan hash sudah terbit atau belum (hash baru
/// muncul sesudah node mengambil invoice dari offer).
PaymentDetails _offerPayment(int idByte, {required bool withHash}) {
  return PaymentDetails(
    id: PaymentId(data: Uint8List.fromList([idByte])),
    kind: PaymentKind_Bolt12Offer(
      hash: withHash
          ? PaymentHash(
              data: U8Array32(Uint8List.fromList(List.filled(32, 0xAB))),
            )
          : null,
      offerId: OfferId(
        field0: U8Array32(Uint8List.fromList(List.filled(32, 1))),
      ),
    ),
    amountMsat: BigInt.from(5000000),
    direction: PaymentDirection.outbound,
    status: PaymentStatus.succeeded,
    latestUpdateTimestamp: BigInt.from(1762000000),
  );
}

PaymentDetails _bolt11Payment(int idByte) {
  return PaymentDetails(
    id: PaymentId(data: Uint8List.fromList([idByte])),
    kind: PaymentKind_Bolt11(
      hash: PaymentHash(
        data: U8Array32(Uint8List.fromList(List.filled(32, idByte))),
      ),
    ),
    amountMsat: BigInt.from(1000),
    direction: PaymentDirection.outbound,
    status: PaymentStatus.succeeded,
    latestUpdateTimestamp: BigInt.from(1762000000),
  );
}

void main() {
  group('findBolt12PaymentHashHex', () {
    test('hash pembayaran offer ditemukan dari ID-nya', () {
      final payments = [_bolt11Payment(3), _offerPayment(7, withHash: true)];
      expect(
        findBolt12PaymentHashHex(payments, '07'),
        'ab' * 32,
      );
    });

    test('hash belum terbit → null (bukan tebakan)', () {
      final payments = [_offerPayment(7, withHash: false)];
      expect(findBolt12PaymentHashHex(payments, '07'), isNull);
    });

    test('ID tak dikenal → null', () {
      final payments = [_offerPayment(7, withHash: true)];
      expect(findBolt12PaymentHashHex(payments, '09'), isNull);
    });

    test('pembayaran Bolt11 ber-ID sama → null (khusus offer)', () {
      final payments = [_bolt11Payment(7)];
      expect(findBolt12PaymentHashHex(payments, '07'), isNull);
    });
  });
}
