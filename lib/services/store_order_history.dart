import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../utils/store_mode_logic.dart';
import 'store_database.dart';
import 'store_draft.dart';
import 'store_order_archive.dart';
import 'store_token_counter.dart';

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
  /// 'nusan': hash invoice penjualan. Era 'rp': hanya terisi pada
  /// record lama yang penukaran poinnya masih memakai invoice
  /// (hash invoice penukaran itu). Penukaran model jurnal tidak
  /// memindahkan Lightning apa pun, jadi record 'rp' baru selalu
  /// null di field ini.
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

  /// Offer Bolt12 pelanggan yang menerima penerbitan poin
  /// transaksi ini (bentuk ternormalisasi: trim + huruf kecil),
  /// terisi hanya bila penerbitan dibayar ke offer — penerbitan
  /// ke invoice sekali pakai tidak mencatat identitas yang bisa
  /// dipakai ulang. Field ini kunci JURNAL poin toko: saldo
  /// penukaran seorang pelanggan = poin terbit ke offer-nya
  /// dikurangi poin yang sudah ditukar atas offer yang sama.
  /// null untuk record lama & penerbitan via invoice.
  final String? pointsRecipientOffer;

  /// Offer Bolt12 yang dipakai pelanggan untuk MENUKAR poin pada
  /// transaksi ini (jurnal toko), ternormalisasi seperti
  /// [pointsRecipientOffer]. null bila transaksi ini tidak
  /// menukar poin (atau record lama pra-jurnal).
  final String? pointsRedeemOffer;

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

  /// Penanda shift tempat record ini tercatat: milidetik epoch
  /// waktu BUKA shiftnya (identitas shift di tabel shifts).
  /// null untuk record lama & record yang dicatat tanpa shift
  /// berjalan. Laporan shift tetap memakai jendela waktu —
  /// kolom ini bahan penelusuran, bukan kunci agregasi.
  final int? shiftOpenedMs;

  /// Stempel operator Fase A: id & nama operator yang sedang
  /// login saat record ini dicatat (penjualan oleh "siapa" —
  /// bahan akuntabilitas laporan level nota & baris Kasir di
  /// struk). '' untuk record sebelum Fase A / tanpa sesi.
  final String operatorId;
  final String operatorName;

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
    this.pointsRecipientOffer,
    this.pointsRedeemOffer,
    this.customerName = '',
    this.billNo = 0,
    this.tokenNo = 0,
    this.shiftOpenedMs,
    this.operatorId = '',
    this.operatorName = '',
  });

  bool get isRupiahEra => era == storeEraRupiah;

  /// Salinan record dengan status penerbitan poin diperbarui —
  /// dipakai saat poin tertunda diterbitkan/dibatalkan dari
  /// antre, tanpa mengubah fakta penjualan apa pun.
  CompletedOrder withIssueStatus(
    String status, {
    String? issueHashHex,
    String? recipientOffer,
  }) {
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
      pointsRecipientOffer: recipientOffer ?? pointsRecipientOffer,
      pointsRedeemOffer: pointsRedeemOffer,
      customerName: customerName,
      billNo: billNo,
      tokenNo: tokenNo,
      shiftOpenedMs: shiftOpenedMs,
      operatorId: operatorId,
      operatorName: operatorName,
    );
  }

  /// Salinan record berstempel operator Fase A (id + nama
  /// operator yang sedang login) — dicap layar Mode Toko pada
  /// record hasil halaman pembayaran tepat sebelum dicatat,
  /// untuk penjualan lunas maupun VOID pra-lunas.
  CompletedOrder withOperator({
    required String operatorId,
    required String operatorName,
  }) {
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
      pointsRecipientOffer: pointsRecipientOffer,
      pointsRedeemOffer: pointsRedeemOffer,
      customerName: customerName,
      billNo: billNo,
      tokenNo: tokenNo,
      shiftOpenedMs: shiftOpenedMs,
      operatorId: operatorId,
      operatorName: operatorName,
    );
  }

  /// Salinan record yang ditandai VOID — jalur pembatalan
  /// penjualan LUNAS (Fase A): fakta penjualan tidak berubah
  /// sama sekali, hanya statusnya; laporan & jurnal poin
  /// mengecualikan record VOID, jadi penanda ini sekaligus
  /// membalikkan seluruh dampak tercatat penjualan itu.
  /// Otorisasi (PIN admin) & audit adalah urusan pemanggil.
  CompletedOrder markVoid() {
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
      isVoid: true,
      payMethod: payMethod,
      cashReceivedRp: cashReceivedRp,
      changeRp: changeRp,
      pointsRedeemed: pointsRedeemed,
      pointsDiscountRp: pointsDiscountRp,
      pointsEarned: pointsEarned,
      pointsIssueStatus: pointsIssueStatus,
      pointsIssueHashHex: pointsIssueHashHex,
      pointsRecipientOffer: pointsRecipientOffer,
      pointsRedeemOffer: pointsRedeemOffer,
      customerName: customerName,
      billNo: billNo,
      tokenNo: tokenNo,
      shiftOpenedMs: shiftOpenedMs,
      operatorId: operatorId,
      operatorName: operatorName,
    );
  }

  /// Salinan record dengan metadata struk (Bill No & Token No)
  /// dicap — dipakai layar Mode Toko tepat sebelum record lunas
  /// disimpan: Bill No dihitung dari record lunas pada
  /// tanggal transaksi dan Token No diambil dari penghitung
  /// antrean harian, keduanya
  /// baru dapat ditentukan saat pencatatan, bukan saat kasir
  /// masih berada di halaman pembayaran.
  CompletedOrder withReceiptMeta({
    int? billNo,
    int? tokenNo,
    int? shiftOpenedMs,
  }) {
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
      pointsRecipientOffer: pointsRecipientOffer,
      pointsRedeemOffer: pointsRedeemOffer,
      customerName: customerName,
      billNo: billNo ?? this.billNo,
      tokenNo: tokenNo ?? this.tokenNo,
      shiftOpenedMs: shiftOpenedMs ?? this.shiftOpenedMs,
      operatorId: operatorId,
      operatorName: operatorName,
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
    if (pointsRecipientOffer != null)
      'pointsRecipientOffer': pointsRecipientOffer,
    if (pointsRedeemOffer != null) 'pointsRedeemOffer': pointsRedeemOffer,
    if (customerName.isNotEmpty) 'customerName': customerName,
    if (billNo != 0) 'billNo': billNo,
    if (tokenNo != 0) 'tokenNo': tokenNo,
    if (shiftOpenedMs != null) 'shiftOpenedMs': shiftOpenedMs,
    if (operatorId.isNotEmpty) 'operatorId': operatorId,
    if (operatorName.isNotEmpty) 'operatorName': operatorName,
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
    final recipientOffer = raw['pointsRecipientOffer'];
    final redeemOffer = raw['pointsRedeemOffer'];
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
      pointsRecipientOffer:
          recipientOffer is String && recipientOffer.isNotEmpty
              ? recipientOffer
              : null,
      pointsRedeemOffer: redeemOffer is String && redeemOffer.isNotEmpty
          ? redeemOffer
          : null,
      // Metadata struk: record lama tanpa field ini terbaca
      // kosong/tanpa nomor (kompatibel mundur).
      customerName: customer is String ? customer : '',
      billNo: intOr0(raw['billNo']),
      tokenNo: intOr0(raw['tokenNo']),
      shiftOpenedMs: raw['shiftOpenedMs'] is num
          ? (raw['shiftOpenedMs'] as num).toInt()
          : null,
      operatorId: raw['operatorId'] is String
          ? raw['operatorId'] as String
          : '',
      operatorName: raw['operatorName'] is String
          ? raw['operatorName'] as String
          : '',
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
      other.pointsRecipientOffer == pointsRecipientOffer &&
      other.pointsRedeemOffer == pointsRedeemOffer &&
      other.customerName == customerName &&
      other.billNo == billNo &&
      other.tokenNo == tokenNo &&
      other.shiftOpenedMs == shiftOpenedMs &&
      other.operatorId == operatorId &&
      other.operatorName == operatorName &&
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
    pointsRecipientOffer,
    pointsRedeemOffer,
    Object.hash(
      customerName,
      billNo,
      tokenNo,
      shiftOpenedMs,
      operatorId,
      operatorName,
      Object.hashAll(lines),
    ),
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
  String? pointsRedeemOffer,
  String customerName = '',
  String operatorId = '',
  String operatorName = '',
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
    pointsRedeemOffer: pointsRedeemOffer,
    customerName: customerName.trim(),
    operatorId: operatorId,
    operatorName: operatorName,
  );
}

/// Bentuk ternormalisasi offer Bolt12 untuk kunci jurnal poin:
/// trim + huruf kecil (offer adalah string bech32; perbandingan
/// jurnal tidak boleh gagal hanya karena huruf besar dari hasil
/// tempel/pindai).
String normalizePointsOffer(String raw) => raw.trim().toLowerCase();

/// Saldo poin JURNAL toko untuk satu offer pelanggan: poin yang
/// sudah DITERBITKAN ke offer itu (status 'issued' dan offer
/// tercatat) dikurangi poin yang sudah DITUKAR atas offer yang
/// sama. Inilah satu-satunya dasar penukaran poin model jurnal:
/// hak potongan lahir dari penerbitan toko sendiri yang tercatat,
/// bukan dari saldo dompet pelanggan dan bukan dari pembayaran
/// apa pun pada saat penukaran. Record VOID tidak dihitung;
/// penerbitan yang belum berstatus 'issued' (masih tertunda)
/// belum memberi hak; record tanpa offer tercatat berada di luar
/// jurnal. Hasil berlantai 0.
int pointsJournalBalanceFor(List<CompletedOrder> orders, String offer) {
  final key = normalizePointsOffer(offer);
  if (key.isEmpty) return 0;
  var balance = 0;
  for (final order in orders) {
    if (order.isVoid) continue;
    if (order.pointsRecipientOffer == key &&
        order.pointsIssueStatus == issueStatusIssued) {
      balance += order.pointsEarned;
    }
    if (order.pointsRedeemOffer == key) {
      balance -= order.pointsRedeemed;
    }
  }
  return balance < 0 ? 0 : balance;
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

// ---------------------------------------------------------------------
// Pemetaan baris SQLite untuk record pesanan (dipakai store ini
// dan impor satu-kali di store_database.dart — satu-satunya
// tafsir skema tabel orders/order_lines).
// ---------------------------------------------------------------------

int _autoRowCounter = 0;

/// Kunci baris internal tabel orders: record ber-id memakai
/// id-nya; record lama tanpa id (era v1) mendapat kunci buatan
/// yang stabil untuk sesi impor/insert itu.
String completedOrderRowKey(CompletedOrder order, {String? forced}) {
  if (forced != null) return forced;
  if (order.id.isNotEmpty) return 'id:${order.id}';
  _autoRowCounter++;
  return 'auto:${DateTime.now().microsecondsSinceEpoch}:$_autoRowCounter';
}

/// Tulis satu record + baris-barisnya ke tabel orders &
/// order_lines lewat [executor] (Database atau Transaction).
Future<void> insertCompletedOrder(
  DatabaseExecutor executor,
  CompletedOrder order, {
  String? rowKey,
}) async {
  final key = completedOrderRowKey(order, forced: rowKey);
  await executor.insert('orders', {
    'row_key': key,
    'id': order.id,
    'time_ms': order.time.millisecondsSinceEpoch,
    'era': order.era,
    'status': order.isVoid ? 'void' : 'paid',
    'subtotal_rp': order.subtotalRp,
    'total_discount_rp': order.totalDiscountRp,
    'grand_total_rp': order.grandTotalRp,
    'payment_hash': order.paymentHashHex,
    'pay_method': order.payMethod,
    'cash_received_rp': order.cashReceivedRp,
    'change_rp': order.changeRp,
    'points_redeemed': order.pointsRedeemed,
    'points_discount_rp': order.pointsDiscountRp,
    'points_earned': order.pointsEarned,
    'points_issue_status': order.pointsIssueStatus,
    'points_issue_hash': order.pointsIssueHashHex,
    'points_recipient_offer': order.pointsRecipientOffer,
    'points_redeem_offer': order.pointsRedeemOffer,
    'operator_id': order.operatorId,
    'operator_name': order.operatorName,
    'customer_name': order.customerName,
    'bill_no': order.billNo,
    'token_no': order.tokenNo,
    'order_discount_kind': order.orderDiscount?.kind.name,
    'order_discount_value': order.orderDiscount?.value,
    'shift_opened_ms': order.shiftOpenedMs,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await executor.delete(
    'order_lines',
    where: 'order_row_key = ?',
    whereArgs: [key],
  );
  for (var i = 0; i < order.lines.length; i++) {
    final line = order.lines[i];
    await executor.insert('order_lines', {
      'order_row_key': key,
      'seq': i,
      'code': line.code,
      'label': line.label,
      'category': line.category,
      'unit_price_rp': line.unitPriceRp,
      'qty': line.qty,
      'discount_kind': line.discount?.kind.name,
      'discount_value': line.discount?.value,
      'note': line.note,
    });
  }
}

Discount? _discountFromColumns(Object? kind, Object? value) {
  if (value is! num || value <= 0) return null;
  return switch (kind) {
    'percent' => Discount.percent(value > 100 ? 100 : value.toInt()),
    'fixed' => Discount.fixed(value.toInt()),
    _ => null,
  };
}

CompletedOrder _orderFromRows(
  Map<String, Object?> row,
  List<Map<String, Object?>> lineRows,
) {
  int intOr0(Object? v) => v is num ? v.toInt() : 0;
  final lines = <OrderLine>[
    for (final l in lineRows)
      OrderLine(
        code: l['code'] is String && (l['code'] as String).isNotEmpty
            ? l['code'] as String
            : null,
        label: l['label'] as String,
        unitPriceRp: intOr0(l['unit_price_rp']),
        qty: intOr0(l['qty']),
        category: l['category'] is String ? l['category'] as String : '',
        discount: _discountFromColumns(l['discount_kind'], l['discount_value']),
        note: l['note'] is String ? l['note'] as String : '',
      ),
  ];
  final hash = row['payment_hash'];
  final method = row['pay_method'];
  final issueHash = row['points_issue_hash'];
  return CompletedOrder(
    id: row['id'] is String ? row['id'] as String : '',
    time: DateTime.fromMillisecondsSinceEpoch(intOr0(row['time_ms'])),
    lines: lines,
    orderDiscount: _discountFromColumns(
      row['order_discount_kind'],
      row['order_discount_value'],
    ),
    era: row['era'] == storeEraRupiah ? storeEraRupiah : storeEraNusan,
    subtotalRp: intOr0(row['subtotal_rp']),
    totalDiscountRp: intOr0(row['total_discount_rp']),
    grandTotalRp: intOr0(row['grand_total_rp']),
    paymentHashHex: hash is String && hash.isNotEmpty ? hash : null,
    isVoid: row['status'] == 'void',
    payMethod: method == payMethodCash || method == payMethodQris
        ? method as String
        : null,
    cashReceivedRp: intOr0(row['cash_received_rp']),
    changeRp: intOr0(row['change_rp']),
    pointsRedeemed: intOr0(row['points_redeemed']),
    pointsDiscountRp: intOr0(row['points_discount_rp']),
    pointsEarned: intOr0(row['points_earned']),
    pointsIssueStatus: switch (row['points_issue_status']) {
      issueStatusIssued => issueStatusIssued,
      issueStatusPending => issueStatusPending,
      issueStatusWaived => issueStatusWaived,
      _ => issueStatusNone,
    },
    pointsIssueHashHex: issueHash is String && issueHash.isNotEmpty
        ? issueHash
        : null,
    pointsRecipientOffer: row['points_recipient_offer'] is String &&
            (row['points_recipient_offer'] as String).isNotEmpty
        ? row['points_recipient_offer'] as String
        : null,
    pointsRedeemOffer: row['points_redeem_offer'] is String &&
            (row['points_redeem_offer'] as String).isNotEmpty
        ? row['points_redeem_offer'] as String
        : null,
    operatorId: row['operator_id'] is String
        ? row['operator_id'] as String
        : '',
    operatorName: row['operator_name'] is String
        ? row['operator_name'] as String
        : '',
    customerName: row['customer_name'] is String
        ? row['customer_name'] as String
        : '',
    billNo: intOr0(row['bill_no']),
    tokenNo: intOr0(row['token_no']),
    shiftOpenedMs: row['shift_opened_ms'] is num
        ? (row['shift_opened_ms'] as num).toInt()
        : null,
  );
}

/// Muat record dari tabel orders (rentang baris [where] opsional)
/// urut waktu naik lalu urutan tulis — urutan yang sama dengan
/// daftar era SharedPreferences.
Future<List<CompletedOrder>> loadCompletedOrders(
  DatabaseExecutor executor, {
  String? where,
  List<Object?>? whereArgs,
}) async {
  final rows = await executor.query(
    'orders',
    where: where,
    whereArgs: whereArgs,
    orderBy: 'time_ms ASC, rowid ASC',
  );
  final orders = <CompletedOrder>[];
  for (final row in rows) {
    final lineRows = await executor.query(
      'order_lines',
      where: 'order_row_key = ?',
      whereArgs: [row['row_key']],
      orderBy: 'seq ASC',
    );
    orders.add(_orderFromRows(row, lineRows));
  }
  return orders;
}

/// Penyimpanan riwayat pesanan Mode Toko di SQLite
/// (store_pos.db, tabel orders + order_lines) — sejak migrasi
/// 4 Nov 2026 menggantikan SharedPreferences.
///
/// Batas aktif [maxRecords] record terakhir (keputusan NUX
/// 4 Nov 2026): record yang berlebih dari batas itu TIDAK
/// dibuang — ia diarsipkan otomatis ke berkas JSONL di storage
/// HP (StoreOrderArchive) dan hanya dihapus dari basis data
/// sesudah arsipnya tertulis; tulis arsip yang gagal
/// membiarkan record tetap aktif untuk dicoba lagi pada
/// pelunasan berikutnya.
class StoreOrderHistoryStore {
  /// Kunci SharedPreferences era lama (sumber impor satu-kali).
  static const String storageKey = 'store_order_history_v1';
  static const int maxRecords = 1000;

  StoreOrderHistoryStore({
    StoreDatabase? database,
    StoreOrderArchive? archive,
    int? maxRecordsOverride,
  }) : _database = database ?? StoreDatabase.instance,
       _archive = archive ?? StoreOrderArchive.instance,
       _maxRecords = maxRecordsOverride ?? maxRecords;

  final StoreDatabase _database;
  final StoreOrderArchive _archive;
  final int _maxRecords;

  Future<List<CompletedOrder>> load() async {
    try {
      final db = await _database.database;
      return await loadCompletedOrders(db);
    } catch (_) {
      return const [];
    }
  }

  /// Ganti seluruh isi riwayat (transaksi: hapus + tulis ulang)
  /// lalu jalankan pemeliharaan arsip overflow.
  Future<void> save(List<CompletedOrder> orders) async {
    try {
      final db = await _database.database;
      await db.transaction((txn) async {
        await txn.delete('order_lines');
        await txn.delete('orders');
        for (final order in orders) {
          await insertCompletedOrder(txn, order);
        }
      });
      await _archiveOverflow();
    } catch (_) {
      // Abaikan — penjualan sesi ini tetap tampil di layar.
    }
  }

  /// Tambahkan satu record (satu transaksi), lalu jalankan
  /// pemeliharaan arsip overflow.
  Future<void> append(CompletedOrder order) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await insertCompletedOrder(txn, order);
    });
    await _archiveOverflow();
  }

  /// Catat satu penjualan LUNAS secara atomik (keputusan NUX
  /// 4 Nov 2026 — pelunasan = SATU transaksi basis data):
  /// dalam satu transaksi yang sama: hitung nomor bill dari
  /// record tanggal transaksi (semantik yang sama dengan
  /// nextBillSeqForDate — lunas era rupiah pada tanggal
  /// kalender yang sama), majukan penghitung token harian
  /// (bila [issueToken]), cap metadata struk ke record, tulis
  /// record + barisnya, dan bersihkan draf pesanan. Mengembalikan
  /// record yang sudah tercap persis seperti tersimpan.
  /// Pemeliharaan arsip overflow berjalan SESUDAH transaksi
  /// (berkas arsip di luar basis data; penghapusan hanya sesudah
  /// arsip tertulis).
  Future<CompletedOrder> recordSettledSale(
    CompletedOrder result, {
    required bool stampMeta,
    required bool issueToken,
    int? shiftOpenedMs,
  }) async {
    final db = await _database.database;
    final settled = await db.transaction<CompletedOrder>((txn) async {
      var stamped = result;
      if (stampMeta) {
        final dayStart = DateTime(
          result.time.year,
          result.time.month,
          result.time.day,
        );
        final dayEnd = dayStart.add(const Duration(days: 1));
        final countRows = await txn.rawQuery(
          'SELECT COUNT(*) AS c FROM orders '
          "WHERE era = 'rp' AND status = 'paid' "
          'AND time_ms >= ? AND time_ms < ?',
          [
            dayStart.millisecondsSinceEpoch,
            dayEnd.millisecondsSinceEpoch,
          ],
        );
        final paidToday = (countRows.first['c'] as num?)?.toInt() ?? 0;
        var tokenNo = 0;
        if (issueToken) {
          final state = decodeTokenCounter(
            await storeKvGet(txn, StoreTokenCounterStore.storageKey),
          );
          final advance = advanceTokenCounter(
            state: state,
            now: DateTime.now(),
          );
          await storeKvSet(
            txn,
            StoreTokenCounterStore.storageKey,
            encodeTokenCounter(advance.state),
          );
          tokenNo = advance.issued;
        }
        stamped = result.withReceiptMeta(
          billNo: paidToday + 1,
          tokenNo: tokenNo,
          shiftOpenedMs: shiftOpenedMs,
        );
      } else if (shiftOpenedMs != null) {
        stamped = result.withReceiptMeta(shiftOpenedMs: shiftOpenedMs);
      }
      await insertCompletedOrder(txn, stamped);
      await storeKvDelete(txn, StoreDraftStore.storageKey);
      return stamped;
    });
    await _archiveOverflow();
    return settled;
  }

  /// Perbarui record ber-id sama (status penerbitan poin) tanpa
  /// mengubah fakta penjualannya. Record tak ber-id atau tidak
  /// ditemukan → tidak ada perubahan (bukan record v2 yang bisa
  /// diperbarui).
  Future<void> replace(CompletedOrder updated) async {
    if (updated.id.isEmpty) return;
    try {
      final db = await _database.database;
      await db.transaction((txn) async {
        final changed = await txn.update(
          'orders',
          {
            'points_issue_status': updated.pointsIssueStatus,
            'points_issue_hash': updated.pointsIssueHashHex,
            'points_recipient_offer': updated.pointsRecipientOffer,
          },
          where: 'id = ?',
          whereArgs: [updated.id],
        );
        if (changed == 0) return;
      });
    } catch (_) {
      // Abaikan — status di layar tetap yang berlaku sesi ini.
    }
  }

  /// Pemeliharaan batas aktif: bila jumlah record melebihi
  /// [_maxRecords], record tertua (urut waktu) ditulis ke arsip
  /// berkas LEBIH DULU; hanya bila arsip tertulis mereka
  /// dihapus dari basis data. Kegagalan apa pun (termasuk tulis
  /// arsip) membiarkan record tetap aktif — dicoba lagi pada
  /// penambahan berikutnya.
  Future<void> _archiveOverflow() async {
    try {
      final db = await _database.database;
      final countRows = await db.rawQuery('SELECT COUNT(*) AS c FROM orders');
      final count = (countRows.first['c'] as num?)?.toInt() ?? 0;
      if (count <= _maxRecords) return;
      final excess = count - _maxRecords;
      final keyRows = await db.query(
        'orders',
        columns: ['row_key'],
        orderBy: 'time_ms ASC, rowid ASC',
        limit: excess,
      );
      final keys = [for (final r in keyRows) r['row_key'] as String];
      if (keys.isEmpty) return;
      final placeholders = List.filled(keys.length, '?').join(',');
      final doomed = await loadCompletedOrders(
        db,
        where: 'row_key IN ($placeholders)',
        whereArgs: keys,
      );
      // Urutkan sesuai urutan tertua (loadCompletedOrders sudah
      // urut waktu) — arsip menerima urutan kronologis.
      await _archive.appendOrders(doomed);
      await db.transaction((txn) async {
        await txn.delete(
          'order_lines',
          where: 'order_row_key IN ($placeholders)',
          whereArgs: keys,
        );
        await txn.delete(
          'orders',
          where: 'row_key IN ($placeholders)',
          whereArgs: keys,
        );
      });
    } catch (_) {
      // Arsip gagal → record tetap aktif; dicoba lagi nanti.
    }
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
