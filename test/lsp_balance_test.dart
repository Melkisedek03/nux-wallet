import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/lsp_service.dart';

const _lspId =
    '02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _peerId =
    '03bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

ChannelDetails _channel({
  required BigInt outboundMsat,
  BigInt? reserveSats,
  String counterpartyHex = _lspId,
  bool isOutbound = true,
}) {
  return ChannelDetails(
    channelId: ChannelId(
      data: U8Array32(Uint8List.fromList(List.filled(32, 1))),
    ),
    counterpartyNodeId: PublicKey(hex: counterpartyHex),
    channelValueSats: BigInt.from(25000),
    unspendablePunishmentReserve: reserveSats,
    userChannelId: UserChannelId(data: Uint8List.fromList(List.filled(16, 0))),
    feerateSatPer1000Weight: 1000,
    outboundCapacityMsat: outboundMsat,
    inboundCapacityMsat: BigInt.zero,
    isOutbound: isOutbound,
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

  group('splitBalanceBySource', () {
    test('memisahkan JIT, Self, dan channel langsung', () {
      final channels = [
        // Channel JIT: ke LSP, didanai LSP (inbound).
        _channel(outboundMsat: BigInt.from(5000000), isOutbound: false),
        // Channel self-funded: ke LSP, didanai sendiri (outbound).
        _channel(outboundMsat: BigInt.from(3000000)),
        // Channel langsung: pihak seberang bukan LSP.
        _channel(outboundMsat: BigInt.from(1000000), counterpartyHex: _peerId),
      ];
      final split = splitBalanceBySource(channels, _lspId);
      expect(split.jitMsat, BigInt.from(5000000));
      expect(split.selfFundedMsat, BigInt.from(3000000));
      expect(split.directMsat, BigInt.from(1000000));
      expect(
        split.jitMsat + split.selfFundedMsat + split.directMsat,
        BigInt.from(9000000),
      );
    });

    test('cadangan hantu channel langsung tidak bocor ke rincian', () {
      final channels = [
        _channel(outboundMsat: BigInt.from(5000000)),
        _channel(
          outboundMsat: BigInt.zero,
          reserveSats: BigInt.from(1000),
          counterpartyHex: _peerId,
        ),
      ];
      final split = splitBalanceBySource(channels, _lspId);
      expect(split.directMsat, BigInt.zero);
      expect(split.selfFundedMsat, BigInt.from(5000000));
      expect(split.jitMsat, BigInt.zero);
    });

    test('channel langsung masuk (penerima) tetap langsung', () {
      // Pihak yang menerima channel langsung melihatnya inbound —
      // arah tidak boleh memindahkannya ke JIT.
      final channels = [
        _channel(
          outboundMsat: BigInt.from(2000000),
          counterpartyHex: _peerId,
          isOutbound: false,
        ),
      ];
      final split = splitBalanceBySource(channels, _lspId);
      expect(split.directMsat, BigInt.from(2000000));
      expect(split.jitMsat, BigInt.zero);
      expect(split.selfFundedMsat, BigInt.zero);
    });

    test('ID LSP dicocokkan tanpa peka huruf besar/kecil', () {
      final channels = [_channel(outboundMsat: BigInt.from(7000))];
      final split = splitBalanceBySource(channels, _lspId.toUpperCase());
      expect(split.selfFundedMsat, BigInt.from(7000));
      expect(split.jitMsat, BigInt.zero);
      expect(split.directMsat, BigInt.zero);
    });

    test('daftar kosong menghasilkan nol untuk ketiganya', () {
      final split = splitBalanceBySource(const [], _lspId);
      expect(split.jitMsat, BigInt.zero);
      expect(split.selfFundedMsat, BigInt.zero);
      expect(split.directMsat, BigInt.zero);
    });
  });
}
