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
  bool isOutbound = true,
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
    isOutbound: isOutbound,
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

  /// Jeda buatan listChannels — tes umpan balik refresh
  /// menyalakannya SESUDAH muatan awal supaya keadaan
  /// menyegarkan di tengah-penerbangan bisa diamati.
  Duration listDelay = Duration.zero;

  /// Jumlah pemanggilan listChannels.
  int listCalls = 0;

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
  Future<List<ChannelDetails>> listChannels() async {
    listCalls++;
    if (listDelay > Duration.zero) {
      await Future.delayed(listDelay);
    }
    return channels;
  }

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

  /// Tutup kerja sama gagal (untuk memicu dialog tutup paksa).
  bool failClose = false;

  /// Tutup paksa gagal.
  bool failForceClose = false;

  /// Channel yang tutup kerja sama / tutup paksa-nya diminta.
  final List<ChannelDetails> closedChannels = [];
  final List<ChannelDetails> forceClosedChannels = [];

  /// Tutup tidak mengubah daftar channel: tes mengendalikan
  /// keadaan daftar secara eksplisit (pola yang sama seperti
  /// tes kemajuan disiapkan) — channel tetap terdaftar sesudah
  /// tutup dimulai (jendela penutupan), lalu tes mengeluarkannya
  /// untuk meniru handshake yang selesai.
  @override
  Future<void> closeChannel(ChannelDetails channel) async {
    if (failClose) throw StateError('peer tidak terjangkau');
    closedChannels.add(channel);
  }

  @override
  Future<void> forceCloseChannel(ChannelDetails channel) async {
    if (failForceClose) throw StateError('gagal siar');
    forceClosedChannels.add(channel);
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
/// Tinggi ujung null bila tidak diisi (baris perkiraan buka
/// kunci tidak tampil).
class _FakeFeeEstimateService extends FeeEstimateService {
  final BigInt? estimate;
  final BigInt? fundingFee;
  final int? tipHeight;

  _FakeFeeEstimateService({
    BigInt? estimate,
    BigInt? fundingFee,
    this.tipHeight,
  }) : estimate = estimate ?? BigInt.from(250),
       fundingFee = fundingFee ?? BigInt.from(250);

  @override
  Future<BigInt?> estimateFundingFee() async => estimate;

  @override
  Future<BigInt?> fetchFundingFee(String fundingTxid) async => fundingFee;

  @override
  Future<int?> fetchTipHeight() async => tipHeight;
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

/// Indikator berputar di AppBar — bedakan dari spinner layar
/// penuh muat pertama (di body, bukan di AppBar).
Finder get _appBarSpinner => find.descendant(
  of: find.byType(AppBar),
  matching: find.byType(CircularProgressIndicator),
);

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
      // Txid pendanaan tampil lengkap di kartu disiapkan DAN di
      // kartu channel-nya sendiri (PR 2: txid menetap di kartu).
      expect(find.text('cc' * 32), findsNWidgets(2));
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
      // Dua batang 3/6: kartu disiapkan DAN kartu channel
      // regulernya (channel yang sama muncul di daftar, masih
      // menunggu — kartunya kini ikut menampilkan batang).
      final bars = find.byType(LinearProgressIndicator);
      expect(bars, findsNWidgets(2));
      for (final bar in tester.widgetList<LinearProgressIndicator>(bars)) {
        expect(bar.value, closeTo(3 / 6, 0.001));
      }

      // Ketuk ikon salin kartu disiapkan (yang pertama — kartu
      // channel di bawahnya kini punya ikon salin sendiri, PR 2):
      // txid disalin, snackbar tampil.
      await tester.tap(find.byIcon(Icons.copy_rounded).first);
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

  group('ChannelsScreen txid pendanaan di kartu (PR 2)', () {
    testWidgets('kartu channel siap menampilkan txid lengkap', (tester) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(
              AppConfig.lspNodeId,
              fundingTxo: _fundingTxo('dd' * 32),
              confirmations: 6,
              confirmationsRequired: 6,
            ),
            _channel(
              _peerId,
              channelValueSats: 20000,
              fundingTxo: _fundingTxo('ee' * 32),
              confirmations: 6,
              confirmationsRequired: 6,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Tx pendanaan'), findsNWidgets(2));
      expect(find.text('dd' * 32), findsOneWidget);
      expect(find.text('ee' * 32), findsOneWidget);
      expect(find.text('Siap'), findsNWidgets(2));
    });

    testWidgets('kartu channel menunggu: txid + kemajuan x/6', (tester) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(
              _peerId,
              usable: false,
              channelValueSats: 300000,
              fundingTxo: _fundingTxo('ff' * 32),
              confirmations: 2,
              confirmationsRequired: 6,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('ff' * 32), findsOneWidget);
      expect(find.text('Menunggu konfirmasi • Konfirmasi 2/6'), findsOneWidget);
    });

    testWidgets('ketuk ikon salin kartu: txid disalin', (tester) async {
      _mockClipboard();
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(
              AppConfig.lspNodeId,
              fundingTxo: _fundingTxo('dd' * 32),
              confirmations: 6,
              confirmationsRequired: 6,
            ),
          ],
        ),
      );
      await tester.tap(find.byIcon(Icons.copy_rounded));
      await _pumpManual(tester);
      expect(_copiedText, 'dd' * 32);
      expect(find.text('Disalin'), findsOneWidget);
    });

    testWidgets('tanpa fundingTxo: baris txid tidak tampil', (tester) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(channels: [_channel(AppConfig.lspNodeId)]),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Tx pendanaan'), findsNothing);
    });
  });

  group('ChannelsScreen umpan balik refresh + label jenis (PR 1)', () {
    testWidgets('tombol segarkan: indikator tampil sampai muat ulang selesai', (
      tester,
    ) async {
      final service = _FakeLspService(
        channels: [_channel(AppConfig.lspNodeId, channelValueSats: 25000)],
      );
      await _pumpScreen(tester, service: service);
      expect(_appBarSpinner, findsNothing);
      expect(find.text('Siap'), findsOneWidget);

      // Muat ulang dengan jeda: tombol ditekan, daftar berubah
      // di belakang layar.
      service.listDelay = const Duration(milliseconds: 500);
      service.channels = [
        _channel(AppConfig.lspNodeId, channelValueSats: 25000),
        _channel(_peerId, channelValueSats: 20000, userIdFill: 1),
      ];
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pump();
      expect(_appBarSpinner, findsOneWidget);

      // Jeda berlalu: indikator hilang, tombol kembali,
      // daftar baru tampil.
      await tester.pump(const Duration(milliseconds: 600));
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(_appBarSpinner, findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      expect(find.text('Siap'), findsNWidgets(2));
    });

    testWidgets('tarik-untuk-segarkan: indikator + daftar diperbarui', (
      tester,
    ) async {
      // Delapan kartu supaya daftar bisa di-scroll (tanpa
      // scroll, tarik tidak memicu RefreshIndicator).
      final service = _FakeLspService(
        channels: [
          for (var i = 0; i < 8; i++)
            _channel(
              _peerId,
              channelValueSats: 20000 + i * 1000,
              userIdFill: i,
            ),
        ],
      );
      await _pumpScreen(tester, service: service);
      // Jeda 2 detik: fling sendiri memakan ~400 ms waktu palsu,
      // jadi jeda 500 ms hampir habis sebelum indikator diamati.
      service.listDelay = const Duration(seconds: 2);
      service.channels = [
        _channel(AppConfig.lspNodeId, channelValueSats: 25000),
      ];

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      // onRefresh RefreshIndicator baru menyala setelah
      // animasi snap + settle scroll pasca-lepas (~0,5–1 detik
      // waktu palsu) — tunggu sampai _muat benar-benar
      // berjalan, lalu amati indikatornya (jeda 2 detik
      // memberi ruang longgar).
      for (var i = 0; i < 10 && service.listCalls < 2; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(service.listCalls, 2);
      expect(_appBarSpinner, findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2100));
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(_appBarSpinner, findsNothing);
      expect(find.text('Via LSP'), findsOneWidget);
      expect(find.text('Channel langsung'), findsNothing);
    });

    testWidgets('label jenis: JIT vs Self-Funded vs langsung', (tester) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(AppConfig.lspNodeId, isOutbound: false),
            _channel(
              AppConfig.lspNodeId,
              isOutbound: true,
              channelValueSats: 11000,
              userIdFill: 1,
            ),
            _channel(_peerId, channelValueSats: 20000, userIdFill: 2),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Via LSP — JIT'), findsOneWidget);
      expect(find.text('Via LSP — Self-Funded'), findsOneWidget);
      expect(find.text('Channel Langsung'), findsOneWidget);
    });

    testWidgets('label jenis: ID node LSP tidak peka huruf', (tester) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(AppConfig.lspNodeId.toUpperCase(), isOutbound: false),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Via LSP — JIT'), findsOneWidget);
    });

    testWidgets('label panjang tidak melipat di layar sempit', (tester) async {
      // Ponsel sempit (360 px logis): label jenis di barisnya
      // sendiri harus tetap satu baris — cacat melipat
      // huruf-per-huruf hidup di Row judul (jatah PR R3),
      // bukan di sini. Lebar > 50 membuktikan teks terbentang
      // horizontal (label yang melipat selebar satu huruf,
      // ~10 px). devicePixelRatio tes adalah 3,0 — tanpa
      // disetel 1,0, ukuran logisnya jadi 120×213.
      //
      // Sengaja hanya channel SIAP (status pendek "Siap"):
      // status panjang channel menunggu ("Menunggu konfirmasi
      // • Konfirmasi 0/6") meluberkan Row judul yang
      // statusnya tanpa batas lebar — cacat yang sudah
      // diketahui itu jatah PR R3, bukan tes ini.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(
              AppConfig.lspNodeId,
              isOutbound: true,
              channelValueSats: 11000,
            ),
            _channel(_peerId, channelValueSats: 300000, userIdFill: 1),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      final labelSize = tester.getSize(find.text('Via LSP — Self-Funded'));
      expect(labelSize.width, greaterThan(50));
      expect(labelSize.height, lessThan(30));
      final directSize = tester.getSize(find.text('Channel Langsung'));
      expect(directSize.width, greaterThan(50));
      expect(directSize.height, lessThan(30));
    });
  });

  group('ChannelsScreen tutup paksa + cacat kartu (R3)', () {
    testWidgets('tutup kerja sama: snackbar berlabel + kartu Menutup…', (
      tester,
    ) async {
      final service = _FakeLspService(
        channels: [_channel(_peerId, channelValueSats: 20000)],
      );
      await _pumpScreen(tester, service: service);
      await tester.tap(find.text('Tutup Channel'));
      await _pumpManual(tester);
      expect(find.text('Tutup channel ini?'), findsOneWidget);
      // Tombol konfirmasi dialog adalah "Tutup Channel" kedua
      // (tombol kartu masih ada di belakang dialog).
      await tester.tap(find.text('Tutup Channel').last);
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(service.closedChannels, hasLength(1));
      // Hasil tutup BERLABEL jenisnya (kerja sama, bukan
      // "Penutupan dimulai" yang ambigu).
      expect(
        find.text(
          'Penutupan kerja sama dimulai. Saldo akan masuk ke dompet on-chain setelah transaksi penutup terkonfirmasi.',
        ),
        findsOneWidget,
      );
      // Channel masih terdaftar (handshake belum selesai):
      // kartunya "Menutup…", bukan "Menunggu konfirmasi".
      expect(find.text('Menutup…'), findsOneWidget);
      expect(find.textContaining('Menunggu konfirmasi'), findsNothing);

      // Channel meninggalkan daftar: kartu hilang, tanpa error.
      service.channels = [];
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await _pumpManual(tester);
      expect(find.text('Menutup…'), findsNothing);
      expect(find.text('Belum ada channel'), findsOneWidget);
    });

    testWidgets('tutup paksa: dialog menampilkan 144 blok + perkiraan '
        'buka kunci', (tester) async {
      final service = _FakeLspService(
        channels: [_channel(_peerId, channelValueSats: 20000)],
      )..failClose = true;
      await _pumpScreen(
        tester,
        service: service,
        feeEstimates: _FakeFeeEstimateService(tipHeight: 1500),
      );
      await tester.tap(find.text('Tutup Channel'));
      await _pumpManual(tester);
      await tester.tap(find.text('Tutup Channel').last);
      await _pumpManual(tester);

      expect(find.text('Tutup kerja sama tidak berhasil'), findsOneWidget);
      expect(find.textContaining('jeda pengaman 144 blok'), findsOneWidget);
      // Perkiraan buka kunci: ujung 1500 + 144 blok.
      expect(
        find.text('Perkiraan terbuka: sekitar blok 1644.'),
        findsOneWidget,
      );
      // Catatan hari hanya di mainnet — di build testnet ini
      // tidak tampil.
      expect(find.textContaining('10 hari'), findsNothing);

      await tester.tap(find.text('Tutup Paksa'));
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(service.forceClosedChannels, hasLength(1));
      expect(
        find.text(
          'Tutup paksa dimulai. Dana akan tersapu ke dompet on-chain sesudah jeda pengaman berakhir.',
        ),
        findsOneWidget,
      );
      expect(find.text('Menutup…'), findsOneWidget);
    });

    testWidgets('tutup paksa tanpa tinggi ujung: baris perkiraan tidak '
        'tampil', (tester) async {
      final service = _FakeLspService(
        channels: [_channel(_peerId, channelValueSats: 20000)],
      )..failClose = true;
      await _pumpScreen(
        tester,
        service: service,
        feeEstimates: _FakeFeeEstimateService(),
      );
      await tester.tap(find.text('Tutup Channel'));
      await _pumpManual(tester);
      await tester.tap(find.text('Tutup Channel').last);
      await _pumpManual(tester);
      expect(find.text('Tutup kerja sama tidak berhasil'), findsOneWidget);
      expect(find.textContaining('jeda pengaman 144 blok'), findsOneWidget);
      expect(find.textContaining('Perkiraan terbuka'), findsNothing);
      // Batal — jangan tutup paksa di tes ini.
      await tester.tap(find.text('Batal'));
      await _pumpManual(tester);
      expect(service.forceClosedChannels, isEmpty);
    });

    testWidgets('peringatan tutup channel langsung menyebut (penambangan)', (
      tester,
    ) async {
      final service = _FakeLspService(
        channels: [_channel(_peerId, channelValueSats: 20000)],
      );
      await _pumpScreen(tester, service: service);
      await tester.tap(find.text('Tutup Channel'));
      await _pumpManual(tester);
      expect(find.text('Tutup channel ini?'), findsOneWidget);
      expect(find.textContaining('(penambangan)'), findsOneWidget);
      // Batal — tes ini hanya memeriksa salinan peringatan.
      await tester.tap(find.text('Batal'));
      await _pumpManual(tester);
      expect(service.closedChannels, isEmpty);
    });

    testWidgets('hitungan konfirmasi tidak pernah melebihi wajib '
        '(69/6 → 6/6)', (tester) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(
              _peerId,
              usable: false,
              channelValueSats: 20000,
              fundingTxo: _fundingTxo('aa' * 32),
              confirmations: 69,
              confirmationsRequired: 6,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Menunggu konfirmasi • Konfirmasi 6/6'), findsOneWidget);
      expect(find.textContaining('69/6'), findsNothing);
    });

    testWidgets('layar sempit + channel menunggu: label tidak melipat, '
        'tanpa luber', (tester) async {
      // Kasus luber 168 px dari PR #43: status panjang channel
      // menunggu di layar 360 px. Sesudah R3, status ada di
      // barisnya sendiri — label tetap satu baris, status
      // terlipat di batas kata, tanpa overflow.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(
              _peerId,
              usable: false,
              channelValueSats: 300000,
              fundingTxo: _fundingTxo('ff' * 32),
              confirmations: 0,
              confirmationsRequired: 6,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      final labelSize = tester.getSize(find.text('Channel langsung'));
      expect(labelSize.width, greaterThan(50));
      expect(labelSize.height, lessThan(30));
      expect(find.text('Menunggu konfirmasi • Konfirmasi 0/6'), findsOneWidget);
    });
  });

  group('ChannelsScreen batang kemajuan konfirmasi kartu', () {
    testWidgets('kartu menunggu: batang tampil di antara status dan '
        'label jenis, nilai 2/6', (tester) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(
              _peerId,
              usable: false,
              channelValueSats: 300000,
              fundingTxo: _fundingTxo('ff' * 32),
              confirmations: 2,
              confirmationsRequired: 6,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Menunggu konfirmasi • Konfirmasi 2/6'), findsOneWidget);
      expect(find.text('Channel Langsung'), findsOneWidget);
      final bar = find.byType(LinearProgressIndicator);
      expect(bar, findsOneWidget);
      expect(
        tester.widget<LinearProgressIndicator>(bar).value,
        closeTo(2 / 6, 0.001),
      );
      // Penempatan: batang di antara baris status dan label jenis.
      final statusY = tester
          .getCenter(find.text('Menunggu konfirmasi • Konfirmasi 2/6'))
          .dy;
      final barY = tester.getCenter(bar).dy;
      final labelY = tester.getCenter(find.text('Channel Langsung')).dy;
      expect(statusY, lessThan(barY));
      expect(barY, lessThan(labelY));
    });

    testWidgets('kartu siap: batang tidak tampil', (tester) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [_channel(_peerId, channelValueSats: 20000)],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Siap'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('kartu peer-down: batang tidak tampil', (tester) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(
              _peerId,
              usable: false,
              channelReady: true,
              channelValueSats: 20000,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Siap (peer tidak tersambung)'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('kartu menutup: batang tidak tampil', (tester) async {
      final service = _FakeLspService(
        channels: [_channel(_peerId, channelValueSats: 20000)],
      );
      await _pumpScreen(tester, service: service);
      await tester.tap(find.text('Tutup Channel'));
      await _pumpManual(tester);
      await tester.tap(find.text('Tutup Channel').last);
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Menutup…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('hitungan basi 69/6: batang penuh, tidak meluber nilai', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(
              _peerId,
              usable: false,
              channelValueSats: 20000,
              fundingTxo: _fundingTxo('aa' * 32),
              confirmations: 69,
              confirmationsRequired: 6,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Menunggu konfirmasi • Konfirmasi 6/6'), findsOneWidget);
      final bar = find.byType(LinearProgressIndicator);
      expect(bar, findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(bar).value, 1.0);
    });

    testWidgets('jumlah wajib tidak diketahui: batang tak tentu', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(
              _peerId,
              usable: false,
              channelValueSats: 20000,
              fundingTxo: _fundingTxo('bb' * 32),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Menunggu konfirmasi'), findsOneWidget);
      final bar = find.byType(LinearProgressIndicator);
      expect(bar, findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(bar).value, isNull);
    });

    testWidgets('layar 360 px + channel menunggu: batang tampil tanpa '
        'luber', (tester) async {
      // Regresi luber 168 px (PR #43) + batang baru: di layar
      // 360 px, batang harus muat di dalam kartu.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpScreen(
        tester,
        service: _FakeLspService(
          channels: [
            _channel(
              _peerId,
              usable: false,
              channelValueSats: 300000,
              fundingTxo: _fundingTxo('ff' * 32),
              confirmations: 0,
              confirmationsRequired: 6,
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Menunggu konfirmasi • Konfirmasi 0/6'), findsOneWidget);
      final bar = find.byType(LinearProgressIndicator);
      expect(bar, findsOneWidget);
      expect(tester.getBottomRight(bar).dx, lessThanOrEqualTo(360));
      expect(tester.getSize(bar).width, greaterThan(100));
      final labelSize = tester.getSize(find.text('Channel langsung'));
      expect(labelSize.width, greaterThan(50));
      expect(labelSize.height, lessThan(30));
    });
  });

  group('R3 helpers murni', () {
    test('forceCloseUnlockEstimate: ujung + 144 blok', () {
      expect(forceCloseDelayBlocks, 144);
      expect(forceCloseUnlockEstimate(1500), 1644);
      expect(forceCloseUnlockEstimate(0), 144);
    });

    test('cappedConfirmations: tidak pernah melebihi wajib', () {
      expect(cappedConfirmations(69, 6), 6);
      expect(cappedConfirmations(6, 6), 6);
      expect(cappedConfirmations(3, 6), 3);
      expect(cappedConfirmations(0, 6), 0);
      expect(cappedConfirmations(-1, 6), 0);
    });
  });
}
