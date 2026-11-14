import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/lsp_service.dart';

ChannelDetails _channel({
  required bool usable,
  required int outboundMsat,
  String? counterparty,
  int? reserveSats,
}) {
  return ChannelDetails(
    channelId: ChannelId(
      data: U8Array32(Uint8List.fromList(List.filled(32, 1))),
    ),
    counterpartyNodeId: PublicKey(hex: counterparty ?? '02${'11' * 32}'),
    channelValueSats: BigInt.from(25000),
    userChannelId:
        UserChannelId(data: Uint8List.fromList(List.filled(16, 0))),
    feerateSatPer1000Weight: 1000,
    outboundCapacityMsat: BigInt.from(outboundMsat),
    inboundCapacityMsat: BigInt.zero,
    isOutbound: false,
    isChannelReady: usable,
    isUsable: usable,
    unspendablePunishmentReserve: reserveSats == null
        ? null
        : BigInt.from(reserveSats),
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
  group('totalUsableOutboundCapacityMsat', () {
    test('tanpa channel: nol', () {
      expect(totalUsableOutboundCapacityMsat([]), BigInt.zero);
    });

    test('hanya channel usable yang dijumlahkan', () {
      final channels = [
        _channel(usable: true, outboundMsat: 657000),
        _channel(usable: false, outboundMsat: 9000000),
      ];
      expect(totalUsableOutboundCapacityMsat(channels),
          BigInt.from(657000));
    });

    test('beberapa channel usable dijumlahkan', () {
      final channels = [
        _channel(usable: true, outboundMsat: 1000000),
        _channel(usable: true, outboundMsat: 2500000),
        _channel(usable: false, outboundMsat: 4000000),
      ];
      expect(totalUsableOutboundCapacityMsat(channels),
          BigInt.from(3500000));
    });
  });

  group('usableOutboundCapacityToPeer', () {
    const peer =
        '035d4490410d765e327bd33bcaaa0db8bc1b0ea7ca0f8df7e9db8d9279b16683b0';
    const lsp =
        '02b69d63f7f07765257d729b4141426abff80a91088eb439ec6f2e9669b6423549';

    test('tanpa channel: nol', () {
      expect(usableOutboundCapacityToPeer([], peer), BigInt.zero);
    });

    test('peer null: nol', () {
      final channels = [_channel(usable: true, outboundMsat: 1000000)];
      expect(usableOutboundCapacityToPeer(channels, null), BigInt.zero);
    });

    test('hanya channel ke peer itu yang dijumlahkan', () {
      final channels = [
        _channel(usable: true, outboundMsat: 679000000, counterparty: peer),
        _channel(usable: true, outboundMsat: 5000000000, counterparty: lsp),
        _channel(usable: true, outboundMsat: 100000000, counterparty: peer),
      ];
      expect(
        usableOutboundCapacityToPeer(channels, peer),
        BigInt.from(779000000),
      );
    });

    test('channel peer yang belum usable dikecualikan', () {
      final channels = [
        _channel(usable: false, outboundMsat: 900000000, counterparty: peer),
        _channel(usable: true, outboundMsat: 679000000, counterparty: peer),
      ];
      expect(
        usableOutboundCapacityToPeer(channels, peer),
        BigInt.from(679000000),
      );
    });

    test('perbandingan ID tidak peka huruf besar/kecil', () {
      final channels = [
        _channel(usable: true, outboundMsat: 679000000, counterparty: peer),
      ];
      expect(
        usableOutboundCapacityToPeer(channels, peer.toUpperCase()),
        BigInt.from(679000000),
      );
    });

    test('cadangan TIDAK dikurangi lagi: kapasitas keluar node '
        'sudah bersih dari cadangan', () {
      // Kasus lapangan 13 Nov 2026: sisi channel 880.000 nusan
      // dengan cadangan 201.000 nusan → yang bisa dikirim
      // 679.000 nusan. outboundCapacityMsat node SUDAH sebesar
      // 679.000.000 msat; mengurangkan cadangan sekali lagi
      // akan memberi angka 478.000 yang salah.
      final channels = [
        _channel(
          usable: true,
          outboundMsat: 679000000,
          counterparty: peer,
          reserveSats: 201000,
        ),
      ];
      expect(
        usableOutboundCapacityToPeer(channels, peer),
        BigInt.from(679000000),
      );
    });
  });

  group('evaluateSend', () {
    // Satuan msat. Patokan kasus lapangan 31 Okt: saldo 995 nusan
    // (995.000 msat), kapasitas kirim 0 karena cadangan 1.000 nusan
    // pada channel 25.000.
    test('kasus lapangan: saldo 995, kirim 500 → tertahan cadangan', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(500000),
          balanceMsat: BigInt.from(995000),
          usableOutboundMsat: BigInt.zero,
          hasUsableChannel: true,
        ),
        SendCheck.reserveHeld,
      );
    });

    test('saldo bertambah melewati cadangan: kirim yang sama → ok', () {
      // Sesudah terima 662: saldo 1.657, kapasitas kirim 657 —
      // pembayaran 500 yang tadinya gagal memang lolos di lapangan.
      expect(
        evaluateSend(
          amountMsat: BigInt.from(500000),
          balanceMsat: BigInt.from(1657000),
          usableOutboundMsat: BigInt.from(657000),
          hasUsableChannel: true,
        ),
        SendCheck.ok,
      );
    });

    test('nominal persis sebesar kapasitas kirim → ok', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(657000),
          balanceMsat: BigInt.from(1657000),
          usableOutboundMsat: BigInt.from(657000),
          hasUsableChannel: true,
        ),
        SendCheck.ok,
      );
    });

    test('nominal melewati saldo → saldo tidak cukup', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(2000000),
          balanceMsat: BigInt.from(1657000),
          usableOutboundMsat: BigInt.from(657000),
          hasUsableChannel: true,
        ),
        SendCheck.insufficientBalance,
      );
    });

    test('di atas saldo DAN di atas kapasitas: saldo didahulukan', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(9000000),
          balanceMsat: BigInt.from(995000),
          usableOutboundMsat: BigInt.zero,
          hasUsableChannel: true,
        ),
        SendCheck.insufficientBalance,
      );
    });

    test('tanpa channel usable: pemeriksaan cadangan dilewati', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(500000),
          balanceMsat: BigInt.from(995000),
          usableOutboundMsat: BigInt.zero,
          hasUsableChannel: false,
        ),
        SendCheck.ok,
      );
    });

    test('tanpa channel usable pun saldo tetap diperiksa', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(2000000),
          balanceMsat: BigInt.from(995000),
          usableOutboundMsat: BigInt.zero,
          hasUsableChannel: false,
        ),
        SendCheck.insufficientBalance,
      );
    });
  });

  group('evaluateSend dengan batas peer (lingkup offline)', () {
    // Patokan kasus lapangan 13 Nov 2026: saldo kirim gabungan
    // besar (channel LSP ikut terhitung) tetapi channel langsung
    // ke perangkat tertaut tinggal 679.000 nusan yang bisa
    // dikirim — nominal di antaranya harus tertahan sebagai
    // batas peer, bukan lolos lalu gagal tanpa rute di node.
    test('muat di gabungan, melewati lingkup → batas peer', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(1000000000),
          balanceMsat: BigInt.from(2000000000),
          usableOutboundMsat: BigInt.from(1500000000),
          hasUsableChannel: true,
          scopedUsableOutboundMsat: BigInt.from(679000000),
        ),
        SendCheck.peerLimit,
      );
    });

    test('muat di lingkup → ok', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(50000000),
          balanceMsat: BigInt.from(2000000000),
          usableOutboundMsat: BigInt.from(1500000000),
          hasUsableChannel: true,
          scopedUsableOutboundMsat: BigInt.from(679000000),
        ),
        SendCheck.ok,
      );
    });

    test('nominal persis sebesar lingkup → ok', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(679000000),
          balanceMsat: BigInt.from(2000000000),
          usableOutboundMsat: BigInt.from(1500000000),
          hasUsableChannel: true,
          scopedUsableOutboundMsat: BigInt.from(679000000),
        ),
        SendCheck.ok,
      );
    });

    test('melewati gabungan juga: cadangan didahulukan', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(1600000000),
          balanceMsat: BigInt.from(2000000000),
          usableOutboundMsat: BigInt.from(1500000000),
          hasUsableChannel: true,
          scopedUsableOutboundMsat: BigInt.from(679000000),
        ),
        SendCheck.reserveHeld,
      );
    });

    test('melewati saldo juga: saldo didahulukan', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(3000000000),
          balanceMsat: BigInt.from(2000000000),
          usableOutboundMsat: BigInt.from(1500000000),
          hasUsableChannel: true,
          scopedUsableOutboundMsat: BigInt.from(679000000),
        ),
        SendCheck.insufficientBalance,
      );
    });

    test('lingkup null: perilaku lama (tanpa batas peer)', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(1000000000),
          balanceMsat: BigInt.from(2000000000),
          usableOutboundMsat: BigInt.from(1500000000),
          hasUsableChannel: true,
        ),
        SendCheck.ok,
      );
    });

    test('lingkup nol: nominal apa pun → batas peer', () {
      expect(
        evaluateSend(
          amountMsat: BigInt.from(50000000),
          balanceMsat: BigInt.from(2000000000),
          usableOutboundMsat: BigInt.from(1500000000),
          hasUsableChannel: true,
          scopedUsableOutboundMsat: BigInt.zero,
        ),
        SendCheck.peerLimit,
      );
    });
  });
}
