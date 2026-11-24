import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/screens/receive_screen.dart';
import 'package:nux_wallet/services/lsp_service.dart';
import 'package:nux_wallet/services/offline_bridge.dart';
import 'package:nux_wallet/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Layanan palsu minimal: node berjalan, tanpa pembayaran, tanpa
/// kapasitas terima (gerbang kode statis tertutup — tombolnya
/// tetap tampil dalam konteks online, hanya dinonaktifkan).
class _FakeLspService extends LspService {
  final bool offlineMode;

  _FakeLspService({this.offlineMode = false});

  @override
  bool get isRunning => true;

  @override
  bool get isOfflineMode => offlineMode;

  @override
  Future<List<PaymentDetails>> listPayments() async => [];

  @override
  Future<BigInt> usableInboundCapacityMsat() async => BigInt.zero;

  @override
  Future<Event?> pollNextEvent() async => null;
}

Widget _app(Widget home) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('id'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

/// Pompa manual: pengawas event layar memakai timer periodik 2
/// detik, jadi pumpAndSettle tidak pernah selesai.
Future<void> _pumpManual(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ReceiveScreen catatan Kode Bayar Statis offline (G5.2)', () {
    testWidgets('boot offline: catatan tampil, tombol kode tidak ada', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(ReceiveScreen(lspService: _FakeLspService(offlineMode: true))),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Kode Bayar Statis tidak bisa dipakai tanpa internet — terima lewat invoice di atas.',
        ),
        findsOneWidget,
      );
      expect(find.text('Kode Bayar Statis'), findsNothing);
    });

    testWidgets('sesi jembatan aktif: catatan tampil', (tester) async {
      final bridge = OfflineBridgeService()..sessionActive = true;
      await tester.pumpWidget(
        _app(ReceiveScreen(lspService: _FakeLspService(), bridge: bridge)),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Kode Bayar Statis tidak bisa dipakai tanpa internet — terima lewat invoice di atas.',
        ),
        findsOneWidget,
      );
      expect(find.text('Kode Bayar Statis'), findsNothing);
    });

    testWidgets('online: tombol kode tampil, catatan tidak ada', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(ReceiveScreen(lspService: _FakeLspService())),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Kode Bayar Statis'), findsOneWidget);
      expect(
        find.text(
          'Kode Bayar Statis tidak bisa dipakai tanpa internet — terima lewat invoice di atas.',
        ),
        findsNothing,
      );
    });
  });
}
