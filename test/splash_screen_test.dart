import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/screens/splash_screen.dart';
import 'package:nux_wallet/theme.dart';

Widget _app(Widget home) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    locale: const Locale('id'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

void main() {
  group('SplashScreen tawaran offline (G1.1)', () {
    testWidgets('sebelum ambang: tawaran tidak tampil', (tester) async {
      await tester.pumpWidget(_app(SplashScreen(onSkipToOffline: () async {})));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('Menghubungkan ke LSP…'), findsOneWidget);
      expect(find.text('Lama tersambung?'), findsNothing);
      expect(find.text('Lanjutkan tanpa internet'), findsNothing);
    });

    testWidgets('sesudah ambang 20 detik: tawaran tampil', (tester) async {
      await tester.pumpWidget(_app(SplashScreen(onSkipToOffline: () async {})));
      // Waktu palsu: 20 detik berlalu tanpa menunggu dinding.
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Lama tersambung?'), findsOneWidget);
      expect(find.text('Lanjutkan tanpa internet'), findsOneWidget);
    });

    testWidgets('tanpa callback: tawaran tidak tampil bahkan sesudah ambang', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const SplashScreen()));
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Lama tersambung?'), findsNothing);
      expect(find.text('Lanjutkan tanpa internet'), findsNothing);
    });

    testWidgets('ambang bisa disuntik untuk tes', (tester) async {
      await tester.pumpWidget(
        _app(
          SplashScreen(
            waitThreshold: const Duration(seconds: 1),
            onSkipToOffline: () async {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Lanjutkan tanpa internet'), findsOneWidget);
    });

    testWidgets('ketuk tombol: callback dipanggil, keadaan sibuk tampil', (
      tester,
    ) async {
      var called = false;
      final gate = Completer<void>();
      await tester.pumpWidget(
        _app(
          SplashScreen(
            waitThreshold: const Duration(seconds: 1),
            onSkipToOffline: () async {
              called = true;
              await gate.future;
            },
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.tap(find.text('Lanjutkan tanpa internet'));
      await tester.pump();
      expect(called, isTrue);
      expect(find.text('Menyiapkan mode offline…'), findsOneWidget);
      expect(find.text('Lanjutkan tanpa internet'), findsNothing);
      gate.complete();
      await tester.pump();
      expect(find.text('Menyiapkan mode offline…'), findsNothing);
      expect(find.text('Lanjutkan tanpa internet'), findsOneWidget);
    });
  });
}
