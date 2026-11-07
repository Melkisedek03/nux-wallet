import 'dart:io';
import 'dart:typed_data';

import 'package:ldk_node/ldk_node.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:ldk_node/src/generated/api/builder.dart';
import 'package:ldk_node/src/generated/api/node.dart';
import 'package:ldk_node/src/utils/frb.dart';

import 'offline_bridge.dart';

/// Service untuk koneksi ke LSP Nusacoin via LSPS2 (bLIP-52).
class LspService {
  FfiNode? _node;
  bool _running = false;
  bool _offlineMode = false;
  String? _lspHost;
  String? _lspNodeId;

  bool get isRunning => _running;

  /// True bila node dijalankan lewat boot mode offline: node dibangun
  /// tanpa sumber likuiditas LSPS2 karena host LSP tidak di-resolve
  /// (tanpa internet). Lihat parameter offlineMode di init().
  bool get isOfflineMode => _offlineMode;

  Future<void> init({
    required List<int> seedBytes,
    required String storagePath,
    required String lspAddress,
    required String lspNodeId,
    String? lspToken,
    required String electrumUrl,
    bool isTestnet = true,
    bool offlineMode = false,
  }) async {
    // Inisialisasi runtime flutter_rust_bridge (kelas `core` di
    // binding) sebelum panggilan API pertama. verifyInit idempotent:
    // aman dipanggil ulang saat retry. Tanpa ini aplikasi berhenti
    // dengan StateError "flutter_rust_bridge has not been initialized".
    await Frb.verifyInit();
    // lspAddress format "host:port" — host boleh hostname (mis.
    // lsp.taobot.org) atau IPv4 dotted. Hostname di-resolve ke IPv4 dulu
    // supaya memakai jalur SocketAddress.tcpIpV4 yang sudah terbukti di
    // uji handshake LSPS2 19 Okt 2026.
    final sep = lspAddress.lastIndexOf(':');
    if (sep < 0) {
      throw StateError(
        'Format lspAddress salah: "$lspAddress" (mesti host:port)',
      );
    }
    final lspHost = lspAddress.substring(0, sep);
    final lspPort = int.parse(lspAddress.substring(sep + 1));
    _lspHost = lspHost;
    _lspNodeId = lspNodeId;
    // Mode offline (kondisi ekstrem tanpa internet): resolusi DNS host
    // LSP pasti gagal dan LSPS2 memang tidak terjangkau, jadi resolusi
    // dan konfigurasi likuiditas dilewati — node dibangun TANPA sumber
    // likuiditas. Node tetap bisa berjalan, menerima peer lokal, dan
    // membayar lewat channel yang sudah ada; membuka channel JIT baru
    // tidak tersedia sampai node dimulai ulang dengan internet
    // (otomatis lewat heartbeat di main.dart, atau mulai ulang
    // aplikasi secara manual).
    _offlineMode = offlineMode;
    LiquiditySourceConfig? liquidityConfig;
    if (!offlineMode) {
      final addrs = await InternetAddress.lookup(lspHost);
      final ipv4 = addrs.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () =>
            throw StateError('Tidak ada alamat IPv4 untuk host "$lspHost"'),
      );
      liquidityConfig = LiquiditySourceConfig(
        lsps2Service: (
          SocketAddress.tcpIpV4(addr: U8Array4(ipv4.rawAddress), port: lspPort),
          PublicKey(hex: lspNodeId),
          lspToken,
        ),
      );
    }

    final config = Config(
      // Testnet = Nusacoin testnet (X11) — chain hash-nya cocok dengan
      // server LSP. JANGAN pakai Network.testnet: itu Bitcoin testnet3,
      // chain hash-nya beda sehingga handshake P2P dengan LSP ditolak
      // dan sync header dari electrs gagal.
      network: isTestnet ? Network.nusacoinTestnet : Network.nusacoin,
      storageDirPath: storagePath,
      // Khusus testnet (spike offline): node juga mendengarkan di
      // localhost supaya jembatan Bluetooth bisa menyambungkan
      // peer masuk dari HP lain di dekatnya (lihat
      // offline_bridge.dart). Tanpa announcementAddresses alamat
      // ini tidak diumumkan ke jaringan gossip, dan mainnet tidak
      // berubah sama sekali.
      listeningAddresses: isTestnet
          ? [
              SocketAddress.tcpIpV4(
                addr: U8Array4(Uint8List.fromList([127, 0, 0, 1])),
                port: OfflineBridgeService.nodeListenPort,
              ),
            ]
          : null,
      trustedPeers0Conf: [PublicKey(hex: lspNodeId)],
      probingLiquidityLimitMultiplier: BigInt.from(3),
      // Mode offline: node boleh start walaupun electrs tidak
      // terjangkau (start ldk-node sebaliknya menggagalkan boot
      // saat chain source tidak bisa disambungkan atau estimasi
      // fee pertamanya gagal). Boot normal tidak berubah: flag
      // mati dan kegagalan yang sama tetap menghentikan boot.
      tolerateOfflineStart: offlineMode,
    );

    final chainConfig = ChainDataSourceConfig.electrum(serverUrl: electrumUrl);

    final builder = FfiBuilder.createBuilder(
      config: config,
      chainDataSourceConfig: chainConfig,
      liquiditySourceConfig: liquidityConfig,
    );

    // setEntropySeedBytes MEMAKAN builder (parameter `self` di Rust)
    // dan mengembalikan builder baru — nilai kembalinya WAJIB yang
    // dipakai. Memanggil build() pada builder lama melempar
    // DroppableDisposedException (RustArc sudah di-dispose).
    final configuredBuilder = builder.setEntropySeedBytes(seedBytes: seedBytes);

    _node = await configuredBuilder.build();
    await _node!.start();
    _running = true;
  }

  Future<String> createJitInvoice({
    required BigInt amountMsat,
    required String description,
    int expirySecs = 3600,
  }) async {
    _ensureRunning();
    final payment = await FfiNode.bolt11Payment(ptr: _node!);
    final invoice = await payment.receiveViaJitChannelUnsafe(
      amountMsat: amountMsat,
      description: description,
      expirySecs: expirySecs,
    );
    return invoice.signedRawInvoice;
  }

  /// Buat invoice Bolt11 biasa (tanpa kelahiran channel) untuk
  /// nominal [amountMsat], lewat channel yang sudah ada. Layak
  /// dipanggil hanya bila kapasitas terima channel usable
  /// mencukupi — pemilihan jalurnya di [chooseReceiveInvoiceRoute].
  Future<String> createRegularInvoice({
    required BigInt amountMsat,
    required String description,
    int expirySecs = 3600,
  }) async {
    _ensureRunning();
    final payment = await FfiNode.bolt11Payment(ptr: _node!);
    final invoice = await payment.receiveUnsafe(
      amountMsat: amountMsat,
      description: description,
      expirySecs: expirySecs,
    );
    return invoice.signedRawInvoice;
  }

  /// Jumlah peer yang sedang tersambung ke node ini.
  Future<int> connectedPeerCount() async {
    _ensureRunning();
    final peers = await _node!.listPeers();
    return peers.where((p) => p.isConnected).length;
  }

  /// ID node Lightning dompet ini (hex 66 karakter) — dibagikan
  /// ke HP lain yang mau menyambung sebagai peer, misalnya lewat
  /// jembatan offline.
  Future<String> ownNodeId() async {
    _ensureRunning();
    final id = await _node!.nodeId();
    return id.hex;
  }

  /// Sambungkan node ke peer [nodeIdHex] di alamat IPv4
  /// [host]:[port]. Untuk jembatan offline, host adalah
  /// 127.0.0.1 dan port adalah port listener jembatan di HP ini;
  /// byte-nya diteruskan jembatan ke HP seberang.
  Future<void> connectToPeer(String nodeIdHex, String host, int port) async {
    _ensureRunning();
    final parts = host.split('.').map(int.parse).toList();
    if (parts.length != 4 || parts.any((p) => p < 0 || p > 255)) {
      throw ArgumentError('Host harus IPv4 dotted: "$host"');
    }
    await _node!.connect(
      nodeId: PublicKey(hex: nodeIdHex),
      address: SocketAddress.tcpIpV4(
        addr: U8Array4(Uint8List.fromList(parts)),
        port: port,
      ),
      persist: true,
    );
  }

  /// Daftar lengkap peer beserta status koneksinya — bahan
  /// pembuktian layar uji offline (peer tampil isConnected).
  Future<List<PeerDetails>> listPeerDetails() async {
    _ensureRunning();
    return _node!.listPeers();
  }

  /// Buka channel privat (tidak diumumkan) ke peer [nodeIdHex]
  /// sebesar [amountSats] nusan, didanai dari dompet on-chain
  /// internal node. Alamat [host]:[port] hanya dipakai ldk-node
  /// untuk menyambung bila peer belum tersambung; bila koneksi
  /// peer sudah berdiri (mis. lewat jembatan offline), alamat
  /// tidak didial dan channel dibuka di atas koneksi yang ada.
  /// Mengembalikan ID channel sementara dari node.
  Future<UserChannelId> openChannelToPeer(
    String nodeIdHex,
    String host,
    int port,
    BigInt amountSats,
  ) async {
    _ensureRunning();
    final parts = host.split('.').map(int.parse).toList();
    if (parts.length != 4 || parts.any((p) => p < 0 || p > 255)) {
      throw ArgumentError('Host harus IPv4 dotted: "$host"');
    }
    return await _node!.openChannel(
      nodeId: PublicKey(hex: nodeIdHex),
      socketAddress: SocketAddress.tcpIpV4(
        addr: U8Array4(Uint8List.fromList(parts)),
        port: port,
      ),
      channelAmountSats: amountSats,
    );
  }

  /// Alamat terima on-chain dompet internal node (SegWit bech32,
  /// diturunkan dari seed dompet yang sama, jalur BIP84). Inilah
  /// alamat yang diisi dana untuk mendanai pembukaan channel
  /// manual seperti [openChannelToPeer].
  Future<String> onchainAddress() async {
    _ensureRunning();
    final onchain = await FfiNode.onChainPayment(ptr: _node!);
    final address = await onchain.newAddress();
    return address.s;
  }

  /// Saldo on-chain internal node yang bisa dibelanjakan saat ini
  /// (nusan utuh) — dana yang tersedia untuk mendanai channel.
  Future<BigInt> spendableOnchainBalanceSats() async {
    _ensureRunning();
    final balances = await _node!.listBalances();
    return balances.spendableOnchainBalanceSats;
  }

  /// Buat offer Bolt12 statis: nominal bebas (ditentukan pembayar)
  /// dan TANPA kedaluwarsa — satu string `lno1…` yang bisa dibayar
  /// berulang kali, fondasi kode bayar Mode Toko.
  ///
  /// SYARAT terbukti dari spike Bolt12 2 Nov 2026: pembuatan offer
  /// membutuhkan blinded path, dan blinded path membutuhkan minimal
  /// satu peer tersambung (di produksi peer itu LSP). Node tanpa
  /// peer melempar OfferCreationFailed — pemanggil wajib memeriksa
  /// [connectedPeerCount] dulu dan menunda pembuatan bila masih 0
  /// (lihat Bolt12OfferService), bukan membiarkan error ini tampil.
  Future<String> createStaticOffer({required String description}) async {
    _ensureRunning();
    final payment = await FfiNode.bolt12Payment(ptr: _node!);
    final offer = await payment.receiveVariableAmountUnsafe(
      description: description,
      expirySecs: null,
    );
    return offer.s;
  }

  /// Daftar channel node saat ini, apa adanya dari binding.
  Future<List<ChannelDetails>> listChannels() async {
    _ensureRunning();
    return await _node!.listChannels();
  }

  /// Total kapasitas terima (msat) dari channel yang usable saat
  /// ini — plafon nominal yang masih bisa diterima lewat invoice
  /// biasa tanpa melahirkan channel baru.
  Future<BigInt> usableInboundCapacityMsat() async {
    return totalUsableInboundCapacityMsat(await listChannels());
  }

  /// Total kapasitas kirim (msat) dari channel yang usable saat
  /// ini — plafon nominal yang benar-benar bisa dikirim sekarang.
  /// Angka node ini sudah bersih dari cadangan pengaman channel,
  /// jadi inilah angka jujur untuk layar Kirim.
  Future<BigInt> usableOutboundCapacityMsat() async {
    return totalUsableOutboundCapacityMsat(await listChannels());
  }

  /// Kirim pembayaran invoice dan kembalikan ID pembayaran-nya.
  ///
  /// PERHATIAN: kembalian send() hanya berarti perintah kirim
  /// DITERIMA node — pembayaran belum tentu sampai. Hasil akhir
  /// (sukses/gagal) baru diketahui belakangan di catatan pembayaran;
  /// pantau lewat [waitForPaymentOutcome]. Menampilkan "berhasil"
  /// hanya dari send() adalah centang prematur.
  Future<PaymentId> payInvoice(String invoiceStr) async {
    _ensureRunning();
    final payment = await FfiNode.bolt11Payment(ptr: _node!);
    final invoice = Bolt11Invoice(signedRawInvoice: invoiceStr);
    return await payment.send(invoice: invoice);
  }

  /// Bayar offer Bolt12 bernominal TETAP (nominalnya tertulis di
  /// offer) dan kembalikan ID pembayaran-nya.
  ///
  /// PERHATIAN sama seperti [payInvoice]: kembalian hanya berarti
  /// perintah kirim DITERIMA node; hasil akhir dipantau lewat
  /// [waitForPaymentOutcome] — pembayaran offer tercatat di daftar
  /// pembayaran node dengan ID yang sama seperti pembayaran
  /// Bolt11 (jenisnya PaymentKind_Bolt12Offer), jadi penungguan
  /// hasil tidak butuh jalur khusus.
  ///
  /// String offer diparse node dari bentuk teksnya ([Offer.s]);
  /// string yang tidak sah ditolak node di sini. Memakai offer
  /// tanpa nominal pada jalur ini ditolak node (InvalidOffer) —
  /// pemanggil menentukan jalur dari info offer lebih dulu
  /// (lihat parseOfferInfo di utils/bolt12_info.dart).
  Future<PaymentId> payOffer(String offerStr) async {
    _ensureRunning();
    final payment = await FfiNode.bolt12Payment(ptr: _node!);
    return await payment.send(offer: Offer(s: offerStr));
  }

  /// Bayar offer Bolt12 TANPA nominal tetap (variable-amount,
  /// mis. Kode Bayar Statis) dengan nominal pilihan pembayar
  /// sebesar [amountMsat]. Pasangan [payOffer] — keterangan
  /// hasil akhir di sana berlaku sama.
  Future<PaymentId> payOfferUsingAmount(
    String offerStr,
    BigInt amountMsat,
  ) async {
    _ensureRunning();
    final payment = await FfiNode.bolt12Payment(ptr: _node!);
    return await payment.sendUsingAmount(
      offer: Offer(s: offerStr),
      amountMsat: amountMsat,
    );
  }

  /// Tunggu hasil akhir pembayaran [paymentId] dengan memeriksa
  /// catatan pembayaran node berkala.
  ///
  /// Mengembalikan status final (succeeded/failed) begitu terlihat,
  /// atau null bila sampai [timeout] statusnya masih pending —
  /// null BUKAN berarti gagal: pembayaran masih berjalan dan hasil
  /// akhirnya akan muncul di Riwayat. Polling catatan pembayaran
  /// (bukan antrean event) dipilih supaya tidak merebut event yang
  /// dibutuhkan layar Terima.
  Future<PaymentStatus?> waitForPaymentOutcome(
    PaymentId paymentId, {
    Duration timeout = const Duration(seconds: 60),
    Duration interval = const Duration(seconds: 2),
  }) async {
    _ensureRunning();
    final idHex = paymentIdHex(paymentId);
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final payments = await listPayments();
      final status = findPaymentStatus(payments, idHex);
      if (status != null && status != PaymentStatus.pending) return status;
      if (!DateTime.now().add(interval).isBefore(deadline)) return null;
      await Future<void>.delayed(interval);
    }
  }

  Future<BigInt> getLightningBalance() async {
    _ensureRunning();
    // Saldo dihitung per channel pada presisi msat: kapasitas keluar
    // ditambah cadangan hukuman milik sendiri, yang memang bagian
    // dari saldo tetapi tidak bisa dibelanjakan. Total dari
    // listBalances berbasis sat utuh (dibulatkan ke bawah per
    // channel), sehingga sisa sub-sat — mis. 0,5 nusan dari invoice
    // 1,5 — hilang dari kartu saldo bila memakai total itu.
    // Konsekuensi yang disadari: HTLC keluar yang sedang terbang
    // belum terhitung sampai selesai/gagal, jadi angka ini bisa
    // tampil lebih rendah sesaat selama pembayaran berlangsung.
    // Perhatian satuan: unspendablePunishmentReserve dari binding
    // berdenominasi SAT (nusan utuh), sedangkan outboundCapacityMsat
    // berdenominasi msat — cadangan wajib dikonversi ke msat sebelum
    // dijumlahkan. Tanpa konversi, kartu saldo tampil 999 nusan
    // lebih rendah per channel bercadangan 1.000 (terverifikasi dari
    // rekonsiliasi riwayat testnet 2 Nov 2026).
    var total = BigInt.zero;
    for (final channel in await listChannels()) {
      total += countedChannelBalanceMsat(channel);
    }
    return total;
  }

  /// Rincian saldo Lightning per sumber channel: subtotal channel
  /// yang pihak seberangnya node LSP dan subtotal channel langsung
  /// (antar-HP). Jumlah keduanya selalu sama dengan
  /// [getLightningBalance]. Rincian ini penting karena kemampuan
  /// belanja tidak melebur seperti angkanya: saat offline, hanya
  /// porsi channel langsung yang bisa bergerak, jadi kartu saldo
  /// yang hanya menampilkan total gabungan menyesatkan.
  Future<({BigInt lspMsat, BigInt directMsat})>
  getLightningBalanceBreakdown() async {
    _ensureRunning();
    return splitBalanceBySource(await listChannels(), _lspNodeId ?? '');
  }

  /// Ambil seluruh riwayat pembayaran dari node, terbaru di depan.
  ///
  /// Binding tidak menjamin urutan, jadi hasil diurutkan menurun
  /// menurut latestUpdateTimestamp. Semua status ikut terbawa
  /// (termasuk menunggu/gagal) dan semua jenis pembayaran
  /// (Lightning + on-chain) — penyaringan tampilan urusan UI.
  Future<List<PaymentDetails>> listPayments() async {
    _ensureRunning();
    final payments = await _node!.listPayments();
    payments.sort(
      (a, b) => b.latestUpdateTimestamp.compareTo(a.latestUpdateTimestamp),
    );
    return payments;
  }

  /// Ambil satu event node dari antrean (non-blocking).
  ///
  /// Mengembalikan null bila antrean kosong. Dipakai layar Terima
  /// untuk menunggu event pembayaran masuk (Event.paymentReceived).
  ///
  /// Catatan: nextEvent() hanya mengintip (peek) — event yang sama akan
  /// terus dikembalikan sampai ditandai selesai lewat eventHandled().
  /// Karena itu setiap event yang terbaca langsung ditandai selesai di
  /// sini, supaya event berikutnya (mis. PaymentReceived) bisa maju.
  Future<Event?> pollNextEvent() async {
    _ensureRunning();
    final event = await _node!.nextEvent();
    if (event != null) {
      await _node!.eventHandled();
    }
    return event;
  }

  /// Probe murah untuk heartbeat mode offline: true bila host LSP
  /// bisa di-resolve ke alamat IPv4 — persis prasyarat boot normal
  /// yang gagal saat boot offline dipilih. Tidak membuka koneksi
  /// apa pun, hanya resolusi DNS.
  Future<bool> probeLspReachable() async {
    final host = _lspHost;
    if (host == null) return false;
    try {
      final addrs = await InternetAddress.lookup(host);
      return addrs.any((a) => a.type == InternetAddressType.IPv4);
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    if (_running && _node != null) {
      await _node!.stop();
      _running = false;
      _node = null;
    }
  }

  void _ensureRunning() {
    if (!_running || _node == null) {
      throw StateError('Node belum diinisialisasi. Panggil init() dulu.');
    }
  }
}

/// Saldo satu channel yang dihitung ke kartu saldo, dalam msat:
/// kapasitas keluar ditambah cadangan hukuman milik sendiri
/// (unspendablePunishmentReserve, berdenominasi sat, dikonversi ke
/// msat) — tetapi cadangan hanya dihitung sebatas kapasitas keluar
/// channel itu. Cadangan adalah syarat tercetak atas saldo milik
/// sendiri ("kelak wajib menyisakan sekian"), bukan uang yang sedang
/// dipegang: pada channel yang saldonya nol (mis. channel langsung
/// yang seluruhnya didanai pihak seberang) cadangan penuh akan tampil
/// sebagai saldo hantu di kartu penerima. Pada channel bersaldo,
/// cadangan memang bagian dari saldo (kembali saat channel ditutup),
/// jadi rumus lama tidak berubah hasilnya di sana.
BigInt countedChannelBalanceMsat(ChannelDetails channel) {
  final outboundMsat = channel.outboundCapacityMsat;
  var reserveMsat =
      (channel.unspendablePunishmentReserve ?? BigInt.zero) * BigInt.from(1000);
  if (reserveMsat > outboundMsat) reserveMsat = outboundMsat;
  return outboundMsat + reserveMsat;
}

/// Pisahkan total saldo channel menjadi subtotal per sumber:
/// channel yang pihak seberangnya node LSP [lspNodeIdHex] masuk
/// lspMsat, sisanya (channel langsung antar-HP) masuk directMsat.
/// Per channel memakai [countedChannelBalanceMsat], jadi subtotal
/// mewarisi batas cadangan yang sama dan jumlah kedua subtotal
/// selalu sama dengan total kartu saldo.
({BigInt lspMsat, BigInt directMsat}) splitBalanceBySource(
  List<ChannelDetails> channels,
  String lspNodeIdHex,
) {
  final lsp = lspNodeIdHex.toLowerCase();
  var lspMsat = BigInt.zero;
  var directMsat = BigInt.zero;
  for (final channel in channels) {
    final amount = countedChannelBalanceMsat(channel);
    if (channel.counterpartyNodeId.hex.toLowerCase() == lsp) {
      lspMsat += amount;
    } else {
      directMsat += amount;
    }
  }
  return (lspMsat: lspMsat, directMsat: directMsat);
}

/// Bentuk hex ID pembayaran. Pencocokan pembayaran antar-panggilan
/// memakai hex ini, bukan equality objek PaymentId, supaya tidak
/// bergantung pada identitas objek data di binding.
String paymentIdHex(PaymentId id) =>
    id.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Bentuk hex payment hash — kunci tautan catatan pembayaran node
/// ke invoice tersimpan lokal (SavedInvoice.paymentHashHex).
String paymentHashHex(PaymentHash hash) =>
    hash.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Status pembayaran ber-ID [idHex] dalam daftar [payments];
/// null bila catatannya belum muncul.
PaymentStatus? findPaymentStatus(List<PaymentDetails> payments, String idHex) {
  for (final p in payments) {
    if (paymentIdHex(p.id) == idHex) return p.status;
  }
  return null;
}

/// Apakah invoice ber-payment-hash [hashHex] sudah LUNAS
/// menurut catatan pembayaran node: ada pembayaran MASUK berstatus
/// succeeded yang hash-nya sama.
///
/// Catatan node adalah sumber kebenaran yang sama dengan yang
/// dibaca daftar Riwayat, dan simpanan lokal invoice harus tunduk
/// padanya — bukan hanya pada jam kedaluwarsa lokal. Pembayaran
/// bisa tiba saat pengguna berada di layar lain, sehingga
/// penghapusan simpanan oleh pengawas event layar Terima (satu-
/// satunya pemicu penghapusan) tidak sempat berjalan; tanpa
/// rekonsiliasi ini invoice yang sudah lunas dipulihkan lagi
/// sebagai "belum dibayar" dan bertentangan dengan Riwayat.
bool invoiceAlreadyPaid(List<PaymentDetails> payments, String hashHex) {
  for (final p in payments) {
    if (p.direction != PaymentDirection.inbound) continue;
    if (p.status != PaymentStatus.succeeded) continue;
    final kind = p.kind;
    final String kindHashHex;
    if (kind is PaymentKind_Bolt11) {
      kindHashHex = paymentHashHex(kind.hash);
    } else if (kind is PaymentKind_Bolt11Jit) {
      kindHashHex = paymentHashHex(kind.hash);
    } else {
      continue;
    }
    if (kindHashHex == hashHex) return true;
  }
  return false;
}

/// Jalur pembuatan invoice untuk layar Terima.
enum ReceiveInvoiceRoute {
  /// Invoice Bolt11 biasa lewat channel yang sudah ada.
  regular,

  /// Invoice JIT: pembayaran yang datang sekaligus melahirkan
  /// channel baru.
  jit,
}

/// Total kapasitas terima (msat) dari channel yang usable.
///
/// Channel yang belum usable (belum channel-ready atau peer sedang
/// tidak tersambung) tidak dihitung: pembayaran tidak bisa
/// mendarat lewat channel seperti itu.
BigInt totalUsableInboundCapacityMsat(List<ChannelDetails> channels) {
  var total = BigInt.zero;
  for (final c in channels) {
    if (c.isUsable) total += c.inboundCapacityMsat;
  }
  return total;
}

/// Total kapasitas kirim (msat) dari channel yang usable.
///
/// Pasangan [totalUsableInboundCapacityMsat] untuk arah keluar.
/// Kapasitas keluar dari node SUDAH mengeluarkan cadangan pengaman
/// channel dan pembayaran yang sedang berjalan, jadi jumlah inilah
/// batas kirim yang sesungguhnya — bukan saldo penuh.
BigInt totalUsableOutboundCapacityMsat(List<ChannelDetails> channels) {
  var total = BigInt.zero;
  for (final c in channels) {
    if (c.isUsable) total += c.outboundCapacityMsat;
  }
  return total;
}

/// Hasil pemeriksaan pra-bayar layar Kirim.
enum SendCheck {
  /// Nominal bisa dicoba dibayar — keputusan akhir tetap di node.
  ok,

  /// Nominal melewati saldo: memang tidak cukup, titik.
  insufficientBalance,

  /// Saldo terlihat cukup tetapi nominal melewati kapasitas kirim:
  /// selisihnya tertahan sebagai cadangan pengaman channel.
  reserveHeld,
}

/// Periksa nominal invoice terhadap saldo & kapasitas kirim
/// SEBELUM pembayaran dicoba (keputusan NUX 31 Okt 2026).
///
/// Latarnya temuan RouteNotFound 31 Okt: dompet bersaldo 995 nusan
/// gagal mengirim 500 berulang kali dan aplikasi hanya berkata
/// "gagal" sesudah mencoba — padahal batas kirimnya memang 0,
/// karena dari saldo selalu disisakan cadangan pengaman channel
/// (di jaringan ini 1.000 nusan untuk channel 25.000). Layar harus
/// berkata benar sebelum kejadian: nominal di atas saldo =
/// [SendCheck.insufficientBalance]; nominal yang muat di saldo
/// tetapi tidak di kapasitas kirim = [SendCheck.reserveHeld],
/// dengan penjelasan bahwa cadangannya bukan potongan.
///
/// Tanpa channel usable, kapasitas kirim tidak bisa dinilai
/// (penyebabnya bisa koneksi, bukan cadangan) → pemeriksaan
/// cadangan dilewati dan node yang memutuskan seperti sebelumnya.
SendCheck evaluateSend({
  required BigInt amountMsat,
  required BigInt balanceMsat,
  required BigInt usableOutboundMsat,
  required bool hasUsableChannel,
}) {
  if (amountMsat > balanceMsat) return SendCheck.insufficientBalance;
  if (hasUsableChannel && amountMsat > usableOutboundMsat) {
    return SendCheck.reserveHeld;
  }
  return SendCheck.ok;
}

/// Pilih jalur pembuatan invoice Terima ("Jalur 1", keputusan NUX
/// 30 Okt 2026): nominal konkret yang muat dalam kapasitas terima
/// channel yang sudah ada memakai invoice biasa — dompet yang
/// jalurnya sudah jadi bisa menerima berapa pun, termasuk di bawah
/// minimum kelahiran JIT (1.000 nusan). Invoice JIT hanya bila
/// kapasitas tidak cukup (jalur memang harus lahir) atau nominal
/// tidak ditentukan (amountless mempertahankan perilaku lama).
ReceiveInvoiceRoute chooseReceiveInvoiceRoute({
  required BigInt? amountMsat,
  required BigInt usableInboundCapacityMsat,
}) {
  if (amountMsat == null) return ReceiveInvoiceRoute.jit;
  return usableInboundCapacityMsat >= amountMsat
      ? ReceiveInvoiceRoute.regular
      : ReceiveInvoiceRoute.jit;
}
