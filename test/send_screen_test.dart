import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/lib.dart';
import 'package:nux_wallet/l10n/app_localizations.dart';
import 'package:nux_wallet/screens/send_screen.dart';
import 'package:nux_wallet/services/lsp_service.dart';
import 'package:nux_wallet/services/offline_bridge.dart';
import 'package:nux_wallet/theme.dart';
import 'package:nux_wallet/utils/bolt11_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _peerId =
    '035d4490410d765e327bd33bcaaa0db8bc1b0ea7ca0f8df7e9db8d9279b16683b0';
const _lspId =
    '02b69d63f7f07765257d729b4141426abff80a91088eb439ec6f2e9669b6423549';

// Invoice uji 50u (5.000 nusan = 5.000.000 msat) yang sama
// dengan test/bolt11_info_test.dart. Timestamp aslinya sudah
// lewat, jadi untuk jalur yang butuh invoice belum kedaluwarsa
// (konteks pesan tanpa-rute) dipakai [_freshInvoice] yang
// mengemas ulang timestamp-nya ke waktu sekarang.
const _invoice50u =
    'lntn50u1p4dtvwydqjw44xjgz2f92zqnj4tqpp56e07u6ce6ryn9q094a8mlj2nv4ycaxl4fevez4wy48dvh2t5cjpqsp5pu2ya79p07tltuvnkfn6wszvcs5aqjqw8ptsaz0896q722632lfq9qyysgqcqzpvxqrrssrzjq2mf6clh7pmk2ftaw2d5zs2zd2llsz53pz8tgw0vduhfv6dkgg65jqqqqyqq2xsqqcqqqqqqqqqqqqqqfqgczp89wecast6hl4eymf8hlrt2zpw6x52qc4hgt0vsf2yh2h5j3xjcth7k8csyyvpanydw8v6xwxgkm74qtcw3aumxm8gkvcfhwf2ggq24yfp8';

const _bech32Charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

/// Kemas ulang [invoice] dengan timestamp sekarang (checksum
/// bech32 dihitung ulang) — tanda tangannya tidak disentuh,
/// dan parser aplikasi memang tidak memverifikasi tanda tangan
/// (hanya checksum + hash + kedaluwarsa). Invoice hasil
/// kemasan ini belum kedaluwarsa selama satu jam ke depan.
String _freshInvoice(String invoice) {
  final s = invoice.trim().toLowerCase();
  final sep = s.lastIndexOf('1');
  final hrp = s.substring(0, sep);
  final words = s
      .substring(sep + 1)
      .split('')
      .map(_bech32Charset.indexOf)
      .toList();
  final payload = words.sublist(0, words.length - 6);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  for (var i = 0; i < 7; i++) {
    payload[i] = (now >> (5 * (6 - i))) & 31;
  }
  final values = <int>[
    ...hrp.codeUnits.map((c) => c >> 5),
    0,
    ...hrp.codeUnits.map((c) => c & 31),
    ...payload,
    0,
    0,
    0,
    0,
    0,
    0,
  ];
  var chk = 1;
  const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  for (final v in values) {
    final top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (var i = 0; i < 5; i++) {
      if ((top >> i) & 1 == 1) chk ^= gen[i];
    }
  }
  final checksum = List.generate(6, (i) => ((chk ^ 1) >> (5 * (5 - i))) & 31);
  return hrp +
      '1' +
      [...payload, ...checksum].map((w) => _bech32Charset[w]).join();
}

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

PeerDetails _peer(String nodeIdHex, {bool connected = true}) {
  return PeerDetails(
    nodeId: PublicKey(hex: nodeIdHex),
    address: SocketAddress.tcpIpV4(
      addr: U8Array4(Uint8List.fromList([127, 0, 0, 1])),
      port: 9735,
    ),
    isConnected: connected,
  );
}

/// Layanan palsu: saldo, channel, dan peer bisa diatur per tes;
/// perintah kirim bisa dibuat gagal sinkron (meniru node yang
/// menolak perintah karena tanpa rute).
class _FakeLspService extends LspService {
  List<ChannelDetails> channels;
  List<PeerDetails> peers;
  BigInt? balanceMsat;
  bool throwOnPay;

  _FakeLspService({
    this.channels = const [],
    this.peers = const [],
    this.balanceMsat,
    this.throwOnPay = false,
  });

  @override
  bool get isRunning => true;

  @override
  Future<List<ChannelDetails>> listChannels() async => channels;

  @override
  Future<List<PeerDetails>> listPeerDetails() async => peers;

  @override
  Future<BigInt> getLightningBalance() async => balanceMsat ?? BigInt.zero;

  @override
  Future<PaymentId> payInvoice(String invoiceStr) async {
    if (throwOnPay) throw Exception('node menolak perintah kirim');
    return PaymentId(data: Uint8List.fromList(List.filled(32, 7)));
  }

  @override
  Future<PaymentStatus?> waitForPaymentOutcome(
    PaymentId paymentId, {
    Duration timeout = const Duration(seconds: 60),
    Duration interval = const Duration(seconds: 2),
  }) async => PaymentStatus.succeeded;
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

/// Pompa manual: layar menyalakan future baca saldo saat init,
/// dan panel sukses memakai animasi — beberapa pompa cukup
/// untuk futures lokal selesai tanpa menunggu animasi.
Future<void> _pumpManual(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Jembatan dalam keadaan tertaut mode gabung ke peer uji (HELLO
/// sudah diterima sehingga peerNodeId dikenal). Pola yang sama
/// dengan test/offline_mode_screen_test.dart.
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

/// Tempel [invoice] lewat tombol Tempel (kolom kode readOnly —
/// mengetik manual tidak mungkin, sesuai keputusan 10 Nov 2026)
/// lalu tekan tombol Bayar di layar (bukan tombol dialog).
/// Tombol-tombol ada di bawah kolom gulir, jadi dipastikan
/// terlihat dulu.
///
/// Clipboard dimock lewat kanal platform: `Clipboard.setData`
/// tidak pernah kembali di lingkungan tes ini, jadi handler mock
/// menjawab `Clipboard.getData` langsung dengan invoice.
/// Pembersihan mock tidak diperlukan — setiap tes memasang
/// handler-nya sendiri sebelum menempel.
Future<void> _enterInvoiceAndPay(WidgetTester tester, String invoice) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': invoice};
      }
      return null;
    },
  );
  final pasteButton = find.widgetWithText(OutlinedButton, 'Tempel');
  await tester.ensureVisible(pasteButton);
  await tester.tap(pasteButton);
  await _pumpManual(tester);
  final payButton = find.widgetWithText(ElevatedButton, 'Bayar').first;
  await tester.ensureVisible(payButton);
  await tester.tap(payButton);
  await _pumpManual(tester);
}

/// Tekan tombol Bayar di dialog konfirmasi (tombol Bayar yang
/// kedua di pohon widget — yang pertama milik layar di bawah
/// dialog).
Future<void> _confirmDialog(WidgetTester tester) async {
  final confirm = find.widgetWithText(ElevatedButton, 'Bayar').last;
  await tester.tap(confirm);
  await _pumpManual(tester);
}

void main() {
  group('SendScreen batas kirim offline', () {
    testWidgets('nominal melewati channel langsung tertahan pra-bayar '
        'dengan kotak batas peer', (tester) async {
      // Lapangan 13 Nov 2026, diskalakan ke invoice uji 50u:
      // channel langsung tinggal 4.000 nusan yang bisa dikirim,
      // channel LSP masih 5.000.000 — angka gabungan menjanjikan
      // 5.004.000, tetapi hanya peer tertaut yang tersambung.
      final fake = _FakeLspService(
        channels: [
          _channel(_peerId, outboundMsat: 4000000),
          _channel(_lspId, outboundMsat: 5000000000),
        ],
        peers: [_peer(_peerId)],
        balanceMsat: BigInt.from(6000000000),
      );
      await tester.pumpWidget(
        _app(SendScreen(lspService: fake, bridge: _linkedBridge())),
      );
      await _pumpManual(tester);
      // Baris "Bisa dikirim" menampilkan angka lingkup peer.
      expect(find.text('Bisa dikirim: 4.000 nusan'), findsOneWidget);
      await _enterInvoiceAndPay(tester, _invoice50u);
      expect(tester.takeException(), isNull);
      // Ditolak sebelum dialog konfirmasi, dengan kotak batas peer.
      expect(find.text('Bayar invoice ini?'), findsNothing);
      expect(
        find.text(
          'Jumlah ini melebihi yang bisa dikirim ke perangkat yang '
          'tertaut. Batasnya sekarang 4.000 nusan.',
        ),
        findsOneWidget,
      );
      // Bukan kotak cadangan: nominal muat di angka gabungan.
      expect(find.textContaining('cadangan pengaman'), findsNothing);
    });

    testWidgets('nominal muat di channel langsung: dialog tampil, '
        'pembayaran berhasil', (tester) async {
      final fake = _FakeLspService(
        channels: [
          _channel(_peerId, outboundMsat: 6000000),
          _channel(_lspId, outboundMsat: 5000000000),
        ],
        peers: [_peer(_peerId)],
        balanceMsat: BigInt.from(6000000000),
      );
      await tester.pumpWidget(
        _app(SendScreen(lspService: fake, bridge: _linkedBridge())),
      );
      await _pumpManual(tester);
      await _enterInvoiceAndPay(tester, _freshInvoice(_invoice50u));
      expect(tester.takeException(), isNull);
      expect(find.text('Bayar invoice ini?'), findsOneWidget);
      expect(find.textContaining('melebihi yang bisa dikirim'), findsNothing);
      await _confirmDialog(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Pembayaran Berhasil!'), findsOneWidget);
    });

    testWidgets('tanpa sesi offline: angka gabungan berlaku, '
        'dialog tampil', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeLspService(
        channels: [
          _channel(_peerId, outboundMsat: 4000000),
          _channel(_lspId, outboundMsat: 5000000000),
        ],
        peers: [_peer(_peerId), _peer(_lspId)],
        balanceMsat: BigInt.from(6000000000),
      );
      await tester.pumpWidget(_app(SendScreen(lspService: fake)));
      await _pumpManual(tester);
      // Tanpa sesi, baris "Bisa dikirim" tetap angka gabungan.
      expect(find.text('Bisa dikirim: 5.004.000 nusan'), findsOneWidget);
      await _enterInvoiceAndPay(tester, _invoice50u);
      expect(tester.takeException(), isNull);
      expect(find.text('Bayar invoice ini?'), findsOneWidget);
    });

    testWidgets('peer lain masih tersambung: pembatasan tidak '
        'berlaku walau sesi aktif', (tester) async {
      final fake = _FakeLspService(
        channels: [
          _channel(_peerId, outboundMsat: 4000000),
          _channel(_lspId, outboundMsat: 5000000000),
        ],
        peers: [_peer(_peerId), _peer(_lspId)],
        balanceMsat: BigInt.from(6000000000),
      );
      await tester.pumpWidget(
        _app(SendScreen(lspService: fake, bridge: _linkedBridge())),
      );
      await _pumpManual(tester);
      await _enterInvoiceAndPay(tester, _invoice50u);
      expect(tester.takeException(), isNull);
      // LSP masih tersambung → jalur itu bisa dipakai, angka
      // gabungan tetap benar.
      expect(find.text('Bayar invoice ini?'), findsOneWidget);
    });

    testWidgets('gagal kirim sinkron dalam konteks offline: pesan '
        'tanpa-rute berbahasa awam', (tester) async {
      final fake = _FakeLspService(
        channels: [_channel(_peerId, outboundMsat: 6000000)],
        peers: [_peer(_peerId)],
        balanceMsat: BigInt.from(6000000000),
        throwOnPay: true,
      );
      await tester.pumpWidget(
        _app(SendScreen(lspService: fake, bridge: _linkedBridge())),
      );
      await _pumpManual(tester);
      final fresh = _freshInvoice(_invoice50u);
      expect(parseBolt11Info(fresh)?.isExpiredAt(DateTime.now()), isFalse);
      await _enterInvoiceAndPay(tester, fresh);
      expect(find.text('Bayar invoice ini?'), findsOneWidget);
      await _confirmDialog(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Jalur ke perangkat yang tertaut tidak bisa membawa '
          'jumlah ini. Coba jumlah yang lebih kecil.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('gagal kirim sinkron di luar konteks offline: '
        'pesan umum seperti sebelumnya', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeLspService(
        channels: [_channel(_lspId, outboundMsat: 5000000000)],
        peers: [_peer(_lspId)],
        balanceMsat: BigInt.from(6000000000),
        throwOnPay: true,
      );
      await tester.pumpWidget(_app(SendScreen(lspService: fake)));
      await _pumpManual(tester);
      await _enterInvoiceAndPay(tester, _freshInvoice(_invoice50u));
      expect(find.text('Bayar invoice ini?'), findsOneWidget);
      await _confirmDialog(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Pembayaran gagal. Coba lagi.'), findsOneWidget);
      expect(find.textContaining('perangkat yang tertaut'), findsNothing);
    });
  });
}
