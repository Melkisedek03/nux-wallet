import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/screens/privacy_policy_screen.dart';
import 'package:nux_wallet/theme.dart';
import 'package:nux_wallet/utils/privacy_policy.dart';

Widget _app(Widget home, {Locale locale = const Locale('id')}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

/// Tampilan kebijakan palsu: tombol-tombol memanggil balik layar
/// seolah WebView sungguhan (sampai bawah / gagal muat).
Widget _fakeView(
  BuildContext context, {
  required String url,
  required VoidCallback onReachedBottom,
  required VoidCallback onLoadFailed,
  required VoidCallback onLoadStarted,
}) {
  return Column(
    children: [
      Text('URL:$url'),
      TextButton(
        onPressed: onReachedBottom,
        child: const Text('SIM_BOTTOM'),
      ),
      TextButton(onPressed: onLoadFailed, child: const Text('SIM_FAIL')),
    ],
  );
}

/// Settle tanpa pumpAndSettle: indikator LinearProgressIndicator
/// (indeterminate) di layar beranimasi selamanya, jadi pumpAndSettle
/// tidak pernah kembali. Lima frame @100ms cukup untuk transisi rute.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

CheckboxListTile _consentTile(WidgetTester tester) =>
    tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));

ElevatedButton _continueButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Lanjut'));

/// Pompa layar persetujuan lewat Navigator supaya nilai pop-nya
/// bisa dibaca (true = setuju, false = lewati). Mengembalikan
/// pengambil hasil pop.
Future<bool? Function()> _openConsent(WidgetTester tester) async {
  bool? result;
  await tester.pumpWidget(
    _app(
      Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.push<bool>(
                ctx,
                MaterialPageRoute(
                  builder: (_) => PrivacyPolicyScreen.consent(
                    policyViewBuilder: _fakeView,
                  ),
                ),
              );
            },
            child: const Text('BUKA'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('BUKA'));
  await _settle(tester);
  expect(find.text('URL:$privacyPolicyUrlId'), findsOneWidget);
  return () => result;
}

void main() {
  group('PrivacyPolicyScreen mode persetujuan', () {
    testWidgets('awal: centangan + Lanjut terkunci, petunjuk gulir tampil', (
      tester,
    ) async {
      await _openConsent(tester);
      expect(find.text('Gulir sampai ke bawah untuk mengaktifkan centangan'),
          findsOneWidget);
      expect(_consentTile(tester).onChanged, isNull);
      expect(_continueButton(tester).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sampai bawah → centangan aktif; centang → Lanjut aktif', (
      tester,
    ) async {
      await _openConsent(tester);
      await tester.tap(find.text('SIM_BOTTOM'));
      await tester.pump();
      expect(_consentTile(tester).onChanged, isNotNull);
      expect(_continueButton(tester).onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(_consentTile(tester).value, isTrue);
      expect(_continueButton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Lanjut sesudah centang → pop true', (tester) async {
      final getResult = await _openConsent(tester);
      await tester.tap(find.text('SIM_BOTTOM'));
      await tester.pump();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Lanjut'));
      await _settle(tester);
      expect(getResult(), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('gagal muat → Lewati tampil dan pop false', (tester) async {
      final getResult = await _openConsent(tester);
      await tester.tap(find.text('SIM_FAIL'));
      await tester.pump();
      expect(
        find.text(
          'Kebijakan privasi gagal dimuat. Periksa koneksi internet Anda lalu coba lagi.',
        ),
        findsOneWidget,
      );
      expect(find.text('Muat ulang'), findsOneWidget);
      expect(find.text('Lewati untuk sekarang'), findsOneWidget);
      await tester.tap(find.text('Lewati untuk sekarang'));
      await _settle(tester);
      expect(getResult(), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('PrivacyPolicyScreen mode baca', () {
    testWidgets('tanpa centangan/tombol; URL mengikuti locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const PrivacyPolicyScreen.read(policyViewBuilder: _fakeView),
          locale: const Locale('en'),
        ),
      );
      await tester.pump();
      expect(find.text('URL:$privacyPolicyUrlEn'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Continue'), findsNothing);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
