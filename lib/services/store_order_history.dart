import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/store_mode_logic.dart';

/// Satu penjualan Mode Toko yang LUNAS, tersimpan lengkap sebagai
/// bahan laporan penjualan (print 58mm + PDF — renderingnya
/// menyusul mengikuti contoh format dari NUX; file ini fondasi
/// datanya, format-agnostik).
///
/// Yang disimpan adalah FAKTA penjualan saat terjadi: baris-baris
/// apa adanya (label, harga satuan, qty, diskon baris), diskon
/// order, dan tiga angka hasil hitung (subtotal, total diskon,
/// total akhir) — supaya laporan kelak tidak perlu menebak ulang
/// dari keadaan katalog yang mungkin sudah berubah.
///
/// Hanya penjualan BERPESANAN yang tercatat di sini (invoice toko
/// terbayar). Pembayaran kode statis tanpa pesanan berjalan bukan
/// pesanan — tidak punya baris — jadi tidak masuk riwayat ini
/// (ia tetap terhitung di ringkasan sesi layar).
class CompletedOrder {
  final DateTime time;
  final List<OrderLine> lines;
  final Discount? orderDiscount;
  final int subtotalNusan;
  final int totalDiscountNusan;
  final int grandTotalNusan;

  /// Hash pembayaran (hex) bila diketahui dari invoice toko.
  final String? paymentHashHex;

  const CompletedOrder({
    required this.time,
    required this.lines,
    required this.orderDiscount,
    required this.subtotalNusan,
    required this.totalDiscountNusan,
    required this.grandTotalNusan,
    required this.paymentHashHex,
  });

  Map<String, Object?> toJson() => {
    'timeMs': time.millisecondsSinceEpoch,
    'lines': lines.map(_lineToJson).toList(),
    'orderDiscount': _discountToJson(orderDiscount),
    'subtotalNusan': subtotalNusan,
    'totalDiscountNusan': totalDiscountNusan,
    'grandTotalNusan': grandTotalNusan,
    'paymentHashHex': paymentHashHex,
  };

  /// Baca satu record; null bila bentuknya tidak sah (waktu/baris/
  /// angka hasil tidak utuh). Angka hasil WAJIB ada di simpanan —
  /// record tanpa itu bukan fakta penjualan yang bisa dilaporkan.
  static CompletedOrder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final timeMs = raw['timeMs'];
    final rawLines = raw['lines'];
    final subtotal = raw['subtotalNusan'];
    final totalDiscount = raw['totalDiscountNusan'];
    final grandTotal = raw['grandTotalNusan'];
    if (timeMs is! num || rawLines is! List || rawLines.isEmpty) return null;
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
    return CompletedOrder(
      time: DateTime.fromMillisecondsSinceEpoch(timeMs.toInt()),
      lines: lines,
      orderDiscount: _discountFromJson(raw['orderDiscount']),
      subtotalNusan: subtotal.toInt(),
      totalDiscountNusan: totalDiscount.toInt(),
      grandTotalNusan: grandTotal.toInt(),
      paymentHashHex: hash is String && hash.isNotEmpty ? hash : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CompletedOrder &&
      other.time.millisecondsSinceEpoch == time.millisecondsSinceEpoch &&
      other.orderDiscount == orderDiscount &&
      other.subtotalNusan == subtotalNusan &&
      other.totalDiscountNusan == totalDiscountNusan &&
      other.grandTotalNusan == grandTotalNusan &&
      other.paymentHashHex == paymentHashHex &&
      _linesEqual(other.lines, lines);

  @override
  int get hashCode => Object.hash(
    time.millisecondsSinceEpoch,
    orderDiscount,
    subtotalNusan,
    totalDiscountNusan,
    grandTotalNusan,
    paymentHashHex,
    Object.hashAll(lines),
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
  'unitPriceNusan': l.unitPriceNusan,
  'qty': l.qty,
  'discount': _discountToJson(l.discount),
};

OrderLine? _lineFromJson(Object? raw) {
  if (raw is! Map) return null;
  final label = raw['label'];
  final price = raw['unitPriceNusan'];
  final qty = raw['qty'];
  if (label is! String || label.isEmpty) return null;
  if (price is! num || price < 0 || qty is! num || qty <= 0) return null;
  final code = raw['code'];
  return OrderLine(
    code: code is String && code.isNotEmpty ? code : null,
    label: label,
    unitPriceNusan: price.toInt(),
    qty: qty.toInt(),
    discount: _discountFromJson(raw['discount']),
  );
}

/// Susun record penjualan dari keadaan pesanan saat pembayaran
/// lunas — angka hasil dihitung dengan fungsi murni yang sama
/// dengan yang menampilkan total ke kasir, jadi yang tersimpan
/// persis yang dilihat kasir.
CompletedOrder buildCompletedOrder({
  required DateTime time,
  required List<OrderLine> lines,
  required Discount? orderDiscount,
  required String? paymentHashHex,
}) {
  return CompletedOrder(
    time: time,
    lines: List.unmodifiable(lines),
    orderDiscount: orderDiscount,
    subtotalNusan: orderSubtotalNusan(lines),
    totalDiscountNusan: orderTotalDiscountNusan(lines, orderDiscount),
    grandTotalNusan: orderGrandTotalNusan(lines, orderDiscount),
    paymentHashHex: paymentHashHex,
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
}

/// Penjualan satu label item dalam satu rentang laporan.
class ItemSales {
  final String label;
  final int qty;

  /// Nilai bersih baris label ini (sesudah diskon baris; diskon
  /// order tidak dialokasikan per item — ia potongan tingkat
  /// pesanan, terlihat di total laporan, bukan di baris item).
  final int netNusan;

  const ItemSales({
    required this.label,
    required this.qty,
    required this.netNusan,
  });

  @override
  bool operator ==(Object other) =>
      other is ItemSales &&
      other.label == label &&
      other.qty == qty &&
      other.netNusan == netNusan;

  @override
  int get hashCode => Object.hash(label, qty, netNusan);
}

/// Rekap penjualan satu rentang waktu — bahan mentah laporan
/// (rendering print/PDF menyusul; bentuk angka di sini final).
class SalesReport {
  final int transactionCount;

  /// Σ (harga × qty) sebelum diskon apa pun.
  final int grossNusan;

  /// Σ seluruh diskon (baris + order).
  final int discountNusan;

  /// Σ total akhir yang sungguh dibayar.
  final int netNusan;

  /// Per label item, urut nilai bersih menurun (yang terbesar
  /// duluan — urutan alami laporan penjualan).
  final List<ItemSales> perItem;

  const SalesReport({
    required this.transactionCount,
    required this.grossNusan,
    required this.discountNusan,
    required this.netNusan,
    required this.perItem,
  });
}

/// Agregasi murni riwayat pesanan untuk rentang [from] (inklusif)
/// sampai [to] (eksklusif) — mis. satu hari kalender penuh.
/// Baris bebas teragregasi di bawah labelnya sendiri (label yang
/// sama dari banyak pesanan menjadi satu baris laporan).
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
    if (order.time.isBefore(from) || !order.time.isBefore(to)) continue;
    txCount++;
    discount += order.totalDiscountNusan;
    net += order.grandTotalNusan;
    for (final line in order.lines) {
      gross += line.lineGrossNusan;
      final prev = byLabel[line.label];
      byLabel[line.label] = ItemSales(
        label: line.label,
        qty: (prev?.qty ?? 0) + line.qty,
        netNusan: (prev?.netNusan ?? 0) + line.lineTotalNusan,
      );
    }
  }
  final perItem = byLabel.values.toList()
    ..sort((a, b) => b.netNusan.compareTo(a.netNusan));
  return SalesReport(
    transactionCount: txCount,
    grossNusan: gross,
    discountNusan: discount,
    netNusan: net,
    perItem: perItem,
  );
}
