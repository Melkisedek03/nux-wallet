import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/screens/onchain_screen.dart';
import 'package:nux_wallet/services/lsp_service.dart';
import 'package:nux_wallet/theme.dart';

/// Layanan palsu: saldo dengan KEDUA baris turunan tampil
/// (spendable < total, timelock > 0 dengan tinggi buka) supaya
/// kartu keterangan yang rawan terjepit benar-benar ter-render.
class _FakeLspService extends LspService {
  @override
  Future<OnchainOverview> getOnchainOverview() async => (
        totalSats: BigInt.from(100000),
        spendableSats: BigInt.from(90000),
        timelockSats: BigInt.from(10000),
        timelockHeight: 73683,
      );

  @override
  Future<String> onchainAddress() async =>
      'nu1qtestalamatdepositpanjangsekali0123456789abcdef';
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required double width,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('id'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
            textScaler: TextScaler.linear(textScale)),
        child: OnchainScreen(lspService: _FakeLspService()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'HP sempit 320: kartu timelock label di atas nilai, tanpa luapan',
      (tester) async {
    await _pumpScreen(tester, width: 320);
    expect(tester.takeException(), isNull);
    expect(find.text('Menunggu timelock'), findsOneWidget);

    // Yang dijaga di sini adalah LABEL: bentuk Row lama membuat
    // label "Menunggu timelock" kebagian lebar 0 dan menumpuk
    // vertikal setinggi 320dp (nilai tetap satu baris horizontal
    // dan meluber ke kanan) — koreksi NUX 13 Nov. Nilai boleh
    // terlipat di batas kata, tapi tidak boleh menumpuk.
    final labelFinder = find.text('Menunggu timelock');
    expect(labelFinder, findsOneWidget);
    final labelRect = tester.getRect(labelFinder);
    expect(labelRect.height, lessThan(30));

    final valueFinder = find.textContaining('terbuka ~blok 73683');
    expect(valueFinder, findsOneWidget);
    final valueRect = tester.getRect(valueFinder);
    // Momo (font aplikasi) punya tinggi baris ~21dp pada 15sp:
    // nilai terlipat wajar jadi 3 baris pada lebar 320 — batas 70
    // (3 baris) memisahkan ini dari bentuk Row lama yang meluber
    // 247dp ke kanan kartu.
    expect(valueRect.height, lessThan(70));

    // Column: label di atas, nilai di bawah.
    expect(labelRect.bottom, lessThanOrEqualTo(valueRect.top + 1));
  });

  testWidgets('HP sempit 320 + skala teks 1.3: tetap tanpa luapan',
      (tester) async {
    await _pumpScreen(tester, width: 320, textScale: 1.3);
    expect(tester.takeException(), isNull);
    final valueRect =
        tester.getRect(find.textContaining('terbuka ~blok 73683'));
    expect(valueRect.height, lessThan(90));
  });
}
