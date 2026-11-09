import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/lsp_service.dart';
import '../services/print_service.dart';
import '../services/store_catalog.dart';
import '../services/store_customers.dart';
import '../services/store_draft.dart';
import '../services/store_telegram.dart';
import '../services/store_hold.dart';
import '../services/store_operators.dart';
import '../services/store_order_history.dart';
import '../services/store_settings.dart';
import '../services/store_shift.dart';
import '../utils/animated_checkmark.dart';
import '../utils/bolt11_info.dart';
import '../utils/bolt12_info.dart';
import '../utils/coin_alert.dart';
import '../utils/format.dart';
import '../utils/friendly_error.dart';
import '../utils/receive_watch.dart';
import '../utils/rupiah_input.dart';
import '../utils/store_migration.dart';
import '../utils/store_mode_logic.dart';
import '../utils/store_receipt.dart';
import '../utils/store_report.dart';
import 'scan_screen.dart';
import 'store_customers_screen.dart';
import 'store_operator_gate.dart';
import 'store_receipt_preview.dart';
import 'store_point_rules_screen.dart';
import 'store_reports_screen.dart';
import 'store_sales_history_screen.dart';
import 'store_settings_screen.dart';
import 'store_shift_report_screen.dart';

/// Mode Toko v2 — kasir (PoS) di dalam ELNUX untuk UMKM.
///
/// KERANGKA (Pedoman miniPOS tim, keputusan NUX 3 Nov 2026):
/// rupiah adalah alat pembayaran; nusan adalah POIN loyalitas.
/// Karena itu layar ini adalah kasir RUPIAH: harga, total, dan
/// pelunasan selalu rupiah (tunai dicatat dengan kembalian, QRIS
/// dicatat metodenya — pemrosesan QRIS di luar aplikasi). Poin
/// nusan hanya punya dua peran di sini, keduanya tercatat jujur:
/// DITUKAR sebagai potongan harga (baris diskon rupiah, hanya
/// sesudah perpindahan poin terverifikasi dari node) dan
/// DITERBITKAN sebagai bonus sesudah pembayaran rupiah lunas.
/// TIDAK ADA alur di layar ini yang melunasi belanja dengan
/// poin.
///
/// Satu sumber kebenaran nominal penjualan adalah DAFTAR BARIS
/// pesanan: baris ditambah dengan (a) memindai QR/barcode produk,
/// (b) mengetuk item katalog (sekaligus "item cepat"), atau
/// (c) nominal bebas dari keypad. Penyelesaian pesanan berjalan
/// lewat HALAMAN PEMBAYARAN (_StorePaymentPage): penukaran poin
/// opsional + pelunasan rupiah; hasilnya satu record penjualan
/// era 'rp' di riwayat (bahan laporan shift).
///
/// Alur shift (keputusan NUX 3 Nov 2026): kasir MEMULAI dengan
/// Buka Shift; tanpa shift terbuka panel kasir nonaktif dan
/// pesanan tidak bisa diselesaikan — semua penjualan tercatat
/// di dalam shift. Pesanan yang dibatalkan kasir dari halaman
/// pembayaran tercatat sebagai VOID. Laporan per shift (atau
/// per tanggal) dibuka dari kartu shift di panel status.
///
/// Penyempurnaan lapangan (NUX 3 Nov 2026): pesanan bisa DITAHAN
/// untuk tamu yang bayar belakangan (daftar tahan persisten;
/// Tutup Shift memperingatkan bila masih ada yang ditahan,
/// tetapi tidak menghapusnya); keypad mode ganda — Qty (bawaan:
/// digit = pengali item berikutnya) dan Nominal; tiap baris
/// pesanan bisa diberi catatan singkat yang ikut tercetak pada
/// struk rinci pelanggan; katalog dapat dicari dan field
/// Kategori menyarankan kategori yang sudah ada sebagai chip.
///
/// Penerbitan poin yang gagal/dilewati TIDAK membatalkan
/// penjualan: record-nya berstatus 'pending' dan masuk antre
/// "Poin Tertunda" di panel status, bisa diterbitkan ulang atau
/// ditandai batal terbit dari sana.
class StoreModeScreen extends StatefulWidget {
  final LspService lspService;

  const StoreModeScreen({super.key, required this.lspService});

  @override
  State<StoreModeScreen> createState() => _StoreModeScreenState();
}

class _StoreModeScreenState extends State<StoreModeScreen>
    with WidgetsBindingObserver {
  // --- Pesanan berjalan ---
  int _keypadRp = 0;
  List<OrderLine> _lines = const [];
  Discount? _orderDiscount;

  // --- Keypad mode ganda (keputusan NUX 3 Nov 2026) ---
  /// True = mode Qty (BAWAAN saat layar dibuka): digit keypad
  /// menyusun pengali untuk item berikutnya yang ditambahkan
  /// dari katalog/scan. False = mode Nominal: nominal bebas
  /// rupiah + jumlah cepat + judul kustom.
  bool _qtyKeypadMode = true;

  /// Nilai pengali yang sedang disusun di mode Qty; 0 = belum
  /// diatur, pengali efektifnya 1. Kembali 0 sesudah dipakai.
  int _qtyMultiplier = 0;

  int get _effectiveQty => _qtyMultiplier <= 0 ? 1 : _qtyMultiplier;

  // --- Pesanan ditahan (tamu bayar belakangan) ---
  final _holdStore = HeldOrderStore();
  List<HeldOrder> _heldOrders = const [];

  // --- Draf pesanan (jaring pengaman background) ---
  final _draftStore = StoreDraftStore();

  // --- Katalog (store v2, harga rupiah) ---
  final _catalogStore = StoreCatalogStore();
  List<CatalogItem> _catalog = const [];

  /// Kolom cari katalog (nama/kode) + kolom judul kustom untuk
  /// baris nominal bebas. Keduanya dibersihkan mengikuti reset
  /// pesanan sesudah penjualan lunas (lihat _resetOrderPanel).
  final _searchController = TextEditingController();
  String _searchQuery = '';

  /// Kategori katalog terpilih pada saringan kasir (null =
  /// semua kategori). Mengikuti pola tab kategori desain
  /// landscape referensi NUX (8 Nov 2026): kasir menyaring grid
  /// produk per kategori, di kedua mode layar.
  String? _catalogCategory;
  final _freeTitleController = TextEditingController();

  // --- Shift kasir ---
  final _shiftStore = StoreShiftStore();
  List<StoreShift> _shifts = const [];
  StoreShift? _openShift;

  // --- Pengaturan toko & program poin ---
  final _settingsStore = StoreSettingsStore();
  StoreSettings _settings = StoreSettings.defaults;

  // --- Operator & peran (Fase A) ---
  final _operatorStore = StoreOperatorStore();
  final _auditStore = StoreAuditStore();

  /// Sesi operator yang sedang login; null = belum login —
  /// badan layar digantikan gerbang operator (login / buat
  /// owner pertama). Sesi hanya hidup di ingatan: proses
  /// aplikasi mati = login ulang, memang disengaja.
  StoreOperator? _operator;

  /// ID outlet perangkat ini untuk struk: 6 karakter pertama
  /// node_id ELNUX perangkat (identitas cabang dari node_id —
  /// ide NUX 4 Nov 2026), tampil sesudah nomor token.
  /// '' selagi node belum terbaca; struk lalu hanya
  /// menampilkan nomor token.
  String _outletId = '';

  // --- Penjualan terakhir & panel sukses ---
  // (Penghitung token kini dinaikkan di dalam transaksi
  // pelunasan basis data — lihat recordSettledSale.)
  final _historyStore = StoreOrderHistoryStore();
  CompletedOrder? _saleRecord;
  bool _received = false;
  Timer? _celebrationTimer;

  /// Penggulir dua tata letak layar: HP satu kolom memakai
  /// [_pageScrollController] (seluruh halaman), tablet dua
  /// panel memakai [_statusScrollController] (panel status —
  /// panel perayaan penjualan tinggal di panel itu). Dipakai
  /// untuk menggulir ke bawah tepat sesudah penjualan lunas
  /// (permintaan NUX 4 Nov 2026).
  final _pageScrollController = ScrollController();
  final _statusScrollController = ScrollController();

  /// Penanda blok perayaan penjualan lunas — sasaran
  /// ensureVisible pelengkap sesudah gulir ke bawah.
  final _celebrationKey = GlobalKey();

  /// Penerbitan poin sedang berjalan (kirim ke pelanggan) —
  /// tombol terbit dinonaktifkan & Tutup Shift terhalang sesaat.
  bool _issuing = false;

  /// Record era 'rp' yang poinnya berstatus 'pending' — bahan
  /// penanda & daftar antre "Poin Tertunda".
  List<CompletedOrder> _pendingIssues = const [];

  // --- Ringkasan sesi ---
  StoreSessionSummary _session = StoreSessionSummary.empty;

  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _celebrationTimer?.cancel();
    _pageScrollController.dispose();
    _statusScrollController.dispose();
    _searchController.dispose();
    _freeTitleController.dispose();
    super.dispose();
  }

  /// Jaring pengaman background (temuan NUX 4 Nov 2026): saat
  /// aplikasi masuk background (paused — mis. tombol Home
  /// tertekan tak sengaja) atau hendak dilepas sistem
  /// (detached), salin pesanan berjalan ke slot draf. Pesanan
  /// kosong justru MEMBERSIHKAN draf: tidak ada lagi yang perlu
  /// diselamatkan, dan draf lama tidak boleh bangkit sebagai
  /// pesanan hantu.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    if (_lines.isEmpty) {
      unawaited(_draftStore.clear());
      return;
    }
    unawaited(
      _draftStore.save(lines: List.of(_lines), orderDiscount: _orderDiscount),
    );
  }

  /// Muat semua keadaan lokal, lalu jalankan migrasi v1 → v2
  /// satu kali (rancangan §7) sebelum layar dipakai.
  /// Baca node_id dompet untuk ID outlet struk. Gagal (node
  /// belum jalan) tidak menghalangi Mode Toko: struk cukup
  /// tanpa ID outlet.
  Future<void> _loadOutletId() async {
    try {
      final nodeId = await widget.lspService.ownNodeId();
      if (!mounted) return;
      setState(() => _outletId = outletIdFromNodeId(nodeId));
    } catch (_) {
      // Node belum berjalan — biarkan kosong.
    }
  }

  Future<void> _init() async {
    unawaited(_loadOutletId());
    final settings = await _settingsStore.load();
    var shifts = await _shiftStore.load();
    final held = await _holdStore.load();
    final catalog = await _catalogStore.load();
    if (!mounted) return;

    var openShift = openShiftIn(shifts);
    final migrationNote = await _runMigrationOnce(shifts, openShift);
    if (migrationNote != null) {
      // Migrasi bisa menutup shift terbuka — segarkan keadaan.
      shifts = await _shiftStore.load();
      openShift = openShiftIn(shifts);
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _shifts = shifts;
      _openShift = openShift;
      _heldOrders = held;
      _catalog = catalog;
    });
    await _loadPendingIssues();
    if (migrationNote != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.palette.card,
          title: Text(ctx.l10n.storeMigrationTitle),
          content: Text(migrationNote),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.storeMigrationOk),
            ),
          ],
        ),
      );
    }
    await _restoreDraftIfAny();
  }

  /// Pulihkan draf pesanan dari jaring pengaman background
  /// (temuan NUX 4 Nov 2026): hanya bila pesanan berjalan
  /// kosong dan draf ada. Draf dikembalikan persis seperti
  /// semula (baris + diskon order), slotnya dikosongkan, dan
  /// kasir diberi tahu singkat — kasir tidak boleh menginput
  /// ulang pesanan yang sudah disusun.
  Future<void> _restoreDraftIfAny() async {
    if (_lines.isNotEmpty) return;
    final draft = await _draftStore.load();
    if (draft == null || !mounted) return;
    await _draftStore.clear();
    if (!mounted) return;
    setState(() {
      _lines = List.of(draft.lines);
      _orderDiscount = draft.orderDiscount;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.storeDraftRestored)));
  }

  /// Eksekusi migrasi era satu kali; mengembalikan teks
  /// pemberitahuan untuk dialog bila ada hal yang perlu
  /// diketahui kasir (pesanan ditahan gugur / katalog perlu
  /// diisi ulang / shift lama ditutup), null bila tidak ada.
  Future<String?> _runMigrationOnce(
    List<StoreShift> shifts,
    StoreShift? openShift,
  ) async {
    final flag = StoreMigrationFlagStore();
    final done = await flag.isDone();
    // Keadaan simpanan v1 dibaca dari kunci lamanya langsung —
    // store v2 menunjuk kunci baru dan tidak melihat data v1.
    var legacyHeldCount = 0;
    var legacyCatalogNonEmpty = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      legacyHeldCount = decodeHeldOrders(
        prefs.getString('store_held_orders_v1'),
      ).length;
      legacyCatalogNonEmpty = decodeCatalog(
        prefs.getString('store_catalog_items_v1'),
      ).isNotEmpty;
    } catch (_) {
      // Gagal baca simpanan lama = tidak ada yang diketahui
      // untuk dimigrasikan; jangan mengarang.
    }
    final plan = planStoreMigration(
      alreadyDone: done,
      hasOpenLegacyShift: openShift != null && openShift.era == storeEraNusan,
      legacyHeldCount: legacyHeldCount,
      legacyCatalogNonEmpty: legacyCatalogNonEmpty,
    );
    if (!plan.hasActions) {
      if (!done) await flag.markDone();
      return null;
    }
    if (plan.closeOpenLegacyShift && openShift != null) {
      final closed = openShift.close(DateTime.now());
      final next = [
        for (final s in shifts) s == openShift ? closed : s,
      ];
      await _shiftStore.save(next);
    }
    if (plan.droppedHeldOrders > 0) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('store_held_orders_v1');
      } catch (_) {
        // Abaikan — kunci lama yang tertinggal tidak dibaca v2.
      }
    }
    await flag.markDone();
    if (!plan.hasNotices && !plan.closeOpenLegacyShift) return null;
    final l10n = context.l10n;
    final parts = <String>[
      if (plan.closeOpenLegacyShift) l10n.storeMigrationShiftClosed,
      if (plan.droppedHeldOrders > 0)
        l10n.storeMigrationHeldDropped(plan.droppedHeldOrders),
      if (plan.catalogNeedsRefill) l10n.storeMigrationCatalog,
    ];
    return parts.join('\n\n');
  }

  Future<void> _loadPendingIssues() async {
    final orders = await _historyStore.load();
    if (!mounted) return;
    setState(() {
      _pendingIssues = [
        for (final o in orders)
          if (o.isRupiahEra &&
              !o.isVoid &&
              o.pointsIssueStatus == issueStatusPending)
            o,
      ];
    });
  }

  String get _reportLocale =>
      context.l10n.localeName.startsWith('en') ? 'en' : 'id';

  // ------------------------------------------------------------------
  // Operator & gerbang admin (Fase A)
  // ------------------------------------------------------------------

  /// Ganti operator: sesi sekarang ditutup (tercatat di audit
  /// sebagai logout) dan gerbang login tampil lagi. Shift yang
  /// sedang berjalan TIDAK ikut tertutup — stempel pembukanya
  /// tetap, penjualan berikutnya berstempel operator baru.
  Future<void> _switchOperator() async {
    final current = _operator;
    if (current == null) return;
    await _auditStore.append(
      operator: current,
      action: StoreAuditAction.logout,
    );
    if (!mounted) return;
    setState(() => _operator = null);
  }

  /// Gerbang PIN admin di tempat untuk aksi sensitif
  /// (keputusan NUX (a)): owner yang sedang login lolos
  /// langsung; kasir memicu dialog PIN — owner mana pun boleh
  /// menyetujui TANPA mengganti sesi kasir. Persetujuan
  /// tercatat di audit atas nama kasir peminta + nama
  /// penyetuju. Mengembalikan true bila aksi boleh jalan.
  Future<bool> _requireAdminApproval(String actionLabel) async {
    final me = _operator;
    if (me == null) return false;
    if (me.isOwner) return true;
    final pin = await showStorePinDialog(
      context,
      title: context.l10n.storeAdminPinTitle,
      body: context.l10n.storeAdminPinBody,
    );
    if (pin == null || !mounted) return false;
    final approver = await _operatorStore.verifyAnyOwnerPin(pin);
    if (!mounted) return false;
    if (approver == null) {
      _snack(context.l10n.storeOperatorWrongPin);
      return false;
    }
    await _auditStore.append(
      operator: me,
      action: StoreAuditAction.adminOverride,
      detail: '$actionLabel — approved by ${approver.name}',
    );
    if (!mounted) return false;
    _snack(context.l10n.storeAdminApproved);
    return true;
  }

  // ------------------------------------------------------------------
  // Shift kasir (alur NUX: Open Shift dulu, Close Shift penutup)
  // ------------------------------------------------------------------

  /// Dialog input Modal awal laci saat membuka shift
  /// (permintaan NUX 5 Nov 2026): kolom besar/tebal berformat
  /// ribuan saat mengetik + kartu pecahan akumulatif seperti
  /// halaman pembayaran. Bawaan Rp0 — batal mengembalikan
  /// null (shift tidak jadi dibuka).
  Future<int?> _promptOpeningFloat() async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: '0');
    var value = 0;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void setValue(int v) {
            value = v;
            controller.text = formatRupiahInput(
              v,
              thousandsSep: l10n.localeName == 'en' ? ',' : '.',
            );
            setLocal(() {});
          }

          return AlertDialog(
            backgroundColor: ctx.palette.card,
            title: Text(l10n.storeOpeningFloatTitle),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.storeOpeningFloatHint,
                    style: TextStyle(
                      fontSize: 12,
                      color: ctx.palette.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      RupiahAmountFormatter(
                        thousandsSep: l10n.localeName == 'en' ? ',' : '.',
                      ),
                    ],
                    onChanged: (v) =>
                        setLocal(() => value = parseRupiahAmount(v)),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.storeOpeningFloatLabel,
                      prefixText: 'Rp ',
                      filled: true,
                      fillColor: ctx.palette.cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Rp0'),
                        onPressed: () => setValue(0),
                      ),
                      for (final denom in const [
                        5000,
                        10000,
                        20000,
                        50000,
                        100000,
                      ])
                        ActionChip(
                          label: Text('+${formatRupiah(denom)}'),
                          onPressed: () => setValue(
                            cashAddDenomRp(currentRp: value, denomRp: denom),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, value),
                child: Text(l10n.storeShiftOpen),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _openShiftAction() async {
    if (_openShift != null) return;
    final openingFloat = await _promptOpeningFloat();
    if (openingFloat == null || !mounted) return;
    final me = _operator;
    final shift = StoreShift(
      openedAt: DateTime.now(),
      era: storeEraRupiah,
      operatorId: me?.id ?? '',
      operatorName: me?.name ?? '',
      openingFloatRp: openingFloat,
    );
    final next = [..._shifts, shift];
    await _shiftStore.save(next);
    if (me != null) {
      await _auditStore.append(
        operator: me,
        action: StoreAuditAction.shiftOpen,
      );
    }
    if (!mounted) return;
    setState(() {
      _shifts = next;
      _openShift = shift;
    });
  }

  /// Posisi tunai laci untuk [shift] dari [records]: modal
  /// awal + tunai yang diterapkan ke tagihan dalam jendela
  /// shift (non-tunai tidak ikut — permintaan NUX 5 Nov
  /// 2026).
  ({int cashSalesRp, int positionRp}) _shiftCashPosition(
    StoreShift shift,
    List<CompletedOrder> records,
  ) {
    var cashSales = 0;
    for (final record in records) {
      if (!record.isRupiahEra || record.isVoid) continue;
      if (!shift.containsTime(record.time)) continue;
      cashSales += cashAppliedRpOf(record);
    }
    return (
      cashSalesRp: cashSales,
      positionRp: shift.openingFloatRp + cashSales,
    );
  }

  /// Blok teks posisi tunai untuk dialog konfirmasi tutup
  /// shift: Modal, tunai terjual, posisi terakhir di laci.
  Widget _cashPositionText(
    BuildContext ctx,
    StoreShift shift,
    List<CompletedOrder> records,
  ) {
    final l10n = ctx.l10n;
    final pos = _shiftCashPosition(shift, records);
    return Text(
      '${l10n.storeReportOpeningFloat}: Rp${_fmtRp(shift.openingFloatRp)}\n'
      '${l10n.storeReportCash}: Rp${_fmtRp(pos.cashSalesRp)}\n'
      '${l10n.storeReportCashPosition}: Rp${_fmtRp(pos.positionRp)}',
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    );
  }

  /// Tutup shift. Terhalang sesaat selama penerbitan poin
  /// berjalan (supaya status record tidak berpacu dengan
  /// penutupan). Sesudah bersih, tutup berhasil dan laporan
  /// shift yang baru ditutup ditawarkan.
  Future<void> _requestCloseShift() async {
    final shift = _openShift;
    if (shift == null) return;
    final l10n = context.l10n;
    if (_issuing) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.storeCloseShiftBlocked)));
      return;
    }
    // Record untuk posisi tunai di dialog konfirmasi.
    final records = await _historyStore.load();
    if (!mounted) return;
    if (_heldOrders.isNotEmpty) {
      // Peringatan khusus (keputusan NUX 3 Nov 2026): masih ada
      // pesanan ditahan yang BELUM dibayar — kasir harus sadar
      // sebelum menutup shift. Pesanan ditahan tidak ikut
      // tertutup/terhapus: ia tetap tersimpan dan bisa
      // dilanjutkan di shift berikutnya. Dialog ini merangkap
      // konfirmasi tutup pada jalur ini.
      final heldTotal = _heldOrders.fold(0, (sum, h) => sum + h.grandTotalRp);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.palette.card,
          title: Text(l10n.storeCloseShiftHeldTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.storeCloseShiftHeldBody(
                  _heldOrders.length,
                  'Rp${_fmtRp(heldTotal)}',
                ),
              ),
              const SizedBox(height: 12),
              _cashPositionText(ctx, shift, records),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.storeBack),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.storeCloseShiftHeldConfirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _performCloseShift(shift);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.storeCloseShiftConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.storeCloseShiftConfirmBody),
            const SizedBox(height: 12),
            _cashPositionText(ctx, shift, records),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.storeShiftClose),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _performCloseShift(shift);
  }

  /// Susun ringkasan shift tertutup & kirim ke Telegram
  /// owner (Bot API, tanpa server perantara). Isi = angka
  /// laporan shift yang sama: periode, kasir, invoice,
  /// income, per metode, modal & posisi tunai, VOID, order
  /// ditahan, poin. Snack memberi tahu hasil kirimnya.
  Future<void> _sendShiftReportTelegram(StoreShift closed) async {
    final l10n = context.l10n;
    final records = await _historyStore.load();
    final summary = aggregateShiftSales(
      records,
      from: closed.openedAt,
      to: closed.windowEnd(DateTime.now()),
    );
    final pos = _shiftCashPosition(closed, records);
    final heldInWindow = _heldOrders
        .where(
          (h) =>
              !h.heldAt.isBefore(closed.openedAt) &&
              h.heldAt.isBefore(closed.windowEnd(DateTime.now())),
        )
        .toList();
    final lines = <String>[
      '📊 ${l10n.storeReportSummaryTitle} — '
          '${_settings.storeName.isEmpty ? l10n.storeMode : _settings.storeName}',
      formatShiftPeriod(
        openedAt: closed.openedAt,
        closedAt: closed.closedAt,
        locale: l10n.localeName.startsWith('en') ? 'en' : 'id',
        stillOpenWord: l10n.storeShiftStillOpen,
      ),
      if (closed.operatorName.isNotEmpty)
        '${l10n.storeReceiptCashier}: ${closed.operatorName}',
      '${l10n.storeReportInvoices}: ${summary.invoiceCount}',
      '${l10n.storeReportIncome}: Rp${_fmtRp(summary.incomeRp)}',
      for (final entry in summary.methodTotalsRp.entries)
        '${entry.key == payMethodCash ? l10n.storeCash : entry.key}: '
            'Rp${_fmtRp(entry.value)}',
      '${l10n.storeReportOpeningFloat}: Rp${_fmtRp(closed.openingFloatRp)}',
      '${l10n.storeReportCashPosition}: Rp${_fmtRp(pos.positionRp)}',
      'VOID: ${summary.voids.count}',
      '${l10n.storeReportHeldInfo}: ${heldInWindow.length} '
          '(Rp${_fmtRp(heldInWindow.fold(0, (s, h) => s + h.grandTotalRp))})',
      if (summary.pointsIssued > 0 || summary.pointsRedeemed > 0)
        '${l10n.storeReportPointsIssued}: ${summary.pointsIssued} • '
            '${l10n.storeReportPointsRedeemed}: ${summary.pointsRedeemed}',
    ];
    final sent = await sendTelegramMessage(
      botToken: _settings.telegramBotToken,
      chatId: _settings.telegramChatId,
      text: lines.join('\n'),
    );
    if (!mounted) return;
    _snack(sent ? l10n.storeTelegramSent : l10n.storeTelegramFailed);
  }

  /// Eksekusi tutup shift sesudah semua pagar & konfirmasi
  /// lolos: simpan shift tertutup, lalu tawarkan laporannya.
  Future<void> _performCloseShift(StoreShift shift) async {
    final l10n = context.l10n;
    final closed = shift.close(DateTime.now());
    final next = [
      for (final s in _shifts) s == shift ? closed : s,
    ];
    await _shiftStore.save(next);
    final me = _operator;
    if (me != null) {
      await _auditStore.append(
        operator: me,
        action: StoreAuditAction.shiftClose,
      );
    }
    if (!mounted) return;
    setState(() {
      _shifts = next;
      _openShift = null;
    });
    // Kirim laporan ke Telegram owner bila dikonfigurasi
    // (permintaan NUX 5 Nov 2026): berjalan di latar, hasil
    // diberitahukan lewat snack — kegagalannya tidak
    // mengubah fakta shift yang sudah tertutup.
    if (_settings.telegramConfigured) {
      _sendShiftReportTelegram(closed);
    }
    final view = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.storeShiftClosedTitle),
        content: Text(l10n.storeShiftClosedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.storeLater),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.storeViewReport),
          ),
        ],
      ),
    );
    if (view == true && mounted) _openShiftReport(closed);
  }

  /// Apakah shift ini "milik" operator sesi untuk keperluan
  /// laporan (keputusan NUX (b): kasir hanya melihat laporan
  /// shift-nya sendiri)? Owner melihat semua; shift warisan
  /// tanpa stempel operator dianggap milik siapa pun yang
  /// sedang bertugas (ia lahir sebelum ada peran).
  bool _isOwnShift(StoreShift shift) {
    final me = _operator;
    if (me == null) return false;
    if (me.isOwner) return true;
    return shift.operatorId.isEmpty || shift.operatorId == me.id;
  }

  Future<void> _openShiftReport(StoreShift shift) async {
    if (!_isOwnShift(shift) &&
        !await _requireAdminApproval('report:${shift.openedAt}')) {
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreShiftReportScreen.forShift(shift),
      ),
    );
  }

  Future<void> _pickDayReport() async {
    // Laporan per tanggal melintasi shift & operator: khusus
    // owner; kasir wajib persetujuan PIN admin (keputusan (b)).
    if (!(_operator?.isOwner ?? false) &&
        !await _requireAdminApproval('report:day')) {
      return;
    }
    if (!mounted) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2025, 1, 1),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreShiftReportScreen.forDay(picked),
      ),
    );
  }

  /// Pemilih laporan: shift berjalan, per tanggal, atau shift
  /// lampau dari daftar tersimpan.
  Future<void> _openReportChooser() async {
    final l10n = context.l10n;
    final closed = _shifts.where((s) => !s.isOpen).toList().reversed.toList();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                child: Text(
                  l10n.storeSalesReport,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_openShift != null)
                ListTile(
                  leading: const Icon(Icons.play_circle_outline_rounded),
                  title: Text(l10n.storeReportCurrentShift),
                  subtitle: Text(
                    formatShiftPeriod(
                      openedAt: _openShift!.openedAt,
                      closedAt: null,
                      locale: _reportLocale,
                      stillOpenWord: l10n.storeShiftStillOpen,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openShiftReport(_openShift!);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: Text(l10n.storeReportByDate),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickDayReport();
                },
              ),
              if (closed.isNotEmpty) ...[
                const Divider(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
                  child: Text(
                    l10n.storeReportPastShifts,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final s in closed)
                  ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(
                      formatShiftPeriod(
                        openedAt: s.openedAt,
                        closedAt: s.closedAt,
                        locale: _reportLocale,
                        stillOpenWord: l10n.storeShiftStillOpen,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openShiftReport(s);
                    },
                  ),
              ],
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Pesanan
  // ------------------------------------------------------------------

  int get _grandTotal => orderGrandTotalRp(_lines, _orderDiscount);

  void _addProduct(CatalogItem item) {
    // Pengali adalah state keypad yang sama lintas mode
    // (Qty/Nominal): pengali yang sedang tertunda berlaku untuk
    // penambahan ini (ketuk katalog maupun hasil scan lewat
    // sini), lalu pengali kembali belum diatur (efektif ×1).
    final qty = _effectiveQty;
    setState(() {
      _lines = orderAddProduct(
        _lines,
        code: item.code,
        label: item.name,
        unitPriceRp: item.priceRp,
        category: item.category,
        defaultDiscount: item.defaultDiscount,
        qty: qty,
      );
      _qtyMultiplier = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          qty > 1
              ? context.l10n.storeProductAddedQty(item.name, qty)
              : context.l10n.storeProductAdded(item.name),
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // --- Keypad mode ganda: satu keypad fisik, dua sasaran ---

  void _pressKeypadDigit(int digit) {
    setState(() {
      if (_qtyKeypadMode) {
        _qtyMultiplier = qtyMultiplierPressDigit(_qtyMultiplier, digit);
      } else {
        _keypadRp = keypadPressDigit(_keypadRp, digit);
      }
    });
  }

  void _pressKeypadDoubleZero() {
    setState(() {
      if (_qtyKeypadMode) {
        _qtyMultiplier = qtyMultiplierPressDoubleZero(_qtyMultiplier);
      } else {
        _keypadRp = keypadPressDoubleZero(_keypadRp);
      }
    });
  }

  void _pressKeypadBackspace() {
    setState(() {
      if (_qtyKeypadMode) {
        _qtyMultiplier = keypadBackspace(_qtyMultiplier);
      } else {
        _keypadRp = keypadBackspace(_keypadRp);
      }
    });
  }

  void _pressKeypadClear() {
    setState(() {
      if (_qtyKeypadMode) {
        _qtyMultiplier = 0;
      } else {
        _keypadRp = 0;
      }
    });
  }

  void _addFreeAmount() {
    if (_keypadRp <= 0) return;
    // Judul kustom opsional: terisi → jadi label baris (untuk
    // barang yang belum terinput di katalog); kosong → label
    // baku "Item Bebas". Kolom judul dibersihkan sesudah baris
    // ditambahkan, sama seperti keypad kembali ke 0.
    final label = resolveFreeItemLabel(
      _freeTitleController.text,
      fallbackLabel: context.l10n.storeFreeItem,
    );
    // Pengali tertunda berlaku juga untuk item bebas (temuan
    // lapangan NUX 3 Nov 2026): baris ditambahkan sebanyak
    // pengali, lalu pengali kembali belum diatur (efektif ×1),
    // persis seperti jalur katalog.
    final qty = _effectiveQty;
    setState(() {
      _lines = orderAddFreeAmount(
        _lines,
        label: label,
        amountRp: _keypadRp,
        qty: qty,
      );
      _keypadRp = 0;
      _qtyMultiplier = 0;
    });
    _freeTitleController.clear();
  }

  /// Konfirmasi sebelum satu baris pesanan benar-benar dibuang —
  /// dipakai DUA jalan: tombol hapus baris, dan tombol minus yang
  /// akan membuat qty menjadi 0 (minus pada qty > 1 mengurangi
  /// langsung tanpa dialog, lihat _decrementLine). Dialog menyebut
  /// label itemnya; "Batal" membiarkan baris & qty apa adanya.
  Future<void> _confirmRemoveLine(int index) async {
    if (index < 0 || index >= _lines.length) return;
    final line = _lines[index];
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.storeRemoveLineTitle),
        content: Text(l10n.storeRemoveLineMessage(line.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.storeRemoveLineConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Cari ulang posisi baris yang sama (daftar bisa bergeser
    // selama dialog terbuka); tidak ketemu = sudah tidak ada,
    // tidak ada yang perlu dihapus.
    final idx = _lines.indexOf(line);
    if (idx < 0) return;
    setState(() => _lines = orderRemoveLine(_lines, idx));
  }

  /// Tombol minus pada baris pesanan: qty > 1 langsung berkurang
  /// satu; qty 1 berarti pengurangan berikutnya membuang baris —
  /// itu lewat konfirmasi _confirmRemoveLine dulu.
  void _decrementLine(int index) {
    if (index < 0 || index >= _lines.length) return;
    if (_lines[index].qty <= 1) {
      _confirmRemoveLine(index);
    } else {
      setState(() => _lines = orderChangeQty(_lines, index, -1));
    }
  }

  // ------------------------------------------------------------------
  // Pesanan ditahan (tamu bayar belakangan — keputusan NUX 3 Nov)
  // ------------------------------------------------------------------

  /// Bersihkan panel pesanan penuh TANPA perayaan — pola reset
  /// yang sama dengan sesudah penjualan lunas, dipakai sesudah
  /// pesanan ditahan.
  ///
  /// Ini CORONG tunggal berakhirnya pesanan berjalan dengan
  /// disengaja (lunas, dibatalkan/VOID, ditahan manual maupun
  /// otomatis) — karena itu slot draf background juga
  /// dibersihkan di sini: pesanan yang sudah berakhir tidak
  /// boleh bangkit lagi sebagai draf hantu.
  void _resetOrderPanel() {
    unawaited(_draftStore.clear());
    _lines = const [];
    _orderDiscount = null;
    _keypadRp = 0;
    _qtyMultiplier = 0;
    _searchQuery = '';
    _searchController.clear();
    _freeTitleController.clear();
  }

  /// Inti tahan pesanan — SATU jalur untuk tombol Tahan Pesanan
  /// manual maupun tahan otomatis saat keluar layar: susun
  /// entri lewat [buildHeldOrder], simpan ke daftar tahan yang
  /// sama, lalu bersihkan panel. Mengembalikan true hanya bila
  /// entri sungguh tersimpan — pagar keluar bergantung padanya:
  /// simpanan gagal berarti kasir TIDAK boleh keluar.
  Future<bool> _parkCurrentOrder() async {
    if (_lines.isEmpty) return false;
    final held = buildHeldOrder(
      now: DateTime.now(),
      lines: _lines,
      orderDiscount: _orderDiscount,
    );
    final next = [..._heldOrders, held];
    final saved = await _holdStore.saveChecked(next);
    if (!saved) return false;
    if (mounted) {
      setState(() {
        _heldOrders = next;
        _resetOrderPanel();
      });
    }
    return true;
  }

  /// Tahan pesanan berjalan: parkir apa adanya ke daftar tahan
  /// persisten, lalu panel dibersihkan untuk pelanggan berikut.
  Future<void> _holdCurrentOrder() async {
    final parked = await _parkCurrentOrder();
    if (!parked || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.storeHeldSaved)));
  }

  /// Pagar keluar layar Mode Toko (temuan NUX 4 Nov 2026),
  /// dipanggil PopScope bila pesanan berjalan terisi: tawarkan
  /// dialog — "Tetap di Sini" membatalkan keluar (pesanan utuh
  /// di layar); "Tahan & Keluar" menahan pesanan lewat jalur
  /// yang sama persis dengan tahan manual, lalu keluar.
  /// Simpanan tahan yang GAGAL membatalkan keluar: kasir tetap
  /// di layar dengan pesan, pesanannya tidak hilang.
  Future<void> _confirmExitWithOpenOrder() async {
    if (storeExitDecisionFor(_lines) == StoreExitDecision.leaveFreely) {
      Navigator.of(context).pop();
      return;
    }
    final l10n = context.l10n;
    final holdAndLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.storeExitHoldTitle),
        content: Text(l10n.storeExitHoldBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.storeExitStay),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.storeExitHoldLeave),
          ),
        ],
      ),
    );
    if (holdAndLeave != true || !mounted) return;
    final parked = await _parkCurrentOrder();
    if (!mounted) return;
    if (parked) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.storeExitHoldFailed)));
    }
  }

  /// Ringkasan satu entri tahan untuk daftar & dialog: label
  /// baris pertama, ditambah "+sisa baris" bila lebih dari satu.
  String _heldSummary(HeldOrder held) {
    if (held.lines.isEmpty) return '';
    final first = held.lines.first.label;
    return held.lines.length == 1
        ? first
        : '$first +${held.lines.length - 1}';
  }

  /// Lembar daftar pesanan ditahan: ketuk entri = Lanjutkan
  /// (muat kembali persis jadi pesanan berjalan), ikon hapus =
  /// buang permanen lewat konfirmasi.
  Future<void> _openHeldOrders() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final l10n = ctx.l10n;
          // Susunan lembar seperti Kelola Katalog (perbaikan
          // ListView yang sama, persetujuan NUX 9 Nov 2026):
          // tinggi dibatasi 75% layar, judul diam di atas,
          // daftar entri ListView yang bergeser sendiri —
          // susunan kolom utuh lama membuat atas lembar
          // terpotong bila pesanan ditahan banyak.
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                    child: Text(
                      l10n.storeHeldTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _heldOrders.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                            child: Text(
                              l10n.storeHeldEmpty,
                              style: TextStyle(
                                fontSize: 13,
                                color: ctx.palette.muted,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _heldOrders.length,
                            itemBuilder: (ctx, i) {
                              final held = _heldOrders[i];
                              return ListTile(
                                leading: const Icon(
                                  Icons.pause_circle_outline_rounded,
                                ),
                                title: Text(
                                  _heldSummary(held),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  l10n.storeHeldEntryMeta(
                                    _receiptTime(held.heldAt),
                                    held.totalQty,
                                    'Rp${_fmtRp(held.grandTotalRp)}',
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 21,
                                  ),
                                  onPressed: () async {
                                    final removed =
                                        await _confirmDeleteHeld(held);
                                    if (removed) setSheet(() {});
                                  },
                                ),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _resumeHeldOrder(held);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Lanjutkan satu pesanan ditahan: muat kembali persis
  /// (baris + diskon order) jadi pesanan berjalan dan keluarkan
  /// dari daftar tahan. HANYA bila pesanan berjalan kosong —
  /// selain itu kasir disuruh menahan/menyelesaikan dulu yang
  /// berjalan, supaya dua pesanan tidak pernah tercampur.
  Future<void> _resumeHeldOrder(HeldOrder held) async {
    final l10n = context.l10n;
    if (_lines.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.storeHeldResumeBlocked)));
      return;
    }
    final next = [for (final h in _heldOrders) if (h.id != held.id) h];
    await _holdStore.save(next);
    if (!mounted) return;
    setState(() {
      _heldOrders = next;
      _lines = List.of(held.lines);
      _orderDiscount = held.orderDiscount;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.storeHeldResumed)));
  }

  /// Konfirmasi hapus satu entri tahan (pola dialog konfirmasi
  /// yang sama dengan hapus baris). Mengembalikan true bila
  /// entri sungguh terhapus.
  Future<bool> _confirmDeleteHeld(HeldOrder held) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.storeDeleteHeldTitle),
        content: Text(l10n.storeDeleteHeldMessage(_heldSummary(held))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.storeRemoveLineConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    final next = [for (final h in _heldOrders) if (h.id != held.id) h];
    await _holdStore.save(next);
    if (!mounted) return false;
    setState(() => _heldOrders = next);
    return true;
  }

  void _clearCatalogSearch() {
    _searchController.clear();
    if (_searchQuery.isNotEmpty) setState(() => _searchQuery = '');
  }

  /// Pindai QR/barcode produk: kode yang terdaftar langsung masuk
  /// pesanan; kode yang belum terdaftar TIDAK diabaikan — kasir
  /// diberi tahu dan ditawari pendaftaran cepat dengan kode sudah
  /// terisi, dan sesudah tersimpan itemnya langsung masuk pesanan.
  Future<void> _scanProductCode() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (raw == null || !mounted) return;
    final code = raw.trim();
    if (code.isEmpty) return;
    final found = findCatalogItemByCode(_catalog, code);
    if (found != null) {
      _addProduct(found);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.storeCodeNotRegistered)),
    );
    await _openCatalogManager(initialCode: code);
    if (!mounted) return;
    final now = findCatalogItemByCode(_catalog, code);
    if (now != null) _addProduct(now);
  }

  Future<void> _openCatalogManager({String? initialCode}) async {
    // Katalog & harga adalah wilayah admin (keputusan (a)):
    // kasir wajib persetujuan PIN admin untuk membukanya.
    if (!await _requireAdminApproval('catalog')) return;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CatalogManagerSheet(
        initialItems: _catalog,
        initialCode: initialCode,
        onChanged: (items) {
          setState(() => _catalog = items);
          _catalogStore.save(items);
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // Diskon
  // ------------------------------------------------------------------

  Future<void> _editLineDiscount(int index) async {
    final result = await _showDiscountDialog(
      title: context.l10n.storeSetDiscount,
      current: _lines[index].discount,
    );
    if (result == null || !mounted) return;
    // Gerbang diskon Fase A: diskon baris BARU di atas ambang
    // pengaturan wajib persetujuan PIN admin sebelum diterapkan.
    if (!result.cleared && result.discount != null) {
      final line = _lines[index];
      final discountRp = discountAmountFor(
        line.unitPriceRp * line.qty,
        result.discount,
      );
      if (discountExceedsAdminThreshold(
            discountRp: discountRp,
            baseRp: line.unitPriceRp * line.qty,
            thresholdPercent: _settings.adminDiscountThresholdPercent,
          ) &&
          !await _requireAdminApproval('discount:line')) {
        return;
      }
      if (!mounted) return;
    }
    setState(() {
      _lines = orderSetLineDiscount(
        _lines,
        index,
        result.cleared ? null : result.discount,
      );
    });
  }

  /// Edit catatan satu baris pesanan: dialog teks singkat;
  /// simpan menerapkan teks sesudah trim (kosong = catatan
  /// dihapus). Baris dicari ulang sesudah dialog (pola
  /// _confirmRemoveLine) supaya aman dari pergeseran daftar.
  Future<void> _editLineNote(int index) async {
    if (index < 0 || index >= _lines.length) return;
    final line = _lines[index];
    final l10n = context.l10n;
    final controller = TextEditingController(text: line.note);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.storeLineNoteTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: line.label,
            filled: true,
            fillColor: ctx.palette.cardAlt,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          if (line.note.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: Text(l10n.storeClearNote),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.storeSaveNote),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null || !mounted) return;
    final idx = _lines.indexOf(line);
    if (idx < 0) return;
    setState(() => _lines = orderSetLineNote(_lines, idx, saved));
  }

  Future<void> _editOrderDiscount() async {
    final result = await _showDiscountDialog(
      title: context.l10n.storeOrderDiscount,
      current: _orderDiscount,
    );
    if (result == null || !mounted) return;
    // Gerbang diskon Fase A (sama seperti diskon baris, basis =
    // subtotal sesudah diskon baris).
    if (!result.cleared && result.discount != null) {
      final base = orderSubtotalRp(_lines);
      if (discountExceedsAdminThreshold(
            discountRp: discountAmountFor(base, result.discount),
            baseRp: base,
            thresholdPercent: _settings.adminDiscountThresholdPercent,
          ) &&
          !await _requireAdminApproval('discount:order')) {
        return;
      }
      if (!mounted) return;
    }
    setState(() => _orderDiscount = result.cleared ? null : result.discount);
  }

  /// Dialog atur diskon: persen ATAU nominal rupiah, dapat
  /// dihapus. Mengembalikan null bila dibatalkan (tanpa
  /// perubahan).
  Future<_DiscountEditResult?> _showDiscountDialog({
    required String title,
    required Discount? current,
  }) {
    return showDialog<_DiscountEditResult>(
      context: context,
      builder: (ctx) {
        var kind = current?.kind ?? DiscountKind.percent;
        final controller = TextEditingController(
          text: current == null ? '' : current.value.toString(),
        );
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              backgroundColor: ctx.palette.card,
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<DiscountKind>(
                    segments: [
                      ButtonSegment(
                        value: DiscountKind.percent,
                        label: Text(ctx.l10n.storeDiscountPercent),
                      ),
                      ButtonSegment(
                        value: DiscountKind.fixed,
                        label: Text(ctx.l10n.storeDiscountFixed),
                      ),
                    ],
                    selected: {kind},
                    onSelectionChanged: (s) => setLocal(() => kind = s.first),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: ctx.l10n.storeDiscountValue,
                      filled: true,
                      fillColor: ctx.palette.cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                if (current != null)
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(ctx, const _DiscountEditResult.cleared()),
                    child: Text(ctx.l10n.storeRemoveDiscount),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(ctx.l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    final value = int.tryParse(controller.text) ?? 0;
                    if (value <= 0) {
                      Navigator.pop(ctx, const _DiscountEditResult.cleared());
                      return;
                    }
                    Navigator.pop(
                      ctx,
                      _DiscountEditResult(
                        discount: kind == DiscountKind.percent
                            ? Discount.percent(value > 100 ? 100 : value)
                            : Discount.fixed(value),
                      ),
                    );
                  },
                  child: Text(ctx.l10n.storeApplyDiscount),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Penyelesaian pembayaran (halaman pembayaran)
  // ------------------------------------------------------------------

  /// Buka halaman pembayaran untuk pesanan berjalan. Hasilnya:
  /// null = kembali tanpa catatan (pesanan utuh); record VOID =
  /// pesanan dibatalkan kasir (catat, bersihkan panel); record
  /// lunas = penjualan tercatat (panel sukses + penerbitan poin).
  Future<void> _openPayment() async {
    if (_openShift == null || _lines.isEmpty) return;
    // Riwayat segar untuk JURNAL poin halaman pembayaran:
    // saldo penukaran pelanggan dihitung dari penerbitan &
    // penukaran yang sudah tercatat sampai saat ini.
    final journalOrders = await _historyStore.load();
    if (!mounted) return;
    final result = await Navigator.push<CompletedOrder>(
      context,
      MaterialPageRoute(
        builder: (_) => _StorePaymentPage(
          lines: List.of(_lines),
          orderDiscount: _orderDiscount,
          settings: _settings,
          lspService: widget.lspService,
          history: journalOrders,
        ),
      ),
    );
    if (result == null || !mounted) return;
    // Stempel operator Fase A: record tercatat atas nama
    // operator yang sedang login — lunas maupun VOID.
    final me = _operator;
    final result2 = me == null
        ? result
        : result.withOperator(operatorId: me.id, operatorName: me.name);
    if (result2.isVoid) {
      await _historyStore.append(
        result2.withReceiptMeta(
          shiftOpenedMs: _openShift?.openedAt.millisecondsSinceEpoch,
        ),
      );
      if (!mounted) return;
      setState(_resetOrderPanel);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.storeVoidRecorded)));
      return;
    }
    // Cap metadata struk TEPAT saat pencatatan, di dalam SATU
    // transaksi basis data (recordSettledSale): Bill No = nomor
    // urut lunas pada TANGGAL transaksi (lintas shift, dari
    // record tanggal itu; tampil INV<YYMMDD>-<urut 4 digit>),
    // Token No = nomor antrean harian dari penghitungnya (naik
    // sekali per transaksi lunas, hanya bila pengaturan toko
    // menampilkannya), tulis record + bersihkan draf — atomik,
    // tidak ada lagi penulisan setengah jadi antar-store.
    var settled = result2;
    final shift = _openShift;
    if (shift != null) {
      settled = await _historyStore.recordSettledSale(
        result2,
        stampMeta: true,
        issueToken: _settings.showTokenNumber,
        shiftOpenedMs: shift.openedAt.millisecondsSinceEpoch,
      );
    } else {
      await _historyStore.append(result2);
    }
    if (!mounted) return;
    setState(() {
      _session = _session.recordSale(settled.grandTotalRp);
      _saleRecord = settled;
      _received = true;
      _resetOrderPanel();
    });
    CoinAlert.play();
    _scrollToSaleCelebration();
    await _loadPendingIssues();
    _armCelebrationTimer();
  }

  /// Panel sukses boleh menutup otomatis HANYA bila tidak ada
  /// keputusan penerbitan poin yang menggantung — selama poin
  /// berstatus 'pending' pada penjualan ini, panel menunggu
  /// kasir (Terbitkan / Lewati / Selesai) supaya poin pelanggan
  /// tidak hilang terlupakan di antre.
  bool get _saleAwaitingIssueDecision =>
      _saleRecord != null &&
      _saleRecord!.pointsEarned > 0 &&
      _saleRecord!.pointsIssueStatus == issueStatusPending;

  /// Gulir halus ke bawah sampai panel perayaan penjualan
  /// yang baru tampil terlihat (permintaan NUX 4 Nov 2026).
  /// Panel perayaan ada di ujung panel status: pada tata
  /// letak HP ia tinggal di gulir halaman utama, pada tablet
  /// di gulir panel status — gulir controller mana pun yang
  /// sedang terpasang (yang lain tidak punya klien). Tahap
  /// kedua, satu frame sesudahnya, ensureVisible pada penanda
  /// panel menutup sisa kasus extent yang belum final pada
  /// frame pertama (mis. daftar poin tertunda ikut berubah).
  /// Hanya dipanggil pada transisi penjualan menjadi lunas —
  /// bukan saat VOID, tahan pesanan, atau membuka layar.
  void _scrollToSaleCelebration() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final controller in [
        _pageScrollController,
        _statusScrollController,
      ]) {
        if (!controller.hasClients) continue;
        controller.animateTo(
          controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final celebrationContext = _celebrationKey.currentContext;
        if (celebrationContext != null) {
          Scrollable.ensureVisible(
            celebrationContext,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _armCelebrationTimer() {
    _celebrationTimer?.cancel();
    if (_saleAwaitingIssueDecision) return;
    _celebrationTimer = Timer(receiveCelebrationDuration, _finishCelebration);
  }

  /// Tutup panel sukses: penjualan berikutnya bisa dimulai.
  /// (Baris pesanan sudah dibersihkan saat lunas tercatat.)
  void _finishCelebration() {
    if (!mounted) return;
    _celebrationTimer?.cancel();
    setState(() {
      _received = false;
      _saleRecord = null;
    });
  }

  // ------------------------------------------------------------------
  // Penerbitan poin (toko → pelanggan, sesudah rupiah lunas)
  // ------------------------------------------------------------------

  /// Terbitkan poin satu record: pindai kode dari ELNUX
  /// pelanggan (invoice Bolt11 sejumlah pas poin yang diperoleh,
  /// atau offer Bolt12-nya), lalu bayar lewat jalur kirim dompet
  /// yang sudah ada. Nominal kode WAJIB sama dengan poin yang
  /// diperoleh — kode bernominal lain ditolak, bukan dibayar
  /// sebagian. Hasil akhir ditunggu dari catatan node; sukses →
  /// record ditandai 'issued'; gagal/masih berjalan → tetap
  /// 'pending' (antre Poin Tertunda), penjualan rupiahnya tidak
  /// terpengaruh sama sekali.
  /// Sumber kode tujuan penerbitan poin: bila ada pelanggan
  /// tersimpan, kasir memilih — offer statis pelanggan dari
  /// daftar, atau pindai kode seperti biasa. Tanpa pelanggan
  /// tersimpan langsung ke pemindai (perilaku lama).
  Future<String?> _pickIssueCode() async {
    final customers = await StoreCustomerStore().loadAll();
    if (!mounted) return null;
    if (customers.isEmpty) {
      return Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const ScanScreen()),
      );
    }
    final l10n = context.l10n;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                child: Text(
                  l10n.storeCustomerChoose,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final customer in customers)
                ListTile(
                  leading: const Icon(
                    Icons.person_rounded,
                    color: Color(0xFF34D399),
                  ),
                  title: Text(
                    customer.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onTap: () => Navigator.pop(ctx, customer.offer),
                ),
              const Divider(height: 16),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner_rounded),
                title: Text(l10n.storeCustomerScan),
                onTap: () => Navigator.pop(ctx, '__scan__'),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return null;
    if (picked == '__scan__') {
      return Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (_) => const ScanScreen()),
      );
    }
    return picked;
  }

  Future<void> _issuePoints(CompletedOrder record) async {
    if (_issuing || record.pointsEarned <= 0) return;
    final l10n = context.l10n;
    final raw = await _pickIssueCode();
    if (raw == null || !mounted) return;
    final code = raw.trim();
    if (code.isEmpty) return;
    // Offer penerima (bila kode yang dipindai adalah offer
    // Bolt12): dicatat ke record saat penerbitan sukses sebagai
    // kunci jurnal poin pelanggan. Invoice sekali pakai tidak
    // memberi identitas jurnal (null).
    String? recipientOffer;
    final amountMsat = BigInt.from(record.pointsEarned) * BigInt.from(1000);
    setState(() => _issuing = true);
    try {
      final PaymentId paymentId;
      if (code.startsWith('lno1')) {
        final info = parseOfferInfo(code);
        if (info == null || info.isExpiredAt(DateTime.now())) {
          _snack(l10n.storeIssueInvalidCode);
          return;
        }
        recipientOffer = normalizePointsOffer(code);
        if (info.isFixedAmount) {
          if (info.amountMsat != amountMsat) {
            _snack(l10n.storeIssueAmountMismatch);
            return;
          }
          paymentId = await widget.lspService.payOffer(code);
        } else {
          paymentId = await widget.lspService.payOfferUsingAmount(
            code,
            amountMsat,
          );
        }
      } else {
        final amount = parseBolt11AmountMsat(code);
        if (amount == null) {
          _snack(l10n.storeIssueInvalidCode);
          return;
        }
        if (amount != amountMsat) {
          _snack(l10n.storeIssueAmountMismatch);
          return;
        }
        paymentId = await widget.lspService.payInvoice(code);
      }
      final status = await widget.lspService.waitForPaymentOutcome(paymentId);
      if (!mounted) return;
      if (status == PaymentStatus.succeeded) {
        final updated = record.withIssueStatus(
          issueStatusIssued,
          issueHashHex: paymentIdHex(paymentId),
          recipientOffer: recipientOffer,
        );
        await _historyStore.replace(updated);
        if (!mounted) return;
        if (_saleRecord?.id == updated.id) {
          setState(() => _saleRecord = updated);
        }
        await _loadPendingIssues();
        _snack(
          recipientOffer == null
              ? l10n.storeIssueInvoiceNote
              : l10n.storePointsIssuedOk,
        );
        _armCelebrationTimer();
      } else if (status == PaymentStatus.failed) {
        _snack(l10n.storeIssueFailed);
      } else {
        _snack(l10n.storeIssueStillPending);
      }
    } catch (e) {
      if (!mounted) return;
      _snack(
        friendlyError(
          e,
          fallback: l10n.storeIssueFailed,
          l10n: l10n,
        ),
      );
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------
  // Antre poin tertunda
  // ------------------------------------------------------------------

  /// Lembar antre "Poin Tertunda": penjualan yang poinnya belum
  /// diterbitkan. Per entri: Terbitkan (pindai & bayar ulang —
  /// alur yang sama dengan panel sukses) atau Batal Terbit
  /// (tandai 'waived' lewat konfirmasi; record penjualan tetap).
  Future<void> _openPendingIssues() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final l10n = ctx.l10n;
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                    child: Text(
                      l10n.storePendingTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_pendingIssues.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                      child: Text(
                        l10n.storePendingEmpty,
                        style: TextStyle(
                          fontSize: 13,
                          color: ctx.palette.muted,
                        ),
                      ),
                    )
                  else
                    for (final record in _pendingIssues)
                      ListTile(
                        leading: const Icon(Icons.loyalty_outlined),
                        title: Text(
                          l10n.storePointsEarnedLine(record.pointsEarned),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          l10n.storePendingEntryMeta(
                            _receiptTime(record.time),
                            'Rp${_fmtRp(record.grandTotalRp)}',
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: _issuing
                                  ? null
                                  : () async {
                                      Navigator.pop(ctx);
                                      await _issuePoints(record);
                                    },
                              child: Text(l10n.storePendingIssue),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () async {
                                final waived =
                                    await _confirmWaiveIssue(record);
                                if (waived) setSheet(() {});
                              },
                            ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Konfirmasi "Batal Terbit" satu entri antre: poin memang
  /// TIDAK jadi diterbitkan; record penjualannya tetap tercatat.
  Future<bool> _confirmWaiveIssue(CompletedOrder record) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.storePendingWaiveTitle),
        content: Text(
          l10n.storePendingWaiveBody(
            'Rp${_fmtRp(record.grandTotalRp)}',
            _receiptTime(record.time),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.storePendingWaive),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    await _historyStore.replace(
      record.withIssueStatus(issueStatusWaived),
    );
    if (!mounted) return false;
    if (_saleRecord?.id == record.id) {
      setState(
        () => _saleRecord = record.withIssueStatus(issueStatusWaived),
      );
    }
    await _loadPendingIssues();
    _snack(l10n.storePendingWaived);
    return true;
  }

  // ------------------------------------------------------------------
  // Struk
  // ------------------------------------------------------------------

  /// Label struk dari bahasa aplikasi — dipakai bersama oleh
  /// cetak kertas, pratinjau, dan gambar berbagi.
  StoreReceiptLabels _receiptLabels() {
    final l10n = context.l10n;
    return StoreReceiptLabels(
      customerLabel: l10n.storeReceiptCustomer,
      dateLabel: l10n.storeReceiptDate,
      billNoLabel: l10n.storeReceiptBillNo,
      tokenNoLabel: l10n.storeReceiptTokenNo,
      itemHeader: l10n.storeReceiptItemHeader,
      amountHeader: l10n.storeReceiptAmountHeader,
      discountLabel: l10n.storeReceiptLineDiscount,
      orderDiscountLabel: l10n.storeReceiptOrderDiscount,
      grandTotalLabel: l10n.storeReceiptGrandTotal,
      cashLabel: l10n.storeCash,
      changeLabel: l10n.storeChange,
      qrisLabel: l10n.storeQris,
      promoLabel: l10n.storeReceiptPromo,
      noteWord: l10n.storeNoteWord,
      reprintBanner: l10n.storeReceiptReprintBanner,
      reprintLabel: l10n.storeReceiptReprintLabel,
      cashierLabel: l10n.storeReceiptCashier,
      pointsDiscountLabel: (points) =>
          l10n.storeReceiptPointsDiscountLabel(_fmtRp(points)),
      pointsRuleText: (rate) => l10n.storeReceiptPointsRule(rate),
    );
  }

  /// Data struk penjualan dari model bersama: kop = nama toko
  /// (cadangan: kop pengaturan printer, lalu 'ELNUX'); footer =
  /// teks penutup pengaturan toko (cadangan: bawaan bahasa).
  /// TANPA baris saldo poin (aplikasi toko tidak tahu saldo
  /// dompet pelanggan — pedoman §4).
  StoreReceiptData _receiptData(
    CompletedOrder record,
    PrinterSettings printerSettings, {
    DateTime? reprintAt,
  }) {
    final shopName = _settings.storeName.isNotEmpty
        ? _settings.storeName
        : printerSettings.headerText.trim().isNotEmpty
        ? printerSettings.headerText.trim()
        : 'ELNUX';
    final footer = _settings.receiptFooterText.isNotEmpty
        ? _settings.receiptFooterText
        : context.l10n.storeReceiptFooterDefault;
    return buildStoreReceiptData(
      record: record,
      settings: _settings,
      shopName: shopName,
      footerText: footer,
      outletId: _outletId,
      reprintAt: reprintAt,
    );
  }

  /// Buka Daftar Laporan — khusus owner (permintaan NUX
  /// 8 Nov 2026): kasir wajib persetujuan PIN admin, pola yang
  /// sama dengan Pengaturan Toko. Isi daftarnya (Produk
  /// Terlaris dulu) akan bertambah mengikuti kebutuhan bisnis.
  Future<void> _openReports() async {
    if (!await _requireAdminApproval('reports')) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StoreReportsScreen()),
    );
  }

  /// Buka Pengaturan Toko — wilayah admin (keputusan (a)):
  /// kasir wajib persetujuan PIN admin. Pengaturan dibaca
  /// ulang sesudah kembali, seperti sebelumnya.
  Future<void> _openSettings() async {
    if (!await _requireAdminApproval('settings')) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StoreSettingsScreen()),
    );
    if (!mounted) return;
    final s = await _settingsStore.load();
    if (mounted) setState(() => _settings = s);
  }

  /// Buka Riwayat Penjualan: daftar transaksi selesai yang bisa
  /// ditinjau satu per satu — salinan struknya (cetak ulang /
  /// bagikan) selalu bertanda REPRINT.
  Future<void> _openSalesHistory() async {
    final printerSettings = await PrintService.loadSettings();
    if (!mounted) return;
    final labels = _receiptLabels();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreSalesHistoryScreen(
          receiptLabels: labels,
          receiptDataFor: (record, reprintAt) =>
              _receiptData(record, printerSettings, reprintAt: reprintAt),
          onVoidApproval: () => _requireAdminApproval('sale-void'),
          onVoidSale: _voidSettledSale,
          outletId: _outletId,
        ),
      ),
    );
    // Riwayat mungkin berubah dari layar itu (VOID penjualan
    // lunas) — segarkan antre poin tertunda yang membacanya.
    if (mounted) await _loadPendingIssues();
  }

  /// VOID penjualan LUNAS dari Riwayat Penjualan (Fase A):
  /// persetujuan PIN admin sudah lolos lewat gerbang layar
  /// riwayat; di sini record ditandai VOID (fakta penjualan
  /// utuh, status berbalik — laporan & jurnal poin otomatis
  /// mengecualikannya) dan kejadian + alasannya masuk audit.
  Future<void> _voidSettledSale(CompletedOrder record, String reason) async {
    final voided = record.markVoid();
    await _historyStore.replace(voided);
    final me = _operator;
    if (me != null) {
      final bill = record.billNo > 0
          ? formatBillNo(record.time, record.billNo, outletId: _outletId)
          : record.id;
      await _auditStore.append(
        operator: me,
        action: StoreAuditAction.saleVoid,
        detail: '$bill — $reason',
      );
    }
    if (!mounted) return;
    _snack(context.l10n.storeVoidDone);
  }

  /// Cetak struk penjualan terakhir ke printer thermal lewat
  /// metode khusus struk toko (layout contoh struk kasir).
  Future<void> _printLastReceipt() async {
    final record = _saleRecord;
    if (record == null) return;
    final printerSettings = await PrintService.loadSettings();
    if (!mounted) return;
    final elements = buildStoreReceiptElements(
      _receiptData(record, printerSettings),
      _receiptLabels(),
    );
    final outcome = await PrintService.printStoreReceipt(
      settings: printerSettings,
      elements: elements,
    );
    if (!mounted) return;
    _snack(printOutcomeMessage(context.l10n, outcome));
  }

  /// Bagikan struk penjualan terakhir sebagai gambar: buka
  /// pratinjau struk (kasir melihat struknya dulu), tombol
  /// Bagikan di dalamnya merender gambar JPG lewat share sheet.
  Future<void> _shareLastReceipt() async {
    final record = _saleRecord;
    if (record == null) return;
    final printerSettings = await PrintService.loadSettings();
    if (!mounted) return;
    final elements = buildStoreReceiptElements(
      _receiptData(record, printerSettings),
      _receiptLabels(),
    );
    await showDialog<void>(
      context: context,
      builder: (_) => StoreReceiptPreviewDialog(elements: elements),
    );
  }

  String _receiptTime(DateTime t) {
    final en = context.l10n.localeName.startsWith('en');
    const monthsId = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    const monthsEn = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final months = en ? monthsEn : monthsId;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]} ${t.year} $hh.$mm';
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  String _fmtRp(int rp) => formatRupiah(rp);

  @override
  Widget build(BuildContext context) {
    // Pagar keluar (temuan NUX 4 Nov 2026): selama pesanan
    // berjalan terisi, pop rute ini — tombol back AppBar maupun
    // back sistem — ditahan PopScope dan dialihkan ke dialog
    // tahan-otomatis (_confirmExitWithOpenOrder). Pesanan kosong
    // keluar bebas tanpa dialog. Rute di ATAS layar ini (halaman
    // pembayaran, pemindai, dll.) tidak terpengaruh: pop mereka
    // tidak menyentuh pagar rute ini, jadi kembali dari halaman
    // pembayaran ke Mode Toko tidak pernah memicu dialog.
    return PopScope(
      canPop: _lines.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_confirmExitWithOpenOrder());
      },
      child: Scaffold(
        // Mode landscape (dua panel, sudah login): AppBar
        // ditiadakan atas permintaan NUX 9 Nov 2026 supaya
        // ruang vertikal maksimal untuk daftar pesanan —
        // fungsi pentingnya (tombol kembali + chip operator)
        // pindah ke baris ramping di atas panel-panel
        // (_buildLandscapeSlimBar). Portrait & gerbang login
        // tetap memakai AppBar seperti biasa.
        appBar: _operator != null &&
                storeModeUsesTwoPanels(MediaQuery.of(context).size.width)
            ? null
            : AppBar(
          title: Text(context.l10n.storeMode),
          backgroundColor: Colors.transparent,
          elevation: 0,
          // Chip operator sesi (Fase A): nama + peran operator
          // yang sedang login; ketuk = ganti operator (kembali
          // ke gerbang login). Hanya tampil sesudah login.
          actions: [
            if (_operator != null)
              TextButton.icon(
                onPressed: _switchOperator,
                icon: const Icon(Icons.person_rounded, size: 19),
                label: Text(
                  '${_operator!.name} · ${_operator!.isOwner ? context.l10n.storeOperatorRoleOwner : context.l10n.storeOperatorRoleCashier}',
                ),
              ),
          ],
        ),
        // Gerbang operator Fase A: belum login → badan layar
        // adalah panel login / pembuatan owner pertama; tidak
        // ada jalur menyusun pesanan sebelum sesi dimulai.
        body: _operator == null
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                child: StoreOperatorGate(
                  operatorStore: _operatorStore,
                  auditStore: _auditStore,
                  onExit: () => Navigator.of(context).pop(),
                  onLoggedIn: (op) {
                    if (mounted) setState(() => _operator = op);
                  },
                ),
              )
            : LayoutBuilder(
        builder: (context, constraints) {
          if (storeModeUsesTwoPanels(constraints.maxWidth)) {
            // Dua panel = mode LANDSCAPE tablet (desain
            // referensi NUX 8 Nov 2026): pesanan di kiri,
            // katalog grid di kanan — lihat _buildLandscapeCashier.
            // AppBar ditiadakan di mode ini; baris ramping di
            // atas panel membawa fungsi kembali + chip operator.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildLandscapeSlimBar(context),
                Expanded(child: _buildLandscapeCashier(context)),
              ],
            );
          }
          return SingleChildScrollView(
            controller: _pageScrollController,
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCashier(context),
                const SizedBox(height: 20),
                _buildStatusPanel(context),
              ],
            ),
          );
        },
        ),
      ),
    );
  }

  /// Keadaan "shift belum dibuka": panel kasir nonaktif, yang
  /// tampil hanya gerbang Buka Shift (penegasan alur NUX — tidak
  /// ada jalan menyusun/menyelesaikan pesanan di luar shift).
  Widget _buildShiftGate(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.palette.border),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.lock_clock_rounded,
                size: 44,
                color: Color(0xFF34D399),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.storeShiftNotOpen,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.storeShiftOpenHint,
                style: TextStyle(fontSize: 13, color: context.palette.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _openShiftAction,
                icon: const Icon(Icons.play_circle_rounded, size: 22),
                label: Text(
                  l10n.storeShiftOpen,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Katalog yang tampil di kasir: saringan cari lalu saringan
  /// kategori. Kategori tersimpan yang sudah tidak ada di
  /// katalog (produk terakhirnya terhapus) diperlakukan sebagai
  /// "semua" supaya grid tidak kosong tanpa sebab.
  List<CatalogItem> _visibleCatalog() {
    final searched = filterCatalogItems(_catalog, _searchQuery);
    final selected = _catalogCategory;
    final valid = selected != null &&
        catalogCategories(_catalog).contains(selected);
    return filterCatalogByCategory(searched, valid ? selected : null);
  }

  /// Baris chip saringan kategori (Semua + kategori katalog,
  /// urutan catalogCategories): pola tab kategori desain
  /// landscape referensi, dipakai di kedua mode layar.
  Widget _buildCategoryChips(BuildContext context) {
    final l10n = context.l10n;
    final categories = catalogCategories(_catalog);
    final selected = _catalogCategory != null &&
            categories.contains(_catalogCategory)
        ? _catalogCategory
        : null;
    Widget chip(String? value, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected == value,
        onSelected: (_) => setState(() => _catalogCategory = value),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(null, l10n.storeCategoryAll),
          for (final category in categories) chip(category, category),
        ],
      ),
    );
  }

  /// Baris judul katalog + tombol Kelola — dipakai layout portrait & landscape.
  Widget _buildCatalogHeaderRow(BuildContext context) {
    final l10n = context.l10n;
    // --- Katalog / item cepat + cari + scan ---
    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.storeCatalogTitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: () => _openCatalogManager(),
          child: Text(l10n.storeManageCatalog),
        ),
      ],
    );
  }

  /// Baris cari produk + tombol pindai kode — dipakai layout portrait & landscape.
  Widget _buildSearchRow(BuildContext context) {
    final l10n = context.l10n;
    // Cari produk (nama/kode) menyaring chip secara langsung;
    // tombol scan di sampingnya tetap jalur _scanProductCode:
    // kode terdaftar langsung masuk pesanan (qty +1 bila
    // barisnya sudah ada, dari orderAddProduct).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: l10n.storeSearchHint,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 19),
                      onPressed: _clearCatalogSearch,
                    ),
              filled: true,
              fillColor: context.palette.cardAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _scanProductCode,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Icon(Icons.qr_code_scanner_rounded, size: 22),
        ),
      ],
    );
  }

  /// Bagian keypad mode ganda (Qty | Nominal) — dipakai layout portrait & landscape.
  Widget _buildKeypadSection(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
      // --- Keypad mode ganda: Qty (bawaan) | Nominal ---
      SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: true,
            icon: const Icon(Icons.numbers_rounded, size: 18),
            label: Text(l10n.storeKeypadModeQty),
          ),
          ButtonSegment(
            value: false,
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: Text(l10n.storeKeypadModeAmount),
          ),
        ],
        selected: {_qtyKeypadMode},
        onSelectionChanged: (s) => setState(() => _qtyKeypadMode = s.first),
      ),
      const SizedBox(height: 12),
      if (_qtyKeypadMode) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.palette.cardAlt,
            borderRadius: BorderRadius.circular(16),
          ),
          // Angka pengali saja, rata tengah — tanpa awalan "×"
          // dan tanpa kata "Multiplier" (temuan lapangan NUX
          // 3 Nov 2026: tampilannya cukup angka).
          child: Text(
            '$_effectiveQty',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildKeypad(context),
        const SizedBox(height: 6),
        Text(
          l10n.storeQtyModeHint,
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        ),
      ] else ...[
        // --- Nominal bebas (keypad, rupiah) ---
        Text(
          l10n.storeFreeAmountLabel,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        // Judul kustom opsional untuk baris bebas ini — jalan
        // untuk barang/jasa yang belum terinput di katalog.
        // Kosong berarti label baku "Item Bebas".
        TextField(
          controller: _freeTitleController,
          decoration: InputDecoration(
            labelText: l10n.storeFreeTitleLabel,
            filled: true,
            fillColor: context.palette.cardAlt,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.palette.cardAlt,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Rp${_fmtRp(_keypadRp)}',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'Rp',
                style: TextStyle(
                  fontSize: 15,
                  color: context.palette.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Jumlah cepat pecahan rupiah umum.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final quick in const [
              1000,
              2000,
              5000,
              10000,
              20000,
              50000,
              100000,
            ])
              OutlinedButton(
                onPressed: () => setState(
                  () => _keypadRp = keypadQuickAdd(_keypadRp, quick),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  '+${_fmtRp(quick)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _buildKeypad(context),
        const SizedBox(height: 10),
        // Pengali tertunda ikut berlaku untuk item bebas —
        // tampilkan penanda kecilnya di sini bila > 1 supaya
        // kasir melihat jumlah yang akan ditambahkan, bukan
        // diam-diam mengejutkan di daftar pesanan.
        if (_effectiveQty > 1) ...[
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.palette.cardAlt,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                l10n.storeQtyBadge(_effectiveQty),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _keypadRp > 0 ? _addFreeAmount : null,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: Text(
            l10n.storeAddFreeItem,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
      ],
    );
  }

  /// Blok pesanan: judul + tahan, baris-baris, subtotal, diskon, total — dipakai layout portrait & landscape.
  Widget _buildOrderLinesBlock(BuildContext context) {
    final l10n = context.l10n;
    // Segmen pesanan dibungkus KARTU (permintaan NUX 9 Nov
    // 2026): dari baris judul Pesanan + tombol Ditahan sampai
    // baris Total — menandai segmen pesanan lebih tegas,
    // terpisah dari katalog/keypad di atas dan panel status
    // di bawahnya. Tombol bayar/tahan tetap di luar kartu.
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
      // --- Pesanan ---
      Row(
        children: [
          Expanded(
            child: Text(
              l10n.storeOrderTitle,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_heldOrders.isNotEmpty)
            TextButton.icon(
              onPressed: _openHeldOrders,
              icon: const Icon(Icons.pause_circle_outline_rounded, size: 19),
              label: Text(l10n.storeHeldBadge(_heldOrders.length)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (_lines.isEmpty)
        Text(
          l10n.storeOrderEmpty,
          style: TextStyle(fontSize: 12, color: context.palette.muted),
        )
      else ...[
        for (var i = 0; i < _lines.length; i++) _buildOrderLine(context, i),
        const Divider(height: 20),
        _summaryRow(
          context,
          l10n.storeSubtotal,
          'Rp${_fmtRp(orderSubtotalRp(_lines))}',
        ),
        InkWell(
          onTap: _editOrderDiscount,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _orderDiscount == null
                        ? l10n.storeOrderDiscount
                        : '${l10n.storeOrderDiscount} (${_discountBadge(_orderDiscount!)})',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.palette.label,
                    ),
                  ),
                ),
                Text(
                  orderDiscountAmountRp(_lines, _orderDiscount) > 0
                      ? '−Rp${_fmtRp(orderDiscountAmountRp(_lines, _orderDiscount))}'
                      : l10n.storeSetDiscount,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (orderTotalDiscountRp(_lines, _orderDiscount) > 0)
          _summaryRow(
            context,
            l10n.storeTotalDiscount,
            '−Rp${_fmtRp(orderTotalDiscountRp(_lines, _orderDiscount))}',
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.storeGrandTotal,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              'Rp${_fmtRp(_grandTotal)}',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
      ],
      ),
    );
  }

  /// Blok aksi pesanan: pesan galat + tombol Selesaikan Pembayaran + Tahan Pesanan — dipakai layout portrait & landscape.
  Widget _buildOrderActions(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
        ),
      ],
      const SizedBox(height: 14),
      ElevatedButton(
        onPressed: _lines.isNotEmpty ? _openPayment : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          l10n.storeCheckout,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 10),
      // Tahan pesanan (tamu bayar belakangan): parkir pesanan
      // berjalan ke daftar tahan persisten.
      OutlinedButton.icon(
        onPressed: _lines.isNotEmpty ? _holdCurrentOrder : null,
        icon: const Icon(Icons.pause_circle_outline_rounded, size: 20),
        label: Text(
          l10n.storeHoldOrder,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      ],
    );
  }

  Widget _buildCashier(BuildContext context) {
    if (_openShift == null) return _buildShiftGate(context);
    final l10n = context.l10n;
    final visibleCatalog = _visibleCatalog();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCatalogHeaderRow(context),
        const SizedBox(height: 6),
        _buildSearchRow(context),
        const SizedBox(height: 10),
        if (catalogCategories(_catalog).isNotEmpty) ...[
          _buildCategoryChips(context),
          const SizedBox(height: 10),
        ],
        if (_catalog.isEmpty)
          Text(
            l10n.storeCatalogEmpty,
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          )
        else if (visibleCatalog.isEmpty)
          Text(
            l10n.storeSearchNoResults,
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          )
        else
          // Portrait: pager kartu item ukuran tetap (2 kolom ×
          // maks 5 baris per halaman, geser untuk halaman
          // berikutnya) dalam kartu segmen — lihat _CatalogPager.
          _CatalogPager(
            items: visibleCatalog,
            resetKey: '$_searchQuery|$_catalogCategory|${_catalog.length}',
            priceText: (item) => 'Rp${_fmtRp(item.priceRp)}',
            badgeText: (item) => item.defaultDiscount == null
                ? null
                : '${l10n.storeDiscount} '
                      '${_discountBadge(item.defaultDiscount!)}',
            onTap: _addProduct,
          ),
        const SizedBox(height: 18),
        _buildKeypadSection(context),
        const SizedBox(height: 20),
        _buildOrderLinesBlock(context),
        _buildOrderActions(context),
      ],
    );
  }

  /// Grid tombol produk besar untuk panel katalog landscape
  /// (pola desain referensi NUX 8 Nov 2026): nama produk tebal
  /// di tengah + harga di bawahnya, target sentuh besar untuk
  /// tablet. Ketuk = tambah ke pesanan, sama seperti chip
  /// katalog portrait.
  Widget _buildProductGrid(BuildContext context, List<CatalogItem> visible) {
    final l10n = context.l10n;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisExtent: 96,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final item = visible[i];
        return Material(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _addProduct(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rp${_fmtRp(item.priceRp)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.defaultDiscount != null)
                    Text(
                      '${l10n.storeDiscount} '
                      '${_discountBadge(item.defaultDiscount!)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Layout kasir LANDSCAPE dua panel (desain referensi NUX
  /// 8 Nov 2026, searah pola tablet yang disetujui 2 Nov):
  /// kiri = pesanan (baris-baris + total, panel status di
  /// bawahnya) dengan tombol bayar/tahan menempel di dasar;
  /// kanan = katalog (cari + tab kategori + grid tombol besar)
  /// dengan keypad di bawahnya. Semua bloknya berbagi
  /// implementasi yang sama dengan layout portrait — yang
  /// berbeda hanya susunannya.
  /// Baris ramping pengganti AppBar di mode landscape
  /// (AppBar ditiadakan atas permintaan NUX 9 Nov 2026):
  /// tombol kembali (lewat maybePop — pagar PopScope pesanan
  /// belum selesai tetap berlaku), judul kecil, dan chip
  /// operator yang sama dengan yang dulu di AppBar. Tampil
  /// juga di atas gerbang Buka Shift, supaya kasir tetap
  /// bisa keluar / ganti operator dari sana.
  Widget _buildLandscapeSlimBar(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 21),
            onPressed: () => Navigator.of(context).maybePop(),
            visualDensity: VisualDensity.compact,
          ),
          Text(
            l10n.storeMode,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (_operator != null)
            TextButton.icon(
              onPressed: _switchOperator,
              icon: const Icon(Icons.person_rounded, size: 19),
              label: Text(
                '${_operator!.name} · ${_operator!.isOwner ? l10n.storeOperatorRoleOwner : l10n.storeOperatorRoleCashier}',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLandscapeCashier(BuildContext context) {
    if (_openShift == null) return _buildShiftGate(context);
    final l10n = context.l10n;
    final visibleCatalog = _visibleCatalog();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 4,
          // Panel kiri sepenuhnya untuk daftar pesanan +
          // panel status (permintaan NUX 9 Nov 2026): tombol
          // bayar/tahan sudah pindah ke sisi kanan, jadi ruang
          // geser pesanan memakai seluruh tinggi panel.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 2, 9, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildOrderLinesBlock(context),
                const SizedBox(height: 20),
                _buildStatusPanel(context),
              ],
            ),
          ),
        ),
        VerticalDivider(width: 1, color: context.palette.border),
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(9, 2, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCatalogHeaderRow(context),
                      const SizedBox(height: 6),
                      _buildSearchRow(context),
                      const SizedBox(height: 10),
                      if (catalogCategories(_catalog).isNotEmpty) ...[
                        _buildCategoryChips(context),
                        const SizedBox(height: 10),
                      ],
                      if (_catalog.isEmpty)
                        Text(
                          l10n.storeCatalogEmpty,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        )
                      else if (visibleCatalog.isEmpty)
                        Text(
                          l10n.storeSearchNoResults,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        )
                      else
                        _buildProductGrid(context, visibleCatalog),
                      const SizedBox(height: 18),
                      _buildKeypadSection(context),
                    ],
                  ),
                ),
              ),
              // Tombol Selesaikan Pembayaran + Tahan Pesanan di
              // sisi kanan (permintaan NUX 9 Nov 2026), menempel
              // di dasar panel katalog.
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 0, 18, 14),
                child: _buildOrderActions(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Panel status (kanan / bawah)
  // ------------------------------------------------------------------

  Widget _buildStatusPanel(BuildContext context) {
    if (_openShift == null) return _buildClosedStatusPanel(context);
    final l10n = context.l10n;
    final sale = _saleRecord;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildShiftCard(context),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_rounded, size: 19),
                label: Text(l10n.storeSettingsTitle),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StorePointRulesScreen(),
                  ),
                ),
                icon: const Icon(Icons.menu_book_rounded, size: 19),
                label: Text(l10n.storeRulesButton),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.palette.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: Color(0xFF34D399),
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.storeSessionTitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                    Text(
                      l10n.storeSessionSales(
                        _session.saleCount,
                        _fmtRp(_session.totalRp),
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_pendingIssues.isNotEmpty) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: _openPendingIssues,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.loyalty_rounded,
                    size: 20,
                    color: Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.storePendingBadge(_pendingIssues.length),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (_received && sale != null) ...[
          Center(
            key: _celebrationKey,
            child: AnimatedCheckmark(size: 84),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.storeSaleCompleted,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Rp${_fmtRp(sale.grandTotalRp)}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            sale.payMethod == payMethodCash
                ? '${l10n.storeCash} • Rp${_fmtRp(sale.cashReceivedRp)}'
                : sale.payMethod == payMethodQris
                ? l10n.storeQris
                : l10n.storeReceiptPromo,
            style: TextStyle(fontSize: 13, color: context.palette.muted),
            textAlign: TextAlign.center,
          ),
          if (sale.changeRp > 0)
            Text(
              '${l10n.storeChange} Rp${_fmtRp(sale.changeRp)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF34D399),
              ),
              textAlign: TextAlign.center,
            ),
          if (_settings.pointsEnabled && sale.pointsEarned > 0) ...[
            const SizedBox(height: 14),
            if (sale.pointsIssueStatus == issueStatusIssued)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 19,
                    color: Color(0xFF34D399),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      l10n.storePointsIssuedOk,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            else if (sale.pointsIssueStatus == issueStatusWaived)
              Text(
                l10n.storePendingWaived,
                style: TextStyle(fontSize: 13, color: context.palette.muted),
                textAlign: TextAlign.center,
              )
            else ...[
              Text(
                l10n.storePointsEarnedLine(sale.pointsEarned),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              if (_issuing)
                const Center(child: CircularProgressIndicator())
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _issuePoints(sale),
                        icon: const Icon(
                          Icons.qr_code_scanner_rounded,
                          size: 19,
                        ),
                        label: Text(l10n.storePointsIssueButton),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: _finishCelebration,
                      child: Text(l10n.storePointsSkip),
                    ),
                  ],
                ),
            ],
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _printLastReceipt,
                  icon: const Icon(Icons.print_rounded, size: 19),
                  label: Text(l10n.storePrintReceipt),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareLastReceipt,
                  icon: const Icon(Icons.share_rounded, size: 19),
                  label: Text(l10n.storeShareReceipt),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _finishCelebration,
                child: Text(l10n.storeDoneButton),
              ),
            ],
          ),
        ] else
          Text(
            l10n.storeIdleHint,
            style: TextStyle(fontSize: 13, color: context.palette.muted),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }

  /// Kartu shift berjalan: waktu buka, nomor shift, tombol
  /// Laporan Penjualan (pemilih yang sama seperti panel tertutup —
  /// laporan shift berjalan bisa dibuka kapan pun, tidak harus
  /// menunggu Tutup Shift), dan tombol Tutup Shift.
  Widget _buildShiftCard(BuildContext context) {
    final l10n = context.l10n;
    final shift = _openShift!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: Color(0xFF34D399),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.storeShiftOpenedAt(
                        _receiptTime(shift.openedAt),
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      l10n.storeShiftTitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _openReportChooser,
            icon: const Icon(Icons.assessment_rounded, size: 19),
            label: Text(l10n.storeSalesReport),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openReports,
            icon: const Icon(Icons.insights_rounded, size: 19),
            label: Text(l10n.storeReportsTitle),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openSalesHistory,
            icon: const Icon(Icons.receipt_long_rounded, size: 19),
            label: Text(l10n.storeSalesHistory),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _requestCloseShift,
            icon: const Icon(Icons.stop_circle_outlined, size: 19),
            label: Text(l10n.storeShiftClose),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Panel status saat shift tertutup: hanya pemilih laporan.
  Widget _buildClosedStatusPanel(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.storeSalesReport,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _openReportChooser,
          icon: const Icon(Icons.assessment_rounded, size: 19),
          label: Text(l10n.storeReportPastShifts),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _pickDayReport(),
          icon: const Icon(Icons.calendar_month_rounded, size: 19),
          label: Text(l10n.storeReportByDate),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openReports,
          icon: const Icon(Icons.insights_rounded, size: 19),
          label: Text(l10n.storeReportsTitle),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openSalesHistory,
          icon: const Icon(Icons.receipt_long_rounded, size: 19),
          label: Text(l10n.storeSalesHistory),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  /// Satu baris pesanan. Susunan memilih menurut lebar yang
  /// tersedia: baris tunggal klasik (lebar cukup) atau susunan
  /// bertumpuk untuk panel sempit — panel pesanan landscape
  /// hanya ±40% lebar layar, dan tombol-tombol + total baris
  /// klasik memakan ±300dp tetap, sehingga kolom nama terjepit
  /// sampai ±1 karakter (laporan uji NUX 9 Nov 2026).
  Widget _buildOrderLine(BuildContext context, int i) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 340
          ? _buildOrderLineWide(context, i)
          : _buildOrderLineNarrow(context, i),
    );
  }

  /// Kolom keterangan satu baris pesanan: nama, harga × qty,
  /// lencana diskon, catatan — dipakai kedua susunan.
  Widget _orderLineInfoColumn(BuildContext context, OrderLine line) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line.label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          'Rp${_fmtRp(line.unitPriceRp)} × ${line.qty}',
          style: TextStyle(
            fontSize: 12,
            color: context.palette.muted,
          ),
        ),
        if (line.discount != null)
          Text(
            '${l10n.storeDiscount} ${_discountBadge(line.discount!)}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF34D399),
              fontWeight: FontWeight.w600,
            ),
          ),
        if (line.note.isNotEmpty)
          Text(
            '${l10n.storeNoteWord}: ${line.note}',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: context.palette.muted,
            ),
          ),
      ],
    );
  }

  /// Tombol-tombol aksi satu baris pesanan (catatan, diskon,
  /// kurang, qty, tambah, hapus) — dipakai kedua susunan.
  List<Widget> _orderLineActions(BuildContext context, int i) {
    final line = _lines[i];
    return [
      IconButton(
        icon: Icon(
          line.note.isEmpty
              ? Icons.note_add_outlined
              : Icons.note_alt_rounded,
          size: 19,
          color: line.note.isEmpty ? null : const Color(0xFF34D399),
        ),
        onPressed: () => _editLineNote(i),
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        icon: const Icon(Icons.percent_rounded, size: 19),
        onPressed: () => _editLineDiscount(i),
        visualDensity: VisualDensity.compact,
      ),
      IconButton(
        icon: const Icon(Icons.remove_circle_outline, size: 20),
        onPressed: () => _decrementLine(i),
        visualDensity: VisualDensity.compact,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          '${line.qty}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.add_circle_outline, size: 20),
        onPressed: () =>
            setState(() => _lines = orderChangeQty(_lines, i, 1)),
        visualDensity: VisualDensity.compact,
      ),
    ];
  }

  Widget _buildOrderLineWide(BuildContext context, int i) {
    final line = _lines[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _orderLineInfoColumn(context, line)),
          ..._orderLineActions(context, i),
          SizedBox(
            width: 86,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Rp${_fmtRp(line.lineTotalRp)}',
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            onPressed: () => _confirmRemoveLine(i),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Susunan bertumpuk baris pesanan untuk panel sempit
  /// (panel pesanan landscape): kontrol per item (catatan,
  /// diskon, qty −/+) di baris ATAS tiap item (arah NUX
  /// 9 Nov 2026), di bawahnya nama + keterangan selebar panel
  /// dengan total baris rata kanan. Nama mendapat hampir
  /// seluruh lebar panel, tidak lagi terjepit elemen tetap.
  Widget _buildOrderLineNarrow(BuildContext context, int i) {
    final line = _lines[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ..._orderLineActions(context, i),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                onPressed: () => _confirmRemoveLine(i),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _orderLineInfoColumn(context, line)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  'Rp${_fmtRp(line.lineTotalRp)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeypad(BuildContext context) {
    Widget key(String label, VoidCallback onTap) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Dua mode berbagi keypad fisik yang sama; digit masuk ke
    // buffer yang aktif (pengali qty / nominal rupiah) lewat
    // handler _pressKeypad* di state.
    return Column(
      children: [
        Row(
          children: [
            key('1', () => _pressKeypadDigit(1)),
            key('2', () => _pressKeypadDigit(2)),
            key('3', () => _pressKeypadDigit(3)),
          ],
        ),
        Row(
          children: [
            key('4', () => _pressKeypadDigit(4)),
            key('5', () => _pressKeypadDigit(5)),
            key('6', () => _pressKeypadDigit(6)),
          ],
        ),
        Row(
          children: [
            key('7', () => _pressKeypadDigit(7)),
            key('8', () => _pressKeypadDigit(8)),
            key('9', () => _pressKeypadDigit(9)),
          ],
        ),
        Row(
          children: [
            key('00', _pressKeypadDoubleZero),
            key('0', () => _pressKeypadDigit(0)),
            key('⌫', _pressKeypadBackspace),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: OutlinedButton(
                  onPressed: _pressKeypadClear,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(context.l10n.storeClearKeypad),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: context.palette.label),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _discountBadge(Discount d) => d.kind == DiscountKind.percent
      ? '${d.value}%'
      : '−Rp${_fmtRp(d.value)}';
}

/// Hasil dialog atur diskon: diskon baru, atau tandai dihapus.
class _DiscountEditResult {
  const _DiscountEditResult({this.discount}) : cleared = false;
  const _DiscountEditResult.cleared() : discount = null, cleared = true;
  final Discount? discount;
  final bool cleared;
}

/// Halaman Penyelesaian Pembayaran (Mode Toko v2). Pesanan
/// SELALU diselesaikan dalam rupiah: opsional penukaran poin
/// nusan lebih dulu (dibaca dari JURNAL penerbitan toko untuk
/// offer Bolt12 pelanggan yang dipindai; potongan Rp diterapkan
/// dari catatan itu — pelanggan tidak membayar apa pun saat
/// menukar), lalu sisa dibayar Tunai (dengan hitungan
/// kembalian) atau QRIS (catat saja) — atau Rp0 penuh (promosi /
/// tertutup poin seluruhnya). Mengembalikan [CompletedOrder]
/// lunas atau VOID; null = kembali tanpa catatan apa pun.
class _StorePaymentPage extends StatefulWidget {
  const _StorePaymentPage({
    required this.lines,
    required this.orderDiscount,
    required this.settings,
    required this.lspService,
    required this.history,
  });

  final List<OrderLine> lines;
  final Discount? orderDiscount;
  final StoreSettings settings;
  final LspService lspService;

  /// Riwayat penjualan toko saat halaman dibuka — bahan jurnal
  /// poin (saldo penukaran per offer pelanggan).
  final List<CompletedOrder> history;

  @override
  State<_StorePaymentPage> createState() => _StorePaymentPageState();
}

/// Satu baris pembayaran pada halaman penyelesaian: metode +
/// jumlah yang diketik kasir. Jumlah TUNAI adalah uang yang
/// diserahkan (boleh melebihi sisa — kelebihannya kembalian);
/// jumlah non-tunai harus tepat (tidak boleh melebihi sisa
/// tagihan). Alokasi jumlah TERAPAN per metode dihitung saat
/// penyelesaian di _settle.
class _PayEntry {
  String method;
  final TextEditingController controller = TextEditingController();
  int amountRp = 0;

  _PayEntry(this.method);

  bool get isCash => method == payMethodCash;
}

class _StorePaymentPageState extends State<_StorePaymentPage> {
  final _pointsController = TextEditingController();
  final _customerController = TextEditingController();

  /// Baris-baris pembayaran bill ini (split payment —
  /// permintaan NUX 5 Nov 2026). Mulai dari satu baris Tunai.
  final List<_PayEntry> _entries = [_PayEntry(payMethodCash)];
  // Penukaran poin model JURNAL: offer pelanggan yang terpindai
  // + saldo jurnalnya di toko ini. Klaim yang diterapkan
  // (_redeemApplied) mengunci _redeemPoints sebagai potongan;
  // debit jurnal baru tercatat pada record lunas di _settle.
  // Tidak ada invoice dan tidak ada pembayaran dari pelanggan.
  String? _redeemOffer;

  /// Nama pelanggan tersimpan yang offer-nya sedang dipakai
  /// (null bila offer datang dari pindai langsung).
  String? _redeemCustomerName;
  int _journalBalance = 0;
  bool _redeemApplied = false;
  int _redeemPoints = 0;
  String? _redeemError;

  /// Total yang sudah diketik kasir di semua baris bayar.
  int get _paidTotalRp => _entries.fold(0, (sum, e) => sum + e.amountRp);

  /// Total baris NON-tunai — tidak boleh melebihi sisa
  /// tagihan (non-tunai tidak mengenal kembalian).
  int get _nonCashTotalRp => _entries
      .where((e) => !e.isCash)
      .fold(0, (sum, e) => sum + e.amountRp);

  /// Penyelesaian sah: total menutup sisa tagihan dan bagian
  /// non-tunai tidak melampaui sisa (kelebihan hanya boleh
  /// berasal dari tunai = kembalian).
  bool get _canSettle =>
      _remainingRp > 0 &&
      _paidTotalRp >= _remainingRp &&
      _nonCashTotalRp <= _remainingRp;

  int get _changeRp => _paidTotalRp - _remainingRp;

  int get _dueBeforePoints =>
      orderDueRp(widget.lines, widget.orderDiscount);

  int get _pointsDiscountRp => _redeemApplied
      ? pointsDiscountRpFor(
          points: _redeemPoints,
          rateRpPerPoint: widget.settings.redeemRateRp,
          remainingRp: _dueBeforePoints,
          totalRp: _dueBeforePoints,
          maxPercent: widget.settings.maxRedeemPercent,
        )
      : 0;

  int get _remainingRp => _dueBeforePoints - _pointsDiscountRp;

  /// Plafon poin dari sisi belanja saja (nilai per poin &
  /// persentase maksimal dari total).
  int get _billCapPoints => maxRedeemablePoints(
    rateRpPerPoint: widget.settings.redeemRateRp,
    remainingRp: _dueBeforePoints,
    totalRp: _dueBeforePoints,
    maxPercent: widget.settings.maxRedeemPercent,
  );

  /// Batas tukar yang berlaku: plafon belanja DAN saldo jurnal
  /// pelanggan yang terpindai (0 sebelum ada offer).
  int get _maxPoints =>
      _billCapPoints < _journalBalance ? _billCapPoints : _journalBalance;

  int get _earnedPreview => widget.settings.pointsEnabled
      ? pointsEarnedFor(
          paidRp: _remainingRp,
          stepRp: widget.settings.earnStepRp,
          pointsPerStep: widget.settings.earnPointsPerStep,
        )
      : 0;

  @override
  void dispose() {
    _pointsController.dispose();
    for (final entry in _entries) {
      entry.controller.dispose();
    }
    _customerController.dispose();
    super.dispose();
  }

  /// Pemisah ribuan kolom nominal mengikuti locale aplikasi.
  String get _thousandsSep =>
      context.l10n.localeName == 'en' ? ',' : '.';

  // ---------------- Penukaran poin (jurnal toko) ----------------

  /// Pindai offer Bolt12 pelanggan dari ELNUX miliknya, lalu
  /// baca saldo jurnalnya dari riwayat toko. Penukaran model
  /// jurnal tidak meminta pembayaran apa pun dari pelanggan:
  /// hak potongan lahir dari penerbitan poin toko yang tercatat
  /// untuk offer ini (pointsJournalBalanceFor). Kode selain
  /// offer (mis. invoice sekali pakai) ditolak — invoice tidak
  /// membawa identitas jurnal yang bisa dipakai ulang.
  Future<void> _scanCustomerOffer() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (raw == null || !mounted) return;
    final code = raw.trim();
    final l10n = context.l10n;
    final info = code.toLowerCase().startsWith('lno1')
        ? parseOfferInfo(code)
        : null;
    if (info == null || info.isExpiredAt(DateTime.now())) {
      setState(() => _redeemError = l10n.storeRedeemNeedOffer);
      return;
    }
    _useRedeemOffer(normalizePointsOffer(code));
  }

  /// Pakai satu offer sebagai dasar penukaran (dari pindai
  /// atau dari pelanggan tersimpan): baca saldo jurnalnya dan
  /// reset klaim yang sedang disusun.
  void _useRedeemOffer(String offer, {String? customerName}) {
    setState(() {
      _redeemOffer = offer;
      _redeemCustomerName = customerName;
      // Pelanggan tersimpan yang dipilih untuk penukaran juga
      // mengisi kolom Nama Pelanggan halaman ini (permintaan NUX
      // 8 Nov 2026): nama yang tercatat pada pesanan lunas tidak
      // boleh mengandalkan kasir mengetik ulang nama yang sama.
      // Pindai langsung (tanpa nama) tidak menyentuh kolom.
      if (customerName != null) {
        _customerController.text = customerName;
      }
      _journalBalance = pointsJournalBalanceFor(widget.history, offer);
      _redeemApplied = false;
      _redeemPoints = 0;
      _redeemError = null;
      _pointsController.clear();
    });
  }

  /// Pilih pelanggan tersimpan untuk penukaran (alternatif
  /// memindai kode bayar pelanggan): offer pelanggan terpilih
  /// langsung menjadi dasar penukaran.
  Future<void> _chooseCustomerForRedeem() async {
    final customer = await showStoreCustomerPicker(
      context,
      subtitleFor: (c) => context.l10n.storeRedeemBalance(
        pointsJournalBalanceFor(widget.history, c.offer),
      ),
    );
    if (customer == null || !mounted) return;
    _useRedeemOffer(customer.offer, customerName: customer.name);
  }

  /// Terapkan klaim penukaran: kunci jumlah poin (dijepit ke
  /// batas gabungan saldo jurnal & plafon belanja); potongan
  /// rupiahnya dihitung _pointsDiscountRp. Belum ada catatan
  /// yang berubah di sini — debit jurnal tercatat nanti pada
  /// record lunas (_settle menulis offer penukar ke record),
  /// jadi mengurungkan klaim di halaman ini selalu aman.
  void _applyRedeem() {
    final l10n = context.l10n;
    var points = int.tryParse(_pointsController.text.trim()) ?? 0;
    if (points <= 0 || _maxPoints <= 0) {
      setState(() => _redeemError = l10n.storeRedeemInvalidPoints);
      return;
    }
    if (points > _maxPoints) {
      points = _maxPoints;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.storeRedeemClamped(_maxPoints))),
      );
    }
    setState(() {
      _redeemPoints = points;
      _redeemApplied = true;
      _redeemError = null;
    });
  }

  /// Urungkan klaim yang sudah diterapkan (offer & saldo jurnal
  /// tetap terbaca, kasir bisa menerapkan jumlah lain).
  void _undoRedeem() {
    setState(() {
      _redeemApplied = false;
      _redeemPoints = 0;
    });
  }

  // ---------------- Penyelesaian ----------------

  /// Selesaikan pembayaran dari baris-baris bayar saat ini:
  /// alokasikan jumlah TERAPAN per metode (non-tunai penuh
  /// lebih dulu, tunai menutup sisanya; kelebihan tunai =
  /// kembalian dan tidak tercatat sebagai pembayaran).
  /// Promosi Rp0 (sisa 0) menyelesaikan tanpa pembayaran.
  void _settle() {
    final now = DateTime.now();
    final payments = <OrderPayment>[];
    var tenderedCash = 0;
    if (_remainingRp > 0) {
      var left = _remainingRp;
      for (final entry in _entries) {
        if (entry.isCash) tenderedCash += entry.amountRp;
      }
      for (final entry in _entries.where((e) => !e.isCash)) {
        if (entry.amountRp <= 0) continue;
        payments.add(
          OrderPayment(method: entry.method, amountRp: entry.amountRp),
        );
        left -= entry.amountRp;
      }
      for (final entry in _entries.where((e) => e.isCash)) {
        if (entry.amountRp <= 0 || left <= 0) continue;
        final applied = entry.amountRp < left ? entry.amountRp : left;
        payments.add(OrderPayment(method: payMethodCash, amountRp: applied));
        left -= applied;
      }
    }
    final record = buildCompletedOrder(
      id: now.microsecondsSinceEpoch.toString(),
      time: now,
      lines: widget.lines,
      orderDiscount: widget.orderDiscount,
      paymentHashHex: null,
      payMethod: payments.isEmpty
          ? null
          : payments.length == 1
              ? payments.single.method
              : payMethodSplit,
      payments: payments,
      cashReceivedRp: tenderedCash,
      changeRp: _remainingRp > 0 && _changeRp > 0 ? _changeRp : 0,
      pointsRedeemed: _redeemApplied ? _redeemPoints : 0,
      pointsRedeemOffer: _redeemApplied ? _redeemOffer : null,
      pointsDiscountRp: _pointsDiscountRp,
      pointsEarned: _earnedPreview,
      pointsIssueStatus: _earnedPreview > 0
          ? issueStatusPending
          : issueStatusNone,
      customerName: _customerController.text,
    );
    Navigator.pop(context, record);
  }

  Future<void> _cancelOrder() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.storeVoidConfirmTitle),
        content: Text(l10n.storeVoidConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.storeCancelOrder),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final now = DateTime.now();
    Navigator.pop(
      context,
      buildCompletedOrder(
        id: now.microsecondsSinceEpoch.toString(),
        time: now,
        lines: widget.lines,
        orderDiscount: widget.orderDiscount,
        paymentHashHex: null,
        isVoid: true,
      ),
    );
  }

  /// Baris tunai pertama (dibuat bila belum ada) — sasaran
  /// kartu pecahan & tombol Uang Pas seperti perilaku lama.
  _PayEntry _cashEntry() {
    final existing = _entries.where((e) => e.isCash).firstOrNull;
    if (existing != null) return existing;
    final entry = _PayEntry(payMethodCash);
    _entries.insert(0, entry);
    return entry;
  }

  void _setEntryAmount(_PayEntry entry, int value) {
    entry.controller.text = formatRupiahInput(
      value,
      thousandsSep: _thousandsSep,
    );
    setState(() => entry.amountRp = value);
  }

  void _setCash(int value) => _setEntryAmount(_cashEntry(), value);

  /// Kartu pecahan: tambahkan pecahan ke uang diterima saat ini
  /// (akumulasi di atas ketikan manual maupun ketukan sebelumnya).
  void _addCash(int denom) => _setCash(
        cashAddDenomRp(currentRp: _cashEntry().amountRp, denomRp: denom),
      );

  /// Tambah baris bayar baru: metode pertama yang belum
  /// dipakai (Tunai selalu boleh walau sudah ada — digabung
  /// saat alokasi), terisi sisa yang belum tertutup.
  void _addEntry() {
    final used = _entries.map((e) => e.method).toSet();
    final next = widget.settings.paymentMethods
        .where((m) => !used.contains(m))
        .firstOrNull;
    final entry = _PayEntry(next ?? payMethodCash);
    final left = _remainingRp - _paidTotalRp;
    if (left > 0) {
      entry.amountRp = left;
      entry.controller.text = formatRupiahInput(
        left,
        thousandsSep: _thousandsSep,
      );
    }
    setState(() => _entries.add(entry));
  }

  void _removeEntry(_PayEntry entry) {
    if (_entries.length <= 1) return;
    entry.controller.dispose();
    setState(() => _entries.remove(entry));
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final due = _dueBeforePoints;
    final remaining = _remainingRp;
    // Tidak ada pembayaran berjalan yang perlu dijaga saat
    // keluar halaman: klaim jurnal baru tercatat bila pesanan
    // benar-benar dilunasi, jadi kembali kapan pun aman.
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.storePayTitle),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          // Ruang atas disamakan sisi lain (18) agar label melayang
          // field pertama (Nama Pelanggan) tidak tertutup AppBar.
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _customerController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: l10n.storeCustomerNameLabel,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  filled: true,
                  fillColor: context.palette.cardAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _paySummaryRow(
                context,
                l10n.storePayTotalLabel,
                'Rp${formatRupiah(due)}',
              ),
              if (_pointsDiscountRp > 0)
                _paySummaryRow(
                  context,
                  l10n.storeReceiptPointsDiscount(
                    _redeemPoints,
                    formatRupiah(_pointsDiscountRp),
                  ),
                  '−Rp${formatRupiah(_pointsDiscountRp)}',
                ),
              const Divider(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.storeGrandTotal,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    'Rp${formatRupiah(remaining)}',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (widget.settings.pointsEnabled && due > 0) ...[
                const SizedBox(height: 20),
                _buildRedeemSection(context),
              ],
              const SizedBox(height: 20),
              if (remaining == 0) ...[
                if (due == 0)
                  Text(
                    l10n.storePromoNote,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.palette.muted,
                    ),
                  ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _settle,
                  style: _settleButtonStyle(),
                  child: Text(
                    l10n.storeSettlePromo,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ] else ...[
                // Baris-baris pembayaran (split payment):
                // tiap baris = dropdown metode + kolom jumlah.
                // Kolom jumlah besar & tebal dengan format
                // ribuan saat mengetik (permintaan NUX).
                for (var i = 0; i < _entries.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: context.palette.cardAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: DropdownButton<String>(
                          value: _entries[i].method,
                          underline: const SizedBox.shrink(),
                          items: [
                            DropdownMenuItem(
                              value: payMethodCash,
                              child: Text(l10n.storeCash),
                            ),
                            for (final m in widget.settings.paymentMethods)
                              DropdownMenuItem(value: m, child: Text(m)),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _entries[i].method = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _entries[i].controller,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            RupiahAmountFormatter(
                              thousandsSep: _thousandsSep,
                            ),
                          ],
                          onChanged: (v) => setState(
                            () => _entries[i].amountRp =
                                parseRupiahAmount(v),
                          ),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: InputDecoration(
                            labelText: _entries[i].isCash
                                ? l10n.storeCashReceived
                                : l10n.storePayAmountLabel,
                            prefixText: 'Rp ',
                            filled: true,
                            fillColor: context.palette.cardAlt,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      if (_entries.length > 1)
                        IconButton(
                          onPressed: () => _removeEntry(_entries[i]),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 20),
                        ),
                    ],
                  ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addEntry,
                    icon: const Icon(Icons.add_circle_outline, size: 19),
                    label: Text(l10n.storeAddPayMethod),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Rp0'),
                      onPressed: () => _setCash(0),
                    ),
                    ActionChip(
                      label: Text(l10n.storeCashExact),
                      onPressed: () => _setCash(
                        remaining - _nonCashTotalRp < 0
                            ? 0
                            : remaining - _nonCashTotalRp,
                      ),
                    ),
                    for (final denom in const [
                      5000,
                      10000,
                      20000,
                      50000,
                      100000,
                    ])
                      ActionChip(
                        label: Text('+${formatRupiah(denom)}'),
                        onPressed: () => _addCash(denom),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_nonCashTotalRp > remaining)
                  Text(
                    l10n.storeNonCashOverNote,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.redAccent,
                    ),
                  )
                else if (_canSettle)
                  Text(
                    _changeRp > 0
                        ? '${l10n.storeChange} Rp${formatRupiah(_changeRp)}'
                        : l10n.storeCashExact,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF34D399),
                    ),
                  )
                else if (_paidTotalRp > 0)
                  Text(
                    l10n.storeCashShort(
                      formatRupiah(remaining - _paidTotalRp),
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.redAccent,
                    ),
                  ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _canSettle ? _settle : null,
                  style: _settleButtonStyle(),
                  child: Text(
                    l10n.storeSettle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (_earnedPreview > 0) ...[
                const SizedBox(height: 14),
                Text(
                  l10n.storePointsEarnedLine(_earnedPreview),
                  style: TextStyle(
                    fontSize: 13,
                    color: context.palette.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 22),
              const Divider(height: 1),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _cancelOrder,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                ),
                child: Text(l10n.storeCancelOrder),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _settleButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF10B981),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _paySummaryRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: context.palette.label),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildRedeemSection(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.storeRedeemTitle,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          if (_redeemApplied) ...[
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF34D399),
                  size: 22,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    l10n.storeRedeemApplied(
                      _redeemPoints,
                      formatRupiah(_pointsDiscountRp),
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _undoRedeem,
                child: Text(l10n.storeRedeemUndo),
              ),
            ),
          ] else if (_redeemOffer == null) ...[
            Text(
              l10n.storeRedeemHint,
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _scanCustomerOffer,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
              label: Text(l10n.storeRedeemScanOffer),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _chooseCustomerForRedeem,
              icon: const Icon(Icons.person_rounded, size: 19),
              label: Text(l10n.storeCustomerChoose),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ] else ...[
            if (_redeemCustomerName != null) ...[
              Text(
                '${l10n.storeCustomerTitle}: ${_redeemCustomerName!}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              l10n.storeRedeemBalance(_journalBalance),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if (_journalBalance <= 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.storeRedeemNoBalance,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.muted,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _pointsController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.storeRedeemPointsLabel,
                      filled: true,
                      fillColor: context.palette.cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Tombol Max (permintaan NUX 4 Nov 2026): isi
                // kolom dengan hak tukar penuh yang berlaku
                // (saldo jurnal dibatasi plafon tagihan).
                TextButton(
                  onPressed: _maxPoints > 0
                      ? () => _pointsController.text = '$_maxPoints'
                      : null,
                  child: const Text('Max'),
                ),
                const SizedBox(width: 2),
                ElevatedButton(
                  onPressed: _journalBalance > 0 ? _applyRedeem : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(l10n.storeRedeemApply),
                ),
              ],
            ),
            if (_maxPoints > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.storeRedeemMaxNote(_maxPoints),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.muted,
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _chooseCustomerForRedeem,
                  child: Text(l10n.storeCustomerChoose),
                ),
                TextButton(
                  onPressed: _scanCustomerOffer,
                  child: Text(l10n.storeRedeemScanAgain),
                ),
              ],
            ),
          ],
          if (_redeemError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _redeemError!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lembar kelola katalog: tambah / ubah / hapus item (harga
/// rupiah, kunci v2). Perubahan dilaporkan ke induk lewat
/// [onChanged] — induk yang menyimpan & menyegarkan chip
/// katalog. [initialCode] terisi saat dibuka dari hasil pindai
/// kode yang belum terdaftar: form tambah langsung terbuka
/// dengan kode itu terisi.
class _CatalogManagerSheet extends StatefulWidget {
  const _CatalogManagerSheet({
    required this.initialItems,
    required this.onChanged,
    this.initialCode,
  });

  final List<CatalogItem> initialItems;
  final String? initialCode;
  final ValueChanged<List<CatalogItem>> onChanged;

  @override
  State<_CatalogManagerSheet> createState() => _CatalogManagerSheetState();
}

class _CatalogManagerSheetState extends State<_CatalogManagerSheet> {
  late List<CatalogItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.initialItems);
    final code = widget.initialCode;
    if (code != null && code.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editItem(initialCode: code);
      });
    }
  }

  void _saveAll(List<CatalogItem> items) {
    setState(() => _items = items);
    widget.onChanged(items);
  }

  Future<void> _editItem({
    CatalogItem? existing,
    int? index,
    String? initialCode,
  }) async {
    final l10n = context.l10n;
    final existingDiscount = existing?.defaultDiscount;
    // Kode produk (keputusan NUX 8 Nov 2026): kode adalah kunci
    // input pesanan lewat pindai, jadi WAJIB selalu ada. Saat
    // TAMBAH, kolom terisi kode bawaan otomatis (atau kode hasil
    // pindai yang belum terdaftar) dan boleh diganti di dialog
    // ini saja. Saat UBAH produk yang sudah berkode, kolom
    // terkunci supaya identitas pindainya tidak bergeser
    // diam-diam. Produk warisan tanpa kode (dari era kode belum
    // ditegakkan) mendapat kode bawaan saat diubah dan kali itu
    // boleh diedit, supaya sesudah disimpan tidak ada lagi
    // produk tanpa kode.
    final codeLocked = existing != null && existing.code.isNotEmpty;
    final codeCtl = TextEditingController(
      text: codeLocked
          ? existing.code
          : (initialCode ?? suggestCatalogCode(_items)),
    );
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final priceCtl = TextEditingController(
      text: existing == null ? '' : existing.priceRp.toString(),
    );
    final categoryCtl = TextEditingController(text: existing?.category ?? '');
    DiscountKind? kind = existingDiscount?.kind;
    final discountCtl = TextEditingController(
      text: existingDiscount == null
          ? ''
          : existingDiscount.value.toString(),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            backgroundColor: ctx.palette.card,
            title: Text(
              existing == null ? l10n.storeAddProduct : l10n.storeEditProduct,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtl,
                    enabled: !codeLocked,
                    decoration: InputDecoration(
                      labelText: l10n.storeProductCode,
                      helperText: codeLocked
                          ? l10n.storeProductCodeLocked
                          : l10n.storeProductCodeHint,
                      filled: true,
                      fillColor: ctx.palette.cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtl,
                    decoration: InputDecoration(
                      labelText: l10n.storeProductName,
                      filled: true,
                      fillColor: ctx.palette.cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: priceCtl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: l10n.storeProductPrice,
                      filled: true,
                      fillColor: ctx.palette.cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: categoryCtl,
                    decoration: InputDecoration(
                      labelText: l10n.storeProductCategory,
                      filled: true,
                      fillColor: ctx.palette.cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.storeProductDiscount,
                      style: TextStyle(fontSize: 13, color: ctx.palette.muted),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<DiscountKind?>(
                    segments: [
                      ButtonSegment(
                        value: null,
                        label: const Text('0'),
                      ),
                      ButtonSegment(
                        value: DiscountKind.percent,
                        label: const Text('%'),
                      ),
                      ButtonSegment(
                        value: DiscountKind.fixed,
                        label: const Text('Rp'),
                      ),
                    ],
                    selected: {kind},
                    onSelectionChanged: (s) => setLocal(() => kind = s.first),
                  ),
                  if (kind != null) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: discountCtl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: l10n.storeDiscountValue,
                        filled: true,
                        fillColor: ctx.palette.cardAlt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.storeSaveProduct),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true || !mounted) return;
    // Kode wajib & tidak boleh ganda (lihat catalogCodeError):
    // pesan formulir yang lama sudah menjanjikan kode wajib,
    // kini pemeriksaannya sungguh ada.
    final code = codeCtl.text.trim();
    final codeError = catalogCodeError(_items, code, ownIndex: index);
    if (codeError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            codeError == CatalogCodeError.empty
                ? l10n.storeProductFormError
                : l10n.storeProductCodeDuplicate,
          ),
        ),
      );
      return;
    }
    final name = nameCtl.text.trim();
    final price = int.tryParse(priceCtl.text.trim()) ?? 0;
    if (name.isEmpty || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.storeProductFormError)),
      );
      return;
    }
    Discount? discount;
    final selectedKind = kind;
    if (selectedKind != null) {
      final value = int.tryParse(discountCtl.text.trim()) ?? 0;
      if (value > 0) {
        discount = selectedKind == DiscountKind.percent
            ? Discount.percent(value > 100 ? 100 : value)
            : Discount.fixed(value);
      }
    }
    final category = categoryCtl.text.trim();
    final item = CatalogItem(
      code: code,
      name: name,
      priceRp: price,
      defaultDiscount: discount,
      category: category,
    );
    final next = List<CatalogItem>.of(_items);
    if (index != null && index >= 0 && index < next.length) {
      next[index] = item;
    } else {
      next.add(item);
    }
    _saveAll(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.storeProductSaved(item.name))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Susunan lembar (arah NUX 9 Nov 2026): judul diam di
    // atas, daftar item ListView yang bergeser sendiri di
    // tengah, tombol Tambah Produk diam di bawah. Susunan
    // lama — satu kolom utuh berisi semua item di dalam
    // SingleChildScrollView — membuat bagian atas lembar
    // terpotong keluar layar bila item banyak, karena lembar
    // menjangkar di bawah dan isinya tumbuh melewati layar.
    // Kini tinggi lembar dibatasi (75% layar) dan hanya
    // daftarnya yang bergeser, jadi layout selalu aman.
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Text(
                l10n.storeCatalogManagerTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: _items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                      child: Text(
                        l10n.storeCatalogEmpty,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.palette.muted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        return ListTile(
                          title: Text(
                            item.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Rp${formatRupiah(item.priceRp)}'
                            '${item.code.isEmpty ? '' : ' • ${item.code}'}'
                            '${item.category.isEmpty ? '' : ' • ${item.category}'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    _editItem(existing: item, index: i),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                ),
                                onPressed: () {
                                  final next = List<CatalogItem>.of(_items)
                                    ..removeAt(i);
                                  _saveAll(next);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: ElevatedButton.icon(
                onPressed: () => _editItem(),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(l10n.storeAddProduct),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pager kartu katalog khusus PORTRAIT (arah NUX 9 Nov 2026):
/// kartu item berukuran TETAP — baris 1 nama (1 baris, elipsis
/// bila kepanjangan), baris 2 harga, lencana diskon bawaan
/// bila ada — tersusun 2 kolom × maksimal 5 baris = 10 kartu
/// per halaman; katalog lebih dari 10 berlanjut ke halaman
/// berikutnya yang dicapai dengan geser (PageView). Seluruh
/// pager dibungkus kartu segmen seperti segmen pesanan,
/// supaya segmen katalog tegas terpisah. Set item yang tampil
/// berubah (cari/kategori/katalog berubah) → kembali ke
/// halaman pertama.
class _CatalogPager extends StatefulWidget {
  const _CatalogPager({
    required this.items,
    required this.resetKey,
    required this.priceText,
    required this.badgeText,
    required this.onTap,
  });

  final List<CatalogItem> items;

  /// Tanda set item yang sedang tampil; berubah → pager
  /// kembali ke halaman pertama.
  final String resetKey;
  final String Function(CatalogItem item) priceText;
  final String? Function(CatalogItem item) badgeText;
  final void Function(CatalogItem item) onTap;

  @override
  State<_CatalogPager> createState() => _CatalogPagerState();
}

class _CatalogPagerState extends State<_CatalogPager> {
  static const _cardHeight = 84.0;
  static const _spacing = 10.0;
  static const _perPage = 10;

  final _controller = PageController();
  int _page = 0;

  @override
  void didUpdateWidget(_CatalogPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) {
      _page = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final pageCount = (items.length + _perPage - 1) ~/ _perPage;
    final fullest = items.length < _perPage ? items.length : _perPage;
    final rows = (fullest + 1) ~/ 2;
    final gridHeight = rows * _cardHeight + (rows - 1) * _spacing;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: gridHeight,
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (p) => setState(() => _page = p),
              itemCount: pageCount,
              itemBuilder: (context, page) {
                final start = page * _perPage;
                final end = start + _perPage < items.length
                    ? start + _perPage
                    : items.length;
                final slice = items.sublist(start, end);
                return GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisExtent: _cardHeight,
                        crossAxisSpacing: _spacing,
                        mainAxisSpacing: _spacing,
                      ),
                  itemCount: slice.length,
                  itemBuilder: (context, i) {
                    final item = slice[i];
                    final badge = widget.badgeText(item);
                    return Material(
                      color: context.palette.cardAlt,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => widget.onTap(item),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: context.palette.border,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.priceText(item),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: context.palette.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (badge != null)
                                Text(
                                  badge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (pageCount > 1) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var p = 0; p < pageCount; p++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p == _page
                          ? const Color(0xFF10B981)
                          : context.palette.border,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
