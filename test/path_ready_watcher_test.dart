import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/path_ready_watcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _peerId =
    '035d4490410d765e327bd33bcaaa0db8bc1b0ea7ca0f8df7e9db8d9279b16683b0';
const _lspId =
    '02b69d63f7f07765257d729b4141426abff80a91088eb439ec6f2e9669b6423549';
final _txid = 'aa' * 32;

ChannelDetails _channel(
  String counterpartyHex, {
  bool usable = true,
  bool channelReady = true,
  int? confirmations,
  int? confirmationsRequired,
  String? fundingTxid,
}) {
  return ChannelDetails(
    channelId: ChannelId(
      data: U8Array32(Uint8List.fromList(List.filled(32, 1))),
    ),
    counterpartyNodeId: PublicKey(hex: counterpartyHex),
    channelValueSats: BigInt.from(100000),
    userChannelId: UserChannelId(data: Uint8List.fromList(List.filled(16, 0))),
    fundingTxo: fundingTxid == null
        ? null
        : OutPoint(txid: Txid(hash: fundingTxid), vout: 0),
    confirmations: confirmations,
    confirmationsRequired: confirmationsRequired,
    feerateSatPer1000Weight: 1000,
    outboundCapacityMsat: BigInt.from(99000000),
    inboundCapacityMsat: BigInt.from(1000000),
    isOutbound: true,
    isChannelReady: channelReady,
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PathReadyWatcher', () {
    test('sebelum load, pemeriksaan dilewati', () async {
      final watcher = PathReadyWatcher();
      expect(
        watcher.check([_channel(_peerId, fundingTxid: _txid)], _lspId),
        isEmpty,
      );
      expect(watcher.hasPendingPreparation, isFalse);
    });

    test('pemeriksaan pertama hanya mengisi garis dasar', () async {
      final watcher = PathReadyWatcher();
      await watcher.load();
      expect(
        watcher.check([_channel(_peerId, fundingTxid: _txid)], _lspId),
        isEmpty,
      );
      // Siklus kedua pun tidak menembak: channel sudah usable
      // sejak garis dasar.
      expect(
        watcher.check([_channel(_peerId, fundingTxid: _txid)], _lspId),
        isEmpty,
      );
    });

    test('transisi menjadi usable menembak sekali', () async {
      final watcher = PathReadyWatcher();
      await watcher.load();
      final preparing = _channel(
        _peerId,
        usable: false,
        channelReady: false,
        confirmations: 3,
        confirmationsRequired: 6,
        fundingTxid: _txid,
      );
      expect(watcher.check([preparing], _lspId), isEmpty);
      expect(watcher.hasPendingPreparation, isTrue);
      final ready = _channel(_peerId, fundingTxid: _txid);
      final fresh = watcher.check([ready], _lspId);
      expect(fresh, hasLength(1));
      expect(fresh.first.fundingTxo!.txid.hash, _txid);
      expect(watcher.hasPendingPreparation, isFalse);
      // Siklus berikutnya tidak menembak lagi.
      expect(watcher.check([ready], _lspId), isEmpty);
    });

    test('txid yang sudah diberitahu tidak menembak lagi', () async {
      final watcher = PathReadyWatcher();
      await watcher.load();
      final preparing = _channel(
        _peerId,
        usable: false,
        channelReady: false,
        confirmations: 0,
        confirmationsRequired: 6,
        fundingTxid: _txid,
      );
      expect(watcher.check([preparing], _lspId), isEmpty);
      final ready = _channel(_peerId, fundingTxid: _txid);
      expect(watcher.check([ready], _lspId), hasLength(1));
      await watcher.markNotified([_txid]);

      // Instans baru (simulasi buka ulang aplikasi): garis dasar
      // diisi saat channel masih disiapkan, lalu channel menjadi
      // usable — himpunan "sudah diberitahu" yang dipersist
      // menahan tembakan kedua.
      final watcher2 = PathReadyWatcher();
      await watcher2.load();
      expect(watcher2.check([preparing], _lspId), isEmpty);
      expect(watcher2.check([ready], _lspId), isEmpty);
    });

    test('channel LSP tidak pernah menembak', () async {
      final watcher = PathReadyWatcher();
      await watcher.load();
      final preparingLsp = _channel(
        _lspId,
        usable: false,
        channelReady: false,
        confirmations: 3,
        confirmationsRequired: 6,
        fundingTxid: _txid,
      );
      expect(watcher.check([preparingLsp], _lspId), isEmpty);
      expect(watcher.hasPendingPreparation, isFalse);
      final readyLsp = _channel(_lspId, fundingTxid: _txid);
      expect(watcher.check([readyLsp], _lspId), isEmpty);
    });

    test('channel tanpa fundingTxo tidak menembak', () async {
      final watcher = PathReadyWatcher();
      await watcher.load();
      expect(watcher.check([], _lspId), isEmpty);
      final usableNoTxo = _channel(_peerId);
      expect(watcher.check([usableNoTxo], _lspId), isEmpty);
    });

    test('channel ditutup bukan penyiapan tertunda', () async {
      final watcher = PathReadyWatcher();
      await watcher.load();
      final closing = _channel(
        _peerId,
        usable: false,
        channelReady: false,
        confirmations: 6,
        confirmationsRequired: 6,
        fundingTxid: _txid,
      );
      expect(watcher.check([closing], _lspId), isEmpty);
      expect(watcher.hasPendingPreparation, isFalse);
    });
  });
}
