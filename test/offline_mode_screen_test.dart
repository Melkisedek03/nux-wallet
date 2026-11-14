import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/screens/offline_mode_screen.dart';
import 'package:nux_wallet/services/lsp_service.dart';
import 'package:nux_wallet/services/offline_bridge.dart';
import 'package:nux_wallet/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ownId =
    '039b7213909b561a355832406bdbf18bf6e1ff56cd94c347890658cc02de408cc8';
const _peerId =
    '035d4490410d765e327bd33bcaaa0db8bc1b0ea7ca0f8df7e9db8d9279b16683b0';

ChannelDetails _channel(
  String counterpartyHex, {
  bool usable = true,
  int outboundMsat = 24000000,
}) {
  return ChannelDetails(
    channelId: ChannelId(
      data: U8Array32(Uint8List.fromList(List.filled(32, 1))),
    ),
    counterpartyNodeId: PublicKey(hex: counterpartyHex),
    channelValueSats: BigInt.from(25000),
    userChannelId: UserChannelId(data: Uint8List.fromList(List.filled(16, 0))),
    feerateSatPer1000Weight: 1000,
    outboundCapacityMsat: BigInt.from(outboundMsat),
    inboundCapacityMsat: BigInt.from(1000000),
    isOutbound: true,
    isChannelReady: usable,
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
  _FakeLspService({this.channels = const []});

  @override
  bool get isRunning => true;

  @override
  Future<String> ownNodeId() async => _ownId;

  @override
  Future<List<ChannelDetails>> listChannels() async => channels;
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

void main() {
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

    testWidgets('channel belum usable bukan jalur siap', (tester) async {
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
      expect(find.text('Jalur pembayaran belum ada'), findsOneWidget);
    });

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
}
