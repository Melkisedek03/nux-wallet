import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/screens/onchain_screen.dart';
import 'package:nux_wallet/services/deposit_progress.dart';
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

/// Layanan progres deposit palsu: tinggi ujung bisa diubah
/// antar-pompa supaya tes timer bisa memajukan progres.
class _FakeDepositProgressService extends DepositProgressService {
  int? tipHeight;

  @override
  Future<int?> fetchTipHeight() async => tipHeight;
}

/// Layanan palsu dengan riwayat yang bisa diatur: deposit
/// tertunda apa pun yang dibutuhkan tes.
class _DepositFakeLspService extends LspService {
  List<PaymentDetails> payments = const [];

  @override
  Future<OnchainOverview> getOnchainOverview() async => (
    totalSats: BigInt.from(100000),
    spendableSats: BigInt.from(100000),
    timelockSats: BigInt.zero,
    timelockHeight: null,
  );

  @override
  Future<String> ownNodeId() async => '02${'a' * 64}';

  @override
  Future<String> onchainAddress() async => 'nu1qtestalamatdeposit';

  @override
  Future<List<PaymentDetails>> listPayments() async => payments;
}

PaymentDetails _depositPayment({
  required String txid,
  required ConfirmationStatus confirmation,
  int amountSats = 1500,
  PaymentStatus status = PaymentStatus.pending,
}) {
  return PaymentDetails(
    id: PaymentId(data: Uint8List.fromList([1, 2, 3])),
    kind: PaymentKind_Onchain(
      txid: Txid(hash: txid),
      status: confirmation,
    ),
    amountMsat: BigInt.from(amountSats * 1000),
    direction: PaymentDirection.inbound,
    status: status,
    latestUpdateTimestamp: BigInt.from(1700000000),
  );
}

ConfirmationStatus _confirmedAt(int height) => ConfirmationStatus.confirmed(
  blockHash: '00' * 32,
  height: height,
  timestamp: BigInt.from(1700000000),
);

/// Pompa manual untuk tes deposit: timer 5 detik yang aktif
/// selama ada deposit tertunda membuat pumpAndSettle tidak
/// pernah selesai.
Future<void> _pumpScreenManual(
  WidgetTester tester, {
  LspService? service,
  DepositProgressService? progress,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      locale: const Locale('id'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OnchainScreen(
        lspService: service ?? _FakeLspService(),
        depositProgressService: progress,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Mock saluran platform untuk Clipboard.setData: tanpa mock,
/// setData di lingkungan tes tidak pernah selesai. Menangkap
/// teks yang disalin supaya tes bisa membuktikannya.
///
/// Saluran platform memakai JSONMethodCodec — mock dengan codec
/// standar merusak decode panggilan lain di saluran yang sama
/// (SystemChrome, SystemSound) dan melempar FormatException.
const _platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

String? _copiedText;

void _mockClipboard() {
  _copiedText = null;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_platformChannel, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments;
          if (args is Map) _copiedText = args['text'] as String?;
          return null;
        }
        return null;
      });
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

  testWidgets('deposit tertunda tampil dengan x/6 + batang progres', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _DepositFakeLspService()
      ..payments = [
        _depositPayment(
          txid: 'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899',
          confirmation: _confirmedAt(100),
        ),
      ];
    final progress = _FakeDepositProgressService()..tipHeight = 102;
    await _pumpScreenManual(tester, service: fake, progress: progress);
    expect(find.text('Menunggu konfirmasi'), findsOneWidget);
    expect(find.text('Konfirmasi 3/6'), findsOneWidget);
    expect(find.textContaining('+1.500'), findsOneWidget);
    expect(
      find.text(
        'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899',
      ),
      findsOneWidget,
    );
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.5);
  });

  testWidgets('deposit 0 konfirmasi menampilkan teks menunggu blok pertama', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _DepositFakeLspService()
      ..payments = [
        _depositPayment(
          txid: 'aabbcc',
          confirmation: ConfirmationStatus.unconfirmed(),
        ),
      ];
    final progress = _FakeDepositProgressService()..tipHeight = 102;
    await _pumpScreenManual(tester, service: fake, progress: progress);
    expect(find.text('0/6 — menunggu blok pertama'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0);
  });

  testWidgets('deposit berhasil (6/6) tidak tampil; tidak ada seksi', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _DepositFakeLspService()
      ..payments = [
        _depositPayment(
          txid: 'aabbcc',
          confirmation: _confirmedAt(100),
          status: PaymentStatus.succeeded,
        ),
      ];
    final progress = _FakeDepositProgressService()..tipHeight = 105;
    await _pumpScreenManual(tester, service: fake, progress: progress);
    expect(find.text('Menunggu konfirmasi'), findsNothing);
  });

  testWidgets('tidak ada deposit tertunda: tidak ada seksi', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _DepositFakeLspService()..payments = const [];
    final progress = _FakeDepositProgressService()..tipHeight = 102;
    await _pumpScreenManual(tester, service: fake, progress: progress);
    expect(find.text('Menunggu konfirmasi'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('dua deposit tertunda: dua baris', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _DepositFakeLspService()
      ..payments = [
        _depositPayment(
          txid: 'aaaa11',
          confirmation: _confirmedAt(100),
          amountSats: 1500,
        ),
        _depositPayment(
          txid: 'bbbb22',
          confirmation: ConfirmationStatus.unconfirmed(),
          amountSats: 2500,
        ),
      ];
    final progress = _FakeDepositProgressService()..tipHeight = 101;
    await _pumpScreenManual(tester, service: fake, progress: progress);
    expect(find.text('aaaa11'), findsOneWidget);
    expect(find.text('bbbb22'), findsOneWidget);
    expect(find.text('Konfirmasi 2/6'), findsOneWidget);
    expect(find.text('0/6 — menunggu blok pertama'), findsOneWidget);
  });

  testWidgets('ketuk ikon salin deposit: txid disalin', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _mockClipboard();
    final fake = _DepositFakeLspService()
      ..payments = [
        _depositPayment(txid: 'aabbccddeeff', confirmation: _confirmedAt(100)),
      ];
    final progress = _FakeDepositProgressService()..tipHeight = 101;
    await _pumpScreenManual(tester, service: fake, progress: progress);
    // Ikon salin deposit memakai copy_rounded; ikon salin alamat
    // memakai copy biasa — keduanya bisa dibedakan.
    await tester.tap(find.byIcon(Icons.copy_rounded));
    await tester.pump();
    expect(_copiedText, 'aabbccddeeff');
    expect(find.text('Disalin'), findsOneWidget);
  });

  testWidgets('timer memajukan progres saat ujung naik', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _DepositFakeLspService()
      ..payments = [
        _depositPayment(txid: 'aabbcc', confirmation: _confirmedAt(100)),
      ];
    final progress = _FakeDepositProgressService()..tipHeight = 100;
    await _pumpScreenManual(tester, service: fake, progress: progress);
    expect(find.text('Konfirmasi 1/6'), findsOneWidget);
    progress.tipHeight = 103;
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Konfirmasi 4/6'), findsOneWidget);
  });

  testWidgets('pengambilan ujung gagal: baris tampil tanpa angka', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _DepositFakeLspService()
      ..payments = [
        _depositPayment(txid: 'aabbcc', confirmation: _confirmedAt(100)),
      ];
    final progress = _FakeDepositProgressService()..tipHeight = null;
    await _pumpScreenManual(tester, service: fake, progress: progress);
    expect(find.text('aabbcc'), findsOneWidget);
    expect(find.text('Konfirmasi belum dapat dimuat'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
