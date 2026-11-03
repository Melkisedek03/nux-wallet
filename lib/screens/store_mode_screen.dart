import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/bolt12_service.dart';
import '../services/lsp_service.dart';
import '../services/print_service.dart';
import '../services/store_catalog.dart';
import '../services/store_order_history.dart';
import '../services/store_shift.dart';
import '../utils/animated_checkmark.dart';
import '../utils/bolt11_info.dart';
import '../utils/coin_alert.dart';
import '../utils/format.dart';
import '../utils/friendly_error.dart';
import '../utils/receive_watch.dart';
import '../utils/store_mode_logic.dart';
import '../utils/store_report.dart';
import 'scan_screen.dart';
import 'store_shift_report_screen.dart';

/// Mode Toko — kasir (PoS) di dalam ELNUX untuk UMKM.
///
/// Satu sumber kebenaran nominal penjualan adalah DAFTAR BARIS
/// pesanan: baris ditambah dengan (a) memindai QR/barcode produk,
/// (b) mengetuk item katalog (sekaligus "item cepat"), atau
/// (c) nominal bebas dari keypad. Total akhir pesanan (sesudah
/// diskon baris lalu diskon order) adalah satu-satunya nominal
/// yang dibuat kode bayar.
///
/// Kode bayar per penjualan adalah invoice Bolt11 nominal tetap
/// lewat keputusan jalur yang PERSIS sama dengan layar Terima
/// (Jalur 1: invoice biasa bila kapasitas terima cukup, JIT bila
/// jalur harus lahir — termasuk pesan minimum 1.000 nusan untuk
/// kelahiran). Kode Bayar Statis (offer Bolt12) tersedia untuk
/// QR cetak di meja; pembayaran offer saat panelnya tampil juga
/// dirayakan dan masuk ringkasan sesi.
///
/// Penerimaan diawasi dengan pola pengawas event layar Terima:
/// antrean dikuras dulu, lalu poll Event_PaymentReceived. Untuk
/// invoice toko, event dicocokkan lewat HASH pembayaran invoice
/// aktif — bukan nominal, karena nominal event pada invoice JIT
/// adalah yang sungguh diterima (terpotong fee kelahiran), bukan
/// nominal invoice. Panel sukses tidak pernah tampil sebelum
/// event penerimaan sungguhan (layar adalah kebenarannya).
///
/// Alur shift (keputusan NUX 3 Nov 2026): kasir MEMULAI dengan
/// Buka Shift; tanpa shift terbuka panel kasir nonaktif dan kode
/// bayar tidak bisa dibuat — semua penjualan tercatat di dalam
/// shift. Tutup Shift terhalang selama ada invoice menunggu /
/// perayaan berjalan; invoice yang dibatalkan kasir atau
/// kedaluwarsa tak terbayar dicatat sebagai VOID (satu record
/// per invoice, anti-ganda). Laporan per shift (atau per
/// tanggal) dibuka dari kartu shift di panel status.
class StoreModeScreen extends StatefulWidget {
  final LspService lspService;

  const StoreModeScreen({super.key, required this.lspService});

  @override
  State<StoreModeScreen> createState() => _StoreModeScreenState();
}

/// Penjualan terakhir yang lunas — bahan tombol Cetak Struk
/// selama panel sukses tampil.
class _LastSale {
  final BigInt amountMsat;
  final DateTime time;
  final int discountNusan;
  final String? paymentHashHex;
  final bool isOrderSale;

  const _LastSale({
    required this.amountMsat,
    required this.time,
    required this.discountNusan,
    required this.paymentHashHex,
    required this.isOrderSale,
  });
}

class _StoreModeScreenState extends State<StoreModeScreen> {
  // --- Pesanan berjalan ---
  int _keypadNusan = 0;
  List<OrderLine> _lines = const [];
  Discount? _orderDiscount;

  // --- Katalog ---
  final _catalogStore = StoreCatalogStore();
  List<CatalogItem> _catalog = const [];

  /// Kolom cari katalog (nama/kode) + kolom judul kustom untuk
  /// baris nominal bebas. Keduanya dibersihkan mengikuti reset
  /// pesanan sesudah pembayaran lunas (lihat _finishCelebration).
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final _freeTitleController = TextEditingController();

  // --- Shift kasir ---
  final _shiftStore = StoreShiftStore();
  List<StoreShift> _shifts = const [];
  StoreShift? _openShift;

  // --- Invoice toko aktif ---
  String? _invoice;
  String? _invoiceHashHex;
  DateTime? _invoiceExpiresAt;

  /// Anti-ganda pencatatan VOID: satu invoice toko paling banyak
  /// satu record void (batal dan kedaluwarsa tidak boleh
  /// mencatat dua kali untuk invoice yang sama).
  bool _invoiceVoidRecorded = false;

  /// Total (nusan) saat invoice dibuat — yang ditampilkan selama
  /// menunggu, bukan total pesanan berjalan yang masih bisa
  /// diedit kasir.
  int _invoiceTotalNusan = 0;
  bool _creating = false;
  String? _error;

  // --- Pengawas penerimaan (pola layar Terima) ---
  Timer? _eventTimer;
  int _watchGen = 0;
  bool _watching = false;
  bool _received = false;
  BigInt? _receivedMsat;
  Timer? _celebrationTimer;
  _LastSale? _lastSale;

  // --- Ringkasan sesi ---
  StoreSessionSummary _session = StoreSessionSummary.empty;

  // --- Kode Bayar Statis ---
  late final Bolt12OfferService _bolt12Service = Bolt12OfferService(
    widget.lspService,
  );
  bool _staticOpen = false;
  bool _staticLoading = false;
  String? _staticOffer;
  String? _staticError;

  final _historyStore = StoreOrderHistoryStore();

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _loadShifts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetchStaticOffer();
    });
  }

  @override
  void dispose() {
    _eventTimer?.cancel();
    _celebrationTimer?.cancel();
    _watchGen++;
    _searchController.dispose();
    _freeTitleController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final items = await _catalogStore.load();
    if (mounted) setState(() => _catalog = items);
  }

  // ------------------------------------------------------------------
  // Shift kasir (alur NUX: Open Shift dulu, Close Shift penutup)
  // ------------------------------------------------------------------

  Future<void> _loadShifts() async {
    final shifts = await _shiftStore.load();
    if (!mounted) return;
    setState(() {
      _shifts = shifts;
      _openShift = openShiftIn(shifts);
    });
  }

  String get _reportLocale =>
      context.l10n.localeName.startsWith('en') ? 'en' : 'id';

  Future<void> _openShiftAction() async {
    if (_openShift != null) return;
    final shift = StoreShift(openedAt: DateTime.now());
    final next = [..._shifts, shift];
    await _shiftStore.save(next);
    if (!mounted) return;
    setState(() {
      _shifts = next;
      _openShift = shift;
    });
  }

  /// Tutup shift. TERHALANG selama masih ada invoice menunggu,
  /// invoice sedang dibuat, atau perayaan penerimaan berjalan —
  /// kasir menyelesaikan atau membatalkan dulu (pembatalan
  /// tercatat VOID). Sesudah bersih, tutup berhasil dan laporan
  /// shift yang baru ditutup ditawarkan.
  Future<void> _requestCloseShift() async {
    final shift = _openShift;
    if (shift == null) return;
    final l10n = context.l10n;
    if (_invoice != null || _received || _creating) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.storeCloseShiftBlocked)));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(l10n.storeCloseShiftConfirmTitle),
        content: Text(l10n.storeCloseShiftConfirmBody),
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
    final closed = shift.close(DateTime.now());
    final next = [
      for (final s in _shifts) s == shift ? closed : s,
    ];
    await _shiftStore.save(next);
    if (!mounted) return;
    setState(() {
      _shifts = next;
      _openShift = null;
      _staticOpen = false;
    });
    _syncWatcher();
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

  void _openShiftReport(StoreShift shift) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreShiftReportScreen.forShift(shift),
      ),
    );
  }

  Future<void> _pickDayReport() async {
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

  Future<void> _prefetchStaticOffer() async {
    final result = await _bolt12Service.ensureOffer(
      description: context.l10n.staticOfferDescription,
    );
    if (result.outcome == StaticOfferOutcome.ready && mounted) {
      setState(() => _staticOffer = result.offer);
    }
  }

  // ------------------------------------------------------------------
  // Pesanan
  // ------------------------------------------------------------------

  int get _grandTotal => orderGrandTotalNusan(_lines, _orderDiscount);

  void _addProduct(CatalogItem item) {
    setState(() {
      _lines = orderAddProduct(
        _lines,
        code: item.code,
        label: item.name,
        unitPriceNusan: item.priceNusan,
        category: item.category,
        defaultDiscount: item.defaultDiscount,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.storeProductAdded(item.name)),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _addFreeAmount() {
    if (_keypadNusan <= 0) return;
    // Judul kustom opsional: terisi → jadi label baris (untuk
    // barang yang belum terinput di katalog); kosong → label
    // baku "Item Bebas". Kolom judul dibersihkan sesudah baris
    // ditambahkan, sama seperti keypad kembali ke 0.
    final label = resolveFreeItemLabel(
      _freeTitleController.text,
      fallbackLabel: context.l10n.storeFreeItem,
    );
    setState(() {
      _lines = orderAddFreeAmount(
        _lines,
        label: label,
        amountNusan: _keypadNusan,
      );
      _keypadNusan = 0;
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
    setState(() {
      _lines = orderSetLineDiscount(
        _lines,
        index,
        result.cleared ? null : result.discount,
      );
    });
  }

  Future<void> _editOrderDiscount() async {
    final result = await _showDiscountDialog(
      title: context.l10n.storeOrderDiscount,
      current: _orderDiscount,
    );
    if (result == null || !mounted) return;
    setState(() => _orderDiscount = result.cleared ? null : result.discount);
  }

  /// Dialog atur diskon: persen ATAU nominal, dapat dihapus.
  /// Mengembalikan null bila dibatalkan (tanpa perubahan).
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
  // Kode bayar (invoice toko)
  // ------------------------------------------------------------------

  Future<void> _createPaymentCode() async {
    // Kode bayar hanya di dalam shift terbuka (alur NUX) — panel
    // kasir memang nonaktif tanpa shift; ini pagar keduanya.
    if (_openShift == null) return;
    final total = _grandTotal;
    if (total <= 0 || _lines.isEmpty) return;
    _stopWatching();
    _celebrationTimer?.cancel();
    setState(() {
      _creating = true;
      _error = null;
      _invoice = null;
      _invoiceHashHex = null;
      _invoiceExpiresAt = null;
      _invoiceVoidRecorded = false;
      _received = false;
      _receivedMsat = null;
      _staticOpen = false;
    });

    final amountMsat = BigInt.from(total) * BigInt.from(1000);
    final description = context.l10n.receiveInvoiceDesc(total.toString());

    // Keputusan jalur PERSIS layar Terima (Jalur 1): invoice biasa
    // bila kapasitas terima usable mencukupi, JIT bila jalur harus
    // lahir; gagal baca kapasitas jatuh ke JIT seperti di Terima.
    var route = ReceiveInvoiceRoute.jit;
    try {
      final inbound = await widget.lspService.usableInboundCapacityMsat();
      route = chooseReceiveInvoiceRoute(
        amountMsat: amountMsat,
        usableInboundCapacityMsat: inbound,
      );
    } catch (_) {
      route = ReceiveInvoiceRoute.jit;
    }

    try {
      final invoice = route == ReceiveInvoiceRoute.regular
          ? await widget.lspService.createRegularInvoice(
              amountMsat: amountMsat,
              description: description,
            )
          : await widget.lspService.createJitInvoice(
              amountMsat: amountMsat,
              description: description,
            );
      if (!mounted) return;
      final info = parseBolt11Info(invoice);
      setState(() {
        _invoice = invoice;
        _invoiceTotalNusan = total;
        // Hash untuk pencocokan event penerimaan + waktu
        // kedaluwarsa untuk pencatatan VOID. Invoice toko
        // SENGAJA tidak disimpan ke SavedInvoiceStore: ia urusan
        // kasir sesaat, bukan invoice pending personal yang perlu
        // dipulihkan layar Terima.
        _invoiceHashHex = info?.paymentHashHex;
        _invoiceExpiresAt = info?.expiresAt;
      });
      _syncWatcher();
    } catch (e) {
      if (!mounted) return;
      // Pesan minimum kelahiran JIT sama persis dengan layar
      // Terima — jangan sampai hilang di Mode Toko.
      setState(
        () => _error =
            route == ReceiveInvoiceRoute.jit &&
                amountMsat < BigInt.from(1000000)
            ? context.l10n.receiveJitMinimumNote
            : friendlyError(
                e,
                fallback: context.l10n.createInvoiceFailed,
                l10n: context.l10n,
              ),
      );
    } finally {
      if (mounted) {
        setState(() => _creating = false);
        _syncWatcher();
      }
    }
  }

  /// Catat invoice toko aktif sebagai VOID dari pesanan berjalan
  /// saat ini. Anti-ganda: bendera per invoice memastikan batal
  /// dan kedaluwarsa tidak mencatat dua kali untuk invoice yang
  /// sama (dan invoice yang sudah lunas tidak pernah jadi VOID).
  void _recordVoidForActiveInvoice() {
    if (_invoice == null || _invoiceVoidRecorded || _lines.isEmpty) return;
    _invoiceVoidRecorded = true;
    _historyStore.append(
      buildCompletedOrder(
        time: DateTime.now(),
        lines: _lines,
        orderDiscount: _orderDiscount,
        paymentHashHex: _invoiceHashHex,
        isVoid: true,
      ),
    );
  }

  void _cancelPaymentCode() {
    _recordVoidForActiveInvoice();
    setState(() {
      _invoice = null;
      _invoiceHashHex = null;
      _invoiceExpiresAt = null;
    });
    _syncWatcher();
  }

  /// Kedaluwarsa invoice yang sedang ditunggu terdeteksi di
  /// layar: catat VOID, bersihkan invoice, beri tahu kasir.
  void _checkInvoiceExpiry() {
    final expiresAt = _invoiceExpiresAt;
    if (_invoice == null || expiresAt == null) return;
    if (!DateTime.now().isAfter(expiresAt)) return;
    _recordVoidForActiveInvoice();
    if (!mounted) return;
    setState(() {
      _invoice = null;
      _invoiceHashHex = null;
      _invoiceExpiresAt = null;
      _error = context.l10n.storeInvoiceExpiredVoid;
    });
    _syncWatcher();
  }

  // ------------------------------------------------------------------
  // Pengawas penerimaan (pola layar Terima, commit d27236d1)
  // ------------------------------------------------------------------

  void _syncWatcher() {
    final shouldRun = receiveWatcherShouldRun(
      invoicePending: _invoice != null,
      staticPanelOpen: _staticOpen,
      celebrating: _received,
    );
    if (shouldRun && !_watching) {
      _startWatching();
    } else if (!shouldRun && _watching) {
      _stopWatching();
    }
  }

  void _stopWatching() {
    _eventTimer?.cancel();
    _eventTimer = null;
    _watchGen++;
    _watching = false;
  }

  Future<void> _startWatching() async {
    _eventTimer?.cancel();
    final gen = ++_watchGen;
    _watching = true;
    await _drainEvents();
    if (!mounted || gen != _watchGen) return;
    _eventTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollEvents(gen),
    );
  }

  Future<void> _drainEvents() async {
    try {
      for (var i = 0; i < 100; i++) {
        final e = await widget.lspService.pollNextEvent();
        if (e == null) break;
      }
    } catch (_) {
      // Node belum siap — polling berikutnya yang bekerja.
    }
  }

  Future<void> _pollEvents(int gen) async {
    if (!mounted || gen != _watchGen) return;
    try {
      for (var i = 0; i < 20; i++) {
        final e = await widget.lspService.pollNextEvent();
        if (e == null) break;
        if (e is Event_PaymentReceived) {
          if (_handleReceived(e, gen)) return;
          // Event bukan untuk layar ini (mis. pembayaran lain
          // lewat node yang sama) — lanjut membaca, jangan
          // dirayakan di sini.
        }
      }
    } catch (_) {
      // Gagal baca sesaat — coba lagi di tick berikut.
    }
    // Pembayaran yang datang pada tick ini sudah ditangani di
    // atas (return lebih dulu) — kedaluwarsa hanya dinilai bila
    // invoice masih menunggu sesudah antrean event dibaca.
    if (mounted && gen == _watchGen) _checkInvoiceExpiry();
  }

  String _eventHashHex(Event_PaymentReceived e) =>
      e.paymentHash.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Terima satu event pembayaran. Mengembalikan true bila event
  /// ini adalah penjualan Mode Toko (sudah dirayakan), false bila
  /// bukan urusan layar ini.
  ///
  /// Pencocokan invoice toko lewat HASH pembayaran: event yang
  /// hash-nya sama dengan invoice aktif = penjualan pesanan ini.
  /// Bila hash invoice tak terbaca saat pembuatan (parse gagal),
  /// jatuh ke perilaku layar Terima: pembayaran apa pun selama
  /// menunggu dianggap penjualan ini. Pembayaran offer dirayakan
  /// hanya saat panel statis tampil dan tidak ada invoice aktif.
  bool _handleReceived(Event_PaymentReceived e, int gen) {
    final eventHash = _eventHashHex(e);
    final isOrderSale =
        _invoice != null &&
        (_invoiceHashHex == null || _invoiceHashHex == eventHash);
    final isStaticSale =
        _invoice == null && _staticOpen && _staticOffer != null;
    if (!isOrderSale && !isStaticSale) return false;

    CoinAlert.play();
    final now = DateTime.now();
    var saleDiscountNusan = 0;
    if (isOrderSale) {
      // Invoice ini LUNAS — kunci supaya tidak pernah tercatat
      // VOID oleh jalur batal/kedaluwarsa yang terlambat.
      _invoiceVoidRecorded = true;
      saleDiscountNusan = orderTotalDiscountNusan(_lines, _orderDiscount);
      // Simpan fakta penjualan lengkap sebagai bahan laporan
      // (rendering laporan menyusul; fondasi datanya di sini).
      final record = buildCompletedOrder(
        time: now,
        lines: _lines,
        orderDiscount: _orderDiscount,
        paymentHashHex: eventHash,
      );
      _historyStore.append(record);
    }
    if (!mounted || gen != _watchGen) return true;
    setState(() {
      _session = _session.recordSale(e.amountMsat);
      _lastSale = _LastSale(
        amountMsat: e.amountMsat,
        time: now,
        discountNusan: saleDiscountNusan,
        paymentHashHex: eventHash,
        isOrderSale: isOrderSale,
      );
      _received = true;
      _receivedMsat = e.amountMsat;
      if (isOrderSale) {
        _invoice = null;
        _invoiceHashHex = null;
        _invoiceExpiresAt = null;
      }
    });
    _celebrationTimer?.cancel();
    _celebrationTimer = Timer(receiveCelebrationDuration, _finishCelebration);
    _syncWatcher();
    return true;
  }

  /// Jeda perayaan selesai: reset panel; bila penjualan terakhir
  /// adalah pesanan, pesanan dibersihkan — siap penjualan berikut
  /// tanpa keluar Mode Toko.
  void _finishCelebration() {
    if (!mounted) return;
    setState(() {
      _received = false;
      _receivedMsat = null;
      if (_lastSale?.isOrderSale ?? false) {
        _lines = const [];
        _orderDiscount = null;
        _keypadNusan = 0;
        // Keadaan penyusun pesanan kembali bersih untuk
        // pelanggan berikutnya, satu bundel dengan pesanan:
        // saringan katalog dan judul bebas ikut direset.
        _searchQuery = '';
        _searchController.clear();
        _freeTitleController.clear();
      }
    });
    _syncWatcher();
  }

  // ------------------------------------------------------------------
  // Kode Bayar Statis
  // ------------------------------------------------------------------

  void _toggleStaticCode() {
    setState(() => _staticOpen = !_staticOpen);
    if (_staticOpen && _staticOffer == null && !_staticLoading) {
      _loadStaticOffer();
    }
    _syncWatcher();
  }

  Future<void> _loadStaticOffer() async {
    setState(() {
      _staticLoading = true;
      _staticError = null;
    });
    final result = await _bolt12Service.ensureOffer(
      description: context.l10n.staticOfferDescription,
    );
    if (!mounted) return;
    setState(() {
      _staticLoading = false;
      switch (result.outcome) {
        case StaticOfferOutcome.ready:
          _staticOffer = result.offer;
          _staticError = null;
        case StaticOfferOutcome.needsPeer:
          _staticError = context.l10n.staticCodeNeedsConnection;
        case StaticOfferOutcome.failed:
          _staticError = context.l10n.staticCodeFailed;
      }
    });
  }

  // ------------------------------------------------------------------
  // Struk
  // ------------------------------------------------------------------

  Future<void> _printLastReceipt() async {
    final sale = _lastSale;
    if (sale == null) return;
    final l10n = context.l10n;
    final settings = await PrintService.loadSettings();
    final outcome = await PrintService.printReceipt(
      settings: settings,
      receipt: ReceiptData(
        typeText: l10n.storeMode,
        statusText: l10n.txSucceeded,
        amountText: '+${formatNusan(sale.amountMsat)} nusan',
        timeText: _receiptTime(sale.time),
        hashLabel: sale.paymentHashHex != null ? 'Hash' : null,
        hashValue: sale.paymentHashHex,
      ),
      typeLabel: l10n.txType,
      statusLabel: l10n.txStatus,
      timeLabel: l10n.txTime,
      // PrintService tidak punya baris rincian bebas; keterangan
      // diskon perjalanan lewat footer bawaan struk (teks bebas
      // di kaki struk) bila penjualan ini punya diskon.
      defaultFooter: sale.discountNusan > 0
          ? l10n.storeReceiptDiscountNote(
              formatNusan(BigInt.from(sale.discountNusan) * BigInt.from(1000)),
            )
          : l10n.receiptDefaultFooter,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(printOutcomeMessage(l10n, outcome))));
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

  String _fmtNusan(int nusan) =>
      formatNusan(BigInt.from(nusan) * BigInt.from(1000));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.storeMode),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (storeModeUsesTwoPanels(constraints.maxWidth)) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 9, 18),
                    child: _buildCashier(context),
                  ),
                ),
                VerticalDivider(width: 1, color: context.palette.border),
                Expanded(
                  flex: 4,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(9, 4, 18, 18),
                    child: _buildStatusPanel(context),
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
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
    );
  }

  /// Keadaan "shift belum dibuka": panel kasir nonaktif, yang
  /// tampil hanya gerbang Buka Shift (penegasan alur NUX — tidak
  /// ada jalan menyusun/menagih pesanan di luar shift).
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

  Widget _buildCashier(BuildContext context) {
    if (_openShift == null) return _buildShiftGate(context);
    final l10n = context.l10n;
    final visibleCatalog = filterCatalogItems(_catalog, _searchQuery);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- Katalog / item cepat + cari + scan ---
        Row(
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
        ),
        const SizedBox(height: 6),
        // Cari produk (nama/kode) menyaring chip secara langsung;
        // tombol scan di sampingnya tetap jalur _scanProductCode:
        // kode terdaftar langsung masuk pesanan (qty +1 bila
        // barisnya sudah ada, dari orderAddProduct).
        Row(
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
        ),
        const SizedBox(height: 10),
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in visibleCatalog)
                ActionChip(
                  label: Text(
                    item.defaultDiscount == null
                        ? '${item.name} • ${_fmtNusan(item.priceNusan)}'
                        : '${item.name} • ${_fmtNusan(item.priceNusan)} • ${l10n.storeDiscount} ${_discountBadge(item.defaultDiscount!)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  onPressed: () => _addProduct(item),
                ),
            ],
          ),
        const SizedBox(height: 18),
        // --- Nominal bebas (keypad) ---
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
                  _fmtNusan(_keypadNusan),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'nusan',
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
        Row(
          children: [
            for (final quick in const [5000, 10000, 20000, 50000]) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(
                    () => _keypadNusan = keypadQuickAdd(_keypadNusan, quick),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    '+${_fmtNusan(quick)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ]..removeLast(),
        ),
        const SizedBox(height: 10),
        _buildKeypad(context),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _keypadNusan > 0 ? _addFreeAmount : null,
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
        const SizedBox(height: 20),
        // --- Pesanan ---
        Text(
          l10n.storeOrderTitle,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
            _fmtNusan(orderSubtotalNusan(_lines)),
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
                    orderDiscountAmountNusan(_lines, _orderDiscount) > 0
                        ? '−${_fmtNusan(orderDiscountAmountNusan(_lines, _orderDiscount))}'
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
          if (orderTotalDiscountNusan(_lines, _orderDiscount) > 0)
            _summaryRow(
              context,
              l10n.storeTotalDiscount,
              '−${_fmtNusan(orderTotalDiscountNusan(_lines, _orderDiscount))}',
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
                '${_fmtNusan(_grandTotal)} nusan',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (_grandTotal <= 0) ...[
            const SizedBox(height: 8),
            Text(
              l10n.storeZeroTotalHint,
              style: TextStyle(
                fontSize: 12,
                color: context.palette.warningIcon,
              ),
            ),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ],
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed:
              (_lines.isNotEmpty &&
                  _grandTotal > 0 &&
                  !_creating &&
                  _invoice == null)
              ? _createPaymentCode
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _creating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  l10n.storeCreateCode,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildKeypad(BuildContext context) {
    Widget key(String label, VoidCallback onTap) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Container(
                height: 58,
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            children: [
              for (final d in row)
                key(
                  d,
                  () => setState(
                    () => _keypadNusan = keypadPressDigit(
                      _keypadNusan,
                      int.parse(d),
                    ),
                  ),
                ),
            ],
          ),
        Row(
          children: [
            key(
              '00',
              () => setState(
                () => _keypadNusan = keypadPressDoubleZero(_keypadNusan),
              ),
            ),
            key(
              '0',
              () => setState(
                () => _keypadNusan = keypadPressDigit(_keypadNusan, 0),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Material(
                  color: context.palette.card,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(
                      () => _keypadNusan = keypadBackspace(_keypadNusan),
                    ),
                    child: Container(
                      height: 58,
                      alignment: Alignment.center,
                      child: const Icon(Icons.backspace_outlined, size: 22),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() => _keypadNusan = 0),
            child: Text(context.l10n.storeClearKeypad),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderLine(BuildContext context, int index) {
    final l10n = context.l10n;
    final line = _lines[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
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
                  '${_fmtNusan(line.unitPriceNusan)} × ${line.qty}',
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
                TextButton(
                  onPressed: () => _editLineDiscount(index),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    line.discount == null
                        ? l10n.storeSetDiscount
                        : '${l10n.storeDiscount} ${_discountBadge(line.discount!)} • ${l10n.storeSetDiscount}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 22),
            // Minus ke qty 0 = buang baris → konfirmasi dulu;
            // minus biasa mengurangi langsung (lihat _decrementLine).
            onPressed: () => _decrementLine(index),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${line.qty}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 22),
            onPressed: () =>
                setState(() => _lines = orderChangeQty(_lines, index, 1)),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 21),
            // Hapus baris selalu lewat konfirmasi dulu.
            onPressed: () => _confirmRemoveLine(index),
          ),
          SizedBox(
            width: 86,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (line.lineDiscountNusan > 0)
                  Text(
                    _fmtNusan(line.lineGrossNusan),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                Text(
                  _fmtNusan(line.lineTotalNusan),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (line.lineDiscountNusan > 0)
                  Text(
                    '−${_fmtNusan(line.lineDiscountNusan)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF34D399),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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

  String _discountBadge(Discount d) => switch (d.kind) {
    DiscountKind.percent => '${d.value}%',
    DiscountKind.fixed => '−${_fmtNusan(d.value)}',
  };

  Widget _buildStatusPanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildShiftCard(context),
        const SizedBox(height: 16),
        if (_openShift != null)
          _buildSellingStatusPanel(context)
        else
          _buildClosedStatusPanel(context),
      ],
    );
  }

  /// Kartu status shift: selalu tampil di panel status — status
  /// buka/tutup, waktu buka, aksi Tutup Shift dan Laporan
  /// Penjualan (pemilih shift berjalan / per tanggal / lampau).
  Widget _buildShiftCard(BuildContext context) {
    final l10n = context.l10n;
    final shift = _openShift;
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
          Row(
            children: [
              Icon(
                shift != null
                    ? Icons.storefront_rounded
                    : Icons.lock_outline_rounded,
                color: const Color(0xFF34D399),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.storeShiftTitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                    Text(
                      shift != null
                          ? l10n.storeShiftOpenedAt(
                              _receiptTime(shift.openedAt),
                            )
                          : l10n.storeShiftNotOpen,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (shift != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x2610B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.storeShiftStillOpen,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF34D399),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (shift != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _requestCloseShift,
                    child: Text(l10n.storeShiftClose),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openReportChooser,
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: Text(l10n.storeSalesReport),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Panel status saat shift tertutup: penjualan nonaktif; yang
  /// ditawarkan hanya membuka shift (di panel kasir) atau melihat
  /// laporan periode lampau.
  Widget _buildClosedStatusPanel(BuildContext context) {
    return Text(
      context.l10n.storeShiftOpenHint,
      style: TextStyle(fontSize: 13, color: context.palette.muted),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildSellingStatusPanel(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ringkasan sesi — akumulator sesi ini saja, dinyatakan
        // apa adanya (bukan laporan harian).
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.palette.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.storefront_rounded,
                color: Color(0xFF34D399),
                size: 22,
              ),
              const SizedBox(width: 10),
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
                        formatNusan(_session.totalMsat),
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_received) ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0x2610B981),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x6610B981)),
            ),
            child: Column(
              children: [
                const AnimatedCheckmark(),
                const SizedBox(height: 12),
                Text(
                  l10n.paymentReceived,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF34D399),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.receivedAmount(
                    formatNusan(_receivedMsat ?? BigInt.zero),
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.fundsArrived,
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _printLastReceipt,
                  icon: const Icon(Icons.print_rounded, size: 19),
                  label: Text(l10n.storePrintReceipt),
                ),
              ],
            ),
          ),
        ] else if (_invoice != null) ...[
          Text(
            l10n.storeWaitingPayment,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '${_fmtNusan(_invoiceTotalNusan)} nusan',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: QrImageView(
                data: _invoice!,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _cancelPaymentCode,
            child: Text(l10n.storeCancelCode),
          ),
        ] else ...[
          Text(
            l10n.storeIdleHint,
            style: TextStyle(fontSize: 13, color: context.palette.muted),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _invoice == null ? _toggleStaticCode : null,
          icon: const Icon(Icons.qr_code_2_rounded, size: 20),
          label: Text(
            l10n.staticCodeTitle,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF34D399),
            side: BorderSide(
              color: const Color(0xFF10B981).withValues(alpha: 0.5),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        if (_staticOpen) ...[
          const SizedBox(height: 16),
          if (_staticLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF34D399),
                ),
              ),
            )
          else if (_staticOffer != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: QrImageView(
                  data: _staticOffer!,
                  version: QrVersions.auto,
                  size: 240,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.staticCodeHint,
              style: TextStyle(fontSize: 12, color: context.palette.muted),
              textAlign: TextAlign.center,
            ),
          ] else if (_staticError != null) ...[
            Text(
              _staticError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _staticLoading ? null : _loadStaticOffer,
              child: Text(l10n.updateRetry),
            ),
          ],
        ],
      ],
    );
  }
}

/// Hasil dialog atur diskon: nilai baru, atau [cleared] untuk
/// menghapus diskon. null dari dialog = batal, tanpa perubahan.
class _DiscountEditResult {
  final Discount? discount;
  final bool cleared;

  const _DiscountEditResult({this.discount}) : cleared = false;
  const _DiscountEditResult.cleared() : discount = null, cleared = true;
}

/// Lembar kelola katalog: daftar item (hapus), tambah item (kode
/// diketik atau dari scan), diskon bawaan opsional. Perubahan
/// langsung diteruskan ke [onChanged] untuk disimpan pemiliknya.
class _CatalogManagerSheet extends StatefulWidget {
  final List<CatalogItem> initialItems;
  final String? initialCode;
  final void Function(List<CatalogItem> items) onChanged;

  const _CatalogManagerSheet({
    required this.initialItems,
    required this.initialCode,
    required this.onChanged,
  });

  @override
  State<_CatalogManagerSheet> createState() => _CatalogManagerSheetState();
}

class _CatalogManagerSheetState extends State<_CatalogManagerSheet> {
  late List<CatalogItem> _items = [...widget.initialItems];
  late final _codeController = TextEditingController(
    text: widget.initialCode ?? '',
  );
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _categoryController = TextEditingController();
  final _discountValueController = TextEditingController();
  DiscountKind? _discountKind;
  String? _formError;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    _discountValueController.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(List.unmodifiable(_items));

  String _itemSubtitle(CatalogItem item) {
    String nusanOf(int nusan) =>
        formatNusan(BigInt.from(nusan) * BigInt.from(1000));
    var text = '${item.code} • ${nusanOf(item.priceNusan)} nusan';
    if (item.category.isNotEmpty) text = '$text • ${item.category}';
    final d = item.defaultDiscount;
    if (d != null) {
      final badge = d.kind == DiscountKind.percent
          ? '${d.value}%'
          : '−${nusanOf(d.value)}';
      text = '$text • ${context.l10n.storeDiscount} $badge';
    }
    return text;
  }

  /// Ketuk item di daftar = muat ke formulir untuk diedit
  /// (termasuk kategori); simpan menimpa item berkode sama.
  void _loadIntoForm(CatalogItem item) {
    setState(() {
      _codeController.text = item.code;
      _nameController.text = item.name;
      _priceController.text = item.priceNusan.toString();
      _categoryController.text = item.category;
      _discountKind = item.defaultDiscount?.kind;
      _discountValueController.text =
          item.defaultDiscount?.value.toString() ?? '';
      _formError = null;
    });
  }

  Future<void> _scanIntoCode() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (raw == null || !mounted) return;
    setState(() => _codeController.text = raw.trim());
  }

  void _saveItem() {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final price =
        int.tryParse(
          _priceController.text.replaceAll('.', '').replaceAll(',', ''),
        ) ??
        0;
    if (code.isEmpty || name.isEmpty || price <= 0) {
      setState(() => _formError = context.l10n.storeProductFormError);
      return;
    }
    Discount? discount;
    final dv = int.tryParse(_discountValueController.text) ?? 0;
    if (_discountKind != null && dv > 0) {
      discount = _discountKind == DiscountKind.percent
          ? Discount.percent(dv > 100 ? 100 : dv)
          : Discount.fixed(dv);
    }
    final item = CatalogItem(
      code: code,
      name: name,
      priceNusan: price,
      defaultDiscount: discount,
      category: _categoryController.text.trim(),
    );
    setState(() {
      _items = [
        for (final existing in _items)
          if (existing.code != code) existing,
        item,
      ];
      _formError = null;
      _codeController.clear();
      _nameController.clear();
      _priceController.clear();
      _categoryController.clear();
      _discountValueController.clear();
      _discountKind = null;
    });
    _emit();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.storeProductSaved(name))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.storeCatalogTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (_items.isEmpty)
              Text(
                l10n.storeCatalogEmpty,
                style: TextStyle(fontSize: 12, color: context.palette.muted),
              )
            else
              for (final item in _items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _loadIntoForm(item),
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(_itemSubtitle(item)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 21),
                    onPressed: () {
                      setState(
                        () => _items = [
                          for (final e in _items)
                            if (e.code != item.code) e,
                        ],
                      );
                      _emit();
                    },
                  ),
                ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      labelText: l10n.storeProductCode,
                      filled: true,
                      fillColor: context.palette.cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  onPressed: _scanIntoCode,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.storeProductName,
                filled: true,
                fillColor: context.palette.cardAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l10n.storeProductPrice,
                filled: true,
                fillColor: context.palette.cardAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _categoryController,
              decoration: InputDecoration(
                labelText: l10n.storeProductCategory,
                filled: true,
                fillColor: context.palette.cardAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.storeProductDiscount,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.palette.label,
                    ),
                  ),
                ),
                SegmentedButton<DiscountKind?>(
                  segments: [
                    ButtonSegment(value: null, label: Text('—')),
                    ButtonSegment(
                      value: DiscountKind.percent,
                      label: Text('%'),
                    ),
                    ButtonSegment(
                      value: DiscountKind.fixed,
                      label: Text('nusan'),
                    ),
                  ],
                  selected: {_discountKind},
                  onSelectionChanged: (s) =>
                      setState(() => _discountKind = s.first),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: _discountValueController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: '0',
                      filled: true,
                      fillColor: context.palette.cardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_formError != null) ...[
              const SizedBox(height: 8),
              Text(
                _formError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _saveItem,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                l10n.storeSaveProduct,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
