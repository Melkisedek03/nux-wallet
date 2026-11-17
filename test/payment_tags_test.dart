import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/services/csv_export.dart';
import 'package:nux_wallet/services/payment_notes.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _hash = 'ab' * 32;

PaymentDetails _bolt11Payment() {
  return PaymentDetails(
    id: PaymentId(data: Uint8List.fromList([7])),
    kind: PaymentKind_Bolt11(
      hash: PaymentHash(
        data: U8Array32(Uint8List.fromList(List.filled(32, 0xAB))),
      ),
    ),
    amountMsat: BigInt.from(1000),
    direction: PaymentDirection.outbound,
    status: PaymentStatus.succeeded,
    latestUpdateTimestamp: BigInt.from(1762000000),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PaymentTagStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saveDirect → loadAll memuat tag direct', () async {
      final store = PaymentTagStore();
      expect(await store.loadAll(), isEmpty);
      await store.saveDirect(_hash);
      expect(await store.loadAll(), {_hash: paymentTagDirect});
    });

    test('hash bukan 64 karakter tidak disimpan', () async {
      final store = PaymentTagStore();
      await store.saveDirect('abc');
      expect(await store.loadAll(), isEmpty);
    });

    test('tag bertahan lintas instance (persisten)', () async {
      await PaymentTagStore().saveDirect(_hash);
      expect(await PaymentTagStore().loadAll(), {_hash: 'direct'});
    });
  });

  group('historyRowTag', () {
    test('JIT menang atas tag direct (JIT lahir dari LSP)', () {
      expect(
        historyRowTag(isJit: true, isOnchain: false, routeTag: 'direct'),
        '⚡ JIT',
      );
    });

    test('on-chain menang atas tag direct', () {
      expect(
        historyRowTag(isJit: false, isOnchain: true, routeTag: 'direct'),
        '⛓ on-chain',
      );
    });

    test('tag direct pada Lightning biasa → ⚡ direct', () {
      expect(
        historyRowTag(isJit: false, isOnchain: false, routeTag: 'direct'),
        '⚡ direct',
      );
    });

    test('tanpa tag → ⚡ polos', () {
      expect(
        historyRowTag(isJit: false, isOnchain: false, routeTag: null),
        '⚡',
      );
    });

    test('Bolt12 masuk berlabel → tag labelnya', () {
      expect(
        historyRowTag(
          isJit: false,
          isOnchain: false,
          routeTag: null,
          isBolt12Inbound: true,
          bolt12Label: 'Warung Bu Tini',
        ),
        '⚡ Warung Bu Tini',
      );
    });

    test('Bolt12 masuk tanpa label → ⚡ polos (tidak berubah)', () {
      expect(
        historyRowTag(
          isJit: false,
          isOnchain: false,
          routeTag: null,
          isBolt12Inbound: true,
        ),
        '⚡',
      );
      expect(
        historyRowTag(
          isJit: false,
          isOnchain: false,
          routeTag: null,
          isBolt12Inbound: true,
          bolt12Label: '   ',
        ),
        '⚡',
      );
    });

    test('label diabaikan bila bukan Bolt12 masuk', () {
      expect(
        historyRowTag(
          isJit: false,
          isOnchain: false,
          routeTag: null,
          bolt12Label: 'Warung Bu Tini',
        ),
        '⚡',
      );
    });

    test('label menang atas tag direct', () {
      expect(
        historyRowTag(
          isJit: false,
          isOnchain: false,
          routeTag: 'direct',
          isBolt12Inbound: true,
          bolt12Label: 'Warung Bu Tini',
        ),
        '⚡ Warung Bu Tini',
      );
    });

    test('JIT dan on-chain tetap menang atas label', () {
      expect(
        historyRowTag(
          isJit: true,
          isOnchain: false,
          routeTag: null,
          isBolt12Inbound: true,
          bolt12Label: 'Warung Bu Tini',
        ),
        '⚡ JIT',
      );
      expect(
        historyRowTag(
          isJit: false,
          isOnchain: true,
          routeTag: null,
          isBolt12Inbound: true,
          bolt12Label: 'Warung Bu Tini',
        ),
        '⛓ on-chain',
      );
    });
  });

  group('bolt12OfferLabelTag', () {
    test('label pendek tampil utuh dengan awalan ⚡', () {
      expect(bolt12OfferLabelTag('Warung Bu Tini'), '⚡ Warung Bu Tini');
    });

    test('label tepat 20 rune tidak dipangkas', () {
      expect(
        bolt12OfferLabelTag('ABCDEFGHIJKLMNOPQRST'),
        '⚡ ABCDEFGHIJKLMNOPQRST',
      );
    });

    test('label panjang dipangkas di 20 rune + …', () {
      expect(
        bolt12OfferLabelTag('ABCDEFGHIJKLMNOPQRSTUVWXY'),
        '⚡ ABCDEFGHIJKLMNOPQRST…',
      );
    });

    test('pangkasan per rune, aman untuk emoji', () {
      expect(bolt12OfferLabelTag('🏪' * 25), '⚡ ${'🏪' * 20}…');
    });

    test('spasi tepi dipangkas sebelum dihitung', () {
      expect(bolt12OfferLabelTag('  Warung Bu Tini  '), '⚡ Warung Bu Tini');
    });
  });

  group('CSV type label', () {
    test('pembayaran bertag direct → Lightning Direct', () {
      final csv = buildTransactionsCsv(
        [_bolt11Payment()],
        routeTags: {_hash: 'direct'},
      );
      expect(csv, contains('Lightning Direct'));
    });

    test('tanpa tag → Lightning biasa', () {
      final csv = buildTransactionsCsv([_bolt11Payment()]);
      expect(csv, isNot(contains('Lightning Direct')));
      expect(csv, contains(',Lightning,'));
    });
  });
}
