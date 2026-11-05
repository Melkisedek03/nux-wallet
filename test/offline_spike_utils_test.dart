import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/offline_spike_utils.dart';

const _lspId =
    '02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _peerId =
    '03bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _otherId =
    '02cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

ChannelDetails _channel(String counterpartyHex) {
  return ChannelDetails(
    channelId:
        ChannelId(data: U8Array32(Uint8List.fromList(List.filled(32, 1)))),
    counterpartyNodeId: PublicKey(hex: counterpartyHex),
    channelValueSats: BigInt.from(25000),
    userChannelId:
        UserChannelId(data: Uint8List.fromList(List.filled(16, 0))),
    feerateSatPer1000Weight: 1000,
    outboundCapacityMsat: BigInt.from(24000000),
    inboundCapacityMsat: BigInt.from(1000000),
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
      maxDustHtlcExposure:
          MaxDustHTLCExposure_FeeRateMultiplier(BigInt.from(1000)),
      forceCloseAvoidanceMaxFeeSatoshis: BigInt.from(1000),
      acceptUnderpayingHtlcs: false,
    ),
  );
}

PeerDetails _peer(String nodeIdHex, {required bool connected}) {
  return PeerDetails(
    nodeId: PublicKey(hex: nodeIdHex),
    address: SocketAddress.tcpIpV4(
      addr: U8Array4(Uint8List.fromList([127, 0, 0, 1])),
      port: 19735,
    ),
    isConnected: connected,
  );
}

void main() {
  group('parseNusanToMsat', () {
    test('bilangan bulat menjadi msat', () {
      expect(parseNusanToMsat('25000'), BigInt.from(25000000));
      expect(parseNusanToMsat('0'), BigInt.zero);
    });

    test('pecahan sampai 3 desimal, pemisah titik atau koma', () {
      expect(parseNusanToMsat('1.5'), BigInt.from(1500));
      expect(parseNusanToMsat('1,5'), BigInt.from(1500));
      expect(parseNusanToMsat('0.001'), BigInt.one);
      expect(parseNusanToMsat('2.25'), BigInt.from(2250));
    });

    test('spasi di tepi ditoleransi', () {
      expect(parseNusanToMsat('  3  '), BigInt.from(3000));
    });

    test('teks tidak valid menghasilkan null', () {
      expect(parseNusanToMsat(''), isNull);
      expect(parseNusanToMsat('abc'), isNull);
      expect(parseNusanToMsat('-5'), isNull);
      expect(parseNusanToMsat('1.0000'), isNull);
      expect(parseNusanToMsat('1.5.2'), isNull);
      expect(parseNusanToMsat('.5'), isNull);
    });
  });

  group('directChannels', () {
    test('channel LSP disaring keluar, channel langsung dipertahankan', () {
      final result = directChannels(
        [_channel(_lspId), _channel(_peerId)],
        _lspId,
      );
      expect(result.length, 1);
      expect(result.single.counterpartyNodeId.hex, _peerId);
    });

    test('daftar kosong tetap kosong', () {
      expect(directChannels(const [], _lspId), isEmpty);
    });
  });

  group('bridgeCounterpartId', () {
    test('satu peer non-LSP tersambung dipilih', () {
      final peers = [
        _peer(_lspId, connected: true),
        _peer(_peerId, connected: true),
      ];
      expect(bridgeCounterpartId(peers, _lspId), _peerId);
    });

    test('peer non-LSP yang putus tidak dipilih', () {
      final peers = [
        _peer(_lspId, connected: true),
        _peer(_peerId, connected: false),
      ];
      expect(bridgeCounterpartId(peers, _lspId), isNull);
    });

    test('dua calon non-LSP berarti ambigu: null', () {
      final peers = [
        _peer(_peerId, connected: true),
        _peer(_otherId, connected: true),
      ];
      expect(bridgeCounterpartId(peers, _lspId), isNull);
    });
  });

  group('canOpenDirectChannel', () {
    test('peer tersambung dan sesi online: boleh', () {
      expect(
        canOpenDirectChannel(peerConnected: true, sessionOffline: false),
        isTrue,
      );
    });

    test('peer tersambung tapi sesi offline: ditolak', () {
      expect(
        canOpenDirectChannel(peerConnected: true, sessionOffline: true),
        isFalse,
      );
    });

    test('peer belum tersambung: ditolak di kedua mode sesi', () {
      expect(
        canOpenDirectChannel(peerConnected: false, sessionOffline: false),
        isFalse,
      );
      expect(
        canOpenDirectChannel(peerConnected: false, sessionOffline: true),
        isFalse,
      );
    });
  });
}
