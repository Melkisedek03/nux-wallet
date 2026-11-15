import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/screens/onchain_screen.dart';
import 'package:nux_wallet/services/lsp_service.dart';
import 'package:nux_wallet/services/onchain_address_store.dart';
import 'package:nux_wallet/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  LspService? service,
  int open = 0,
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
        // Kunci berbeda per "buka": tanpa ini pumpWidget memakai
        // ulang State lama (initState tidak jalan lagi) sehingga
        // "buka lagi" tidak pernah teruji.
        child: OnchainScreen(
          key: ValueKey('buka-$open'),
          lspService: service ?? _FakeLspService(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Layanan palsu penghitung: tiap panggilan onchainAddress
/// menurunkan alamat BERBEDA (seperti node asli) supaya tes bisa
/// membuktikan layar tidak meminta alamat baru tanpa perintah.
class _CountingFakeLspService extends LspService {
  int addressCalls = 0;
  String nodeId = '02${'a' * 64}';

  @override
  Future<OnchainOverview> getOnchainOverview() async => (
        totalSats: BigInt.from(100000),
        spendableSats: BigInt.from(90000),
        timelockSats: BigInt.from(10000),
        timelockHeight: 73683,
      );

  @override
  Future<String> ownNodeId() async => nodeId;

  @override
  Future<String> onchainAddress() async {
    addressCalls++;
    return 'nu1qtestalamat$addressCalls';
  }
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

  testWidgets('buka dua kali: alamat sama, node tidak diminta alamat baru',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _CountingFakeLspService();
    await _pumpScreen(tester, width: 360, service: fake);
    expect(find.text('nu1qtestalamat1'), findsOneWidget);
    expect(fake.addressCalls, 1);
    // Buka lagi (instance layar baru, simpanan yang sama).
    await _pumpScreen(tester, width: 360, service: fake, open: 1);
    expect(find.text('nu1qtestalamat1'), findsOneWidget);
    expect(fake.addressCalls, 1);
  });

  testWidgets('tombol Refresh: alamat baru, tersimpan, buka lagi tetap itu',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _CountingFakeLspService();
    await _pumpScreen(tester, width: 360, service: fake);
    expect(find.text('nu1qtestalamat1'), findsOneWidget);
    await tester.tap(find.byTooltip('Alamat baru'));
    await tester.pumpAndSettle();
    expect(find.text('nu1qtestalamat2'), findsOneWidget);
    expect(fake.addressCalls, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(OnchainAddressStore.addressKey),
      'nu1qtestalamat2',
    );
    // Buka lagi: tetap alamat baru, tanpa generate lagi.
    await _pumpScreen(tester, width: 360, service: fake, open: 1);
    expect(find.text('nu1qtestalamat2'), findsOneWidget);
    expect(fake.addressCalls, 2);
  });

  testWidgets('dompet berganti (ID node berubah): simpanan lama tak berlaku',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _CountingFakeLspService();
    await _pumpScreen(tester, width: 360, service: fake);
    expect(fake.addressCalls, 1);
    fake.nodeId = '02${'b' * 64}';
    await _pumpScreen(tester, width: 360, service: fake, open: 1);
    expect(find.text('nu1qtestalamat2'), findsOneWidget);
    expect(fake.addressCalls, 2);
  });
}
