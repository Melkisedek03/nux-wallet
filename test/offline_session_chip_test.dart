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
  });
}
