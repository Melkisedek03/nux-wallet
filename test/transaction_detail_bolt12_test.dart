import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/screens/transaction_detail_screen.dart';
import 'package:nux_wallet/theme.dart';

PaymentDetails _bolt12Payment({required PaymentDirection direction}) {
  return PaymentDetails(
    id: PaymentId(data: Uint8List.fromList([9])),
    kind: PaymentKind.bolt12Offer(
      offerId: OfferId(field0: U8Array32(Uint8List(32))),
    ),
    amountMsat: BigInt.from(5000000),
    direction: direction,
    status: PaymentStatus.succeeded,
    latestUpdateTimestamp: BigInt.from(1762000000),
  );
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required PaymentDetails payment,
  String? bolt12Label,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('id'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TransactionDetailScreen(payment: payment, bolt12Label: bolt12Label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Bolt12 masuk berlabel: jenis tampil tag labelnya', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      payment: _bolt12Payment(direction: PaymentDirection.inbound),
      bolt12Label: 'Warung Bu Tini',
    );
    expect(tester.takeException(), isNull);
    // Sama persis dengan tag baris riwayat (helper bersama).
    expect(find.text('⚡ Warung Bu Tini'), findsOneWidget);
  });

  testWidgets('Bolt12 masuk tanpa label: jenis tetap ⚡ Lightning', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      payment: _bolt12Payment(direction: PaymentDirection.inbound),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('⚡ Lightning'), findsOneWidget);
  });

  testWidgets('Bolt12 keluar berlabel: label diabaikan', (tester) async {
    await _pumpDetail(
      tester,
      payment: _bolt12Payment(direction: PaymentDirection.outbound),
      bolt12Label: 'Warung Bu Tini',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('⚡ Lightning'), findsOneWidget);
    expect(find.text('⚡ Warung Bu Tini'), findsNothing);
  });

  testWidgets('label panjang di detail terpangkas sama seperti baris', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      payment: _bolt12Payment(direction: PaymentDirection.inbound),
      bolt12Label: 'ABCDEFGHIJKLMNOPQRSTUVWXY',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('⚡ ABCDEFGHIJKLMNOPQRST…'), findsOneWidget);
  });
}
