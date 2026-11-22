import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/deposit_progress.dart';

PaymentDetails _onchain({
  required String txid,
  required ConfirmationStatus confirmation,
  BigInt? amountMsat,
  required PaymentDirection direction,
  required PaymentStatus status,
}) {
  return PaymentDetails(
    id: PaymentId(data: Uint8List.fromList([1, 2, 3])),
    kind: PaymentKind_Onchain(
      txid: Txid(hash: txid),
      status: confirmation,
    ),
    amountMsat: amountMsat,
    direction: direction,
    status: status,
    latestUpdateTimestamp: BigInt.from(1700000000),
  );
}

PaymentDetails _bolt11InboundPending() {
  return PaymentDetails(
    id: PaymentId(data: Uint8List.fromList([4, 5, 6])),
    kind: PaymentKind_Bolt11(
      hash: PaymentHash(
        data: U8Array32(Uint8List.fromList(List.filled(32, 7))),
      ),
    ),
    amountMsat: BigInt.from(1500),
    direction: PaymentDirection.inbound,
    status: PaymentStatus.pending,
    latestUpdateTimestamp: BigInt.from(1700000000),
  );
}

ConfirmationStatus _confirmed(int height) => ConfirmationStatus.confirmed(
  blockHash: '00' * 32,
  height: height,
  timestamp: BigInt.from(1700000000),
);

void main() {
  group('depositConfirmations', () {
    test('belum terkonfirmasi → 0, tanpa perlu tinggi ujung', () {
      expect(
        depositConfirmations(
          status: ConfirmationStatus.unconfirmed(),
          tipHeight: null,
        ),
        0,
      );
      expect(
        depositConfirmations(
          status: ConfirmationStatus.unconfirmed(),
          tipHeight: 100,
        ),
        0,
      );
    });

    test('terkonfirmasi di ujung → 1', () {
      expect(depositConfirmations(status: _confirmed(100), tipHeight: 100), 1);
    });

    test('sebagian: tinggi 100, ujung 102 → 3', () {
      expect(depositConfirmations(status: _confirmed(100), tipHeight: 102), 3);
    });

    test('tepat 6: tinggi 100, ujung 105 → 6', () {
      expect(depositConfirmations(status: _confirmed(100), tipHeight: 105), 6);
    });

    test('di atas 6 dicap ke 6/6', () {
      expect(depositConfirmations(status: _confirmed(100), tipHeight: 200), 6);
    });

    test('ujung di bawah tinggi konfirmasi (tepi reorg) → 0', () {
      expect(depositConfirmations(status: _confirmed(100), tipHeight: 99), 0);
    });

    test('terkonfirmasi + ujung tidak diketahui → null', () {
      expect(
        depositConfirmations(status: _confirmed(100), tipHeight: null),
        isNull,
      );
    });
  });

  group('pendingDepositPayments', () {
    test('masuk on-chain menunggu → ikut', () {
      final payments = [
        _onchain(
          txid: 'aa',
          confirmation: ConfirmationStatus.unconfirmed(),
          amountMsat: BigInt.from(1500000),
          direction: PaymentDirection.inbound,
          status: PaymentStatus.pending,
        ),
      ];
      expect(pendingDepositPayments(payments), hasLength(1));
    });

    test('keluar on-chain menunggu → tidak ikut', () {
      final payments = [
        _onchain(
          txid: 'aa',
          confirmation: ConfirmationStatus.unconfirmed(),
          amountMsat: BigInt.from(1500000),
          direction: PaymentDirection.outbound,
          status: PaymentStatus.pending,
        ),
      ];
      expect(pendingDepositPayments(payments), isEmpty);
    });

    test('masuk on-chain berhasil → tidak ikut (6/6 sudah lewat)', () {
      final payments = [
        _onchain(
          txid: 'aa',
          confirmation: _confirmed(100),
          amountMsat: BigInt.from(1500000),
          direction: PaymentDirection.inbound,
          status: PaymentStatus.succeeded,
        ),
      ];
      expect(pendingDepositPayments(payments), isEmpty);
    });

    test('masuk on-chain gagal → tidak ikut', () {
      final payments = [
        _onchain(
          txid: 'aa',
          confirmation: ConfirmationStatus.unconfirmed(),
          amountMsat: BigInt.from(1500000),
          direction: PaymentDirection.inbound,
          status: PaymentStatus.failed,
        ),
      ];
      expect(pendingDepositPayments(payments), isEmpty);
    });

    test('masuk Lightning menunggu → tidak ikut', () {
      expect(pendingDepositPayments([_bolt11InboundPending()]), isEmpty);
    });
  });

  group('pendingDeposits', () {
    test('jumlah msat diubah ke nusan utuh', () {
      final deposits = pendingDeposits([
        _onchain(
          txid: 'aa',
          confirmation: _confirmed(100),
          amountMsat: BigInt.from(1500000),
          direction: PaymentDirection.inbound,
          status: PaymentStatus.pending,
        ),
      ], 102);
      expect(deposits, hasLength(1));
      expect(deposits.first.txid, 'aa');
      expect(deposits.first.amountSats, BigInt.from(1500));
      expect(deposits.first.confirmations, 3);
    });

    test('pembayaran tanpa jumlah dilewati', () {
      final deposits = pendingDeposits([
        _onchain(
          txid: 'aa',
          confirmation: _confirmed(100),
          amountMsat: null,
          direction: PaymentDirection.inbound,
          status: PaymentStatus.pending,
        ),
      ], 102);
      expect(deposits, isEmpty);
    });

    test('ujung tidak diketahui → konfirmasi null, baris tetap ada', () {
      final deposits = pendingDeposits([
        _onchain(
          txid: 'aa',
          confirmation: _confirmed(100),
          amountMsat: BigInt.from(1500000),
          direction: PaymentDirection.inbound,
          status: PaymentStatus.pending,
        ),
      ], null);
      expect(deposits, hasLength(1));
      expect(deposits.first.confirmations, isNull);
    });

    test('urutan riwayat dipertahankan', () {
      final deposits = pendingDeposits([
        _onchain(
          txid: 'baru',
          confirmation: ConfirmationStatus.unconfirmed(),
          amountMsat: BigInt.from(1000),
          direction: PaymentDirection.inbound,
          status: PaymentStatus.pending,
        ),
        _onchain(
          txid: 'lama',
          confirmation: _confirmed(100),
          amountMsat: BigInt.from(2000),
          direction: PaymentDirection.inbound,
          status: PaymentStatus.pending,
        ),
      ], 102);
      expect(deposits.map((d) => d.txid).toList(), ['baru', 'lama']);
    });
  });

  group('DepositProgressService.fetchTipHeight', () {
    test('200 dengan angka → tinggi', () async {
      final service = DepositProgressService(
        client: MockClient((_) async => http.Response('73690', 200)),
      );
      expect(await service.fetchTipHeight(), 73690);
    });

    test('spasi/newline di sekitar angka ditoleransi', () async {
      final service = DepositProgressService(
        client: MockClient((_) async => http.Response('  73690\n', 200)),
      );
      expect(await service.fetchTipHeight(), 73690);
    });

    test('bukan 200 → null', () async {
      final service = DepositProgressService(
        client: MockClient((_) async => http.Response('nope', 500)),
      );
      expect(await service.fetchTipHeight(), isNull);
    });

    test('isi bukan angka → null', () async {
      final service = DepositProgressService(
        client: MockClient((_) async => http.Response('bukan angka', 200)),
      );
      expect(await service.fetchTipHeight(), isNull);
    });

    test('pengecualian jaringan → null (gagal-terbuka)', () async {
      final service = DepositProgressService(
        client: MockClient((_) async => throw Exception('putus')),
      );
      expect(await service.fetchTipHeight(), isNull);
    });
  });
}
