import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/config.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/screens/channels_screen.dart';
import 'package:nux_wallet/services/fee_estimate.dart';
import 'package:nux_wallet/services/lsp_service.dart';
import 'package:nux_wallet/theme.dart';
import 'package:nux_wallet/unit_controller.dart';
import 'package:nux_wallet/utils/format.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _peerId =
    '035d4490410d765e327bd33bcaaa0db8bc1b0ea7ca0f8df7e9db8d9279b16683b0';

OutPoint _fundingTxo(String txid) => OutPoint(txid: Txid(hash: txid), vout: 0);

ChannelDetails _channel(
  String counterpartyHex, {
  bool usable = true,
  bool? channelReady,
  int outboundMsat = 24000000,
  int channelValueSats = 25000,
  OutPoint? fundingTxo,
  int? confirmations,
  int? confirmationsRequired,
  int userIdFill = 0,
}) {
  return ChannelDetails(
    channelId: ChannelId(
      data: U8Array32(Uint8List.fromList(List.filled(32, 1))),
    ),
    counterpartyNodeId: PublicKey(hex: counterpartyHex),
    channelValueSats: BigInt.from(channelValueSats),
    userChannelId: UserChannelId(
      data: Uint8List.fromList(List.filled(16, userIdFill)),
    ),
    fundingTxo: fundingTxo,
    confirmations: confirmations,
    confirmationsRequired: confirmationsRequired,
    feerateSatPer1000Weight: 1000,
    outboundCapacityMsat: BigInt.from(outboundMsat),
    inboundCapacityMsat: BigInt.from(1000000),
    isOutbound: true,
    isChannelReady: channelReady ?? usable,
    isUsable: usable,
    counterpartyUnspendablePunishmentReserve: BigInt.from(1000),
    nextOutboundHtlcLimitMsat: BigInt.zero,
    nextOutboundHtlcMinimumMsat: BigInt.zero,
    inboundHtlcMinimumMsat: BigInt.from(1000),
    config: ChannelConfig(
      forwardingFeeProportionalMillionths: 0,
      forwardingFeeBaseMsat: 0,
      cltvExpiryDelta: 72,
      maxDustHtlcExposure: MaxDustHTLCExposure_FeeRateMultiplier(
        BigInt.from(1000),
      ),
      forceCloseAvoidanceMaxFeeSatoshis: BigInt.from(1000),
      acceptUnderpayingHtlcs: false,
    ),
  );
}

/// Layanan palsu: node berjalan, daftar channel bisa diatur per
/// tes; `openChannelToLsp` meniru node (channel muncul dalam
/// keadaan disiapkan 0/6 pada listChannels berikutnya) dan
/// meniru pagar boot offline layanan nyata.
class _FakeLspService extends LspService {
  List<ChannelDetails> channels;
  BigInt spendableSats;
  bool offlineMode;
  bool failOpen;

  /// Nominal setiap pembukaan channel ke LSP yang diminta layar.
  final List<BigInt> openedAmounts = [];

  _FakeLspService({
    List<ChannelDetails> channels = const [],
    BigInt? spendableSats,
    this.offlineMode = false,
    this.failOpen = false,
  }) : channels = List.of(channels),
       spendableSats = spendableSats ?? BigInt.from(200000);

  @override
  bool get isRunning => true;

  @override
  bool get isOfflineMode => offlineMode;

  @override
  Future<List<ChannelDetails>> listChannels() async => channels;

  @override
  Future<BigInt> spendableOnchainBalanceSats() async => spendableSats;

  @override
  Future<UserChannelId> openChannelToLsp(BigInt amountSats) async {
    if (offlineMode) {
      throw StateError('Buka channel ke LSP ditolak pada sesi boot offline.');
    }
    if (failOpen) throw StateError('boom');
    openedAmounts.add(amountSats);
    final userId = UserChannelId(data: Uint8List.fromList(List.filled(16, 9)));
    channels = [
      ...channels,
      _channel(
        AppConfig.lspNodeId,
        usable: false,
        channelValueSats: amountSats.toInt(),
        fundingTxo: _fundingTxo('cc' * 32),
        confirmations: 0,
        confirmationsRequired: 6,
        userIdFill: 9,
      ),
    ];
    return userId;
  }

  @override
  Future<OnchainOverview> getOnchainOverview() async => (
    totalSats: spendableSats,
    spendableSats: spendableSats,
    timelockSats: BigInt.zero,
    timelockHeight: null,
  );

  @override
  Future<String> onchainAddress() async =>
      'tn1qtestalamatdepositpanjangsekali0123456789abcdef';
}

/// Perkiraan biaya palsu: tarif tetap 250 nusan, biaya pasti
/// 250 nusan — cukup untuk membuktikan alur, tanpa HTTP.
class _FakeFeeEstimateService extends FeeEstimateService {
  final BigInt? estimate;
  final BigInt? fundingFee;

  _FakeFeeEstimateService({BigInt? estimate, BigInt? fundingFee})
    : estimate = estimate ?? BigInt.from(250),
      fundingFee = fundingFee ?? BigInt.from(250);

  @override
  Future<BigInt?> estimateFundingFee() async => estimate;

  @override
  Future<BigInt?> fetchFundingFee(String fundingTxid) async => fundingFee;
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

/// Pompa manual sebagai pengganti pumpAndSettle: kartu disiapkan
/// menyalakan timer periodik 5 detik, yang membuat pumpAndSettle
/// tidak pernah selesai. Beberapa pompa cukup untuk futures lokal
/// selesai.
Future<void> _pumpManual(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  _FakeLspService? service,
  FeeEstimateService? feeEstimates,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    _app(
      ChannelsScreen(
        lspService: service ?? _FakeLspService(),
        feeEstimateService: feeEstimates ?? _FakeFeeEstimateService(),
      ),
    ),
  );
  await _pumpManual(tester);
}

Future<void> _tapOpenButton(WidgetTester tester) async {
  await tester.tap(find.text('Buka Channel ke LSP'));
  await _pumpManual(tester);
}

/// Mock saluran platform untuk Clipboard.setData: tanpa mock,
/// setData di lingkungan tes tidak pernah selesai. Menangkap
/// teks yang disalin supaya tes bisa membuktikannya.
///
/// Saluran platform memakai JSONMethodCodec (SystemChannels.
/// platform) — mock dengan codec standar merusak decode
/// panggilan lain di saluran yang sama (SystemChrome,
/// SystemSound) dan melempar FormatException.
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
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_platformChannel, null);
  });

  group('ChannelsScreen buka channel ke LSP', () {
    testWidgets('tombol tampil di atas daftar channel', (tester) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(AppConfig.lspNodeId),
            _channel(_peerId, channelValueSats: 20000),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Buka Channel ke LSP'), findsOneWidget);
      expect(find.text('Via LSP'), findsOneWidget);
      expect(find.text('Channel langsung'), findsOneWidget);
      expect(find.text('Siap'), findsNWidgets(2));
    });

    testWidgets('tombol tampil saat daftar kosong', (tester) async {
      await _pumpScreen(tester);
      expect(find.text('Buka Channel ke LSP'), findsOneWidget);
      expect(find.text('Belum ada channel'), findsOneWidget);
    });

    testWidgets('lembar nominal: bawaan + saldo + validasi minimum', (
      tester,
    ) async {
      await _pumpScreen(tester);
      await _tapOpenButton(tester);
      expect(find.text('Nominal bawaan'), findsOneWidget);
      expect(find.text('100.000 nusan'), findsOneWidget);
      expect(find.text('Saldo on-chain-mu: 200.000 nusan'), findsOneWidget);

      await tester.tap(find.text('Nominal lain'));
      await _pumpManual(tester);
      expect(find.text('cth. 25.000 nusan'), findsOneWidget);
      expect(
        find.text('Minimal 10.000 nusan, bernilai nusan bulat.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '5.000');
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);
      expect(
        find.text('Minimal 10.000 nusan untuk satu channel.'),
        findsOneWidget,
      );

      // Batas minimum persis diterima.
      await tester.enterText(find.byType(TextField), '10.000');
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);
      expect(find.text('Buka channel ke LSP?'), findsOneWidget);
      expect(find.text('10.000 nusan'), findsOneWidget);
    });

    testWidgets('lembar nominal satuan NUX: parse, hint, dan error '
        'memakai satuan aktif', (tester) async {
      // Temuan lapangan 19 Nov 2026: pengguna satuan NUX mengetik
      // "0,001" lalu ditolak karena parser meng-hardcode nusan.
      // Saklar satuan adalah state statis — kembalikan ke nusan
      // sesudah tes supaya tes lain tidak terpengaruh.
      UnitController.unit.value = DisplayUnit.nux;
      addTearDown(() {
        UnitController.unit.value = DisplayUnit.nusan;
      });
      await _pumpScreen(tester);
      await _tapOpenButton(tester);
      expect(find.text('0,001 NUX'), findsOneWidget);

      await tester.tap(find.text('Nominal lain'));
      await _pumpManual(tester);
      expect(find.text('cth. 0,00025 NUX'), findsOneWidget);
      expect(
        find.text('Minimal 0,0001 NUX, bernilai nusan bulat.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), '0,00005');
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);
      expect(
        find.text('Minimal 0,0001 NUX untuk satu channel.'),
        findsOneWidget,
      );

      // Pecahan nusan ditolak (aturan nusan bulat).
      await tester.enterText(find.byType(TextField), '0,000000015');
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);
      expect(find.text('Tulis jumlah NUX yang sah.'), findsOneWidget);

      // Nominal valid yang BERBEDA dari bawaan (0,001 NUX):
      // lembar yang masih menganimasikan keluar tetap memuat judul
      // bawaan, jadi nominal yang sama akan terhitung ganda.
      await tester.enterText(find.byType(TextField), '0,0005');
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);
      expect(find.text('Buka channel ke LSP?'), findsOneWidget);
      expect(find.text('0,0005 NUX'), findsOneWidget);
    });

    testWidgets('alir penuh: lembar → konfirmasi → channel disiapkan', (
      tester,
    ) async {
      final service = _FakeLspService();
      await _pumpScreen(tester, service: service);
      await _tapOpenButton(tester);
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);

      // Dialog konfirmasi: semua baris sesuai desain.
      expect(find.text('Buka channel ke LSP?'), findsOneWidget);
      expect(find.text('Jumlah channel'), findsOneWidget);
      expect(find.text('100.000 nusan'), findsOneWidget);
      expect(find.text('Biaya jaringan (perkiraan)'), findsOneWidget);
      expect(find.text('±250 nusan'), findsOneWidget);
      expect(find.text('Total dari dompet on-chain'), findsOneWidget);
      expect(find.text('±100.250 nusan'), findsOneWidget);
      expect(
        find.text(
          '100.000 nusan dari dompet on-chain-mu pindah ke channel ini — kamu bisa mengirim ke siapa pun lewat LSP.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Channel siap dipakai setelah 6 konfirmasi jaringan.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Buka Channel'));
      await _pumpManual(tester);
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(service.openedAmounts, [BigInt.from(100000)]);
      expect(find.text('Channel ke LSP sedang disiapkan…'), findsOneWidget);
      expect(find.text('Menunggu konfirmasi pertama…'), findsOneWidget);
      expect(find.text('Nilai channel: 100.000 nusan'), findsOneWidget);
      // Txid pendanaan tampil lengkap di kartu disiapkan.
      expect(find.text('cc' * 32), findsOneWidget);
      // Channel-nya juga tampil di daftar dengan status menunggu.
      expect(find.text('Menunggu konfirmasi • Konfirmasi 0/6'), findsOneWidget);
    });

    testWidgets('kemajuan disiapkan 3/6: progres + biaya pasti + salin txid', (
      tester,
    ) async {
      _mockClipboard();
      final service = _FakeLspService();
      await _pumpScreen(tester, service: service);
      await _tapOpenButton(tester);
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);
      await tester.tap(find.text('Buka Channel'));
      await _pumpManual(tester);
      await _pumpManual(tester);
      expect(find.text('Menunggu konfirmasi pertama…'), findsOneWidget);

      // Pendanaan terkonfirmasi 3/6: putaran timer 5 detik
      // memuat ulang daftar dan kartu mengikuti.
      service.channels = [
        _channel(
          AppConfig.lspNodeId,
          usable: false,
          channelValueSats: 100000,
          fundingTxo: _fundingTxo('cc' * 32),
          confirmations: 3,
          confirmationsRequired: 6,
          userIdFill: 9,
        ),
      ];
      await tester.pump(const Duration(seconds: 5));
      await _pumpManual(tester);
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Konfirmasi 3/6'), findsOneWidget);
      expect(find.text('dari 6 konfirmasi dibutuhkan'), findsOneWidget);
      expect(find.text('Biaya jaringan: 250 nusan'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Ketuk ikon salin: txid disalin, snackbar tampil.
      await tester.tap(find.byIcon(Icons.copy_rounded));
      await _pumpManual(tester);
      expect(_copiedText, 'cc' * 32);
      expect(find.text('Disalin'), findsOneWidget);

      // Channel siap: kartu disiapkan hilang, baris menampilkan Siap.
      service.channels = [
        _channel(
          AppConfig.lspNodeId,
          usable: true,
          channelValueSats: 100000,
          fundingTxo: _fundingTxo('cc' * 32),
          confirmations: 6,
          confirmationsRequired: 6,
          userIdFill: 9,
        ),
      ];
      await tester.pump(const Duration(seconds: 5));
      await _pumpManual(tester);
      expect(find.text('Channel ke LSP sedang disiapkan…'), findsNothing);
      expect(find.text('Siap'), findsOneWidget);
    });

    testWidgets('sesi boot offline: tombol tidak aktif + kalimat jelas', (
      tester,
    ) async {
      await _pumpScreen(tester, service: _FakeLspService(offlineMode: true));
      expect(
        find.text(
          'Membuka channel butuh internet — sesi ini dimulai tanpa internet.',
        ),
        findsOneWidget,
      );
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Buka Channel ke LSP'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('saldo tidak cukup: dialog + Isi Dompet membuka On-chain', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(spendableSats: BigInt.zero),
      );
      await _tapOpenButton(tester);
      expect(find.text('Saldo on-chain belum cukup'), findsOneWidget);
      expect(find.text('Isi Dompet On-chain'), findsOneWidget);

      await tester.tap(find.text('Isi Dompet On-chain'));
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Dompet On-chain'), findsOneWidget);
    });

    testWidgets('pembukaan gagal: pesan umum, tanpa kartu disiapkan', (
      tester,
    ) async {
      final service = _FakeLspService(failOpen: true);
      await _pumpScreen(tester, service: service);
      await _tapOpenButton(tester);
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);
      await tester.tap(find.text('Buka Channel'));
      await _pumpManual(tester);
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(service.openedAmounts, isEmpty);
      expect(
        find.text('Buka channel ke LSP gagal. Coba lagi.'),
        findsOneWidget,
      );
      expect(find.text('Channel ke LSP sedang disiapkan…'), findsNothing);
    });
  });
}
