import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/lsp_service.dart';

ChannelDetails _channel({required BigInt outboundMsat, BigInt? reserveSats}) {
  return ChannelDetails(
    channelId: ChannelId(
      data: U8Array32(Uint8List.fromList(List.filled(32, 1))),
    ),
    counterpartyNodeId: PublicKey(
      hex: '02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
    channelValueSats: BigInt.from(25000),
    unspendablePunishmentReserve: reserveSats,
    userChannelId: UserChannelId(data: Uint8List.fromList(List.filled(16, 0))),
    feerateSatPer1000Weight: 1000,
    outboundCapacityMsat: outboundMsat,
    inboundCapacityMsat: BigInt.zero,
    isOutbound: true,
    isChannelReady: true,
    isUsable: true,
    counterpartyUnspendablePunishmentReserve: BigInt.from(1000),
    nextOutboundHtlcLimitMsat: BigInt.zero,
    nextOutboundHtlcMinimumMsat: BigInt.zero,
    inboundHtlcMinimumMsat: BigInt.from(1000),
    config: ChannelConfig(
      forwardingFeeProportionalMillionths: 0,
      forwardingFeeBaseMsat: 0,
      cltvExpiryDelta: 72,
      maxDustHtlcExposure: MaxDustHTLCExposure_FeeRateMultiplier(
        BigInt.from(1000),
      ),
      forceCloseAvoidanceMaxFeeSatoshis: BigInt.from(1000),
      acceptUnderpayingHtlcs: false,
    ),
  );
}

void main() {
  group('countedChannelBalanceMsat', () {
    test('channel bersaldo: kapasitas keluar + cadangan penuh', () {
      // Pendana 25.000 nusan: keluar 24.000 + cadangan 1.000 sat.
      final ch = _channel(
        outboundMsat: BigInt.from(24000000),
        reserveSats: BigInt.from(1000),
      );
      expect(countedChannelBalanceMsat(ch), BigInt.from(25000000));
    });

    test('channel saldo nol: cadangan tidak menjadi saldo hantu', () {
      // Penerima channel yang didanai pihak seberang: saldo nol,
      // cadangan tercetak 1.000 sat tidak boleh menaikkan kartu.
      final ch = _channel(
        outboundMsat: BigInt.zero,
        reserveSats: BigInt.from(1000),
      );
      expect(countedChannelBalanceMsat(ch), BigInt.zero);
    });

    test('cadangan dibatasi sebesar kapasitas keluar', () {
      // Saldo 500 nusan dengan cadangan tercetak 1.000: yang dihitung
      // hanya cadangan sebatas saldo yang benar-benar ada.
      final ch = _channel(
        outboundMsat: BigInt.from(500000),
        reserveSats: BigInt.from(1000),
      );
      expect(countedChannelBalanceMsat(ch), BigInt.from(1000000));
    });

    test('tanpa cadangan (null): hanya kapasitas keluar', () {
      final ch = _channel(outboundMsat: BigInt.from(7000));
      expect(countedChannelBalanceMsat(ch), BigInt.from(7000));
    });
  });
}
