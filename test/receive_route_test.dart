import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/lsp_service.dart';

ChannelDetails _channel({required bool usable, required int inboundMsat}) {
  return ChannelDetails(
    channelId: ChannelId(
        data: U8Array32(Uint8List.fromList(List.filled(32, 1)))),
    counterpartyNodeId: PublicKey(hex: '02${'11' * 32}'),
    channelValueSats: BigInt.from(25000),
    userChannelId:
        UserChannelId(data: Uint8List.fromList(List.filled(16, 0))),
    feerateSatPer1000Weight: 1000,
    outboundCapacityMsat: BigInt.zero,
    inboundCapacityMsat: BigInt.from(inboundMsat),
    isOutbound: false,
    isChannelReady: usable,
    isUsable: usable,
    counterpartyUnspendablePunishmentReserve: BigInt.from(1000),
    nextOutboundHtlcLimitMsat: BigInt.zero,
    nextOutboundHtlcMinimumMsat: BigInt.zero,
    inboundHtlcMinimumMsat: BigInt.from(1000),
    config: ChannelConfig(
      forwardingFeeProportionalMillionths: 0,
      forwardingFeeBaseMsat: 0,
      cltvExpiryDelta: 72,
      maxDustHtlcExposure:
          MaxDustHTLCExposure_FeeRateMultiplier(BigInt.from(1000)),
      forceCloseAvoidanceMaxFeeSatoshis: BigInt.from(1000),
      acceptUnderpayingHtlcs: false,
    ),
  );
}

void main() {
  group('totalUsableInboundCapacityMsat', () {
    test('tanpa channel: nol', () {
      expect(totalUsableInboundCapacityMsat([]), BigInt.zero);
    });

    test('hanya channel usable yang dijumlahkan', () {
      final channels = [
        _channel(usable: true, inboundMsat: 1525000),
        _channel(usable: false, inboundMsat: 9000000),
      ];
      expect(totalUsableInboundCapacityMsat(channels),
          BigInt.from(1525000));
    });

    test('beberapa channel usable dijumlahkan', () {
      final channels = [
        _channel(usable: true, inboundMsat: 1000000),
        _channel(usable: true, inboundMsat: 2500000),
        _channel(usable: false, inboundMsat: 4000000),
      ];
      expect(totalUsableInboundCapacityMsat(channels),
          BigInt.from(3500000));
    });
  });

  group('chooseReceiveInvoiceRoute', () {
    test('amountless: tetap JIT walau kapasitas besar', () {
      expect(
        chooseReceiveInvoiceRoute(
          amountMsat: null,
          usableInboundCapacityMsat: BigInt.from(100000000),
        ),
        ReceiveInvoiceRoute.jit,
      );
    });

    test('kapasitas cukup untuk nominal di bawah minimum JIT: biasa', () {
      // Kasus yang memotivasi Jalur 1: menerima 995 nusan lewat
      // jalur yang sudah jadi (ruang terima 1.525 nusan) — invoice
      // JIT akan ditolak minimum 1.000, invoice biasa tidak.
      expect(
        chooseReceiveInvoiceRoute(
          amountMsat: BigInt.from(995000),
          usableInboundCapacityMsat: BigInt.from(1525000),
        ),
        ReceiveInvoiceRoute.regular,
      );
    });

    test('kapasitas persis sama dengan nominal: biasa', () {
      expect(
        chooseReceiveInvoiceRoute(
          amountMsat: BigInt.from(5000000),
          usableInboundCapacityMsat: BigInt.from(5000000),
        ),
        ReceiveInvoiceRoute.regular,
      );
    });

    test('kapasitas kurang 1 msat dari nominal: JIT', () {
      expect(
        chooseReceiveInvoiceRoute(
          amountMsat: BigInt.from(5000000),
          usableInboundCapacityMsat: BigInt.from(4999999),
        ),
        ReceiveInvoiceRoute.jit,
      );
    });

    test('belum ada channel usable: JIT', () {
      expect(
        chooseReceiveInvoiceRoute(
          amountMsat: BigInt.from(5000000),
          usableInboundCapacityMsat: BigInt.zero,
        ),
        ReceiveInvoiceRoute.jit,
      );
    });

    test('nominal besar di atas kapasitas: JIT', () {
      expect(
        chooseReceiveInvoiceRoute(
          amountMsat: BigInt.from(40000000),
          usableInboundCapacityMsat: BigInt.from(1525000),
        ),
        ReceiveInvoiceRoute.jit,
      );
    });
  });

  group('receiveIsOfflineContext', () {
    test('boot normal tanpa sesi jembatan: bukan konteks offline', () {
      expect(
        receiveIsOfflineContext(
            bootedOffline: false, bridgeSessionActive: false),
        isFalse,
      );
    });

    test('boot offline saja: konteks offline', () {
      expect(
        receiveIsOfflineContext(
            bootedOffline: true, bridgeSessionActive: false),
        isTrue,
      );
    });

    test('sesi jembatan aktif saja: konteks offline', () {
      expect(
        receiveIsOfflineContext(
            bootedOffline: false, bridgeSessionActive: true),
        isTrue,
      );
    });

    test('keduanya: konteks offline', () {
      expect(
        receiveIsOfflineContext(
            bootedOffline: true, bridgeSessionActive: true),
        isTrue,
      );
    });
  });
}
