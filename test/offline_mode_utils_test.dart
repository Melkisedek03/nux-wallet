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

OutPoint _fundingTxo(String txid) =>
    OutPoint(txid: Txid(hash: txid), vout: 0);

ChannelDetails _channel(
  String counterpartyHex, {
  bool usable = true,
  bool? channelReady,
  OutPoint? fundingTxo,
  int? confirmations,
  int? confirmationsRequired,
  int channelValueSats = 25000,
}) {
  return ChannelDetails(
    channelId: ChannelId(
      data: U8Array32(Uint8List.fromList(List.filled(32, 1))),
    ),
    counterpartyNodeId: PublicKey(hex: counterpartyHex),
    channelValueSats: BigInt.from(channelValueSats),
    userChannelId: UserChannelId(data: Uint8List.fromList(List.filled(16, 0))),
    fundingTxo: fundingTxo,
    confirmations: confirmations,
    confirmationsRequired: confirmationsRequired,
    feerateSatPer1000Weight: 1000,
    outboundCapacityMsat: BigInt.from(24000000),
    inboundCapacityMsat: BigInt.from(1000000),
    isOutbound: true,
    isChannelReady: channelReady ?? usable,
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

  group('isPreparingChannel', () {
    test('jendela negosiasi (tanpa fundingTxo, tanpa konfirmasi)', () {
      expect(isPreparingChannel(_channel(_peerId, usable: false)), isTrue);
    });

    test('menunggu konfirmasi 3/6', () {
      expect(
        isPreparingChannel(
          _channel(
            _peerId,
            usable: false,
            fundingTxo: _fundingTxo('aa' * 32),
            confirmations: 3,
            confirmationsRequired: 6,
          ),
        ),
        isTrue,
      );
    });

    test('channel_ready bukan disiapkan', () {
      expect(isPreparingChannel(_channel(_peerId)), isFalse);
    });

    test('channel ditutup (6/6, belum ready) bukan disiapkan', () {
      expect(
        isPreparingChannel(
          _channel(
            _peerId,
            usable: false,
            channelReady: false,
            fundingTxo: _fundingTxo('aa' * 32),
            confirmations: 6,
            confirmationsRequired: 6,
          ),
        ),
        isFalse,
      );
    });
  });

  group('pathStateFor', () {
    test('daftar kosong berarti belum ada', () {
      expect(pathStateFor([], _peerId), PathState.none);
    });

    test('peer null berarti belum ada', () {
      expect(pathStateFor([_channel(_peerId)], null), PathState.none);
    });

    test('channel peer lain tidak dihitung', () {
      expect(pathStateFor([_channel(_otherId)], _peerId), PathState.none);
    });

    test('channel usable dengan peer berarti siap', () {
      expect(pathStateFor([_channel(_peerId)], _peerId), PathState.ready);
    });

    test('channel menegosiasikan berarti disiapkan', () {
      expect(
        pathStateFor([_channel(_peerId, usable: false)], _peerId),
        PathState.preparing,
      );
    });

    test('channel menunggu konfirmasi berarti disiapkan', () {
      expect(
        pathStateFor(
          [
            _channel(
              _peerId,
              usable: false,
              fundingTxo: _fundingTxo('aa' * 32),
              confirmations: 0,
              confirmationsRequired: 6,
            ),
          ],
          _peerId,
        ),
        PathState.preparing,
      );
    });

    test('pembukaan dalam penerbangan (tanpa channel) berarti disiapkan', () {
      expect(
        pathStateFor([], _peerId, hasOpening: true),
        PathState.preparing,
      );
    });

    test('siap mengalahkan disiapkan (balapan dua channel)', () {
      expect(
        pathStateFor(
          [
            _channel(_peerId, usable: false),
            _channel(_peerId),
          ],
          _peerId,
        ),
        PathState.ready,
      );
    });

    test('perbandingan ID tidak peka huruf besar/kecil', () {
      expect(
        pathStateFor([_channel(_peerId)], _peerId.toUpperCase()),
        PathState.ready,
      );
    });
  });

  group('preparingChannelForPeer', () {
    test('memilih channel yang disiapkan dengan peer itu', () {
      final preparing = _channel(
        _peerId,
        usable: false,
        fundingTxo: _fundingTxo('aa' * 32),
        confirmations: 2,
        confirmationsRequired: 6,
      );
      expect(
        preparingChannelForPeer([_channel(_otherId), preparing], _peerId),
        preparing,
      );
    });

    test('mengabaikan channel siap dan peer lain', () {
      expect(
        preparingChannelForPeer([_channel(_peerId)], _peerId),
        isNull,
      );
      expect(
        preparingChannelForPeer(
          [_channel(_otherId, usable: false)],
          _peerId,
        ),
        isNull,
      );
    });

    test('bila dua, yang konfirmasinya paling banyak dipilih', () {
      final early = _channel(
        _peerId,
        usable: false,
        fundingTxo: _fundingTxo('aa' * 32),
        confirmations: 1,
        confirmationsRequired: 6,
      );
      final late = _channel(
        _peerId,
        usable: false,
        fundingTxo: _fundingTxo('bb' * 32),
        confirmations: 4,
        confirmationsRequired: 6,
      );
      expect(preparingChannelForPeer([early, late], _peerId), late);
    });
  });

  group('preparingDirectChannel', () {
    const lspId =
        '02b69d63f7f07765257d729b4141426abff80a91088eb439ec6f2e9669b6423549';

    test('memilih channel langsung yang disiapkan', () {
      final preparing = _channel(
        _peerId,
        usable: false,
        fundingTxo: _fundingTxo('aa' * 32),
        confirmations: 2,
        confirmationsRequired: 6,
      );
      expect(preparingDirectChannel([preparing], lspId), preparing);
    });

    test('channel LSP tidak pernah dihitung', () {
      expect(
        preparingDirectChannel(
          [
            _channel(
              lspId,
              usable: false,
              fundingTxo: _fundingTxo('aa' * 32),
              confirmations: 2,
              confirmationsRequired: 6,
            ),
          ],
          lspId,
        ),
        isNull,
      );
    });

    test('channel siap diabaikan', () {
      expect(preparingDirectChannel([_channel(_peerId)], lspId), isNull);
    });

    test('daftar kosong berarti null', () {
      expect(preparingDirectChannel([], lspId), isNull);
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

    test('tertaut dengan jalur disiapkan berarti disiapkan', () {
      expect(
        offlineModeState(
          sessionActive: true,
          linked: true,
          pathReady: false,
          pathPreparing: true,
        ),
        OfflineModeState.preparing,
      );
    });

    test('siap mengalahkan disiapkan', () {
      expect(
        offlineModeState(
          sessionActive: true,
          linked: true,
          pathReady: true,
          pathPreparing: true,
        ),
        OfflineModeState.ready,
      );
    });

    test('belum tertaut berarti mencari walau ada penyiapan', () {
      expect(
        offlineModeState(
          sessionActive: true,
          linked: false,
          pathReady: false,
          pathPreparing: true,
        ),
        OfflineModeState.searching,
      );
    });
  });
}
