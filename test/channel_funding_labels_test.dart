import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/payment_notes.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lspNodeId =
    '02b69d63f7f07765257d729b4141426abff80a91088eb439ec6f2e9669b6423549';
const _peerId =
    '035d4490410d765e327bd33bcaaa0db8bc1b0ea7ca0f8df7e9db8d9279b16683b0';

final _txidLsp = 'aa' * 32;
final _txidDirect = 'bb' * 32;
final _txidUnknown = 'cc' * 32;

ChannelDetails _channel(String counterpartyHex, {String? fundingTxid}) {
  return ChannelDetails(
    channelId: ChannelId(
      data: U8Array32(Uint8List.fromList(List.filled(32, 1))),
    ),
    counterpartyNodeId: PublicKey(hex: counterpartyHex),
    channelValueSats: BigInt.from(25000),
    userChannelId: UserChannelId(data: Uint8List.fromList(List.filled(16, 0))),
    fundingTxo: fundingTxid == null
        ? null
        : OutPoint(txid: Txid(hash: fundingTxid), vout: 0),
    confirmations: 6,
    confirmationsRequired: 6,
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
      maxDustHtlcExposure: MaxDustHTLCExposure_FeeRateMultiplier(
        BigInt.from(1000),
      ),
      forceCloseAvoidanceMaxFeeSatoshis: BigInt.from(1000),
      acceptUnderpayingHtlcs: false,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('matchChannelFundingKind', () {
    final channels = [
      _channel(_lspNodeId, fundingTxid: _txidLsp),
      _channel(_peerId, fundingTxid: _txidDirect),
      _channel(_peerId),
    ];

    test('txid pendanaan channel LSP → lsp', () {
      expect(
        matchChannelFundingKind(
          txid: _txidLsp,
          channels: channels,
          lspNodeIdHex: _lspNodeId,
        ),
        fundingKindLsp,
      );
    });

    test('txid pendanaan channel langsung → direct', () {
      expect(
        matchChannelFundingKind(
          txid: _txidDirect,
          channels: channels,
          lspNodeIdHex: _lspNodeId,
        ),
        fundingKindDirect,
      );
    });

    test('txid bukan pendanaan channel mana pun → null', () {
      expect(
        matchChannelFundingKind(
          txid: _txidUnknown,
          channels: channels,
          lspNodeIdHex: _lspNodeId,
        ),
        isNull,
      );
    });

    test('channel tanpa fundingTxo dilewati (jendela negosiasi)', () {
      expect(
        matchChannelFundingKind(
          txid: _txidUnknown,
          channels: [_channel(_peerId)],
          lspNodeIdHex: _lspNodeId,
        ),
        isNull,
      );
    });

    test('perbandingan ID node tidak peka huruf', () {
      expect(
        matchChannelFundingKind(
          txid: _txidLsp,
          channels: channels,
          lspNodeIdHex: _lspNodeId.toUpperCase(),
        ),
        fundingKindLsp,
      );
    });
  });

  group('fundingLabelTextForKind', () {
    test('lsp → teks persis keputusan rancangan', () {
      expect(
        fundingLabelTextForKind(fundingKindLsp),
        'Pembukaan Channel ke LSP⚡',
      );
    });

    test('direct → teks persis keputusan rancangan', () {
      expect(
        fundingLabelTextForKind(fundingKindDirect),
        'Pembukaan Channel Langsung⚡',
      );
    });

    test('jenis tidak dikenal / null → null (tampil on-chain polos)', () {
      expect(fundingLabelTextForKind('jit'), isNull);
      expect(fundingLabelTextForKind(null), isNull);
      expect(fundingLabelTextForKind(''), isNull);
    });
  });

  group('ChannelFundingLabelStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save → loadAll memuat pasangan txid → jenis', () async {
      final store = ChannelFundingLabelStore();
      expect(await store.loadAll(), isEmpty);
      await store.save(_txidLsp, fundingKindLsp);
      await store.save(_txidDirect, fundingKindDirect);
      expect(await store.loadAll(), {
        _txidLsp: fundingKindLsp,
        _txidDirect: fundingKindDirect,
      });
    });

    test('label bertahan lintas instance (persisten sesudah tutup)', () async {
      // Skenario §4.4 rancangan: pasangan dicatat saat channel
      // masih terdaftar; sesudah channel ditutup (dan hilang dari
      // daftar node) simpanan inilah satu-satunya sumber label.
      await ChannelFundingLabelStore().save(_txidDirect, fundingKindDirect);
      expect(await ChannelFundingLabelStore().loadAll(), {
        _txidDirect: fundingKindDirect,
      });
    });

    test('saveAll menyimpan banyak pasangan sekaligus', () async {
      final store = ChannelFundingLabelStore();
      await store.saveAll({
        _txidLsp: fundingKindLsp,
        _txidDirect: fundingKindDirect,
      });
      expect(await store.loadAll(), {
        _txidLsp: fundingKindLsp,
        _txidDirect: fundingKindDirect,
      });
    });

    test('saveAll membuang entri tidak sah, sisanya tetap tersimpan', () async {
      final store = ChannelFundingLabelStore();
      await store.saveAll({
        'terlalu-pendek': fundingKindLsp,
        _txidLsp: 'jenis-tidak-dikenal',
        _txidDirect: fundingKindDirect,
      });
      expect(await store.loadAll(), {_txidDirect: fundingKindDirect});
    });

    test(
      'txid bukan 64 karakter / jenis tidak dikenal tidak disimpan',
      () async {
        final store = ChannelFundingLabelStore();
        await store.save('abc', fundingKindLsp);
        await store.save(_txidLsp, 'jenis-tidak-dikenal');
        expect(await store.loadAll(), isEmpty);
      },
    );

    test('simpanan rusak → peta kosong (fail-open)', () async {
      SharedPreferences.setMockInitialValues({
        ChannelFundingLabelStore.storageKey: 'bukan-json{{',
      });
      expect(await ChannelFundingLabelStore().loadAll(), isEmpty);
    });
  });
}
