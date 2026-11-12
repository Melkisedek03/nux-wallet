import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/lsp_service.dart';

const _peerId =
    '03bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

ChannelId _channelId(int fill) => ChannelId(
      data: U8Array32(Uint8List.fromList(List.filled(32, fill))),
    );

LightningBalance _awaiting({
  required BigInt amountSats,
  required int height,
  required BalanceSource source,
  int channelFill = 1,
}) =>
    LightningBalance.claimableAwaitingConfirmations(
      channelId: _channelId(channelFill),
      counterpartyNodeId: PublicKey(hex: _peerId),
      amountSatoshis: amountSats,
      confirmationHeight: height,
      source: source,
    );

LightningBalance _openChannelClaimable(BigInt amountSats) =>
    LightningBalance.claimableOnChannelClose(
      channelId: _channelId(9),
      counterpartyNodeId: PublicKey(hex: _peerId),
      amountSatoshis: amountSats,
      transactionFeeSatoshis: BigInt.zero,
      outboundPaymentHtlcRoundedMsat: BigInt.zero,
      outboundForwardedHtlcRoundedMsat: BigInt.zero,
      inboundClaimingHtlcRoundedMsat: BigInt.zero,
      inboundHtlcRoundedMsat: BigInt.zero,
    );

BalanceDetails _balances({
  BigInt? total,
  BigInt? spendable,
  List<LightningBalance> lightning = const [],
}) =>
    BalanceDetails(
      totalOnchainBalanceSats: total ?? BigInt.zero,
      spendableOnchainBalanceSats: spendable ?? BigInt.zero,
      totalLightningBalanceSats: BigInt.zero,
      lightningBalances: lightning,
      pendingBalancesFromChannelClosures: const [],
    );

void main() {
  group('onchainOverviewFromBalances', () {
    test('tanpa entri Lightning: total/spendable terus, timelock nol', () {
      final overview = onchainOverviewFromBalances(_balances(
        total: BigInt.from(100000),
        spendable: BigInt.from(99844),
      ));
      expect(overview.totalSats, BigInt.from(100000));
      expect(overview.spendableSats, BigInt.from(99844));
      expect(overview.timelockSats, BigInt.zero);
      expect(overview.timelockHeight, isNull);
    });

    test('satu entri tutup paksa: timelock + tinggi terbukanya', () {
      // Kasus lapangan 11–12 Nov 2026: channel 20.000.000 ditutup
      // paksa, 19.997.276 terkunci sampai ~blok 1535.
      final overview = onchainOverviewFromBalances(_balances(
        lightning: [
          _awaiting(
            amountSats: BigInt.from(19997276),
            height: 1535,
            source: BalanceSource.holderForceClosed,
          ),
        ],
      ));
      expect(overview.timelockSats, BigInt.from(19997276));
      expect(overview.timelockHeight, 1535);
    });

    test('dua entri terkunci: jumlah dijumlah, tinggi terbesar dipakai', () {
      final overview = onchainOverviewFromBalances(_balances(
        lightning: [
          _awaiting(
            amountSats: BigInt.from(1000),
            height: 1500,
            source: BalanceSource.holderForceClosed,
            channelFill: 1,
          ),
          _awaiting(
            amountSats: BigInt.from(2000),
            height: 1535,
            source: BalanceSource.counterpartyForceClosed,
            channelFill: 2,
          ),
        ],
      ));
      expect(overview.timelockSats, BigInt.from(3000));
      expect(overview.timelockHeight, 1535);
    });

    test('sumber tutup kerja sama dikecualikan (sudah di total)', () {
      // Output tutup kerja sama sudah berupa UTXO dompet dan sudah
      // terhitung di totalOnchainBalanceSats — memasukkannya akan
      // menampilkan dana yang sama dua kali selama ~6 blok.
      final overview = onchainOverviewFromBalances(_balances(
        total: BigInt.from(5000),
        spendable: BigInt.from(5000),
        lightning: [
          _awaiting(
            amountSats: BigInt.from(5000),
            height: 1400,
            source: BalanceSource.coopClose,
          ),
        ],
      ));
      expect(overview.timelockSats, BigInt.zero);
      expect(overview.timelockHeight, isNull);
    });

    test('channel yang masih terbuka diabaikan', () {
      // ClaimableOnChannelClose adalah perkiraan "seandainya
      // ditutup paksa sekarang", bukan dana channel tertutup.
      final overview = onchainOverviewFromBalances(_balances(
        lightning: [_openChannelClaimable(BigInt.from(25000))],
      ));
      expect(overview.timelockSats, BigInt.zero);
      expect(overview.timelockHeight, isNull);
    });

    test('sumber HTLC ikut dihitung', () {
      final overview = onchainOverviewFromBalances(_balances(
        lightning: [
          _awaiting(
            amountSats: BigInt.from(500),
            height: 1600,
            source: BalanceSource.htlc,
          ),
        ],
      ));
      expect(overview.timelockSats, BigInt.from(500));
      expect(overview.timelockHeight, 1600);
    });

    test('campuran: hanya tutup paksa + HTLC yang masuk', () {
      final overview = onchainOverviewFromBalances(_balances(
        lightning: [
          _awaiting(
            amountSats: BigInt.from(5000),
            height: 1400,
            source: BalanceSource.coopClose,
            channelFill: 1,
          ),
          _awaiting(
            amountSats: BigInt.from(1000),
            height: 1500,
            source: BalanceSource.holderForceClosed,
            channelFill: 2,
          ),
          _openChannelClaimable(BigInt.from(25000)),
        ],
      ));
      expect(overview.timelockSats, BigInt.from(1000));
      expect(overview.timelockHeight, 1500);
    });
  });
}
