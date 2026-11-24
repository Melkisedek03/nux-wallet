import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/screens/offline_mode_screen.dart';
import 'package:nux_wallet/services/fee_estimate.dart';
import 'package:nux_wallet/services/lsp_service.dart';
import 'package:nux_wallet/services/offline_bridge.dart';
import 'package:nux_wallet/theme.dart';
import 'package:nux_wallet/unit_controller.dart';
import 'package:nux_wallet/utils/format.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ownId =
    '039b7213909b561a355832406bdbf18bf6e1ff56cd94c347890658cc02de408cc8';
const _peerId =
    '035d4490410d765e327bd33bcaaa0db8bc1b0ea7ca0f8df7e9db8d9279b16683b0';

OutPoint _fundingTxo(String txid) =>
    OutPoint(txid: Txid(hash: txid), vout: 0);

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

/// Layanan palsu: node berjalan, ID sendiri tetap, daftar channel
/// bisa diatur per tes. Jembatan dipakai asli (keadaannya diatur
/// langsung lewat field publiknya); saklar dan tombol Sambungkan
/// tidak ditekan di tes ini karena memanggil Nearby lewat
/// MethodChannel tanpa mock platform.
class _FakeLspService extends LspService {
  List<ChannelDetails> channels;
  BigInt spendableSats;
  bool offlineMode;
  bool peerConnected;

  /// Nominal setiap pembukaan channel yang diminta layar.
  final List<BigInt> openedAmounts = [];

  _FakeLspService({
    List<ChannelDetails> channels = const [],
    BigInt? spendableSats,
    this.offlineMode = false,
    this.peerConnected = true,
  }) : channels = List.of(channels),
       spendableSats = spendableSats ?? BigInt.from(200000);

  @override
  bool get isRunning => true;

  @override
  bool get isOfflineMode => offlineMode;

  @override
  Future<String> ownNodeId() async => _ownId;

  @override
  Future<List<ChannelDetails>> listChannels() async => channels;

  @override
  Future<BigInt> spendableOnchainBalanceSats() async => spendableSats;

  @override
  Future<List<PeerDetails>> listPeerDetails() async => [
    PeerDetails(
      nodeId: PublicKey(hex: _peerId),
      address: SocketAddress.tcpIpV4(
        addr: U8Array4(Uint8List.fromList([127, 0, 0, 1])),
        port: 19736,
      ),
      isConnected: peerConnected,
    ),
  ];

  @override
  Future<UserChannelId> openChannelToPeer(
    String nodeIdHex,
    String host,
    int port,
    BigInt amountSats,
  ) async {
    openedAmounts.add(amountSats);
    final userId = UserChannelId(
      data: Uint8List.fromList(List.filled(16, 7)),
    );
    // Meniru node: sesudah pembukaan, channel muncul dalam
    // keadaan disiapkan (0/6) pada listChannels berikutnya.
    channels = [
      ...channels,
      _channel(
        nodeIdHex,
        usable: false,
        channelValueSats: amountSats.toInt(),
        fundingTxo: _fundingTxo('cc' * 32),
        confirmations: 0,
        confirmationsRequired: 6,
        userIdFill: 7,
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

/// Pompa manual sebagai pengganti pumpAndSettle: layar dan baris
/// menyalakan timer periodik selama tertaut, dan kartu mencari
/// memakai CircularProgressIndicator yang tidak pernah berhenti
/// beranimasi — keduanya membuat pumpAndSettle tidak pernah
/// selesai. Beberapa pompa cukup untuk futures lokal selesai.
Future<void> _pumpManual(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Jembatan dalam keadaan tertaut mode gabung ke peer uji (HELLO
/// sudah diterima sehingga peerNodeId dikenal).
OfflineBridgeService _linkedBridge() {
  SharedPreferences.setMockInitialValues({});
  final bridge = OfflineBridgeService();
  bridge.sessionActive = true;
  bridge.role = OfflineBridgeRole.combined;
  bridge.phase = OfflineBridgePhase.linked;
  bridge.linkedEndpointId = 'endpoint-peer';
  bridge.linkedEndpointName = 'ELNUX-035d4490';
  bridge.rememberPeerNodeId(_peerId);
  return bridge;
}

/// Sesi hidup tapi belum tertaut, dengan peer yang diingat dari
/// sesi sebelumnya (varian siap-tanpa-tautan).
OfflineBridgeService _unlinkedBridgeWithPeer() {
  SharedPreferences.setMockInitialValues({});
  final bridge = OfflineBridgeService();
  bridge.sessionActive = true;
  bridge.role = OfflineBridgeRole.combined;
  bridge.phase = OfflineBridgePhase.discovering;
  bridge.rememberPeerNodeId(_peerId);
  return bridge;
}

/// Mock saluran Nearby: mulai iklan/pencarian dan permintaan
/// sambung bisa dibuat gagal per tes. Metode lain mengembalikan
/// null — plugin memperlakukannya sebagai false/void, sesuai
/// perilaku platform yang tidak mengembalikan nilai.
void _mockNearby({bool startOk = true, bool connectOk = true}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('nearby_connections'), (
        call,
      ) async {
        switch (call.method) {
          case 'startAdvertising':
          case 'startDiscovery':
            return startOk;
          case 'requestConnection':
            return connectOk;
          default:
            return null;
        }
      });
}

/// Mock saluran permission_handler untuk uji penyebab kegagalan
/// mulai (G2.3): izin bisa ditolak per nilai, layanan bisa
/// dimatikan. Nilai izin: locationWhenInUse=5, bluetoothScan=28,
/// bluetoothAdvertise=29, bluetoothConnect=30; layanan:
/// location=3, bluetooth=21. Status: ditolak=0, diizinkan=1;
/// layanan: mati=0, nyala=1.
void _mockStartCause({
  Set<int> deniedPermissions = const {},
  int locationService = 1,
  int bluetoothService = 1,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
          if (call.method == 'checkPermissionStatus') {
            return deniedPermissions.contains(call.arguments) ? 0 : 1;
          }
          if (call.method == 'checkServiceStatus') {
            if (call.arguments == 3) return locationService;
            if (call.arguments == 21) return bluetoothService;
            return 1;
          }
          if (call.method == 'requestPermissions') {
            return <int, int>{};
          }
          return null;
        },
      );
}

/// Mock saluran permission_handler: Permission.notification = 17;
/// checkPermissionStatus mengembalikan 0 (ditolak) / 1 (diizinkan).
void _mockNotificationPermission({required bool granted}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
          if (call.method == 'checkPermissionStatus') {
            return granted ? 1 : 0;
          }
          if (call.method == 'requestPermissions') {
            return <int, int>{17: granted ? 1 : 0};
          }
          return null;
        },
      );
}

void main() {
  // Mock izin dan Nearby dipasang per tes; tanpa pembersihan, mock
  // dari satu tes bocor ke tes berikutnya dalam berkas yang sama.
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('nearby_connections'),
      null,
    );
  });

  group('OfflineModeScreen', () {
    testWidgets('sesi mati: kode tampil besar, saklar mati, tanpa kandidat', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(),
            bridge: OfflineBridgeService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Kode perangkat saya'), findsOneWidget);
      expect(find.text('039B 7213'), findsOneWidget);
      expect(find.text('ELNUX-039b7213'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(
        find.text('Bayar tanpa internet dengan perangkat di dekatmu'),
        findsOneWidget,
      );
      expect(find.text('Sambungkan'), findsNothing);
      expect(find.text('Akhiri Sesi'), findsNothing);
    });

    testWidgets('sesi hidup tanpa kandidat: kartu mencari + Akhiri Sesi', (
      tester,
    ) async {
      final bridge = OfflineBridgeService();
      bridge.sessionActive = true;
      bridge.role = OfflineBridgeRole.combined;
      bridge.phase = OfflineBridgePhase.discovering;
      await tester.pumpWidget(
        _app(OfflineModeScreen(lspService: _FakeLspService(), bridge: bridge)),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Mencari perangkat di dekat…'), findsWidgets);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('Akhiri Sesi'), findsOneWidget);
    });

    testWidgets('kandidat tampil dengan nama, kode, dan tombol Sambungkan', (
      tester,
    ) async {
      final bridge = OfflineBridgeService();
      bridge.sessionActive = true;
      bridge.role = OfflineBridgeRole.combined;
      bridge.phase = OfflineBridgePhase.discovering;
      bridge.discovered.add(const DiscoveredHost('e1', 'ELNUX-035d4490'));
      await tester.pumpWidget(
        _app(OfflineModeScreen(lspService: _FakeLspService(), bridge: bridge)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ELNUX-035d4490'), findsOneWidget);
      expect(find.text('035D 4490'), findsOneWidget);
      expect(find.text('Sambungkan'), findsOneWidget);
    });

    testWidgets('tertaut tanpa jalur: Terhubung + Jalur belum ada', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(),
            bridge: _linkedBridge(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Terhubung'), findsOneWidget);
      expect(find.text('ELNUX-035d4490 • 035D 4490'), findsOneWidget);
      expect(find.text('Jalur pembayaran belum ada'), findsOneWidget);
      expect(find.text('Jalur siap — bisa bayar tanpa internet'), findsNothing);
    });

    testWidgets('tertaut dengan channel siap: Jalur siap tampil', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(channels: [_channel(_peerId)]),
            bridge: _linkedBridge(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      // Teks yang sama muncul dua kali dengan sengaja: subjudul
      // keadaan di kartu saklar + kartu keadaan jalur.
      expect(
        find.text('Jalur siap — bisa bayar tanpa internet'),
        findsNWidgets(2),
      );
      expect(find.text('Jalur pembayaran belum ada'), findsNothing);
    });

    testWidgets(
      'channel belum usable berarti jalur disiapkan, bukan belum ada',
      (tester) async {
        await tester.pumpWidget(
          _app(
            OfflineModeScreen(
              lspService: _FakeLspService(
                channels: [_channel(_peerId, usable: false)],
              ),
              bridge: _linkedBridge(),
            ),
          ),
        );
        await _pumpManual(tester);
        expect(tester.takeException(), isNull);
        // Teks yang sama muncul dua kali dengan sengaja: subjudul
        // keadaan di kartu saklar + kartu keadaan jalur.
        expect(find.text('Jalur sedang disiapkan…'), findsNWidgets(2));
        expect(find.text('Menunggu konfirmasi…'), findsOneWidget);
        expect(find.text('Jalur pembayaran belum ada'), findsNothing);
        expect(find.text('Buat Jalur Pembayaran'), findsNothing);
      },
    );

    testWidgets('jalur siap: plafon kirim ke peer tampil di kartu', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(channels: [_channel(_peerId)]),
            bridge: _linkedBridge(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Bisa kirim sampai 24.000 nusan'), findsOneWidget);
    });

    testWidgets('plafon hanya menghitung channel ke peer tertaut', (
      tester,
    ) async {
      const lspId =
          '02b69d63f7f07765257d729b4141426abff80a91088eb439ec6f2e9669b6423549';
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(
              channels: [
                _channel(_peerId, outboundMsat: 679000000),
                _channel(lspId, outboundMsat: 5000000000),
              ],
            ),
            bridge: _linkedBridge(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      // 679.000 nusan (channel langsung), BUKAN 5.679.000
      // (gabungan dengan channel LSP).
      expect(find.text('Bisa kirim sampai 679.000 nusan'), findsOneWidget);
    });

    testWidgets('jalur belum ada: tanpa plafon kirim', (tester) async {
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(),
            bridge: _linkedBridge(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Bisa kirim sampai'), findsNothing);
    });

    testWidgets('tanpa jalur: tombol Buat Jalur tampil', (tester) async {
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(),
            bridge: _linkedBridge(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Buat Jalur Pembayaran'), findsOneWidget);
      expect(find.text('Jalur pembayaran belum ada'), findsOneWidget);
    });

    testWidgets('jalur siap: tombol Buat Jalur disembunyikan', (tester) async {
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(channels: [_channel(_peerId)]),
            bridge: _linkedBridge(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Buat Jalur Pembayaran'), findsNothing);
    });

    testWidgets('jalur disiapkan 0/6: menunggu konfirmasi pertama', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(
              channels: [
                _channel(
                  _peerId,
                  usable: false,
                  channelValueSats: 100000,
                  fundingTxo: _fundingTxo('aa' * 32),
                  confirmations: 0,
                  confirmationsRequired: 6,
                ),
              ],
            ),
            bridge: _linkedBridge(),
            feeEstimateService: _FakeFeeEstimateService(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Jalur sedang disiapkan…'), findsNWidgets(2));
      expect(find.text('Menunggu konfirmasi pertama…'), findsOneWidget);
      expect(
        find.text(
          'Blok baru muncul sesuai jadwal penambangan jaringan — mohon tunggu/mulailah menambang di jaringan Nusacoin secara mandiri.',
        ),
        findsOneWidget,
      );
      expect(find.text('Nilai jalur: 100.000 nusan'), findsOneWidget);
      // Biaya pasti baru diambil sesudah konfirmasi pertama.
      expect(find.textContaining('Biaya jaringan:'), findsNothing);
      expect(find.text('Buat Jalur Pembayaran'), findsNothing);
    });

    testWidgets('jalur disiapkan 3/6: progres + biaya pasti', (tester) async {
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(
              channels: [
                _channel(
                  _peerId,
                  usable: false,
                  channelValueSats: 100000,
                  fundingTxo: _fundingTxo('aa' * 32),
                  confirmations: 3,
                  confirmationsRequired: 6,
                ),
              ],
            ),
            bridge: _linkedBridge(),
            feeEstimateService: _FakeFeeEstimateService(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Konfirmasi 3/6'), findsOneWidget);
      expect(find.text('dari 6 konfirmasi dibutuhkan'), findsOneWidget);
      expect(
        find.text(
          'Blok baru muncul sesuai jadwal penambangan jaringan — mohon tunggu/mulailah menambang di jaringan Nusacoin secara mandiri.',
        ),
        findsOneWidget,
      );
      expect(find.text('Nilai jalur: 100.000 nusan'), findsOneWidget);
      expect(find.text('Biaya jaringan: 250 nusan'), findsOneWidget);
    });

    testWidgets('jalur siap tanpa tautan: kartu siap-tanpa-tautan', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(channels: [_channel(_peerId)]),
            bridge: _unlinkedBridgeWithPeer(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Jalur siap — sambungkan lagi ke ELNUX-035d4490 untuk membayar',
        ),
        findsOneWidget,
      );
      expect(find.text('Buat Jalur Pembayaran'), findsNothing);
    });

    testWidgets('sesi boot offline: tombol tidak aktif + kalimat jelas', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(offlineMode: true),
            bridge: _linkedBridge(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Buat Jalur Pembayaran'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.text(
          'Jalur baru butuh internet sekali saat disiapkan — pembayaran lewat jalur yang sudah siap tetap bisa',
        ),
        findsOneWidget,
      );
    });

    testWidgets('catatan izin notifikasi tampil bila izin ditolak', (
      tester,
    ) async {
      _mockNotificationPermission(granted: false);
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: _FakeLspService(
              channels: [
                _channel(
                  _peerId,
                  usable: false,
                  fundingTxo: _fundingTxo('aa' * 32),
                  confirmations: 3,
                  confirmationsRequired: 6,
                ),
              ],
            ),
            bridge: _linkedBridge(),
            feeEstimateService: _FakeFeeEstimateService(),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Nyalakan izin notifikasi supaya kamu diberi tahu saat jalur siap.',
        ),
        findsOneWidget,
      );
    });
  });

  group('OfflineModeScreen Buat Jalur', () {
    Future<void> pumpLinked(
      WidgetTester tester, {
      _FakeLspService? service,
    }) async {
      // Saluran izin WAJIB di-mock pada tes alur: tanpa mock,
      // Permission.notification.request() di lingkungan tes tidak
      // pernah selesai (bukan MissingPluginException) sehingga
      // alur Buat Jalur macet sebelum lembar nominal. Di perangkat
      // nyata sisi platform selalu menjawab; ini artefak tes saja.
      _mockNotificationPermission(granted: true);
      await tester.pumpWidget(
        _app(
          OfflineModeScreen(
            lspService: service ?? _FakeLspService(),
            bridge: _linkedBridge(),
            feeEstimateService: _FakeFeeEstimateService(),
          ),
        ),
      );
      await _pumpManual(tester);
    }

    /// Kartu jalur berada di bawah lipatan pada viewport tes
    /// 800×600: gulir dulu sebelum mengetuk tombolnya.
    Future<void> tapMakePathButton(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Buat Jalur Pembayaran'));
      await _pumpManual(tester);
      await tester.tap(find.text('Buat Jalur Pembayaran'));
      await _pumpManual(tester);
    }

    testWidgets('lembar nominal: bawaan + saldo + validasi minimum', (
      tester,
    ) async {
      await pumpLinked(tester);
      await tapMakePathButton(tester);
      expect(find.text('Nominal bawaan'), findsOneWidget);
      expect(find.text('100.000 nusan'), findsOneWidget);
      expect(find.text('Saldo on-chain-mu: 200.000 nusan'), findsOneWidget);

      await tester.tap(find.text('Nominal lain'));
      await _pumpManual(tester);
      // Hint hanya contoh nilai (pendek, tidak terpotong);
      // aturan minimum pindah ke helperText di bawah kolom.
      expect(find.text('cth. 25.000 nusan'), findsOneWidget);
      expect(
        find.text('Minimal 10.000 nusan, bernilai nusan bulat.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '5.000');
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);
      expect(
        find.text('Minimal 10.000 nusan untuk satu jalur.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), '50.000');
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);
      // Validasi lolos: lembar tertutup, dialog konfirmasi tampil.
      expect(find.text('Buat jalur ke ELNUX-035d4490?'), findsOneWidget);
      expect(find.text('50.000 nusan'), findsOneWidget);
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
      await pumpLinked(tester);
      await tapMakePathButton(tester);
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
        find.text('Minimal 0,0001 NUX untuk satu jalur.'),
        findsOneWidget,
      );

      // Nominal valid yang BERBEDA dari bawaan (0,001 NUX):
      // lembar yang masih menganimasikan keluar tetap memuat judul
      // bawaan, jadi nominal yang sama akan terhitung ganda.
      await tester.enterText(find.byType(TextField), '0,0005');
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);
      // Validasi lolos: dialog konfirmasi tampil dengan nominal NUX.
      expect(find.text('Buat jalur ke ELNUX-035d4490?'), findsOneWidget);
      expect(find.text('0,0005 NUX'), findsOneWidget);
    });

    testWidgets('alir penuh: lembar → konfirmasi → jalur disiapkan', (
      tester,
    ) async {
      final service = _FakeLspService();
      await pumpLinked(tester, service: service);
      await tapMakePathButton(tester);
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);

      // Dialog konfirmasi: semua baris sesuai desain.
      expect(find.text('Buat jalur ke ELNUX-035d4490?'), findsOneWidget);
      expect(find.text('Jumlah jalur'), findsOneWidget);
      expect(find.text('100.000 nusan'), findsOneWidget);
      expect(find.text('Biaya jaringan (perkiraan)'), findsOneWidget);
      expect(find.text('±250 nusan'), findsOneWidget);
      expect(find.text('Total dari dompet on-chain'), findsOneWidget);
      expect(find.text('±100.250 nusan'), findsOneWidget);
      expect(
        find.text(
          '100.000 nusan dari dompet on-chain-mu pindah ke jalur ini — kamulah yang bisa mengirim lewat jalur ini.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Jalur siap dipakai setelah 6 konfirmasi jaringan. Kamu akan diberi tahu saat sudah siap.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Buat Jalur'));
      await _pumpManual(tester);
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(service.openedAmounts, [BigInt.from(100000)]);
      expect(find.text('Jalur sedang disiapkan…'), findsNWidgets(2));
      expect(find.text('Menunggu konfirmasi pertama…'), findsOneWidget);
      expect(find.text('Nilai jalur: 100.000 nusan'), findsOneWidget);
    });

    testWidgets('saldo tidak cukup: dialog + Isi Dompet membuka On-chain', (
      tester,
    ) async {
      await pumpLinked(
        tester,
        service: _FakeLspService(spendableSats: BigInt.zero),
      );
      await tapMakePathButton(tester);
      expect(find.text('Saldo on-chain belum cukup'), findsOneWidget);
      expect(find.text('Isi Dompet On-chain'), findsOneWidget);

      await tester.tap(find.text('Isi Dompet On-chain'));
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Dompet On-chain'), findsOneWidget);
    });

    testWidgets('peer terputus saat membuka: pesan putus, bukan jargon', (
      tester,
    ) async {
      final service = _FakeLspService(peerConnected: false);
      await pumpLinked(tester, service: service);
      await tapMakePathButton(tester);
      await tester.tap(find.text('Lanjut'));
      await _pumpManual(tester);
      await tester.tap(find.text('Buat Jalur'));
      await _pumpManual(tester);
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(service.openedAmounts, isEmpty);
      expect(
        find.text(
          'Perangkat terputus saat membuat jalur. Dekatkan kedua HP, sambungkan lagi, lalu coba lagi.',
        ),
        findsOneWidget,
      );
    });
  });

  group('OfflineModeRow', () {
    testWidgets('sesi mati: judul + deskripsi fitur', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: OfflineModeRow(
              lspService: _FakeLspService(),
              bridge: OfflineBridgeService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Mode Offline'), findsOneWidget);
      expect(
        find.text('Bayar tanpa internet dengan perangkat di dekatmu'),
        findsOneWidget,
      );
    });

    testWidgets('sesi hidup belum tertaut: subjudul mencari', (tester) async {
      final bridge = OfflineBridgeService();
      bridge.sessionActive = true;
      bridge.role = OfflineBridgeRole.combined;
      bridge.phase = OfflineBridgePhase.discovering;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: OfflineModeRow(lspService: _FakeLspService(), bridge: bridge),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Mencari perangkat di dekat…'), findsOneWidget);
    });

    testWidgets('tertaut: subjudul menyebut perangkat', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: OfflineModeRow(
              lspService: _FakeLspService(),
              bridge: _linkedBridge(),
            ),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Terhubung ke ELNUX-035d4490'), findsOneWidget);
    });

    testWidgets('tertaut dengan jalur siap: subjudul Jalur siap', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: OfflineModeRow(
              lspService: _FakeLspService(channels: [_channel(_peerId)]),
              bridge: _linkedBridge(),
            ),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.text('Jalur siap — bisa bayar tanpa internet'),
        findsOneWidget,
      );
    });

    testWidgets('tertaut dengan jalur disiapkan: subjudul Disiapkan', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: OfflineModeRow(
              lspService: _FakeLspService(
                channels: [
                  _channel(
                    _peerId,
                    usable: false,
                    fundingTxo: _fundingTxo('aa' * 32),
                    confirmations: 3,
                    confirmationsRequired: 6,
                  ),
                ],
              ),
              bridge: _linkedBridge(),
            ),
          ),
        ),
      );
      await _pumpManual(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Jalur sedang disiapkan…'), findsOneWidget);
    });

    testWidgets('ketuk baris membuka layar Mode Offline', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: OfflineModeRow(
              lspService: _FakeLspService(),
              bridge: OfflineBridgeService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mode Offline'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Kode perangkat saya'), findsOneWidget);
    });
  });

  group('Bungkus awam: kegagalan sambung + mulai (G3.1, G2.3)', () {
    /// Jembatan sesi hidup mode gabung dengan satu kandidat —
    /// keadaan awal untuk uji ketukan Sambungkan.
    OfflineBridgeService _discoveringBridgeWithCandidate() {
      SharedPreferences.setMockInitialValues({});
      final bridge = OfflineBridgeService();
      bridge.sessionActive = true;
      bridge.role = OfflineBridgeRole.combined;
      bridge.phase = OfflineBridgePhase.discovering;
      bridge.discovered.add(const DiscoveredHost('e1', 'ELNUX-035d4490'));
      return bridge;
    }

    const _gagalSambung =
        'Tidak bisa tersambung ke perangkat ini. Dekatkan kedua HP, lalu coba lagi.';
    const _gagalGenerik = 'Mode Offline gagal dimulai. Coba lagi.';

    /// Ketuk Sambungkan dan tunggu rantai sambung selesai dalam
    /// waktu nyata. connectCombined mengikat ServerSocket nyata,
    /// dan soket nyata HARUS berjalan di dalam runAsync — di dalam
    /// zona fake-async, bind-nya selesai tetapi teardown tes
    /// menggantung dan tes tidak pernah dianggap selesai.
    /// Selesainya rantai dibaca dari lastError, yang hanya diisi
    /// di ujung cabang gagal; tenggat 5 detik menjaga tes tetap
    /// gagal (bukan menggantung) bila rantai tidak pernah selesai.
    Future<void> _tapConnectAndWait(
      WidgetTester tester,
      OfflineBridgeService bridge,
    ) async {
      bridge.lastError = null;
      await tester.runAsync(() async {
        await tester.tap(find.text('Sambungkan'));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (bridge.lastError == null && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
    }

    testWidgets('G3.1 ketuk Sambungkan gagal: snackbar tampil sekali', (
      tester,
    ) async {
      _mockNearby(connectOk: false);
      final bridge = _discoveringBridgeWithCandidate();
      try {
        await tester.pumpWidget(
          _app(
            OfflineModeScreen(lspService: _FakeLspService(), bridge: bridge),
          ),
        );
        await _pumpManual(tester);
        await _tapConnectAndWait(tester, bridge);
        await _pumpManual(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(_gagalSambung), findsOneWidget);
      } finally {
        // Bersihkan SEBELUM mock dicabut tearDown: stop()
        // memanggil metode Nearby + menutup soket tamu yang
        // dibuka connectCombined — penutupannya di dalam runAsync
        // karena soketnya nyata (alasan yang sama seperti
        // _tapConnectAndWait).
        await tester.runAsync(() => bridge.stop());
      }
    });

    testWidgets('G3.1 sambung otomatis gagal: tanpa snackbar', (tester) async {
      _mockNearby(connectOk: false);
      final bridge = _discoveringBridgeWithCandidate();
      try {
        await tester.pumpWidget(
          _app(
            OfflineModeScreen(lspService: _FakeLspService(), bridge: bridge),
          ),
        );
        await _pumpManual(tester);
        // Meniru sambung-ulang otomatis: jembatan dipanggil
        // langsung, bukan lewat ketukan tombol. Di dalam runAsync
        // karena connectCombined mengikat soket nyata.
        await tester.runAsync(
          () => bridge.connectCombined(
            const DiscoveredHost('e1', 'ELNUX-035d4490'),
          ),
        );
        await _pumpManual(tester);
        expect(tester.takeException(), isNull);
        expect(find.text(_gagalSambung), findsNothing);
      } finally {
        await tester.runAsync(() => bridge.stop());
      }
    });

    testWidgets('G3.1 dua ketukan gagal: satu snackbar per percobaan', (
      tester,
    ) async {
      _mockNearby(connectOk: false);
      final bridge = _discoveringBridgeWithCandidate();
      try {
        await tester.pumpWidget(
          _app(
            OfflineModeScreen(lspService: _FakeLspService(), bridge: bridge),
          ),
        );
        await _pumpManual(tester);
        await _tapConnectAndWait(tester, bridge);
        await _pumpManual(tester);
        expect(find.text(_gagalSambung), findsOneWidget);
        // Tutup snackbar pertama secara eksplisit sebelum percobaan
        // kedua — tanpa ini, snackbar kedua mengantre dan tidak
        // terhitung. Timer durasi snackbar dibuat di dalam runAsync
        // (zona waktu nyata), jadi pompa waktu palsu tidak bisa
        // menghilangkannya; animasi keluarnya sendiri berjalan
        // pada jam palsu.
        final context = tester.element(find.byType(OfflineModeScreen));
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await tester.pumpAndSettle();
        expect(find.text(_gagalSambung), findsNothing);
        await _tapConnectAndWait(tester, bridge);
        await _pumpManual(tester);
        expect(find.text(_gagalSambung), findsOneWidget);
      } finally {
        await tester.runAsync(() => bridge.stop());
      }
    });

    /// Nyalakan sesi dengan Nearby yang gagal mulai, jalankan
    /// [check] sesudah probe penyebab selesai dan kartu error
    /// diperbarui, lalu hentikan jembatan. Pemeriksaan HARUS di
    /// dalam try: stop() mengembalikan fase ke idle dan kartu
    /// error hilang.
    Future<void> _driveStartFailure(
      WidgetTester tester, {
      required void Function() mockPermissions,
      required void Function() check,
    }) async {
      _mockNearby(startOk: false);
      mockPermissions();
      SharedPreferences.setMockInitialValues({});
      final bridge = OfflineBridgeService();
      try {
        await tester.pumpWidget(
          _app(
            OfflineModeScreen(lspService: _FakeLspService(), bridge: bridge),
          ),
        );
        await _pumpManual(tester);
        await tester.tap(find.byType(Switch));
        // Rantai async: mulai jembatan (Nearby mock) + probe
        // penyebab (4 cek izin + 2 cek layanan) + setState.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        expect(bridge.phase, OfflineBridgePhase.error);
        check();
      } finally {
        await tester.runAsync(() => bridge.stop());
      }
    }

    testWidgets('G2.3 izin ditolak: kartu menyebut izin', (tester) async {
      await _driveStartFailure(
        tester,
        mockPermissions: () => _mockStartCause(deniedPermissions: {28}),
        check: () => expect(
          find.text('Izinkan Bluetooth dan Lokasi untuk ELNUX'),
          findsOneWidget,
        ),
      );
    });

    testWidgets('G2.3 Lokasi mati: kartu menyebut Lokasi', (tester) async {
      await _driveStartFailure(
        tester,
        mockPermissions: () => _mockStartCause(locationService: 0),
        check: () => expect(
          find.text('Nyalakan Lokasi untuk memakai Mode Offline'),
          findsOneWidget,
        ),
      );
    });

    testWidgets('G2.3 Bluetooth mati: kartu menyebut Bluetooth', (
      tester,
    ) async {
      await _driveStartFailure(
        tester,
        mockPermissions: () => _mockStartCause(bluetoothService: 0),
        check: () => expect(
          find.text('Nyalakan Bluetooth untuk memakai Mode Offline'),
          findsOneWidget,
        ),
      );
    });

    testWidgets('G2.3 penyebab tidak diketahui: fallback menyebut tindakan', (
      tester,
    ) async {
      await _driveStartFailure(
        tester,
        mockPermissions: () => _mockStartCause(),
        check: () {
          expect(
            find.text(
              'Mode Offline gagal dimulai. Pastikan Bluetooth dan Lokasi menyala, lalu coba lagi.',
            ),
            findsOneWidget,
          );
          // Pesan generik lama tidak boleh tampil lagi di kartu ini.
          expect(find.text(_gagalGenerik), findsNothing);
        },
      );
    });
  });
}
