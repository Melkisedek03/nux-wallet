import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/store_mode_logic.dart';

/// Status penerbitan poin pada record penjualan v2.
const issueStatusNone = 'none';

/// Poin sudah terkirim ke dompet pelanggan (hash tercatat).
const issueStatusIssued = 'issued';

/// Poin belum terkirim — menunggu diterbitkan dari antre
/// "Poin Tertunda" (termasuk yang dilewati kasir saat lunas).
const issueStatusPending = 'pending';

/// Kasir memutuskan poin TIDAK jadi diterbitkan (ditandai dari
/// antre tertunda). Record penjualan tetap sah; hanya status
/// penerbitan poinnya yang dibatalkan.
const issueStatusWaived = 'waived';

/// Metode pembayaran rupiah pada record v2.
const payMethodCash = 'cash';
const payMethodQris = 'qris';

/// Satu pesanan Mode Toko yang SELESAI — lunas ATAU batal (VOID) —
/// tersimpan lengkap sebagai bahan laporan penjualan per shift
/// (print 58mm + PDF). Lihat `lib/utils/store_report.dart` untuk
/// agregasi + renderingnya.
///
/// DUA ERA berbagi satu simpanan:
/// - era 'nusan' (v1): record kasir nusan lama. Tetap terbaca
///   sebagai arsip, tetapi agregasi & laporan v2 MELOMPATINYA —
///   angka dua era tidak pernah dicampur.
/// - era 'rp' (v2): record kasir rupiah. Membawa fakta pembayaran
///   rupiah (metode, uang diterima, kembalian) dan fakta program
///   poin (poin ditukar + nilai potongannya, poin diperoleh +
///   status penerbitannya).
///
/// Yang disimpan adalah FAKTA penjualan saat terjadi: baris-baris
/// apa adanya (label, harga satuan, qty, kategori snapshot,
/// diskon baris, catatan baris), diskon order, dan angka hasil
/// hitung — supaya laporan tidak perlu menebak ulang dari
/// keadaan katalog yang mungkin sudah berubah.
class CompletedOrder {
  /// Id unik record ('' untuk record era lama). Dipakai untuk
  /// memperbarui status penerbitan poin pada record yang sama.
  final String id;
  final DateTime time;
  final List<OrderLine> lines;
  final Discount? orderDiscount;

  /// Era record: [storeEraRupiah] ('rp') atau [storeEraNusan]
  /// ('nusan'). Simpanan lama tanpa penanda era = 'nusan'.
  final String era;

  /// Subtotal (Σ baris sesudah diskon baris), dalam satuan era
  /// record (rupiah untuk era 'rp').
  final int subtotalRp;

  /// Total SELURUH diskon: baris + order + poin (era 'rp').
  final int totalDiscountRp;

  /// Total akhir yang sungguh dibayar rupiah (era 'rp'; untuk
  /// record promosi penuh nilainya 0).
  final int grandTotalRp;

  /// Hash pembayaran Lightning yang terkait record ini. Era
  /// 'nusan': hash invoice penjualan. Era 'rp': hash invoice
  /// PENUKARAN poin (null bila tidak ada penukaran) — satu-satunya
  /// perpindahan Lightning pada penjualan rupiah.
  final String? paymentHashHex;

  /// True = pesanan BATAL (VOID): dibatalkan kasir dari lembar
  /// pembayaran sebelum lunas. Record simpanan lama tanpa field
  /// status terbaca sebagai lunas (kompatibel mundur).
  final bool isVoid;

  /// Metode pembayaran rupiah: [payMethodCash] / [payMethodQris];
  /// null untuk VOID, promosi Rp0, dan record era lama.
  final String? payMethod;

  /// Uang tunai yang diterima kasir (hanya metode tunai).
  final int cashReceivedRp;

  /// Kembalian tunai = diterima − total akhir (hanya tunai).
  final int changeRp;

  /// Poin nusan yang DITUKAR pelanggan pada transaksi ini
  /// (terverifikasi dari node sebelum diskon diterapkan).
  final int pointsRedeemed;

  /// Nilai potongan rupiah dari penukaran poin di atas.
  final int pointsDiscountRp;

  /// Poin nusan yang DIPEROLEH dari transaksi ini (dihitung dari
  /// rupiah yang benar-benar dibayar; 0 untuk VOID & promosi).
  final int pointsEarned;

  /// Status penerbitan [pointsEarned]: 'none' (tidak ada poin /
  /// program mati), 'issued', 'pending', 'waived'.
  final String pointsIssueStatus;

  /// Id pembayaran (hex) pengiriman poin saat berstatus 'issued'.
  final String? pointsIssueHashHex;

  /// Nama pelanggan yang dicatat kasir di halaman pembayaran
  /// (opsional, untuk struk: baris "Customer: …"). '' = tidak
  /// dicatat — record lama tanpa field ini terbaca ''.
  final String customerName;

  /// Nomor urut transaksi LUNAS pada TANGGAL kalender lokal
  /// transaksi (lintas shift), dicap saat record dicatat dari
  /// jumlah record lunas era 'rp' pada tanggal itu. Tampil
  /// di struk sebagai "No. Bill" berformat
  /// INV<YYMMDD>-<urut 4 digit> (formatBillNo di
  /// utils/store_receipt.dart). 0 = tidak bernomor (VOID &
  /// record lama).
  final int billNo;

  /// Nomor antrean harian ("Token No" pada struk) dari
  /// penghitung token harian toko; naik sekali per transaksi
  /// lunas dan mulai lagi dari 1 tiap tanggal baru.
  /// 0 = tidak tampil (penghitung mati / VOID / record lama).
  final int tokenNo;

  const CompletedOrder({
    this.id = '',
    required this.time,
    required this.lines,
    required this.orderDiscount,
    this.era = storeEraNusan,
    required this.subtotalRp,
    required this.totalDiscountRp,
    required this.grandTotalRp,
    required this.paymentHashHex,
    this.isVoid = false,
    this.payMethod,
    this.cashReceivedRp = 0,
    this.changeRp = 0,
    this.pointsRedeemed = 0,
    this.pointsDiscountRp = 0,
    this.pointsEarned = 0,
    this.pointsIssueStatus = issueStatusNone,
    this.pointsIssueHashHex,
    this.customerName = '',
    this.billNo = 0,
    this.tokenNo = 0,
  });

  bool get isRupiahEra => era == storeEraRupiah;

  /// Salinan record dengan status penerbitan poin diperbarui —
  /// dipakai saat poin tertunda diterbitkan/dibatalkan dari
  /// antre, tanpa mengubah fakta penjualan apa pun.
  CompletedOrder withIssueStatus(String status, {String? issueHashHex}) {
    return CompletedOrder(
      id: id,
      time: time,
      lines: lines,
      orderDiscount: orderDiscount,
      era: era,
      subtotalRp: subtotalRp,
      totalDiscountRp: totalDiscountRp,
      grandTotalRp: grandTotalRp,
      paymentHashHex: paymentHashHex,
      isVoid: isVoid,
      payMethod: payMethod,
      cashReceivedRp: cashReceivedRp,
      changeRp: changeRp,
      pointsRedeemed: pointsRedeemed,
      pointsDiscountRp: pointsDiscountRp,
      pointsEarned: pointsEarned,
      pointsIssueStatus: status,
      pointsIssueHashHex: issueHashHex ?? pointsIssueHashHex,
      customerName: customerName,
      billNo: billNo,
      tokenNo: tokenNo,
    );
  }

  /// Salinan record dengan metadata struk (Bill No & Token No)
  /// dicap — dipakai layar Mode Toko tepat sebelum record lunas
  /// disimpan: Bill No dihitung dari record lunas pada
  /// tanggal transaksi dan Token No diambil dari penghitung
  /// antrean harian, keduanya
  /// baru dapat ditentukan saat pencatatan, bukan saat kasir
  /// masih berada di halaman pembayaran.
  CompletedOrder withReceiptMeta({int? billNo, int? tokenNo}) {
    return CompletedOrder(
      id: id,
      time: time,
      lines: lines,
      orderDiscount: orderDiscount,
      era: era,
      subtotalRp: subtotalRp,
      totalDiscountRp: totalDiscountRp,
      grandTotalRp: grandTotalRp,
      paymentHashHex: paymentHashHex,
      isVoid: isVoid,
      payMethod: payMethod,
      cashReceivedRp: cashReceivedRp,
      changeRp: changeRp,
      pointsRedeemed: pointsRedeemed,
      pointsDiscountRp: pointsDiscountRp,
      pointsEarned: pointsEarned,
      pointsIssueStatus: pointsIssueStatus,
      pointsIssueHashHex: pointsIssueHashHex,
      customerName: customerName,
      billNo: billNo ?? this.billNo,
      tokenNo: tokenNo ?? this.tokenNo,
    );
  }

  Map<String, Object?> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'timeMs': time.millisecondsSinceEpoch,
    'lines': lines.map(_lineToJson).toList(),
    'orderDiscount': _discountToJson(orderDiscount),
    'era': era,
    'subtotalRp': subtotalRp,
    'totalDiscountRp': totalDiscountRp,
    'grandTotalRp': grandTotalRp,
    'paymentHashHex': paymentHashHex,
    'status': isVoid ? 'void' : 'paid',
    if (payMethod != null) 'payMethod': payMethod,
    if (cashReceivedRp != 0) 'cashReceivedRp': cashReceivedRp,
    if (changeRp != 0) 'changeRp': changeRp,
    if (pointsRedeemed != 0) 'pointsRedeemed': pointsRedeemed,
    if (pointsDiscountRp != 0) 'pointsDiscountRp': pointsDiscountRp,
    if (pointsEarned != 0) 'pointsEarned': pointsEarned,
    if (pointsIssueStatus != issueStatusNone)
      'pointsIssueStatus': pointsIssueStatus,
    if (pointsIssueHashHex != null) 'pointsIssueHashHex': pointsIssueHashHex,
    if (customerName.isNotEmpty) 'customerName': customerName,
    if (billNo != 0) 'billNo': billNo,
    if (tokenNo != 0) 'tokenNo': tokenNo,
  };

  /// Baca satu record; null bila bentuknya tidak sah (waktu/baris/
  /// angka hasil tidak utuh). Angka hasil WAJIB ada di simpanan —
  /// record tanpa itu bukan fakta penjualan yang bisa dilaporkan.
  /// Angka dibaca dari kunci era record: 'rp' → kunci Rp; tanpa
  /// penanda era → kunci nusan v1 (yang nilainya lalu diperlakukan
  /// sebagai arsip era lama, bukan rupiah).
  static CompletedOrder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final timeMs = raw['timeMs'];
    final rawLines = raw['lines'];
    if (timeMs is! num || rawLines is! List || rawLines.isEmpty) return null;
    final era = raw['era'] == storeEraRupiah
        ? storeEraRupiah
        : storeEraNusan;
    // Record v2 menulis kunci Rp; record v1 hanya kunci nusan.
    // Kehadiran kunci Rp yang memutuskan sumber angka, supaya
    // record era lama yang ditulis ulang tetap terbaca utuh.
    final rp = raw.containsKey('subtotalRp');
    final subtotal = rp ? raw['subtotalRp'] : raw['subtotalNusan'];
    final totalDiscount = rp
        ? raw['totalDiscountRp']
        : raw['totalDiscountNusan'];
    final grandTotal = rp ? raw['grandTotalRp'] : raw['grandTotalNusan'];
    if (subtotal is! num || totalDiscount is! num || grandTotal is! num) {
      return null;
    }
    final lines = <OrderLine>[];
    for (final entry in rawLines) {
      final line = _lineFromJson(entry);
      if (line == null) return null;
      lines.add(line);
    }
    final hash = raw['paymentHashHex'];
    final id = raw['id'];
    final method = raw['payMethod'];
    final issueStatus = raw['pointsIssueStatus'];
    final issueHash = raw['pointsIssueHashHex'];
    final customer = raw['customerName'];
    int intOr0(Object? v) => v is num ? v.toInt() : 0;
    return CompletedOrder(
      id: id is String ? id : '',
      time: DateTime.fromMillisecondsSinceEpoch(timeMs.toInt()),
      lines: lines,
      orderDiscount: _discountFromJson(raw['orderDiscount']),
      era: era,
      subtotalRp: subtotal.toInt(),
      totalDiscountRp: totalDiscount.toInt(),
      grandTotalRp: grandTotal.toInt(),
      paymentHashHex: hash is String && hash.isNotEmpty ? hash : null,
      isVoid: raw['status'] == 'void',
      payMethod: method == payMethodCash || method == payMethodQris
          ? method as String
          : null,
      cashReceivedRp: intOr0(raw['cashReceivedRp']),
      changeRp: intOr0(raw['changeRp']),
      pointsRedeemed: intOr0(raw['pointsRedeemed']),
      pointsDiscountRp: intOr0(raw['pointsDiscountRp']),
      pointsEarned: intOr0(raw['pointsEarned']),
      pointsIssueStatus:
          issueStatus == issueStatusIssued ||
              issueStatus == issueStatusPending ||
              issueStatus == issueStatusWaived
          ? issueStatus as String
          : issueStatusNone,
      pointsIssueHashHex: issueHash is String && issueHash.isNotEmpty
          ? issueHash
          : null,
      // Metadata struk: record lama tanpa field ini terbaca
      // kosong/tanpa nomor (kompatibel mundur).
      customerName: customer is String ? customer : '',
      billNo: intOr0(raw['billNo']),
      tokenNo: intOr0(raw['tokenNo']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CompletedOrder &&
      other.id == id &&
      other.time.millisecondsSinceEpoch == time.millisecondsSinceEpoch &&
      other.orderDiscount == orderDiscount &&
      other.era == era &&
      other.subtotalRp == subtotalRp &&
      other.totalDiscountRp == totalDiscountRp &&
      other.grandTotalRp == grandTotalRp &&
      other.paymentHashHex == paymentHashHex &&
      other.isVoid == isVoid &&
      other.payMethod == payMethod &&
      other.cashReceivedRp == cashReceivedRp &&
      other.changeRp == changeRp &&
      other.pointsRedeemed == pointsRedeemed &&
      other.pointsDiscountRp == pointsDiscountRp &&
      other.pointsEarned == pointsEarned &&
      other.pointsIssueStatus == pointsIssueStatus &&
      other.pointsIssueHashHex == pointsIssueHashHex &&
      other.customerName == customerName &&
      other.billNo == billNo &&
      other.tokenNo == tokenNo &&
      _linesEqual(other.lines, lines);

  @override
  int get hashCode => Object.hash(
    id,
    time.millisecondsSinceEpoch,
    orderDiscount,
    era,
    subtotalRp,
    totalDiscountRp,
    grandTotalRp,
    paymentHashHex,
    isVoid,
    payMethod,
    cashReceivedRp,
    changeRp,
    pointsRedeemed,
    pointsDiscountRp,
    pointsEarned,
    pointsIssueStatus,
    pointsIssueHashHex,
    Object.hash(customerName, billNo, tokenNo, Object.hashAll(lines)),
  );
}

bool _linesEqual(List<OrderLine> a, List<OrderLine> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Map<String, Object?> _discountToJson(Discount? d) => {
  'kind': d?.kind.name,
  'value': d?.value,
};

Discount? _discountFromJson(Object? raw) {
  if (raw is! Map) return null;
  final value = raw['value'];
  if (value is! num || value <= 0) return null;
  return switch (raw['kind']) {
    'percent' => Discount.percent(value > 100 ? 100 : value.toInt()),
    'fixed' => Discount.fixed(value.toInt()),
    _ => null,
  };
}

Map<String, Object?> _lineToJson(OrderLine l) => {
  'code': l.code,
  'label': l.label,
  'unitPriceRp': l.unitPriceRp,
  'qty': l.qty,
  'category': l.category,
  'discount': _discountToJson(l.discount),
  if (l.note.isNotEmpty) 'note': l.note,
};

OrderLine? _lineFromJson(Object? raw) {
  if (raw is! Map) return null;
  final label = raw['label'];
  // Baris v2 menulis 'unitPriceRp'; baris v1 'unitPriceNusan'.
  final price = raw['unitPriceRp'] ?? raw['unitPriceNusan'];
  final qty = raw['qty'];
  if (label is! String || label.isEmpty) return null;
  if (price is! num || price < 0 || qty is! num || qty <= 0) return null;
  final code = raw['code'];
  final category = raw['category'];
  final note = raw['note'];
  return OrderLine(
    code: code is String && code.isNotEmpty ? code : null,
    label: label,
    unitPriceRp: price.toInt(),
    qty: qty.toInt(),
    category: category is String ? category : '',
    discount: _discountFromJson(raw['discount']),
    // Record lama tanpa field note terbaca '' (kompatibel mundur).
    note: note is String ? note : '',
  );
}

/// Serialisasi SATU baris pesanan & diskon untuk store lokal lain
/// yang menyimpan baris yang sama (daftar tahan Mode Toko di
/// `store_hold.dart`) — satu bentuk JSON bersama supaya catatan,
/// kategori, dan diskon baris tidak pernah berbeda tafsir antar
/// store.
Map<String, Object?> orderLineToJson(OrderLine line) => _lineToJson(line);

/// Baca satu baris pesanan dari JSON bersama; null bila tak sah.
OrderLine? orderLineFromJson(Object? raw) => _lineFromJson(raw);

/// Serialisasi satu diskon (atau null) ke bentuk JSON bersama.
Map<String, Object?> discountToJson(Discount? discount) =>
    _discountToJson(discount);

/// Baca satu diskon dari JSON bersama; null = tanpa diskon.
Discount? discountFromJson(Object? raw) => _discountFromJson(raw);

/// Susun record penjualan v2 dari keadaan pesanan saat
/// pembayaran rupiah tercatat lunas — angka hasil dihitung
/// dengan fungsi murni yang sama dengan yang menampilkan total
/// ke kasir, jadi yang tersimpan persis yang dilihat kasir.
///
/// [pointsDiscountRp] adalah potongan penukaran poin yang SUDAH
/// terverifikasi (0 bila tidak ada penukaran); [pointsEarned]
/// dihitung pemanggil dari total akhir (rupiah benar-benar
/// dibayar) dengan parameter toko. Dengan [isVoid] true, record
/// yang sama disusun untuk pesanan yang dibatalkan kasir dari
/// lembar pembayaran (angkanya tetap fakta pesanan saat itu,
/// hanya statusnya batal, dan semua fakta pembayaran/poin nol
/// kecuali yang diteruskan pemanggil).
CompletedOrder buildCompletedOrder({
  String id = '',
  required DateTime time,
  required List<OrderLine> lines,
  required Discount? orderDiscount,
  required String? paymentHashHex,
  bool isVoid = false,
  String? payMethod,
  int cashReceivedRp = 0,
  int pointsRedeemed = 0,
  int pointsDiscountRp = 0,
  int pointsEarned = 0,
  String pointsIssueStatus = issueStatusNone,
  String customerName = '',
}) {
  final subtotal = orderSubtotalRp(lines);
  final orderDisc = orderDiscountAmountRp(lines, orderDiscount);
  final grand = orderGrandTotalRp(
    lines,
    orderDiscount,
    pointsDiscountRp: pointsDiscountRp,
  );
  final lineDisc = lines.fold(0, (s, l) => s + l.lineDiscountRp);
  return CompletedOrder(
    id: id,
    time: time,
    lines: List.unmodifiable(lines),
    orderDiscount: orderDiscount,
    era: storeEraRupiah,
    subtotalRp: subtotal,
    totalDiscountRp: lineDisc + orderDisc + pointsDiscountRp,
    grandTotalRp: grand,
    paymentHashHex: paymentHashHex,
    isVoid: isVoid,
    payMethod: payMethod,
    cashReceivedRp: cashReceivedRp,
    changeRp: payMethod == payMethodCash
        ? cashChangeRp(receivedRp: cashReceivedRp, dueRp: grand)
        : 0,
    pointsRedeemed: pointsRedeemed,
    pointsDiscountRp: pointsDiscountRp,
    pointsEarned: pointsEarned,
    pointsIssueStatus: pointsIssueStatus,
    customerName: customerName.trim(),
  );
}

String encodeOrderHistory(List<CompletedOrder> orders) =>
    jsonEncode(orders.map((o) => o.toJson()).toList());

/// Baca riwayat dari string simpanan; fail-open seperti store
/// lokal lain: rusak → kosong, entri tak sah dilewati satu-satu.
List<CompletedOrder> decodeOrderHistory(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (parsed is! List) return const [];
  final orders = <CompletedOrder>[];
  for (final entry in parsed) {
    final order = CompletedOrder.fromJson(entry);
    if (order != null) orders.add(order);
  }
  return orders;
}

/// Penyimpanan riwayat pesanan Mode Toko di SharedPreferences.
///
/// Batas simpan [maxRecords] record terakhir: laporan yang wajar
/// (harian/mingguan) jauh di bawah itu, dan simpanan lokal tidak
/// boleh tumbuh tanpa batas di HP kasir.
class StoreOrderHistoryStore {
  static const String storageKey = 'store_order_history_v1';
  static const int maxRecords = 1000;

  Future<List<CompletedOrder>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeOrderHistory(prefs.getString(storageKey));
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<CompletedOrder> orders) async {
    try {
      final trimmed = orders.length > maxRecords
          ? orders.sublist(orders.length - maxRecords)
          : orders;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encodeOrderHistory(trimmed));
    } catch (_) {
      // Abaikan — penjualan sesi ini tetap tampil di layar.
    }
  }

  /// Muat, tambahkan satu record, simpan kembali.
  Future<void> append(CompletedOrder order) async {
    final current = await load();
    await save([...current, order]);
  }

  /// Perbarui record ber-id sama (status penerbitan poin) tanpa
  /// mengubah fakta penjualannya. Record tak ber-id atau tidak
  /// ditemukan → tidak ada perubahan (bukan record v2 yang bisa
  /// diperbarui).
  Future<void> replace(CompletedOrder updated) async {
    if (updated.id.isEmpty) return;
    final current = await load();
    final idx = current.indexWhere((o) => o.id == updated.id);
    if (idx < 0) return;
    final next = [...current];
    next[idx] = updated;
    await save(next);
  }
}

/// Penjualan satu label item dalam satu rentang laporan.
class ItemSales {
  final String label;
  final int qty;

  /// Nilai bersih baris label ini (sesudah diskon baris; diskon
  /// order & poin tidak dialokasikan per item — keduanya potongan
  /// tingkat pesanan, terlihat di total laporan, bukan di baris
  /// item).
  final int netRp;

  const ItemSales({required this.label, required this.qty, required this.netRp});

  @override
  bool operator ==(Object other) =>
      other is ItemSales &&
      other.label == label &&
      other.qty == qty &&
      other.netRp == netRp;

  @override
  int get hashCode => Object.hash(label, qty, netRp);
}

/// Rekap penjualan satu rentang waktu — bahan mentah laporan
/// (rendering print/PDF di store_report.dart). Hanya record era
/// rupiah ('rp') yang terhitung; record era nusan adalah arsip.
class SalesReport {
  final int transactionCount;

  /// Σ (harga × qty) sebelum diskon apa pun (rupiah).
  final int grossRp;

  /// Σ seluruh diskon (baris + order + poin).
  final int discountRp;

  /// Σ total akhir yang sungguh dibayar.
  final int netRp;

  /// Per label item, urut nilai bersih menurun (yang terbesar
  /// duluan — urutan alami laporan penjualan).
  final List<ItemSales> perItem;

  const SalesReport({
    required this.transactionCount,
    required this.grossRp,
    required this.discountRp,
    required this.netRp,
    required this.perItem,
  });
}

/// Agregasi murni riwayat pesanan untuk rentang [from] (inklusif)
/// sampai [to] (eksklusif) — mis. satu hari kalender penuh.
/// Hanya record era RUPIAH dan LUNAS yang terhitung (VOID &
/// record era nusan dilewati — rekonsiliasi VOID dan rincian
/// shift dihitung oleh agregasi laporan shift di
/// store_report.dart). Baris bebas teragregasi di bawah labelnya
/// sendiri.
SalesReport aggregateSales(
  List<CompletedOrder> orders, {
  required DateTime from,
  required DateTime to,
}) {
  var txCount = 0;
  var gross = 0;
  var discount = 0;
  var net = 0;
  final byLabel = <String, ItemSales>{};
  for (final order in orders) {
    if (!order.isRupiahEra) continue;
    if (order.time.isBefore(from) || !order.time.isBefore(to)) continue;
    if (order.isVoid) continue;
    txCount++;
    discount += order.totalDiscountRp;
    net += order.grandTotalRp;
    for (final line in order.lines) {
      gross += line.lineGrossRp;
      final prev = byLabel[line.label];
      byLabel[line.label] = ItemSales(
        label: line.label,
        qty: (prev?.qty ?? 0) + line.qty,
        netRp: (prev?.netRp ?? 0) + line.lineTotalRp,
      );
    }
  }
  final perItem = byLabel.values.toList()
    ..sort((a, b) => b.netRp.compareTo(a.netRp));
  return SalesReport(
    transactionCount: txCount,
    grossRp: gross,
    discountRp: discount,
    netRp: net,
    perItem: perItem,
  );
}
