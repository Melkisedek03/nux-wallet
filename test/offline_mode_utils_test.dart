import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/offline_mode_utils.dart';

const _ownId =
    '039b7213909b561a355832406bdbf18bf6e1ff56cd94c347890658cc02de408cc8';
const _peerId =
    '035d4490410d765e327bd33bcaaa0db8bc1b0ea7ca0f8df7e9db8d9279b16683b0';
const _otherId =
    '02cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

ChannelDetails _channel(String counterpartyHex, {bool usable = true}) {
  return ChannelDetails(
    channelId: ChannelId(
      data: U8Array32(Uint8List.fromList(List.filled(32, 1))),
    ),
    counterpartyNodeId: PublicKey(hex: counterpartyHex),
    channelValueSats: BigInt.from(25000),
    userChannelId: UserChannelId(data: Uint8List.fromList(List.filled(16, 0))),
    feerateSatPer1000Weight: 1000,
    outboundCapacityMsat: BigInt.from(24000000),
    inboundCapacityMsat: BigInt.from(1000000),
    isOutbound: true,
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
      maxDustHtlcExposure: MaxDustHTLCExposure_FeeRateMultiplier(
        BigInt.from(1000),
      ),
      forceCloseAvoidanceMaxFeeSatoshis: BigInt.from(1000),
      acceptUnderpayingHtlcs: false,
    ),
  );
}

void main() {
  group('localEndpointName', () {
    test('awalan ELNUX- + 8 hex pertama', () {
      expect(localEndpointName(_ownId), 'ELNUX-039b7213');
    });

    test('huruf besar dinormalkan menjadi kecil', () {
      expect(localEndpointName(_ownId.toUpperCase()), 'ELNUX-039b7213');
    });
  });

  group('formatDeviceCode', () {
    test('8 hex pertama, huruf besar, kelompok 4+4', () {
      expect(formatDeviceCode(_ownId), '039B 7213');
      expect(formatDeviceCode(_peerId), '035D 4490');
    });

    test('ID pendek dikembalikan apa adanya dalam huruf besar', () {
      expect(formatDeviceCode('ab12'), 'AB12');
    });
  });

  group('codeFromEndpointName', () {
    test('nama ELNUX- sah menjadi kode', () {
      expect(codeFromEndpointName('ELNUX-039b7213'), '039B 7213');
    });

    test('nama asing ditolak', () {
      expect(codeFromEndpointName('ELNUX-039b721'), isNull);
      expect(codeFromEndpointName('ELNUX-039b72133'), isNull);
      expect(codeFromEndpointName('ELNUX-zzzzzzzz'), isNull);
      expect(codeFromEndpointName('Galaxy S24'), isNull);
      expect(codeFromEndpointName(''), isNull);
    });
  });

  group('hasReadyPath', () {
    test('channel usable dengan peer berarti siap', () {
      expect(hasReadyPath([_channel(_peerId)], _peerId), isTrue);
    });

    test('channel belum usable bukan jalur siap', () {
      expect(
        hasReadyPath([_channel(_peerId, usable: false)], _peerId),
        isFalse,
      );
    });

    test('channel dengan peer lain bukan jalur siap', () {
      expect(hasReadyPath([_channel(_otherId)], _peerId), isFalse);
    });

    test('peer belum dikenal berarti belum siap', () {
      expect(hasReadyPath([_channel(_peerId)], null), isFalse);
    });

    test('daftar kosong berarti belum siap', () {
      expect(hasReadyPath([], _peerId), isFalse);
    });

    test('perbandingan ID tidak peka huruf besar/kecil', () {
      expect(hasReadyPath([_channel(_peerId)], _peerId.toUpperCase()), isTrue);
    });
  });

  group('offlineModeState', () {
    test('niat mati berarti mati walau tertaut', () {
      expect(
        offlineModeState(sessionActive: false, linked: true, pathReady: true),
        OfflineModeState.off,
      );
    });

    test('sesi hidup belum tertaut berarti mencari', () {
      expect(
        offlineModeState(sessionActive: true, linked: false, pathReady: false),
        OfflineModeState.searching,
      );
    });

    test('tertaut tanpa jalur siap berarti terhubung', () {
      expect(
        offlineModeState(sessionActive: true, linked: true, pathReady: false),
        OfflineModeState.connected,
      );
    });

    test('tertaut dengan jalur siap berarti siap', () {
      expect(
        offlineModeState(sessionActive: true, linked: true, pathReady: true),
        OfflineModeState.ready,
      );
    });
  });
}
