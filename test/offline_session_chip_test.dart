import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/theme.dart';
import 'package:nux_wallet/widgets/offline_session_chip.dart';

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
  group('OfflineSessionChip (G1.4)', () {
    testWidgets('chip tampil dengan teks audit + ikon wifi-off', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const Scaffold(body: OfflineSessionChip())));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Tanpa internet — hanya jalur yang sudah siap yang bisa dipakai',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });

    testWidgets('lebar 360: teks melipat tanpa luapan', (tester) async {
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: SizedBox(width: 360, child: OfflineSessionChip()),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('diketuk dengan onTap: panggilan diteruskan sekali', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(Scaffold(body: OfflineSessionChip(onTap: () => taps++))),
      );
      await tester.pump();
      await tester.tap(
        find.text(
          'Tanpa internet — hanya jalur yang sudah siap yang bisa dipakai',
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(taps, 1);
    });

    testWidgets('tanpa onTap: diketuk pun tidak apa-apa', (tester) async {
      await tester.pumpWidget(_app(const Scaffold(body: OfflineSessionChip())));
      await tester.pump();
      await tester.tap(
        find.text(
          'Tanpa internet — hanya jalur yang sudah siap yang bisa dipakai',
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
