import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/opening_paths_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _peerId =
    '035d4490410d765e327bd33bcaaa0db8bc1b0ea7ca0f8df7e9db8d9279b16683b0';
const _otherId =
    '02cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

UserChannelId _userId(int fill) =>
    UserChannelId(data: Uint8List.fromList(List.filled(16, fill)));

ChannelDetails _channelWithUserId(UserChannelId userId) {
  return ChannelDetails(
    channelId: ChannelId(
      data: U8Array32(Uint8List.fromList(List.filled(32, 1))),
    ),
    counterpartyNodeId: PublicKey(hex: _peerId),
    channelValueSats: BigInt.from(100000),
    userChannelId: userId,
    feerateSatPer1000Weight: 1000,
    outboundCapacityMsat: BigInt.from(99000000),
    inboundCapacityMsat: BigInt.from(1000000),
    isOutbound: true,
    isChannelReady: false,
    isUsable: false,
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('userChannelIdHex', () {
    test('byte di-hex-kan 2 digit per byte', () {
      expect(
        userChannelIdHex(
          UserChannelId(data: Uint8List.fromList([0, 1, 15, 255])),
        ),
        '00010fff',
      );
    });
  });

  group('OpeningPathsStore', () {
    test('noteOpened lalu hasOpeningFor true untuk peer itu', () async {
      final store = OpeningPathsStore();
      await store.load();
      await store.noteOpened(peerNodeIdHex: _peerId, userChannelId: _userId(7));
      expect(store.hasOpeningFor(_peerId), isTrue);
      expect(store.hasOpeningFor(_peerId.toUpperCase()), isTrue);
      expect(store.hasOpeningFor(_otherId), isFalse);
    });

    test('prune menghapus entri yang channel-nya muncul', () async {
      final store = OpeningPathsStore();
      await store.load();
      await store.noteOpened(peerNodeIdHex: _peerId, userChannelId: _userId(7));
      await store.prune([_channelWithUserId(_userId(7))]);
      expect(store.hasOpeningFor(_peerId), isFalse);
    });

    test('prune mempertahankan entri yang channel-nya belum muncul', () async {
      final store = OpeningPathsStore();
      await store.load();
      await store.noteOpened(peerNodeIdHex: _peerId, userChannelId: _userId(7));
      await store.prune([_channelWithUserId(_userId(9))]);
      expect(store.hasOpeningFor(_peerId), isTrue);
      await store.prune([]);
      expect(store.hasOpeningFor(_peerId), isTrue);
    });

    test('entri selamat dari mulai ulang (dipersist)', () async {
      final store = OpeningPathsStore();
      await store.load();
      await store.noteOpened(peerNodeIdHex: _peerId, userChannelId: _userId(7));
      final store2 = OpeningPathsStore();
      await store2.load();
      expect(store2.hasOpeningFor(_peerId), isTrue);
    });

    test('entri tersimpan yang rusak dilewati', () async {
      SharedPreferences.setMockInitialValues({
        'buat_jalur_dalam_pembukaan_v1': [
          'bukan-format-yang-sah',
          '$_peerId|${'07' * 16}',
          '|kosong',
        ],
      });
      final store = OpeningPathsStore();
      await store.load();
      expect(store.hasOpeningFor(_peerId), isTrue);
    });
  });
}
