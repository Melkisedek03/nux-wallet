import 'dart:io';

import 'package:bip39/bip39.dart' as bip39;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'config.dart';
import 'locale_controller.dart';
import 'l10n/app_localizations.dart';
import 'theme.dart';
import 'screens/backup_screen.dart';
import 'screens/receive_screen.dart';
import 'screens/restore_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/send_screen.dart';
import 'screens/offline_spike_screen.dart';
import 'screens/printer_settings_screen.dart';
import 'screens/store_mode_screen.dart';
import 'screens/transaction_detail_screen.dart';
import 'services/lsp_profile.dart';
import 'services/payment_notes.dart';
import 'services/saved_invoices.dart';
import 'services/lsp_service.dart';
import 'services/offline_bridge.dart';
import 'services/csv_export.dart';
import 'services/history_filter.dart';
import 'services/update_service.dart';
import 'unit_controller.dart';
import 'utils/community_links.dart';
import 'utils/format.dart';
import 'utils/coin_alert.dart';
import 'utils/update_dialog.dart';
import 'widgets/lightning_status_pill.dart';
import 'widgets/transaction_row.dart';
import 'utils/friendly_error.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Muat pilihan tema tersimpan (default gelap) sebelum aplikasi jalan.
  await ThemeController.load();
  // Muat pilihan bahasa tersimpan (default Indonesia) sebelum jalan.
  await LocaleController.load();
  // Muat satuan tampilan jumlah tersimpan (default nusan).
  await UnitController.load();
  // Layar tetap menyala selama aplikasi hidup (permintaan NUX):
  // dompet harus siap menerima pembayaran, layar tidak boleh
  // mati sendiri. Diaktifkan lagi setiap aplikasi kembali ke depan.
  WakelockPlus.enable().catchError((_) {});
  runApp(const NuxWalletApp());
}

// Global LspService instance (untuk MVP; pakai DI yang proper di produksi)
final lspService = LspService();

/// Jembatan offline milik aplikasi (tahap produksi A): hidupnya
/// tidak lagi mengikuti layar uji — berpindah layar tidak
/// memutuskannya, dan niat sesinya tersimpan untuk dilanjutkan
/// setelah aplikasi dimulai ulang. Hanya tombol akhiri sesi
/// eksplisit yang menghentikannya.
final offlineBridge = OfflineBridgeService();

class NuxWalletApp extends StatelessWidget {
  const NuxWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [ThemeController.mode, LocaleController.locale, UnitController.unit]),
      builder: (context, _) {
        return MaterialApp(
          title: 'NUX Wallet',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeController.mode.value,
          locale: LocaleController.locale.value,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: LocaleController.supported,
          home: const HomeScreen(),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  int _tabIndex = 0;
  bool _booting = true;
  String? _bootError;

  /// Kata frasa backup dompet ini (null bila dompet lama tanpa frasa).
  List<String>? _mnemonicWords;

  /// True bila dompet diwarisi dari versi sebelum fitur frasa backup:
  /// seed-nya ada tapi tidak ada frasa yang bisa ditampilkan ke user.
  bool _legacyWallet = false;

  /// True bila dompet BARU saja dibuat pada boot ini — frasanya wajib
  /// ditampilkan sekali lewat layar Backup sebelum user memakai dompet.
  bool _isNewWallet = false;

  /// Berkas & direktori dompet (diisi _boot; dipakai aksi reset dompet).
  File? _seedFile;
  File? _mnemonicFile;
  Directory? _storageDir;

  /// Sapaan mengikuti jam lokal HP user.
  String get _greeting {
    final h = DateTime.now().hour;
    if (h >= 4 && h < 11) return context.l10n.greetingMorning;
    if (h >= 11 && h < 15) return context.l10n.greetingAfternoon;
    if (h >= 15 && h < 18) return context.l10n.greetingEvening;
    return context.l10n.greetingNight;
  }

  /// Saldo Lightning terakhir dari node (msat); null = belum terbaca.
  BigInt? _balanceMsat;

  /// Rincian saldo per sumber (LSP vs channel langsung); null =
  /// belum terbaca. Ditampilkan di kartu hanya bila porsi channel
  /// langsung tidak nol — satu-satunya keadaan yang membuat total
  /// gabungan bisa salah dibaca sebagai kemampuan belanja offline.
  ({BigInt lspMsat, BigInt directMsat})? _balanceBreakdown;

  /// Riwayat pembayaran terakhir dari node (terbaru di depan).
  List<PaymentDetails> _payments = const [];

  /// Catatan pembayaran lokal (hash hex → catatan), dimuat
  /// bersama riwayat. Catatan pembayaran node tidak membawa
  /// deskripsi invoice, jadi judul catatan di daftar Aktivitas/
  /// Riwayat dibaca dari peta ini (lihat PaymentNoteStore).
  Map<String, String> _paymentNotes = const {};

  /// Deteksi koin masuk: true setelah muat riwayat pertama selesai —
  /// riwayat lama tidak memicu bunyi/getar, hanya kedatangan baru.
  bool _paymentsPrimed = false;

  /// Kunci pembayaran masuk yang sudah pernah terlihat BERHASIL.
  /// Deteksi membandingkan himpunan ini, bukan kehadiran pembayaran
  /// di daftar: invoice yang dibuat lalu ditunggu tampil di daftar
  /// sebagai pending lebih dulu dengan kunci yang sama, sehingga
  /// deteksi berbasis "kunci belum pernah terlihat" buta terhadap
  /// perubahan status pending → berhasil — persis alur terima yang
  /// paling umum. Yang dirayakan adalah TRANSISInya.
  final Set<String> _receivedAlertKeys = {};

  /// Penyegar berkala dashboard selama aplikasi terbuka.
  Timer? _pollTimer;

  /// Heartbeat deteksi internet selama sesi boot offline.
  Timer? _offlineWatchTimer;

  /// Jumlah probe heartbeat sukses berurutan — restart node ke mode
  /// normal baru dilakukan setelah dua sukses berurutan supaya
  /// jaringan yang naik-turun tidak mengocok node.
  int _probeSuccessStreak = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _offlineWatchTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Pastikan wakelock aktif lagi — beberapa perangkat melepasnya
      // saat aplikasi sempat ke latar.
      WakelockPlus.enable().catchError((_) {});
      if (!_booting && _bootError == null) {
        _refreshDashboard();
      }
    }
  }

  /// Baca ulang saldo Lightning dari node dan tampilkan di dashboard.
  /// Kegagalan baca (mis. node belum sinkron) tidak mengosongkan nilai
  /// terakhir yang berhasil dibaca.
  Future<void> _refreshBalance() async {
    if (!lspService.isRunning) return;
    try {
      // Satu bacaan untuk total + rincian: total adalah jumlah kedua
      // subtotal rincian, jadi angka kartu dan rinciannya tidak bisa
      // berbeda bacaan.
      final breakdown = await lspService.getLightningBalanceBreakdown();
      if (mounted) {
        setState(() {
          _balanceMsat = breakdown.lspMsat + breakdown.directMsat;
          _balanceBreakdown = breakdown;
        });
      }
    } catch (_) {
      // Abaikan — saldo lama tetap ditampilkan.
    }
  }

  /// Baca ulang riwayat pembayaran dari node untuk daftar Aktivitas
  /// dashboard dan tab Riwayat. Pola sama seperti saldo: kegagalan
  /// baca mempertahankan daftar terakhir yang berhasil dibaca.
  String _paymentKey(PaymentDetails p) =>
      p.id.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Future<void> _refreshPayments() async {
    if (!lspService.isRunning) return;
    try {
      final payments = await lspService.listPayments();
      // Deteksi koin masuk: pembayaran inbound yang BARU berstatus
      // berhasil → bunyi cling + getar. "Baru" diukur terhadap
      // himpunan kunci yang sudah pernah terlihat berhasil, supaya
      // perubahan status pending → berhasil ikut tertangkap (lihat
      // _receivedAlertKeys). Muat pertama (riwayat lama) TIDAK
      // memicu — himpunannya hanya diisi sebagai garis dasar.
      final succeededIn = payments
          .where((p) =>
              p.direction == PaymentDirection.inbound &&
              p.status == PaymentStatus.succeeded)
          .map(_paymentKey)
          .toSet();
      if (_paymentsPrimed &&
          succeededIn.difference(_receivedAlertKeys).isNotEmpty) {
        CoinAlert.play();
      }
      _receivedAlertKeys.addAll(succeededIn);
      _paymentsPrimed = true;
      final notes = await PaymentNoteStore().loadAll();
      if (mounted) {
        setState(() {
          _payments = payments;
          _paymentNotes = notes;
        });
      }
    } catch (_) {
      // Abaikan — daftar lama tetap ditampilkan.
    }
  }

  /// Daftar pembayaran untuk DITAMPILKAN di Aktivitas/Riwayat:
  /// pembayaran MASUK yang masih pending (invoice belum dibayar)
  /// disaring keluar — belum ada uang yang bergerak, jadi belum
  /// pantas tampil sebagai baris "Diterima" (keputusan NUX
  /// 30 Okt 2026: layar tidak boleh menimbulkan kesan ada uang
  /// yang menggantung). Invoice-invoice itu tempatnya di layar
  /// Terima sebagai invoice tersimpan. Catatan node (_payments)
  /// sendiri TIDAK diubah: deteksi koin masuk dan logika lain
  /// tetap membaca daftar utuh dari node.
  List<PaymentDetails> get _displayPayments => _payments
      .where((p) => !(p.direction == PaymentDirection.inbound &&
          p.status == PaymentStatus.pending))
      .toList();

  /// Pilihan filter tanggal tab Riwayat (bawaan: seminggu terakhir).
  HistoryRangePreset _historyPreset = HistoryRangePreset.last7Days;

  /// Rentang tanggal pilihan sendiri; hanya berlaku saat
  /// [_historyPreset] bernilai custom.
  DateTimeRange? _historyCustomRange;

  /// Daftar untuk tab Riwayat dan ekspor CSV: [_displayPayments]
  /// yang sudah disaring filter tanggal aktif — ekspor mengikuti
  /// persis yang tampil (keputusan NUX 2 Nov 2026). Beranda TIDAK
  /// memakai daftar ini; aktivitas terbaru di Beranda tetap dari
  /// [_displayPayments] utuh.
  List<PaymentDetails> get _historyPayments {
    final range = historyRangeForPreset(
      _historyPreset,
      now: DateTime.now(),
      customStart: _historyCustomRange?.start,
      customEnd: _historyCustomRange?.end,
    );
    return filterPaymentsByRange(_displayPayments, range);
  }

  /// Label rentang aktif, tampil sebagai subjudul tab Riwayat.
  String get _historyRangeLabel {
    switch (_historyPreset) {
      case HistoryRangePreset.last7Days:
        return context.l10n.historyLast7Days;
      case HistoryRangePreset.last30Days:
        return context.l10n.historyLast30Days;
      case HistoryRangePreset.custom:
        final r = _historyCustomRange;
        if (r == null) return context.l10n.historyCustomRange;
        return '${_shortDate(r.start)} – ${_shortDate(r.end)}';
    }
  }

  /// Tanggal singkat "2 Nov 2026", pola yang sama seperti waktu
  /// lengkap di layar detail transaksi.
  String _shortDate(DateTime d) {
    final en = context.l10n.localeName.startsWith('en');
    const monthsId = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    const monthsEn = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final months = en ? monthsEn : monthsId;
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// Lembar pilihan filter tanggal tab Riwayat. Pilihan "Periode
  /// tanggal" lanjut ke pemilih rentang tanggal sistem; membatalkan
  /// pemilih tidak mengubah filter yang sedang aktif.
  Future<void> _showHistoryFilter() async {
    final l10n = context.l10n;
    final picked = await showModalBottomSheet<HistoryRangePreset>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.historyLast7Days),
              trailing: _historyPreset == HistoryRangePreset.last7Days
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(
                  sheetContext, HistoryRangePreset.last7Days),
            ),
            ListTile(
              title: Text(l10n.historyLast30Days),
              trailing: _historyPreset == HistoryRangePreset.last30Days
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(
                  sheetContext, HistoryRangePreset.last30Days),
            ),
            ListTile(
              title: Text(l10n.historyCustomRange),
              trailing: _historyPreset == HistoryRangePreset.custom
                  ? const Icon(Icons.check)
                  : null,
              onTap: () =>
                  Navigator.pop(sheetContext, HistoryRangePreset.custom),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == HistoryRangePreset.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2025),
        lastDate: now,
        initialDateRange: _historyCustomRange ??
            DateTimeRange(
                start: now.subtract(const Duration(days: 7)), end: now),
      );
      if (range == null || !mounted) return;
      setState(() {
        _historyPreset = HistoryRangePreset.custom;
        _historyCustomRange = range;
      });
    } else {
      setState(() => _historyPreset = picked);
    }
  }

  /// Segarkan saldo + riwayat sekaligus. Dipakai di titik-titik
  /// refresh yang sebelumnya hanya menyegarkan saldo.
  Future<void> _refreshDashboard() async {
    await _refreshBalance();
    await _refreshPayments();
  }

  /// Inisialisasi node LDK + LSPS2 saat aplikasi dibuka.
  ///
  /// Dompet baru lahir dari frasa BIP39 12 kata: seed node (64 byte)
  /// diturunkan dari frasa itu (mnemonicToSeed), lalu frasa + seed
  /// disimpan di app support dir dan frasa ditampilkan sekali ke user.
  /// Dompet lama (seed ada, frasa tidak ada) ditandai legacy.
  /// CATATAN MVP: berkas disimpan sebagai file biasa. Untuk produksi,
  /// pindah ke flutter_secure_storage (Keychain/Keystore).
  Future<void> _boot({bool offlineMode = false}) async {
    try {
      // Profil LSP aktif: pilihan user yang tersimpan bila sah dan
      // jaringannya cocok, selain itu profil bawaan dari AppConfig.
      // Tanpa pilihan tersimpan, perilaku boot PERSIS seperti
      // sebelumnya — persiapan ini belum mengubah endpoint apa pun.
      final lspProfile = await LspProfileStore.load();
      if (!lspProfile.isConfigured) {
        throw StateError(
            context.l10n.lspNodeIdMissing);
      }
      final dir = await getApplicationSupportDirectory();
      // Seed & storage dipisah per network: build mainnet memakai nama
      // berakhiran _mainnet supaya tidak mewarisi seed/storage testnet
      // (APK mainnet menimpa paket yang sama). Nama testnet dibiarkan
      // persis seperti sebelumnya — wallet testnet yang ada tidak berubah.
      final seedName =
          AppConfig.isTestnet ? 'lsp_seed.bin' : 'lsp_seed_mainnet.bin';
      final storageName =
          AppConfig.isTestnet ? 'lsp_storage' : 'lsp_storage_mainnet';
      final mnemonicName = AppConfig.isTestnet
          ? 'wallet_mnemonic.txt'
          : 'wallet_mnemonic_mainnet.txt';
      final seedFile = File('${dir.path}/$seedName');
      final mnemonicFile = File('${dir.path}/$mnemonicName');
      _seedFile = seedFile;
      _mnemonicFile = mnemonicFile;
      List<int>? seedBytes;
      if (await seedFile.exists()) {
        final existing = await seedFile.readAsBytes();
        if (existing.length == 64) {
          seedBytes = existing;
        } else if (existing.length != 32) {
          throw StateError(context.l10n.seedCorrupt(
              existing.length, seedFile.path));
        }
        // Panjang 32 = berkas dari versi awal yang keliru (builder
        // mensyaratkan 64 byte dan selalu menolak 32, jadi node tidak
        // pernah terbangun dengannya) — belum ada wallet/dana di
        // bawah seed itu, aman dibuat ulang di bawah ini.
      }
      if (seedBytes != null) {
        // Dompet yang sudah ada: frasa hanya tersedia bila berkas
        // frasanya ikut ada (dompet dibuat oleh versi frasa BIP39).
        // Dompet dari versi sebelumnya tidak punya frasa — tandai
        // legacy supaya user ditawari membuat dompet baru berfrasa.
        if (await mnemonicFile.exists()) {
          final words = (await mnemonicFile.readAsString())
              .trim()
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .toList();
          if (words.length >= 12 &&
              bip39.validateMnemonic(words.join(' '))) {
            _mnemonicWords = words;
          } else {
            _legacyWallet = true;
          }
        } else {
          _legacyWallet = true;
        }
      }
      if (seedBytes == null) {
        // Dompet BARU: lahir dari frasa BIP39 12 kata. Seed node =
        // mnemonicToSeed (PBKDF2-HMAC-SHA512, 64 byte) — persis format
        // yang diminta builder LDK. Frasa disimpan terpisah supaya bisa
        // ditampilkan lagi dari tab Profil; seed tetap disimpan sebagai
        // berkas 64 byte seperti sebelumnya supaya identitas node
        // stabil antar-update aplikasi.
        final mnemonic = bip39.generateMnemonic();
        seedBytes = bip39.mnemonicToSeed(mnemonic);
        await seedFile.writeAsBytes(seedBytes, flush: true);
        await mnemonicFile.writeAsString(mnemonic, flush: true);
        _mnemonicWords = mnemonic.split(' ');
        _legacyWallet = false;
        _isNewWallet = true;
      }
      final storageDir = Directory('${dir.path}/$storageName');
      _storageDir = storageDir;
      if (!await storageDir.exists()) {
        await storageDir.create(recursive: true);
      }
      await lspService.init(
        seedBytes: seedBytes,
        storagePath: storageDir.path,
        lspAddress: lspProfile.lspAddress,
        lspNodeId: lspProfile.lspNodeId,
        lspToken: lspProfile.lspToken,
        electrumUrl: lspProfile.electrumUrl,
        isTestnet: lspProfile.isTestnet,
        offlineMode: offlineMode,
      );
      await _refreshDashboard();
      if (mounted) setState(() => _booting = false);
      _aturHeartbeatOffline(offlineMode);
      // Jembatan offline: pasang penyambung peer tamu (hanya
      // pemilik LspService yang bisa menyambungkan node) lalu
      // lanjutkan niat sesi tersimpan bila ada. Upaya terbaik —
      // kegagalan di sini tidak menggagalkan boot dompet.
      offlineBridge.peerConnector = (nodeIdHex) => lspService.connectToPeer(
            nodeIdHex,
            '127.0.0.1',
            OfflineBridgeService.guestBridgePort,
          );
      offlineBridge.restoreSession().catchError((_) => false);
      // Segarkan berkala selama aplikasi terbuka: saldo + riwayat
      // selalu mutakhir, dan koin masuk terdeteksi untuk peringatan
      // bunyi + getar (lihat _refreshPayments).
      _pollTimer ??= Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refreshDashboard(),
      );
      // Cek pembaruan OTA diam-diam sekali per sesi (gaya
      // nusan-catcher): hanya bertindak bila ada versi baru.
      // Dompet baru dilewati — layar frasa backup didahulukan;
      // pemeriksaan berjalan pada buka berikutnya.
      if (!_isNewWallet) _cekUpdateOtomatis();
      if (_isNewWallet && mounted) {
        _isNewWallet = false;
        // Dompet baru: tampilkan frasa backup sekali sebelum user
        // memakai dompet — frasa ini satu-satunya cadangan dananya.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _mnemonicWords == null) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BackupScreen(mnemonic: _mnemonicWords!),
            ),
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _booting = false;
          _bootError =
              friendlyError(e,
                  fallback: context.l10n.bootGenericError,
                  l10n: context.l10n);
        });
      }
    }
  }

  /// Kelola heartbeat deteksi internet setelah boot berhasil.
  ///
  /// Hanya aktif selama sesi boot offline. Setiap 20 detik host LSP
  /// di-probe lewat resolusi DNS; dua sukses berurutan berarti
  /// internet kemungkinan sudah kembali, jadi node di-restart DI
  /// DALAM aplikasi ke mode normal (LSPS2 aktif lagi) — user tidak
  /// perlu menutup-buka aplikasi. Boot normal mematikan heartbeat.
  void _aturHeartbeatOffline(bool offlineMode) {
    _offlineWatchTimer?.cancel();
    _offlineWatchTimer = null;
    _probeSuccessStreak = 0;
    if (!offlineMode) return;
    _offlineWatchTimer =
        Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!mounted || _booting) return;
      final reachable = await lspService.probeLspReachable();
      if (!mounted) return;
      if (!reachable) {
        _probeSuccessStreak = 0;
        return;
      }
      _probeSuccessStreak++;
      if (_probeSuccessStreak < 2) return;
      _offlineWatchTimer?.cancel();
      _offlineWatchTimer = null;
      if (mounted) setState(() => _booting = true);
      await lspService.stop();
      await _boot();
    });
  }

  /// Bagikan berkas log node jaringan aktif (ldk_node.log) lewat share
  /// sheet sistem — pola Phoenix: user sendiri yang memicu dari tab
  /// Profil, aplikasi hanya MEMBACA berkas yang sudah ada. Jalur
  /// diresolusi PERSIS seperti _boot: app support dir + nama storage
  /// per network. Yang dibagikan adalah SALINAN di cache bernama
  /// elnux-log-<network>-<tanggal>.log — berkas asli tidak diubah,
  /// dipindah, atau ditambah data apa pun. Log belum ada/kosong →
  /// pesan ringkas; kegagalan lain → pesan ramah tanpa detail teknis.
  /// Penanda cek pembaruan otomatis sesi ini sudah berjalan —
  /// boot ulang di sesi yang sama (reset/restore dompet) tidak
  /// mengulang dialog pembaruan.
  bool _updateCheckRan = false;

  /// Cek pembaruan otomatis diam-diam (gaya nusan-catcher):
  /// dialog hanya muncul bila benar-benar ada versi baru; hasil
  /// lain — sudah terbaru, gagal, kanal nonaktif — senyap.
  Future<void> _cekUpdateOtomatis() async {
    if (_updateCheckRan) return;
    _updateCheckRan = true;
    final hasil = await UpdateService.cek();
    if (!mounted) return;
    if (hasil.status == UpdateCheckStatus.updateAvailable &&
        hasil.info != null) {
      await showUpdateDialog(context, hasil.info!);
    }
  }

  /// Cek pembaruan manual dari tab Profil: selalu beri umpan
  /// balik — dialog bila ada versi baru, snackbar untuk hasil
  /// lainnya.
  Future<void> _cekUpdateManual() async {
    final hasil = await UpdateService.cek();
    if (!mounted) return;
    switch (hasil.status) {
      case UpdateCheckStatus.updateAvailable:
        if (hasil.info != null) {
          await showUpdateDialog(context, hasil.info!);
        }
      case UpdateCheckStatus.upToDate:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.updateUpToDate)),
        );
      case UpdateCheckStatus.failed:
      case UpdateCheckStatus.disabled:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.updateCheckFailed)),
        );
    }
  }

  Future<void> _shareNodeLog() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final storageName =
          AppConfig.isTestnet ? 'lsp_storage' : 'lsp_storage_mainnet';
      final logFile = File('${dir.path}/$storageName/ldk_node.log');
      if (!await logFile.exists() || await logFile.length() == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.shareLogUnavailable)),
          );
        }
        return;
      }
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp = '${now.year}${two(now.month)}${two(now.day)}'
          '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
      final network = AppConfig.isTestnet ? 'testnet' : 'mainnet';
      final cacheDir = await getTemporaryDirectory();
      final copyFile = File('${cacheDir.path}/elnux-log-$network-$stamp.log');
      await logFile.copy(copyFile.path);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(copyFile.path)]),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e,
                fallback: context.l10n.shareLogFailed, l10n: context.l10n)),
          ),
        );
      }
    }
  }

  /// Ekspor riwayat yang sedang tampil di tab Riwayat sebagai
  /// berkas CSV lalu tawarkan lembar bagikan sistem — pola yang
  /// sama seperti Bagikan Log. Yang diekspor persis daftar
  /// tampilannya (_historyPayments, yaitu _displayPayments yang
  /// sudah disaring filter tanggal aktif), jadi invoice masuk
  /// yang belum dibayar dan transaksi di luar periode tidak ikut,
  /// sama seperti di layar.
  Future<void> _exportHistoryCsv() async {
    try {
      final csv = buildTransactionsCsv(_historyPayments);
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp = '${now.year}${two(now.month)}${two(now.day)}'
          '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
      final network = AppConfig.isTestnet ? 'testnet' : 'mainnet';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/elnux-history-$network-$stamp.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)]),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e,
                fallback: context.l10n.historyExportFailed,
                l10n: context.l10n)),
          ),
        );
      }
    }
  }

  /// Hapus dompet lama tanpa frasa dan buat dompet baru berfrasa.
  /// Hanya ditawarkan untuk dompet legacy; pemanggil (tab Profil)
  /// sudah memastikan user paham dompet lama harus KOSONG — dana di
  /// dompet lama hilang permanen begitu berkasnya dihapus.
  Future<void> _resetWalletWithPhrase() async {
    try {
      await lspService.stop();
    } catch (_) {
      // Node mungkin belum sempat start penuh — abaikan.
    }
    if (_seedFile != null && await _seedFile!.exists()) {
      await _seedFile!.delete();
    }
    if (_mnemonicFile != null && await _mnemonicFile!.exists()) {
      await _mnemonicFile!.delete();
    }
    if (_storageDir != null && await _storageDir!.exists()) {
      await _storageDir!.delete(recursive: true);
    }
    if (!mounted) return;
    setState(() {
      _mnemonicWords = null;
      _legacyWallet = false;
      _balanceMsat = null;
      _balanceBreakdown = null;
      _payments = const [];
      _tabIndex = 0;
      _booting = true;
      _bootError = null;
    });
    await _boot();
  }

  /// Pulihkan dompet dari frasa BIP39 yang sudah divalidasi layar
  /// Restore (jumlah kata + checksum). Pola sama dengan
  /// _resetWalletWithPhrase: hentikan node, hapus berkas dompet aktif
  /// (seed + frasa + storage channel), tulis seed turunan frasa
  /// (mnemonicToSeed, sama seperti _boot) + frasanya, lalu boot ulang.
  /// _boot berikutnya membaca seed + frasa yang valid → dompet hasil
  /// restore, bukan legacy, tanpa popup frasa paksa.
  /// PERINGATAN: data dompet aktif hilang permanen; layar Restore sudah
  /// meminta konfirmasi eksplisit. Frasa hanya memulihkan seed dompet —
  /// status channel Lightning (di storage yang dihapus) TIDAK ikut
  /// pulih, jadi restore hanya aman untuk dompet yang channelnya sudah
  /// kosong/tertutup, atau yang frasanya memang cadangan satu-satunya.
  Future<void> _restoreWalletWithPhrase(String mnemonic) async {
    if (!bip39.validateMnemonic(mnemonic)) {
      throw StateError(context.l10n.restoreInvalidWords);
    }
    if (_seedFile == null || _mnemonicFile == null || _storageDir == null) {
      throw StateError(context.l10n.restoreFailed);
    }
    try {
      await lspService.stop();
    } catch (_) {
      // Node mungkin belum sempat start penuh — abaikan.
    }
    final seedBytes = bip39.mnemonicToSeed(mnemonic);
    await _seedFile!.writeAsBytes(seedBytes, flush: true);
    await _mnemonicFile!.writeAsString(mnemonic, flush: true);
    if (await _storageDir!.exists()) {
      await _storageDir!.delete(recursive: true);
    }
    if (!mounted) return;
    setState(() {
      _mnemonicWords = null;
      _legacyWallet = false;
      _balanceMsat = null;
      _balanceBreakdown = null;
      _payments = const [];
      // Primer ulang: riwayat dompet hasil restore tidak boleh memicu
      // bunyi koin masuk saat muat pertama.
      _paymentsPrimed = false;
      _receivedAlertKeys.clear();
      _tabIndex = 0;
      _booting = true;
      _bootError = null;
    });
    await _boot();
  }

  /// Dialog konfirmasi keluar aplikasi, desain selaras tema:
  /// permukaan mengikuti tema, sudut membulat, aksen emerald.
  Future<void> _confirmExit() async {
    final keluar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: ctx.palette.border),
        ),
        title: Text(context.l10n.exitTitle,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: Text(
          context.l10n.exitBody,
          style: TextStyle(
              fontSize: 13.5, color: ctx.palette.secondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel,
                style: TextStyle(color: ctx.palette.secondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(context.l10n.exitConfirm),
          ),
        ],
      ),
    );
    if (keluar == true) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Cegat tombol kembali di layar utama: minta konfirmasi dulu
    // sebelum aplikasi benar-benar keluar.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_booting) {
      // Layar awal bergaya splash: logo + partikel + tagline,
      // tampil selama node LDK + LSPS2 diinisialisasi.
      return const SplashScreen();
    }
    if (_bootError != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('⚠️',
                    style: TextStyle(fontSize: 40),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(context.l10n.bootFailedTitle,
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(_bootError!,
                    style: TextStyle(
                        fontSize: 13, color: context.palette.secondary),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _booting = true;
                      _bootError = null;
                    });
                    _boot();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(context.l10n.bootFailedRetry),
                ),
                // Kondisi ekstrem tanpa internet (spike offline,
                // testnet saja): boot ulang dalam mode offline — node
                // berjalan tanpa LSP/LSPS2 supaya peering lokal dan
                // pembayaran lewat channel yang sudah ada tetap bisa.
                if (AppConfig.isTestnet) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _booting = true;
                        _bootError = null;
                      });
                      _boot(offlineMode: true);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF10B981),
                      side: const BorderSide(color: Color(0xFF10B981)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(context.l10n.bootOfflineButton),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: [
            SingleChildScrollView(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_greeting,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: context.palette.secondary)),
                            const SizedBox(width: 7),
                            // Duplikat ikon live dari kartu saldo
                            // (permintaan NUX) — hijau emerald agar
                            // lebih terlihat di header.
                            PulseDot(
                              active: lspService.isRunning,
                              color: const Color(0xFF34D399),
                              size: 9,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text('Nusanian \u2726',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3)),
                      ],
                    ),
                    Row(
                      children: [
                        // Toggle tema Gelap/Terang — pilihan tersimpan
                        // dan berlaku di semua layar.
                        IconButton(
                          onPressed: ThemeController.toggle,
                          tooltip: context.l10n.changeThemeTooltip,
                          icon: Icon(
                            Theme.of(context).brightness == Brightness.dark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                            color: context.palette.muted,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: context.palette.card,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side:
                                BorderSide(color: context.palette.border),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Lencana ikon aplikasi — ketuk untuk ke tab Profil.
                        GestureDetector(
                          onTap: () => setState(() => _tabIndex = 3),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: context.palette.border),
                            ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset('assets/app_icon.png',
                              fit: BoxFit.cover),
                        ),
                      ),
                    ),
                      ],
                    ),
                  ],
                ),
              ),
              // Balance hero card
              Container(
                margin: const EdgeInsets.all(18),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669), Color(0xFF065F46)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.totalBalance,
                        style: TextStyle(fontSize: 13, color: Colors.white70)),
                    const SizedBox(height: 6),
                    // FittedBox scaleDown: saldo besar (banyak digit)
                    // menyusut mengikuti lebar kartu, tidak meluap
                    // di layar sempit — pola aman yang sama seperti
                    // pil status di bawah.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                              _balanceMsat == null
                                  ? '\u2014'
                                  : context.formatWalletAmountNumber(
                                      _balanceMsat!),
                              style: const TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1,
                                  color: Colors.white)),
                          const SizedBox(width: 6),
                          Text(context.displayUnit.label,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70)),
                        ],
                      ),
                    ),
                    Text(
                        AppConfig.isTestnet
                            ? context.l10n.networkTestnet
                            : context.l10n.networkMainnet,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.white70)),
                    // Rincian per sumber, hanya bila ada channel
                    // langsung bersaldo: total gabungan saja bisa
                    // salah dibaca sebagai yang bisa dibelanjakan
                    // saat offline, padahal yang bergerak offline
                    // hanya porsi channel langsung.
                    if (_balanceBreakdown != null &&
                        _balanceBreakdown!.directMsat > BigInt.zero) ...[
                      const SizedBox(height: 4),
                      Text(
                          '${context.l10n.balanceViaLsp} ${context.formatWalletAmountNumber(_balanceBreakdown!.lspMsat)} • ${context.l10n.balanceDirectChannel} ${context.formatWalletAmountNumber(_balanceBreakdown!.directMsat)} ${context.displayUnit.label}',
                          style: const TextStyle(
                              fontSize: 12.5, color: Colors.white70)),
                    ],
                    const SizedBox(height: 14),
                    // Pil status: widget khusus yang isinya
                    // menyusut mengikuti lebar kartu (lihat
                    // LightningStatusPill) — teks status tidak
                    // bisa mendorong bingkai di ukuran layar atau
                    // skala font berapa pun.
                    LightningStatusPill(
                      active: lspService.isRunning,
                      label: lspService.isRunning
                          ? context.l10n.lightningActive
                          : context.l10n.lightningConnecting,
                    ),
                  ],
                ),
              ),
              // Peringatan dompet lama tanpa frasa backup
              if (_legacyWallet)
                GestureDetector(
                  onTap: () => setState(() => _tabIndex = 3),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: context.palette.warningIcon, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.l10n.legacyStrip,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: context.palette.warningText,
                                height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Quick actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    _quickAction(
                        const Icon(Icons.arrow_outward_rounded, size: 25),
                        context.l10n.send, true, () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SendScreen(lspService: lspService),
                        ),
                      ).then((_) => _refreshDashboard());
                    }),
                    const SizedBox(width: 10),
                    // Keamanan: Terima NONAKTIF selama dompet belum punya
                    // frasa backup (dompet legacy) — dana yang masuk ke
                    // dompet tanpa frasa tidak bisa dipulihkan bila HP
                    // hilang/rusak. Strip peringatan di atas menjelaskan
                    // cara mengaktifkannya (buat dompet berfrasa).
                    _quickAction(
                        const Icon(Icons.south_west_rounded, size: 25),
                        context.l10n.receive, !_legacyWallet, () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ReceiveScreen(lspService: lspService),
                        ),
                      ).then((_) => _refreshDashboard());
                    }),
                    const SizedBox(width: 10),
_quickAction(const Icon(Icons.add_rounded, size: 25), context.l10n.buy, false, () {}),
                    const SizedBox(width: 10),
                    _quickAction(const Icon(Icons.swap_horiz_rounded, size: 25), context.l10n.swap, false, () {})
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // Transactions header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.l10n.activity,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    GestureDetector(
                      onTap: () {
                        setState(() => _tabIndex = 2);
                        _refreshDashboard();
                      },
                      child: Text(context.l10n.seeAll,
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF34D399),
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // Transaction list
              if (_displayPayments.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  child: Text(context.l10n.noActivity,
                      style:
                          TextStyle(fontSize: 13, color: context.palette.muted)),
                )
              else
                ..._displayPayments.take(5).map(_paymentRow),
              const SizedBox(height: 80),
            ],
          ),
            ),
            _ComingSoonPage(
              icon: '\u25CD',
              title: context.l10n.market,
              message: context.l10n.marketSoon,
            ),
            _HistoryPage(
                payments: _historyPayments,
                rowBuilder: _paymentRow,
                onExport: _exportHistoryCsv,
                onFilter: _showHistoryFilter,
                filterLabel: _historyRangeLabel,
                emptyMessage: _displayPayments.isEmpty
                    ? context.l10n.noTransactions
                    : context.l10n.historyNoTransactionsInPeriod),
            _ProfilePage(
              mnemonicWords: _mnemonicWords,
              legacyWallet: _legacyWallet,
              isTestnet: AppConfig.isTestnet,
              onViewBackup: () {
                if (_mnemonicWords == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        BackupScreen(mnemonic: _mnemonicWords!),
                  ),
                );
              },
              onResetWallet: _resetWalletWithPhrase,
              onRestoreWallet: _restoreWalletWithPhrase,
              onShareLog: _shareNodeLog,
              onCheckUpdate: _cekUpdateManual,
              onOpenStoreMode: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StoreModeScreen(lspService: lspService),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      // Floating tab bar
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 20),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: context.palette.border),
        ),
        child: Row(
          children: [
            _tab(0, '\u25C9', context.l10n.home),
            _tab(1, '\u25CD', context.l10n.market),
            _tab(2, '\u21BA', context.l10n.history),
            _tab(3, '\u25CB', context.l10n.profile),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(Widget icon, String label, bool enabled, VoidCallback onTap) {
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1.0 : 0.3,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: context.palette.cardAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.palette.border),
            ),
            child: Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF10B981).withValues(alpha: 0.2),
                        const Color(0xFF10B981).withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                  child: Center(child: icon),
                ),
                const SizedBox(height: 8),
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        color: context.palette.label,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ubah satu catatan pembayaran node menjadi baris daftar
  /// aktivitas/riwayat. Nominal ditampilkan bertanda (+ masuk,
  /// − keluar) dalam nusan; label status hanya muncul untuk
  /// pembayaran yang belum sukses. Pending KELUAR berlabel
  /// "Sedang diproses" (dananya sungguh terkunci); "Menunggu"
  /// hanya tersisa untuk pending masuk, yang oleh penyaring
  /// _displayPayments tidak lagi ditampilkan di daftar.
  /// Judul baris riwayat dari catatan: dipangkas per rune
  /// (aman untuk emoji) supaya baris tetap satu-dua baris;
  /// catatan utuh tampil di layar detail.
  String _noteRowTitle(String note) {
    final runes = note.runes.toList();
    if (runes.length <= 42) return note;
    return '${String.fromCharCodes(runes.take(42))}…';
  }

  /// Hash pembayaran (hex) dari jenis pembayaran Lightning —
  /// kunci menautkan catatan lokal. Null untuk on-chain (yang
  /// tidak punya catatan invoice).
  String? _paymentHashHex(PaymentDetails payment) {
    final kind = payment.kind;
    if (kind is PaymentKind_Bolt11) return _hashHex(kind.hash.data);
    if (kind is PaymentKind_Bolt11Jit) return _hashHex(kind.hash.data);
    if (kind is PaymentKind_Spontaneous) return _hashHex(kind.hash.data);
    return null;
  }

  Widget _paymentRow(PaymentDetails payment) {
    final isIn = payment.direction == PaymentDirection.inbound;
    final hashHex = _paymentHashHex(payment);
    final note = hashHex == null ? null : _paymentNotes[hashHex];
    final kind = payment.kind;
    final tag = kind is PaymentKind_Bolt11Jit
        ? '\u26A1 JIT'
        : kind is PaymentKind_Onchain
            ? '\u26D3 on-chain'
            : '\u26A1';
    final amount = payment.amountMsat == null
        ? '\u2014'
        : '${isIn ? '+' : '\u2212'}${context.formatWalletAmountNumber(payment.amountMsat!)}';
    final time = formatTxTime(
        DateTime.fromMillisecondsSinceEpoch(
            payment.latestUpdateTimestamp.toInt() * 1000),
        locale: context.l10n.localeName);
    return TransactionRow(
      icon: isIn
          ? const Icon(Icons.arrow_downward_rounded, size: 22)
          : const Icon(Icons.arrow_upward_rounded, size: 22),
      // Judul baris = catatan pembayaran bila ada (itulah gunanya
      // catatan ditulis); arah tetap terbaca dari ikon panah dan
      // tanda +/− nominal. Tanpa catatan, judul arah seperti dulu.
      title: note != null
          ? _noteRowTitle(note)
          : isIn
              ? context.l10n.received
              : context.l10n.sent,
      addr: _shortPaymentId(payment.id),
      tag: tag,
      isIn: isIn,
      amount: amount,
      time: time,
      status: switch (payment.status) {
        PaymentStatus.pending =>
          isIn ? context.l10n.pending : context.l10n.processing,
        PaymentStatus.failed => context.l10n.failed,
        PaymentStatus.succeeded => null,
      },
      statusBad: payment.status == PaymentStatus.failed,
      onTap: () => _openPaymentDetail(payment),
    );
  }

  /// Buka layar detail untuk satu catatan pembayaran.
  ///
  /// Untuk pembayaran Lightning, hash dari jenis pembayaran dipakai
  /// mencari invoice tersimpan lokal (lihat SavedInvoiceStore) —
  /// ketemu berarti layar detail bisa menampilkan kembali invoice
  /// pending-nya (QR + Salin); tidak ketemu berarti detail tampil
  /// tanpa invoice, bukan error.
  Future<void> _openPaymentDetail(PaymentDetails payment) async {
    String? hashHex;
    final kind = payment.kind;
    if (kind is PaymentKind_Bolt11) {
      hashHex = _hashHex(kind.hash.data);
    } else if (kind is PaymentKind_Bolt11Jit) {
      hashHex = _hashHex(kind.hash.data);
    } else if (kind is PaymentKind_Spontaneous) {
      hashHex = _hashHex(kind.hash.data);
    }
    SavedInvoice? saved;
    if (hashHex != null) {
      saved = await SavedInvoiceStore().findByHash(hashHex);
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionDetailScreen(
          payment: payment,
          savedInvoice: saved,
          note: hashHex == null ? null : _paymentNotes[hashHex],
        ),
      ),
    );
  }

  String _hashHex(Iterable<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Widget _tab(int index, String icon, String label) {
    final active = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _tabIndex = index);
          if (index == 0 || index == 2) _refreshDashboard();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)])
                : null,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon,
                  style: TextStyle(
                      fontSize: 20,
                      color: active ? Colors.white : context.palette.faint)),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: active ? Colors.white : context.palette.faint)),
            ],
          ),
        ),
      ),
    );
  }
}

/// ID pembayaran dipendekkan untuk subjudul baris daftar:
/// 5 karakter hex awal + 4 karakter hex akhir.
String _shortPaymentId(PaymentId id) {
  final hex = id.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  if (hex.length <= 10) return hex;
  return '${hex.substring(0, 5)}\u2026${hex.substring(hex.length - 4)}';
}

/// Tab Profil — pengaturan dompet: tema, frasa backup & info jaringan.
/// Untuk dompet legacy (tanpa frasa) halaman ini menampung tawaran
/// membuat dompet baru berfrasa, lengkap dengan konfirmasi bahaya.
class _ProfilePage extends StatelessWidget {
  final List<String>? mnemonicWords;
  final bool legacyWallet;
  final bool isTestnet;
  final VoidCallback onViewBackup;
  final Future<void> Function() onResetWallet;

  /// Dipanggil dengan frasa tervalidasi dari layar Restore; mengeksekusi
  /// pergantian dompet (lihat _restoreWalletWithPhrase di HomeScreen).
  final Future<void> Function(String mnemonic) onRestoreWallet;

  /// Bagikan berkas log node lewat share sheet (lihat _shareNodeLog
  /// di HomeScreen) — membantu pemeriksaan saat aplikasi bermasalah.
  final VoidCallback onShareLog;

  /// Cek pembaruan aplikasi secara manual (lihat _cekUpdateManual
  /// di HomeScreen) — dialog OTA nusan-catcher juga bisa dibuka
  /// manual dari pengaturan, bukan hanya cek otomatis.
  final Future<void> Function() onCheckUpdate;

  /// Buka Mode Toko (kasir PoS) — layar penuh di atas Profil,
  /// memakai node dompet yang sama.
  final VoidCallback onOpenStoreMode;

  const _ProfilePage({
    required this.mnemonicWords,
    required this.legacyWallet,
    required this.isTestnet,
    required this.onViewBackup,
    required this.onResetWallet,
    required this.onRestoreWallet,
    required this.onShareLog,
    required this.onCheckUpdate,
    required this.onOpenStoreMode,
  });

  /// Dialog pilih bahasa — dua opsi, yang aktif bertanda centang.
  Future<void> _showLanguageDialog(BuildContext context) async {
    final l10n = context.l10n;
    final current = LocaleController.locale.value;
    final picked = await showDialog<Locale>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.chooseLanguage),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _languageOption(ctx, const Locale('id'),
                l10n.languageIndonesian, current.languageCode == 'id'),
            _languageOption(ctx, const Locale('en'), l10n.languageEnglish,
                current.languageCode == 'en'),
          ],
        ),
      ),
    );
    if (picked != null) await LocaleController.setLocale(picked);
  }

  Widget _languageOption(
      BuildContext ctx, Locale locale, String label, bool selected) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: Color(0xFF34D399))
          : null,
      onTap: () => Navigator.pop(ctx, locale),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(22, 22, 22, 10),
            child: Text(context.l10n.profile,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          // Baris Tema — toggle Gelap/Terang (tersimpan, sama
          // seperti tombol di header dashboard).
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.palette.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(colors: [
                      const Color(0xFF10B981).withValues(alpha: 0.25),
                      const Color(0xFF10B981).withValues(alpha: 0.08),
                    ]),
                  ),
                  child: const Icon(Icons.brightness_6_rounded,
                      color: Color(0xFF34D399), size: 20),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.themeTitle,
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(
                        context.l10n.themeSubtitle,
                        style: TextStyle(
                            fontSize: 12, color: context.palette.muted),
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeController.mode,
                  builder: (context, mode, _) => Switch(
                    value: mode == ThemeMode.dark,
                    onChanged: (dark) => ThemeController.setMode(
                        dark ? ThemeMode.dark : ThemeMode.light),
                    activeThumbColor: const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
          // Baris Bahasa — pilih Indonesia/English (tersimpan,
          // berlaku di semua layar setelah dipilih).
          GestureDetector(
            onTap: () => _showLanguageDialog(context),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.palette.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [
                        const Color(0xFF10B981).withValues(alpha: 0.25),
                        const Color(0xFF10B981).withValues(alpha: 0.08),
                      ]),
                    ),
                    child: const Icon(Icons.language_rounded,
                        color: Color(0xFF34D399), size: 20),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.appLanguage,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        ValueListenableBuilder<Locale>(
                          valueListenable: LocaleController.locale,
                          builder: (context, locale, _) => Text(
                            locale.languageCode == 'en'
                                ? 'English'
                                : 'Bahasa Indonesia',
                            style: TextStyle(
                                fontSize: 12, color: context.palette.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: context.palette.muted),
                ],
              ),
            ),
          ),
          // Baris Satuan — saklar satuan tampilan jumlah dompet
          // (NUX | nusan), berlaku global di saldo, kirim, terima,
          // dan riwayat. Murni tampilan: nilai simpanan & hitungan
          // tetap msat; Mode Toko tidak ikut saklar ini.
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.palette.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.palette.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(colors: [
                      const Color(0xFF10B981).withValues(alpha: 0.25),
                      const Color(0xFF10B981).withValues(alpha: 0.08),
                    ]),
                  ),
                  child: const Icon(Icons.straighten_rounded,
                      color: Color(0xFF34D399), size: 20),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l10n.unitTitle,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(
                        context.l10n.unitSubtitle,
                        style: TextStyle(
                            fontSize: 12, color: context.palette.muted),
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder<DisplayUnit>(
                  valueListenable: UnitController.unit,
                  builder: (context, unit, _) => SegmentedButton<DisplayUnit>(
                    segments: const [
                      ButtonSegment(
                          value: DisplayUnit.nux, label: Text('NUX')),
                      ButtonSegment(
                          value: DisplayUnit.nusan, label: Text('nusan')),
                    ],
                    selected: {unit},
                    onSelectionChanged: (picked) =>
                        UnitController.setUnit(picked.first),
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Baris Backup Wallet
          GestureDetector(
            onTap: legacyWallet ? null : onViewBackup,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.palette.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [
                        const Color(0xFF10B981).withValues(alpha: 0.25),
                        const Color(0xFF10B981).withValues(alpha: 0.08),
                      ]),
                    ),
                    child: const Icon(Icons.key_rounded,
                        color: Color(0xFF34D399), size: 20),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.backupWallet,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                          legacyWallet
                              ? context.l10n.legacyWalletSubtitle
                              : context.l10n.backupSubtitle,
                          style: TextStyle(
                              fontSize: 12, color: context.palette.muted),
                        ),
                      ],
                    ),
                  ),
                  if (!legacyWallet)
                    Icon(Icons.chevron_right_rounded,
                        color: context.palette.muted),
                ],
              ),
            ),
          ),
          // Baris Restore Phrase — pulihkan dompet dari frasa backup.
          // Tersedia untuk semua status dompet (termasuk legacy: restore
          // juga menggantikan dompet tanpa frasa dengan dompet berfrasa).
          GestureDetector(
            onTap: () async {
              final restored = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => RestoreScreen(onRestore: onRestoreWallet),
                ),
              );
              if (restored == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.l10n.restoreSuccess)),
                );
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.palette.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [
                        const Color(0xFF10B981).withValues(alpha: 0.25),
                        const Color(0xFF10B981).withValues(alpha: 0.08),
                      ]),
                    ),
                    child: const Icon(Icons.restore_rounded,
                        color: Color(0xFF34D399), size: 20),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.restoreWallet,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                          context.l10n.restoreSubtitle,
                          style: TextStyle(
                              fontSize: 12, color: context.palette.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: context.palette.muted),
                ],
              ),
            ),
          ),
          // Baris Printer — buka Pengaturan Printer (pilih printer
          // struk 58mm, uji cetak, teks header/footer struk).
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PrinterSettingsScreen(),
              ),
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.palette.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [
                        const Color(0xFF10B981).withValues(alpha: 0.25),
                        const Color(0xFF10B981).withValues(alpha: 0.08),
                      ]),
                    ),
                    child: const Icon(Icons.print_rounded,
                        color: Color(0xFF34D399), size: 20),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.printer,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                          context.l10n.printerSubtitle,
                          style: TextStyle(
                              fontSize: 12, color: context.palette.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: context.palette.muted),
                ],
              ),
            ),
          ),
          // Baris Mode Toko — buka kasir (PoS) untuk menerima
          // pembayaran di toko: pesanan dari katalog/scan/keypad,
          // kode bayar, struk. Node & channel yang sama dengan
          // dompet; tidak ada dompet kedua.
          GestureDetector(
            onTap: onOpenStoreMode,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.palette.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [
                        const Color(0xFF10B981).withValues(alpha: 0.25),
                        const Color(0xFF10B981).withValues(alpha: 0.08),
                      ]),
                    ),
                    child: const Icon(Icons.storefront_rounded,
                        color: Color(0xFF34D399), size: 20),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.storeMode,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                          context.l10n.storeModeSubtitle,
                          style: TextStyle(
                              fontSize: 12, color: context.palette.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: context.palette.muted),
                ],
              ),
            ),
          ),
          // Baris Uji Offline — spike jembatan Bluetooth antar-HP
          // (tahap 1: dua node tersambung sebagai peer tanpa
          // internet). Layar eksperimental khusus testnet; tidak
          // memengaruhi alur dompet normal. Baris ini hanya tampil
          // di build testnet, sejajar dengan listener node yang
          // juga hanya dipasang di testnet.
          if (isTestnet)
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OfflineSpikeScreen(
                  lspService: lspService,
                  bridge: offlineBridge,
                ),
              ),
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.palette.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [
                        const Color(0xFF10B981).withValues(alpha: 0.25),
                        const Color(0xFF10B981).withValues(alpha: 0.08),
                      ]),
                    ),
                    child: const Icon(Icons.bluetooth_rounded,
                        color: Color(0xFF34D399), size: 20),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.offlineSpike,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                          context.l10n.offlineSpikeSubtitle,
                          style: TextStyle(
                              fontSize: 12, color: context.palette.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: context.palette.muted),
                ],
              ),
            ),
          ),
          // Baris Bagikan Log — kirim berkas log node (ldk_node.log)
          // lewat share sheet untuk membantu pemeriksaan masalah,
          // pola yang sama seperti fitur share logs di Phoenix.
          GestureDetector(
            onTap: onShareLog,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.palette.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: context.palette.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [
                        const Color(0xFF10B981).withValues(alpha: 0.25),
                        const Color(0xFF10B981).withValues(alpha: 0.08),
                      ]),
                    ),
                    child: const Icon(Icons.share_rounded,
                        color: Color(0xFF34D399), size: 20),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.l10n.shareLog,
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(
                          context.l10n.shareLogSubtitle,
                          style: TextStyle(
                              fontSize: 12, color: context.palette.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: context.palette.muted),
                ],
              ),
            ),
          ),
          // Baris Periksa Pembaruan — cek manual versi baru
          // (OTA); cek otomatis diam-diam berjalan saat aplikasi
          // dibuka, baris ini untuk pengguna yang ingin memastikan.
          // Selama cek berjalan tampil indikator loading supaya
          // jeda jaringannya tidak terasa hang.
          _UpdateCheckTile(onCheckUpdate: onCheckUpdate),
          // Kartu Komunitas — alamat resmi komunitas Nusacoin di
          // bawah Periksa Pembaruan; tautan dibuka di browser
          // eksternal.
          const _CommunityCard(),
          // Kartu dompet legacy: tawarkan buat ulang berfrasa
          if (legacyWallet)
            Container(
              margin: const EdgeInsets.fromLTRB(18, 10, 18, 4),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.l10n.noPhraseTitle,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.palette.warningText)),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.noPhraseBody,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: context.palette.label,
                        height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: ctx.palette.card,
                          title: Text(ctx.l10n.createNewWalletTitle),
                          content: Text(
                              ctx.l10n.deleteOldWalletBody),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(ctx.l10n.cancel),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(ctx.l10n.deleteAndCreate,
                                  style:
                                      TextStyle(color: Color(0xFFEF4444))),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await onResetWallet();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(context.l10n.createNewWalletButton),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          // Info jaringan
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              isTestnet
                  ? context.l10n.networkTestnetLabel
                  : context.l10n.networkMainnetLabel,
              style: TextStyle(fontSize: 12.5, color: context.palette.muted),
            ),
          ),
          const SizedBox(height: 10),
          // Label versi + nomor build di kaki halaman — nomor build
          // adalah nomor run CI pembuat APK-nya, jadi build yang
          // terpasang bisa dicocokkan dengan run pembuatnya.
          const Center(child: _AppVersionLabel()),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

/// Label versi aplikasi + nomor build di kaki tab Profil, dibaca
/// dari paket yang terpasang (package_info_plus). Selama infonya
/// belum termuat — atau gagal dibaca — label tidak dirender sama
/// sekali, supaya kaki halaman tidak menampilkan teks setengah jadi.
/// Baris "Periksa Pembaruan" di Profil dengan keadaan loading:
/// selama pemeriksaan berjalan, ikon berganti putaran kecil dan
/// label keterangan menjadi "Memeriksa pembaruan…" sementara
/// ketukan ulang diabaikan — jeda jaringan (timeout cek 15 detik)
/// tidak lagi terasa seperti aplikasi hang.
class _UpdateCheckTile extends StatefulWidget {
  final Future<void> Function() onCheckUpdate;

  const _UpdateCheckTile({required this.onCheckUpdate});

  @override
  State<_UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<_UpdateCheckTile> {
  bool _checking = false;

  Future<void> _handleTap() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await widget.onCheckUpdate();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _checking ? null : _handleTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: [
                  const Color(0xFF10B981).withValues(alpha: 0.25),
                  const Color(0xFF10B981).withValues(alpha: 0.08),
                ]),
              ),
              child: _checking
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF34D399),
                        ),
                      ),
                    )
                  : const Icon(Icons.system_update_alt_rounded,
                      color: Color(0xFF34D399), size: 20),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.updateCheckTitle,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    _checking
                        ? context.l10n.updateChecking
                        : context.l10n.updateCheckSubtitle,
                    style: TextStyle(
                        fontSize: 12, color: context.palette.muted),
                  ),
                ],
              ),
            ),
            if (!_checking)
              Icon(Icons.chevron_right_rounded,
                  color: context.palette.muted),
          ],
        ),
      ),
    );
  }
}

/// Kartu Komunitas di Profil (tepat di bawah Periksa Pembaruan):
/// alamat resmi komunitas Nusacoin — dua website dan grup
/// Telegram — dan setiap tautan dibuka di browser eksternal
/// lewat url_launcher. Data tautannya di utils/community_links.
class _CommunityCard extends StatelessWidget {
  const _CommunityCard();

  Future<void> _open(BuildContext context, String url) async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.communityOpenFailed)),
      );
    }
  }

  Widget _groupLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.palette.muted),
      ),
    );
  }

  Widget _linkRow(BuildContext context,
      {required IconData icon, required CommunityLink link}) {
    return InkWell(
      onTap: () => _open(context, link.url),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF34D399)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(link.label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.open_in_new_rounded,
                size: 15, color: context.palette.muted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(colors: [
                    const Color(0xFF10B981).withValues(alpha: 0.25),
                    const Color(0xFF10B981).withValues(alpha: 0.08),
                  ]),
                ),
                child: const Icon(Icons.groups_rounded,
                    color: Color(0xFF34D399), size: 20),
              ),
              const SizedBox(width: 13),
              Text(context.l10n.communityTitle,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ],
          ),
          _groupLabel(context, context.l10n.communityWebsiteLabel),
          for (final link in communityWebsiteLinks)
            _linkRow(context, icon: Icons.public_rounded, link: link),
          _groupLabel(context, context.l10n.communityTelegramGroup),
          for (final link in communityTelegramLinks)
            _linkRow(context, icon: Icons.telegram, link: link),
        ],
      ),
    );
  }
}

class _AppVersionLabel extends StatelessWidget {
  const _AppVersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return const SizedBox.shrink();
        return Text(
          context.l10n.appVersionLabel(info.version, info.buildNumber),
          style: TextStyle(fontSize: 11.5, color: context.palette.muted),
        );
      },
    );
  }
}

/// Tab Riwayat — seluruh pembayaran dari node, terbaru di depan.
class _HistoryPage extends StatelessWidget {
  final List<PaymentDetails> payments;
  final Widget Function(PaymentDetails) rowBuilder;

  /// Ekspor CSV riwayat ini; null menyembunyikan tombolnya.
  final VoidCallback? onExport;

  /// Buka lembar filter tanggal; null menyembunyikan tombolnya.
  final VoidCallback? onFilter;

  /// Label rentang tanggal aktif, tampil di bawah judul supaya
  /// user selalu tahu jendela waktu yang sedang dilihatnya.
  final String filterLabel;

  /// Pesan saat daftar (yang sudah disaring) kosong — dibedakan
  /// pemanggil antara "belum ada transaksi sama sekali" dan
  /// "tidak ada transaksi pada periode ini".
  final String emptyMessage;

  const _HistoryPage(
      {required this.payments,
      required this.rowBuilder,
      this.onExport,
      this.onFilter,
      required this.filterLabel,
      required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(22, 22, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.history,
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text(filterLabel,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.palette.secondary)),
                  ],
                ),
              ),
              if (onFilter != null)
                IconButton(
                  icon: const Icon(Icons.filter_alt_outlined),
                  tooltip: context.l10n.historyFilter,
                  onPressed: onFilter,
                ),
              if (onExport != null)
                IconButton(
                  icon: const Icon(Icons.ios_share_rounded),
                  tooltip: context.l10n.historyExport,
                  onPressed: onExport,
                ),
            ],
          ),
        ),
        Expanded(
          child: payments.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('\u21BA',
                            style: TextStyle(
                                fontSize: 44, color: Color(0xFF34D399))),
                        SizedBox(height: 14),
                        Text(emptyMessage,
                            style: TextStyle(
                                fontSize: 13,
                                color: context.palette.secondary),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: payments.map(rowBuilder).toList(),
                ),
        ),
      ],
    );
  }
}

/// Halaman placeholder untuk tab yang belum punya konten sendiri.
class _ComingSoonPage extends StatelessWidget {
  final String icon;
  final String title;
  final String message;

  const _ComingSoonPage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon,
                style: const TextStyle(
                    fontSize: 44, color: Color(0xFF34D399))),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message,
                style: TextStyle(
                    fontSize: 13, color: context.palette.secondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
