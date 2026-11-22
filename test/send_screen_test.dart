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

// Offer Bolt12 variable-amount (tanpa nominal tetap) — salinan
// dari test/bolt12_info_test.dart. Belum kedaluwarsa,
// deskripsi "Spike Bolt12 ELNUX".
const _offerVariable =
    'lno1qgsxn3j3r9xwswu6tx4j0aw89gq3sgjskk97ts5mtzt0n43rwyqsqqq2zffhq6ttv5syymmvwscnygz9f3892kqsl5qhzq69kgvyfpa0zm5r0rf6ygt79jm838ttyckz6r56m8t5pp7h20hwkgpa4y0ykzqeml5zd3n5dhwdaxkq4df5mgrglu0wqw0hzemxrv3ahhqzqwqu2ncajzcmfvnpjuxzk97g6zmska74cxyvlagn47f36hy6n33scqr5q3jsd9kyea7qy0y59n4er3lyl5ex9qj9shwvsqu3hkzvj2tyvmeztlqmkygxhs7rypjj8yq5m6ch5rxk2nq205lvk50rjag22kln90zgskdqq7hzqfk4dm3s5fu24mrtymju4ehn4qkrfu6h2wnjt40kd2aprad2kp8r5nnnshgjeg23ztkmnv4hf5pe6k8z8e6etmhk075xj2a9pp4gpucruu5eluerhnsvmr8lqeh6tyqqw3uw7zrfhapsthaue0tgckx4v0v6l6qnk7gc6zjfgux8mpxlljgrjnyjs8curnjwlr8m6pxn29jz84vvf7qyh5tctxwh7krfz77t7duyr58098qrct0wl9d78rsldwr0xar2427qsefvwtynt4nyqmfj6njj4e6m6ssel98jrdgafjapu22waldef4u3vggzjuj920fkmwjwy0jqk38msmerthtyr5udalpwaz634g6hcyyht3gq';

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
  BigInt? unspendablePunishmentReserve,
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
    unspendablePunishmentReserve: unspendablePunishmentReserve,
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
/// menolak perintah karena tanpa rute); hasil akhir pembayaran
/// bisa diatur per tes (null = masih pending melewati batas
/// tunggu).
class _FakeLspService extends LspService {
  List<ChannelDetails> channels;
  List<PeerDetails> peers;
  BigInt? balanceMsat;
  bool throwOnPay;
  PaymentStatus? outcome;

  _FakeLspService({
    this.channels = const [],
    this.peers = const [],
    this.balanceMsat,
    this.throwOnPay = false,
    this.outcome = PaymentStatus.succeeded,
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
  Future<List<PaymentDetails>> listPayments() async => [];

  @override
  Future<PaymentId> payInvoice(String invoiceStr) async {
    if (throwOnPay) throw Exception('node menolak perintah kirim');
    return PaymentId(data: Uint8List.fromList(List.filled(32, 7)));
  }

  @override
  Future<PaymentId> payOffer(String offerStr) async {
    if (throwOnPay) throw Exception('node menolak perintah kirim');
    return PaymentId(data: Uint8List.fromList(List.filled(32, 7)));
  }

  @override
  Future<PaymentId> payOfferUsingAmount(
    String offerStr,
    BigInt amountMsat,
  ) async {
    if (throwOnPay) throw Exception('node menolak perintah kirim');
    return PaymentId(data: Uint8List.fromList(List.filled(32, 7)));
  }

  @override
  Future<PaymentStatus?> waitForPaymentOutcome(
    PaymentId paymentId, {
    Duration timeout = const Duration(seconds: 60),
    Duration interval = const Duration(seconds: 2),
  }) async => outcome;
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

/// Tempel [code] lewat tombol Tempel (kolom kode readOnly —
/// mengetik manual tidak mungkin, sesuai keputusan 10 Nov 2026).
///
/// Clipboard dimock lewat kanal platform: `Clipboard.setData`
/// tidak pernah kembali di lingkungan tes ini, jadi handler mock
/// menjawab `Clipboard.getData` langsung dengan kode.
/// Pembersihan mock tidak diperlukan — setiap tes memasang
/// handler-nya sendiri sebelum menempel.
Future<void> _pasteCode(WidgetTester tester, String code) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': code};
      }
      return null;
    },
  );
  final pasteButton = find.widgetWithText(OutlinedButton, 'Tempel');
  await tester.ensureVisible(pasteButton);
  await tester.tap(pasteButton);
  await _pumpManual(tester);
}

/// Tekan tombol Bayar di layar (bukan tombol dialog). Tombol ada
/// di bawah kolom gulir, jadi dipastikan terlihat dulu.
Future<void> _tapPay(WidgetTester tester) async {
  final payButton = find.widgetWithText(ElevatedButton, 'Bayar').first;
  await tester.ensureVisible(payButton);
  await tester.tap(payButton);
  await _pumpManual(tester);
}

/// Tempel [invoice] lalu tekan tombol Bayar di layar.
Future<void> _enterInvoiceAndPay(WidgetTester tester, String invoice) async {
  await _pasteCode(tester, invoice);
  await _tapPay(tester);
}

/// Kolom kode: satu-satunya TextField readOnly di layar.
Finder _codeField() =>
    find.byWidgetPredicate((w) => w is TextField && w.readOnly);

/// Kolom jumlah offer: satu-satunya TextField yang bisa diketik.
Finder _amountField() =>
    find.byWidgetPredicate((w) => w is TextField && !w.readOnly);

/// Isi teks pengontrol dari TextField yang ditemukan [finder].
String _fieldText(WidgetTester tester, Finder finder) =>
    tester.widget<TextField>(finder).controller!.text;

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
      // Baris "Bisa dikirim" menampilkan angka lingkup peer
      // dengan label jalur langsung.
      expect(
        find.text('Bisa dikirim via jalur langsung: 4.000 nusan'),
        findsOneWidget,
      );
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
      // Bukan kotak cadangan: nominal muat di angka gabungan —
      // dan channel uji ini tanpa reserve, jadi baris cadangan
      // kotak batas peer tidak tampil.
      expect(find.textContaining('cadangan pengaman'), findsNothing);
    });

    testWidgets('kotak batas peer menyebut cadangan bila reserve '
        'channel peer > 0', (tester) async {
      // Lapangan 19 Nov 2026: channel langsung bersaldo 15.000
      // nusan, reserve 3.000 — refund 15.000 ditolak batas peer
      // tanpa penjelasan mengapa batasnya 12.000. Diskalakan ke
      // invoice uji 50u: saldo 7.000, reserve 3.000, bisa kirim
      // 4.000 < 5.000.
      final fake = _FakeLspService(
        channels: [
          _channel(
            _peerId,
            outboundMsat: 4000000,
            unspendablePunishmentReserve: BigInt.from(3000),
          ),
          _channel(_lspId, outboundMsat: 5000000000),
        ],
        peers: [_peer(_peerId)],
        balanceMsat: BigInt.from(6000000000),
      );
      await tester.pumpWidget(
        _app(SendScreen(lspService: fake, bridge: _linkedBridge())),
      );
      await _pumpManual(tester);
      await _enterInvoiceAndPay(tester, _invoice50u);
      expect(tester.takeException(), isNull);
      expect(find.text('Bayar invoice ini?'), findsNothing);
      expect(
        find.text(
          'Dari 7.000 nusan di jalur ini, 3.000 nusan disisakan '
          'sebagai cadangan pengaman — tetap milikmu, kembali '
          'bila jalur ditutup.',
        ),
        findsOneWidget,
      );
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
      // Tampilan memakai plafon peer walau LSP tersambung
      // (temuan lapangan 19 Nov 2026: angka gabungan 0,197 NUX
      // menyesatkan dalam konteks tatap muka) — tetapi
      // pemeriksaan pra-bayar tidak membatasi: dialog tetap tampil
      // karena node bisa merutekan via LSP.
      expect(
        find.text('Bisa dikirim via jalur langsung: 4.000 nusan'),
        findsOneWidget,
      );
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

  group('SendScreen reset formulir sesudah sukses', () {
    testWidgets('kirim Bolt11 sukses: kolom kode kosong, baris '
        'nominal hilang, panel sukses tampil', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeLspService(
        channels: [_channel(_lspId, outboundMsat: 5000000000)],
        peers: [_peer(_lspId)],
        balanceMsat: BigInt.from(6000000000),
      );
      await tester.pumpWidget(_app(SendScreen(lspService: fake)));
      await _pumpManual(tester);
      final invoice = _freshInvoice(_invoice50u);
      await _pasteCode(tester, invoice);
      expect(_fieldText(tester, _codeField()), invoice);
      // Keadaan turunan tampil sebelum bayar: baris nominal.
      expect(find.text('Nominal: 5.000 nusan'), findsOneWidget);
      await _tapPay(tester);
      expect(find.text('Bayar invoice ini?'), findsOneWidget);
      await _confirmDialog(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Pembayaran Berhasil!'), findsOneWidget);
      // Formulir bersih seperti baru membuka layar.
      expect(_fieldText(tester, _codeField()), isEmpty);
      expect(find.text('Nominal: 5.000 nusan'), findsNothing);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('kirim offer Bolt12 variable sukses: kolom kode dan '
        'kolom jumlah sama-sama kosong', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeLspService(
        channels: [_channel(_lspId, outboundMsat: 5000000000)],
        peers: [_peer(_lspId)],
        balanceMsat: BigInt.from(6000000000),
      );
      await tester.pumpWidget(_app(SendScreen(lspService: fake)));
      await _pumpManual(tester);
      await _pasteCode(tester, _offerVariable);
      expect(_fieldText(tester, _codeField()), _offerVariable);
      // Panel offer variable tampil dengan kolom jumlah.
      expect(
        find.text(
          'Kode bayar ini tidak menetapkan nominal — tentukan '
          'sendiri jumlah yang mau dibayar.',
        ),
        findsOneWidget,
      );
      await tester.enterText(_amountField(), '2000');
      await _pumpManual(tester);
      await _tapPay(tester);
      expect(find.text('Bayar kode bayar ini?'), findsOneWidget);
      await _confirmDialog(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Pembayaran Berhasil!'), findsOneWidget);
      // Kedua kolom kosong, panel offer ikut hilang.
      expect(_fieldText(tester, _codeField()), isEmpty);
      expect(_amountField(), findsNothing);
      expect(
        find.text(
          'Kode bayar ini tidak menetapkan nominal — tentukan '
          'sendiri jumlah yang mau dibayar.',
        ),
        findsNothing,
      );
    });

    testWidgets('gagal kirim sinkron: nilai formulir dipertahankan '
        'untuk coba ulang', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeLspService(
        channels: [_channel(_lspId, outboundMsat: 5000000000)],
        peers: [_peer(_lspId)],
        balanceMsat: BigInt.from(6000000000),
        throwOnPay: true,
      );
      await tester.pumpWidget(_app(SendScreen(lspService: fake)));
      await _pumpManual(tester);
      final invoice = _freshInvoice(_invoice50u);
      await _enterInvoiceAndPay(tester, invoice);
      expect(find.text('Bayar invoice ini?'), findsOneWidget);
      await _confirmDialog(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Pembayaran gagal. Coba lagi.'), findsOneWidget);
      // Nilai dipertahankan — tidak perlu menempel ulang.
      expect(_fieldText(tester, _codeField()), invoice);
      expect(find.text('Nominal: 5.000 nusan'), findsOneWidget);
    });

    testWidgets('hasil masih pending: nilai formulir dipertahankan', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final fake = _FakeLspService(
        channels: [_channel(_lspId, outboundMsat: 5000000000)],
        peers: [_peer(_lspId)],
        balanceMsat: BigInt.from(6000000000),
        outcome: null,
      );
      await tester.pumpWidget(_app(SendScreen(lspService: fake)));
      await _pumpManual(tester);
      final invoice = _freshInvoice(_invoice50u);
      await _enterInvoiceAndPay(tester, invoice);
      expect(find.text('Bayar invoice ini?'), findsOneWidget);
      await _confirmDialog(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          'Pembayaran masih diproses melewati batas tunggu. '
          'Hasil akhirnya akan tampil di Riwayat — jangan bayar '
          'ulang invoice yang sama sebelum statusnya jelas.',
        ),
        findsOneWidget,
      );
      expect(find.text('Pembayaran Berhasil!'), findsNothing);
      // Nilai dipertahankan — statusnya belum jelas.
      expect(_fieldText(tester, _codeField()), invoice);
      expect(find.text('Nominal: 5.000 nusan'), findsOneWidget);
    });
  });
}
