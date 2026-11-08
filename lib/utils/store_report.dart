/// Agregasi + pembangun teks laporan penjualan Mode Toko v2,
/// mengikuti format contoh PoS NUX (3 Nov 2026): dua dokumen
/// teks monospace 32 kolom (selebar kertas 58mm) — Dokumen 1
/// ringkasan ("SELECTED REPORT") dan Dokumen 2 rincian per item
/// ("MENU SALES DETAILS").
///
/// Semua fungsi di sini murni: laporan hanya disusun dari record
/// tersimpan (StoreOrderHistoryStore) untuk satu jendela waktu —
/// jendela shift (buka→tutup) atau satu hari kalender lokal.
///
/// ERA: hanya record era RUPIAH ('rp') yang terhitung. Record
/// era nusan (v1) adalah arsip dan tidak pernah dicampur ke
/// angka rupiah. Angka uang selalu rupiah; poin tampil dalam
/// satuannya sendiri pada blok poin yang terpisah (pedoman
/// miniPOS §7: omzet rupiah, diskon poin dalam Rp, poin
/// diterbitkan/ditukar dalam poin).
library;

import '../services/store_order_history.dart';
import '../services/store_shift.dart';
import 'format.dart';
import 'store_mode_logic.dart';

/// Lebar dokumen laporan (kolom monospace, kertas 58mm).
const reportWidth = 32;

/// Label teks laporan, diisi layar dari l10n bahasa aplikasi.
/// Struktur & tanda laporan (`*`/`**`, indentasi, garis) tetap;
/// yang berubah mengikuti bahasa hanya labelnya.
class ShiftReportLabels {
  final String summaryTitle;
  final String detailsTitle;
  final String itemQty;
  final String subTotal;
  final String discount;
  final String orderDiscount;

  /// Label baris diskon POIN pada blok diskon (nilai rupiah dari
  /// penukaran poin terverifikasi).
  final String pointsDiscount;
  final String totalOrder;
  final String totalOrderInfo;
  final String invoicesLabel;
  final String invUnit;

  /// Label tender tunai & QRIS (metode pembayaran rupiah).
  final String cashLabel;
  final String qrisLabel;

  /// Label baris-baris laporan 5 Nov 2026: Income (total
  /// diterima), Modal (modal awal laci), Posisi Tunai
  /// (modal + tunai terjual), dan blok info Order Ditahan
  /// (pasangan info VOID untuk pesanan yang ditahan).
  final String incomeLabel;
  final String openingFloatLabel;
  final String cashPositionLabel;
  final String heldInfoLabel;
  final String heldTotalLabel;

  /// Label blok poin: poin diterbitkan (sudah terkirim),
  /// poin tertunda (belum diterbitkan), poin ditukar.
  final String pointsIssued;
  final String pointsPending;
  final String pointsRedeemed;
  final String voidInfo;
  final String voidItemQty;
  final String voidSubTotal;
  final String voidDiscount;
  final String voidTotalOrder;
  final String qtyLabel;
  final String otherCategory;
  final String generatedOn;

  /// Teks jumlah menu satu kelompok rincian, mis. "27 menu(s)"
  /// — fungsi dari l10n (placeholder jumlah di dalam stringnya).
  final String Function(int count) menusText;

  const ShiftReportLabels({
    required this.summaryTitle,
    required this.detailsTitle,
    required this.itemQty,
    required this.subTotal,
    required this.discount,
    required this.orderDiscount,
    required this.pointsDiscount,
    required this.totalOrder,
    required this.totalOrderInfo,
    required this.invoicesLabel,
    required this.invUnit,
    required this.cashLabel,
    required this.qrisLabel,
    required this.incomeLabel,
    required this.openingFloatLabel,
    required this.cashPositionLabel,
    required this.heldInfoLabel,
    required this.heldTotalLabel,
    required this.pointsIssued,
    required this.pointsPending,
    required this.pointsRedeemed,
    required this.voidInfo,
    required this.voidItemQty,
    required this.voidSubTotal,
    required this.voidDiscount,
    required this.voidTotalOrder,
    required this.qtyLabel,
    required this.otherCategory,
    required this.generatedOn,
    required this.menusText,
  });
}

// ---------------------------------------------------------------------
// Agregasi ringkasan (Dokumen 1)
// ---------------------------------------------------------------------

/// Total satu kategori dalam jendela laporan. [category] adalah
/// nilai snapshot mentah di baris pesanan; '' berarti tanpa
/// kategori (ditampilkan sebagai kelompok LAINNYA/OTHER).
class CategorySales {
  final String category;
  final int itemQty;

  /// Σ harga × qty sebelum diskon baris ("Sub Total" kategori).
  final int grossRp;

  /// Σ diskon baris kategori ini saja (diskon order & poin tidak
  /// dialokasikan per kategori — keduanya potongan tingkat
  /// pesanan).
  final int lineDiscountRp;

  const CategorySales({
    required this.category,
    required this.itemQty,
    required this.grossRp,
    required this.lineDiscountRp,
  });

  int get totalRp => grossRp - lineDiscountRp;

  @override
  bool operator ==(Object other) =>
      other is CategorySales &&
      other.category == category &&
      other.itemQty == itemQty &&
      other.grossRp == grossRp &&
      other.lineDiscountRp == lineDiscountRp;

  @override
  int get hashCode => Object.hash(category, itemQty, grossRp, lineDiscountRp);
}

/// Rekap pesanan batal (VOID) dalam jendela laporan.
class VoidSalesSummary {
  final int count;
  final int itemQty;

  /// Σ harga × qty baris pesanan batal sebelum diskon.
  final int grossRp;

  /// Σ seluruh diskon pesanan batal (baris + order), supaya
  /// Sub Total − Discount = Total ORDER rekonsiliasi di blok VOID.
  final int discountRp;

  /// Σ total akhir pesanan batal (yang tidak jadi dibayar).
  final int totalRp;

  const VoidSalesSummary({
    required this.count,
    required this.itemQty,
    required this.grossRp,
    required this.discountRp,
    required this.totalRp,
  });

  static const empty = VoidSalesSummary(
    count: 0,
    itemQty: 0,
    grossRp: 0,
    discountRp: 0,
    totalRp: 0,
  );

  @override
  bool operator ==(Object other) =>
      other is VoidSalesSummary &&
      other.count == count &&
      other.itemQty == itemQty &&
      other.grossRp == grossRp &&
      other.discountRp == discountRp &&
      other.totalRp == totalRp;

  @override
  int get hashCode => Object.hash(count, itemQty, grossRp, discountRp, totalRp);
}

/// Semua angka Dokumen 1 untuk satu jendela.
///
/// Rekonsiliasi yang dijamin: [grossRp] (Sub Total) −
/// [lineDiscountRp] − [orderDiscountRp] − [pointsDiscountRp] =
/// [totalRp] (Total ORDER) — diskon order dan diskon poin
/// ditampilkan terpisah dan tidak dialokasikan per
/// item/kategori.
class ShiftSalesSummary {
  /// Jumlah pesanan lunas dalam jendela (termasuk promosi Rp0).
  final int invoiceCount;
  final int itemQty;

  /// Σ harga × qty sebelum diskon apa pun (rupiah).
  final int grossRp;

  /// Σ diskon baris.
  final int lineDiscountRp;

  /// Σ diskon order yang sungguh terpakai (tidak termasuk
  /// diskon poin — ia terpisah di [pointsDiscountRp]).
  final int orderDiscountRp;

  /// Σ nilai rupiah potongan dari penukaran poin terverifikasi.
  final int pointsDiscountRp;

  /// Σ total akhir yang sungguh dibayar rupiah.
  final int totalRp;

  /// Tender tunai: jumlah transaksi & Σ total akhirnya.
  final int cashCount;
  final int cashTotalRp;

  /// Tender QRIS: jumlah transaksi & Σ total akhirnya.
  final int qrisCount;
  final int qrisTotalRp;

  /// Transaksi promosi penuh (total bayar Rp0, tanpa metode).
  final int promoCount;

  /// Σ poin yang diterbitkan & sudah terkirim ke pelanggan.
  final int pointsIssued;

  /// Σ poin yang diperoleh tetapi BELUM diterbitkan (antre
  /// tertunda, termasuk yang dilewati kasir).
  final int pointsPending;

  /// Σ poin yang ditukar pelanggan (satuannya poin, bukan Rp —
  /// nilai rupiahnya di [pointsDiscountRp]).
  final int pointsRedeemed;

  /// Per kategori: bernama dulu (abjad), tanpa kategori terakhir.
  final List<CategorySales> categories;
  final VoidSalesSummary voids;

  /// Total diterima per metode bayar (kunci tampilan: 'cash'
  /// untuk tunai, selain itu nama metode — 'qris' warisan
  /// dinormalisasi ke 'QRIS'). Dari daftar pembayaran efektif
  /// tiap record, jadi split payment terhitung per bagiannya.
  final Map<String, int> methodTotalsRp;

  const ShiftSalesSummary({
    required this.invoiceCount,
    required this.itemQty,
    required this.grossRp,
    required this.lineDiscountRp,
    required this.orderDiscountRp,
    required this.pointsDiscountRp,
    required this.totalRp,
    required this.cashCount,
    required this.cashTotalRp,
    required this.qrisCount,
    required this.qrisTotalRp,
    required this.promoCount,
    required this.pointsIssued,
    required this.pointsPending,
    required this.pointsRedeemed,
    required this.categories,
    required this.voids,
    this.methodTotalsRp = const {},
  });

  /// Income toko pada jendela ini: seluruh rupiah yang
  /// sungguh diterima dari penjualan lunas (permintaan NUX
  /// 5 Nov 2026 — angka yang sama dengan total penjualan
  /// lunas, ditampilkan dengan labelnya sendiri di laporan).
  int get incomeRp => totalRp;

  /// Tunai yang masuk laci dari penjualan jendela ini (bahan
  /// posisi tunai = modal awal + angka ini).
  int get cashSalesRp => methodTotalsRp[payMethodCash] ?? 0;
}

int _compareCategoryNames(String a, String b) {
  if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// Agregasi murni record pesanan untuk jendela [from] inklusif
/// sampai [to] eksklusif. HANYA record era rupiah: pesanan lunas
/// masuk angka penjualan; pesanan VOID hanya masuk blok VOID.
ShiftSalesSummary aggregateShiftSales(
  List<CompletedOrder> orders, {
  required DateTime from,
  required DateTime to,
}) {
  var invoiceCount = 0;
  var itemQty = 0;
  var gross = 0;
  var lineDiscount = 0;
  var orderDiscount = 0;
  var pointsDiscount = 0;
  var total = 0;
  var cashCount = 0;
  var cashTotal = 0;
  var qrisCount = 0;
  var qrisTotal = 0;
  var promoCount = 0;
  var pointsIssued = 0;
  var pointsPending = 0;
  var pointsRedeemed = 0;
  final catQty = <String, int>{};
  final catGross = <String, int>{};
  final catDiscount = <String, int>{};
  var vCount = 0;
  var vQty = 0;
  var vGross = 0;
  var vDiscount = 0;
  var vTotal = 0;
  final methodTotals = <String, int>{};

  for (final order in orders) {
    if (!order.isRupiahEra) continue;
    if (order.time.isBefore(from) || !order.time.isBefore(to)) continue;
    var oQty = 0;
    var oGross = 0;
    for (final line in order.lines) {
      oQty += line.qty;
      oGross += line.lineGrossRp;
    }
    if (order.isVoid) {
      vCount++;
      vQty += oQty;
      vGross += oGross;
      vDiscount += order.totalDiscountRp;
      vTotal += order.grandTotalRp;
      continue;
    }
    invoiceCount++;
    itemQty += oQty;
    gross += oGross;
    lineDiscount += order.lines.fold(0, (s, l) => s + l.lineDiscountRp);
    // Diskon order yang sungguh terpakai = subtotal − diskon
    // poin − total akhir (record menyimpan ketiganya; sisanya
    // adalah bagian diskon order).
    final orderDisc = order.subtotalRp - order.pointsDiscountRp - order.grandTotalRp;
    orderDiscount += orderDisc < 0 ? 0 : orderDisc;
    pointsDiscount += order.pointsDiscountRp;
    total += order.grandTotalRp;
    // Pembayaran per metode dari daftar pembayaran EFEKTIF
    // (split payment terhitung per bagian; record lama satu
    // metode dipetakan ke jumlah totalnya). Tanpa pembayaran
    // sama sekali & tidak batal = promosi penuh Rp0.
    final effective = effectivePaymentsOf(order);
    if (effective.isEmpty) {
      promoCount++;
    } else {
      var hasCash = false;
      var hasQris = false;
      for (final payment in effective) {
        final key = payment.isCash
            ? payMethodCash
            : payment.method == payMethodQris
                ? 'QRIS'
                : payment.method;
        methodTotals[key] = (methodTotals[key] ?? 0) + payment.amountRp;
        if (payment.isCash) {
          hasCash = true;
          cashTotal += payment.amountRp;
        } else if (key == 'QRIS') {
          hasQris = true;
          qrisTotal += payment.amountRp;
        }
      }
      if (hasCash) cashCount++;
      if (hasQris) qrisCount++;
    }
    pointsRedeemed += order.pointsRedeemed;
    if (order.pointsIssueStatus == issueStatusIssued) {
      pointsIssued += order.pointsEarned;
    } else if (order.pointsIssueStatus == issueStatusPending) {
      pointsPending += order.pointsEarned;
    }
    for (final line in order.lines) {
      catQty[line.category] = (catQty[line.category] ?? 0) + line.qty;
      catGross[line.category] = (catGross[line.category] ?? 0) + line.lineGrossRp;
      catDiscount[line.category] =
          (catDiscount[line.category] ?? 0) + line.lineDiscountRp;
    }
  }

  final categories =
      catQty.keys
          .map(
            (c) => CategorySales(
              category: c,
              itemQty: catQty[c]!,
              grossRp: catGross[c]!,
              lineDiscountRp: catDiscount[c]!,
            ),
          )
          .toList()
        ..sort((a, b) => _compareCategoryNames(a.category, b.category));

  return ShiftSalesSummary(
    invoiceCount: invoiceCount,
    itemQty: itemQty,
    grossRp: gross,
    lineDiscountRp: lineDiscount,
    orderDiscountRp: orderDiscount,
    pointsDiscountRp: pointsDiscount,
    totalRp: total,
    cashCount: cashCount,
    cashTotalRp: cashTotal,
    qrisCount: qrisCount,
    qrisTotalRp: qrisTotal,
    promoCount: promoCount,
    pointsIssued: pointsIssued,
    pointsPending: pointsPending,
    pointsRedeemed: pointsRedeemed,
    categories: categories,
    voids: VoidSalesSummary(
      count: vCount,
      itemQty: vQty,
      grossRp: vGross,
      discountRp: vDiscount,
      totalRp: vTotal,
    ),
    methodTotalsRp: methodTotals,
  );
}

// ---------------------------------------------------------------------
// Agregasi rincian per item (Dokumen 2)
// ---------------------------------------------------------------------

/// Rincian diskon persen pada sebagian/semua unit satu entri
/// rincian: [units] unit terdiskon [percent]%, potongan per unit
/// [perUnitRp] = floor(harga × persen / 100) — konsisten dengan
/// aturan diskon Mode Toko.
class PercentDiscountPart {
  final int percent;
  final int units;
  final int perUnitRp;

  const PercentDiscountPart({
    required this.percent,
    required this.units,
    required this.perUnitRp,
  });

  @override
  bool operator ==(Object other) =>
      other is PercentDiscountPart &&
      other.percent == percent &&
      other.units == units &&
      other.perUnitRp == perUnitRp;

  @override
  int get hashCode => Object.hash(percent, units, perUnitRp);
}

/// Satu entri Dokumen 2: semua baris lunas dengan (kategori,
/// label, harga satuan) yang sama teragregasi jadi satu entri —
/// item yang sama pada harga berbeda tampil sebagai entri
/// terpisah, persis contoh NUX.
class MenuSalesEntry {
  final String category;
  final String label;
  final int unitPriceRp;
  final int qty;
  final int grossRp;

  /// Σ diskon baris (persen + nominal) entri ini — angka dari
  /// record, bukan hitungan ulang.
  final int discountRp;
  final List<PercentDiscountPart> percentParts;

  const MenuSalesEntry({
    required this.category,
    required this.label,
    required this.unitPriceRp,
    required this.qty,
    required this.grossRp,
    required this.discountRp,
    required this.percentParts,
  });

  int get netRp => grossRp - discountRp;
}

/// Rincian satu kategori: daftar entri urut label lalu harga.
class MenuSalesGroup {
  final String category;
  final List<MenuSalesEntry> entries;

  const MenuSalesGroup({required this.category, required this.entries});
}

/// Agregasi murni rincian per item untuk jendela [from, to).
/// Hanya pesanan LUNAS era rupiah; baris VOID & era nusan tidak
/// masuk rincian penjualan.
List<MenuSalesGroup> aggregateMenuDetails(
  List<CompletedOrder> orders, {
  required DateTime from,
  required DateTime to,
}) {
  // Kunci pengelompokan: kategori \u0000 label \u0000 harga satuan.
  final accQty = <String, int>{};
  final accGross = <String, int>{};
  final accDiscount = <String, int>{};
  final accParts = <String, Map<int, int>>{}; // persen -> unit terdiskon
  final meta = <String, (String, String, int)>{};

  for (final order in orders) {
    if (!order.isRupiahEra) continue;
    if (order.isVoid) continue;
    if (order.time.isBefore(from) || !order.time.isBefore(to)) continue;
    for (final line in order.lines) {
      final key =
          '${line.category}\u0000${line.label}\u0000${line.unitPriceRp}';
      meta[key] = (line.category, line.label, line.unitPriceRp);
      accQty[key] = (accQty[key] ?? 0) + line.qty;
      accGross[key] = (accGross[key] ?? 0) + line.lineGrossRp;
      accDiscount[key] = (accDiscount[key] ?? 0) + line.lineDiscountRp;
      final d = line.discount;
      if (d != null && d.kind == DiscountKind.percent && d.value > 0) {
        final parts = accParts.putIfAbsent(key, () => {});
        parts[d.value] = (parts[d.value] ?? 0) + line.qty;
      }
    }
  }

  final byCategory = <String, List<MenuSalesEntry>>{};
  for (final key in accQty.keys) {
    final (category, label, price) = meta[key]!;
    final parts =
        (accParts[key] ?? {}).entries
            .map(
              (e) => PercentDiscountPart(
                percent: e.key,
                units: e.value,
                perUnitRp: (price * e.key) ~/ 100,
              ),
            )
            .toList()
          ..sort((a, b) => b.units.compareTo(a.units));
    byCategory
        .putIfAbsent(category, () => [])
        .add(
          MenuSalesEntry(
            category: category,
            label: label,
            unitPriceRp: price,
            qty: accQty[key]!,
            grossRp: accGross[key]!,
            discountRp: accDiscount[key]!,
            percentParts: parts,
          ),
        );
  }

  final categories = byCategory.keys.toList()..sort(_compareCategoryNames);
  return [
    for (final category in categories)
      MenuSalesGroup(
        category: category,
        entries: byCategory[category]!
          ..sort((a, b) {
            final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
            return byLabel != 0
                ? byLabel
                : a.unitPriceRp.compareTo(b.unitPriceRp);
          }),
      ),
  ];
}

/// Satu entri Laporan Produk Terlaris: semua baris lunas untuk
/// satu produk teragregasi lintas pesanan. Identitas produk =
/// kode baris bila ada (kode adalah identitas stabil produk —
/// nama boleh berubah di katalog, kode tidak); baris tanpa kode
/// (baris bebas keypad) berkelompok menurut labelnya.
class ProductSalesEntry {
  /// Kode produk; '' untuk kelompok baris bebas tanpa kode.
  final String code;

  /// Nama tampil — label dari baris terbaru dalam kelompok.
  final String label;
  final int qty;
  final int grossRp;

  /// Σ diskon baris kelompok ini (angka dari record).
  final int discountRp;

  const ProductSalesEntry({
    required this.code,
    required this.label,
    required this.qty,
    required this.grossRp,
    required this.discountRp,
  });

  /// Omzet bersih kelompok: bruto − diskon baris. (Diskon level
  /// pesanan tidak dialokasikan ke produk — angka ini memang
  /// "penjualan produk", bukan bagian dari total tagihan.)
  int get netRp => grossRp - discountRp;

  @override
  bool operator ==(Object other) =>
      other is ProductSalesEntry &&
      other.code == code &&
      other.label == label &&
      other.qty == qty &&
      other.grossRp == grossRp &&
      other.discountRp == discountRp;

  @override
  int get hashCode => Object.hash(code, label, qty, grossRp, discountRp);
}

/// Agregasi murni Produk Terlaris untuk jendela [from, to).
/// Hanya pesanan LUNAS era rupiah; pesanan VOID & era nusan
/// dikecualikan, sama seperti rincian menu. Urutan: qty
/// terbanyak; seri → omzet bersih terbesar; seri lagi → nama
/// (tak peka huruf). [limit] membatasi hasil sesudah pengurutan
/// (null = semua).
List<ProductSalesEntry> aggregateProductSales(
  List<CompletedOrder> orders, {
  required DateTime from,
  required DateTime to,
  int? limit,
}) {
  final qtyByKey = <String, int>{};
  final grossByKey = <String, int>{};
  final discountByKey = <String, int>{};
  final codeByKey = <String, String>{};
  final labelByKey = <String, String>{};
  final latestByKey = <String, DateTime>{};

  for (final order in orders) {
    if (!order.isRupiahEra) continue;
    if (order.isVoid) continue;
    if (order.time.isBefore(from) || !order.time.isBefore(to)) continue;
    for (final line in order.lines) {
      final code = line.code?.trim() ?? '';
      final key = code.isNotEmpty ? 'C$code' : 'N${line.label}';
      codeByKey[key] = code;
      qtyByKey[key] = (qtyByKey[key] ?? 0) + line.qty;
      grossByKey[key] = (grossByKey[key] ?? 0) + line.lineGrossRp;
      discountByKey[key] =
          (discountByKey[key] ?? 0) + line.lineDiscountRp;
      final latest = latestByKey[key];
      if (latest == null || order.time.isAfter(latest)) {
        latestByKey[key] = order.time;
        labelByKey[key] = line.label;
      }
    }
  }

  final entries = [
    for (final key in qtyByKey.keys)
      ProductSalesEntry(
        code: codeByKey[key]!,
        label: labelByKey[key]!,
        qty: qtyByKey[key]!,
        grossRp: grossByKey[key]!,
        discountRp: discountByKey[key]!,
      ),
  ]..sort((a, b) {
      final byQty = b.qty.compareTo(a.qty);
      if (byQty != 0) return byQty;
      final byNet = b.netRp.compareTo(a.netRp);
      if (byNet != 0) return byNet;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
  if (limit != null && entries.length > limit) {
    return entries.sublist(0, limit);
  }
  return entries;
}

/// Jumlah shift yang jendelanya bersinggungan dengan [from, to)
/// — untuk catatan jujur mode laporan per tanggal ("Meliputi N
/// shift") tanpa mengarang nomor shift.
int countShiftsInWindow(
  List<StoreShift> shifts, {
  required DateTime from,
  required DateTime to,
  required DateTime now,
}) {
  var count = 0;
  for (final shift in shifts) {
    if (!shift.openedAt.isBefore(to)) continue;
    if (!shift.windowEnd(now).isAfter(from)) continue;
    count++;
  }
  return count;
}

// ---------------------------------------------------------------------
// Format tanggal laporan
// ---------------------------------------------------------------------

const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdaysId = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _monthsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _monthsId = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

String _weekday(DateTime t, String locale) =>
    (locale == 'en' ? _weekdaysEn : _weekdaysId)[t.weekday - 1];

String _month(DateTime t, String locale) =>
    (locale == 'en' ? _monthsEn : _monthsId)[t.month - 1];

/// Jam laporan sampai detik (permintaan NUX 4 Nov): `22:24:35`.
String _hhmmss(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';

/// Baris periode mode shift, meniru contoh:
/// `Wed,26 Mar 22:24:35-...(Still Open)`; shift tertutup menampilkan
/// jam tutup (tanggal ikut bila beda hari). Dipersingkat bertahap
/// bila melewati 32 kolom.
String formatShiftPeriod({
  required DateTime openedAt,
  required DateTime? closedAt,
  required String locale,
  required String stillOpenWord,
}) {
  final start =
      '${_weekday(openedAt, locale)},${openedAt.day} '
      '${_month(openedAt, locale)} ${_hhmmss(openedAt)}';
  final startShort =
      '${openedAt.day} ${_month(openedAt, locale)} ${_hhmmss(openedAt)}';
  if (closedAt == null) {
    for (final candidate in [
      '$start-...($stillOpenWord)',
      '$start-($stillOpenWord)',
      '$startShort-...($stillOpenWord)',
      '$startShort-($stillOpenWord)',
    ]) {
      if (candidate.length <= reportWidth) return candidate;
    }
    return '$startShort-($stillOpenWord)'.substring(0, reportWidth);
  }
  final sameDay =
      closedAt.year == openedAt.year &&
      closedAt.month == openedAt.month &&
      closedAt.day == openedAt.day;
  final end = sameDay
      ? _hhmmss(closedAt)
      : '${closedAt.day} ${_month(closedAt, locale)} ${_hhmmss(closedAt)}';
  final full = '$start-$end';
  if (full.length <= reportWidth) return full;
  final short = '$startShort-$end';
  return short.length <= reportWidth ? short : short.substring(0, reportWidth);
}

/// Baris periode mode per tanggal: tanggalnya saja,
/// mis. `Wed, 26 Mar 2026`.
String formatDayPeriod({required DateTime day, required String locale}) =>
    '${_weekday(day, locale)}, ${day.day} ${_month(day, locale)} ${day.year}';

/// Cap waktu footer laporan, meniru contoh: `03 Nov'26 07:55:12`
/// (sampai detik, sama seperti baris periode).
String formatGeneratedStamp(DateTime t, String locale) {
  final yy = (t.year % 100).toString().padLeft(2, '0');
  return '${t.day.toString().padLeft(2, '0')} ${_month(t, locale)}\'$yy '
      '${_hhmmss(t)}';
}

/// Varian ringkas tanpa tahun (`03 Nov 07:55:12`) — dipakai baris
/// footer bila label + cap lengkap melewati 32 kolom; detik tidak
/// pernah dikorbankan, tahun yang disingkat.
String formatGeneratedStampCompact(DateTime t, String locale) =>
    '${t.day.toString().padLeft(2, '0')} ${_month(t, locale)} '
    '${_hhmmss(t)}';

/// Baris footer dokumen: label + cap waktu; jatuh ke cap ringkas
/// (tanpa tahun) bila bentuk lengkapnya melewati lebar kertas.
String _generatedFooter(
  ShiftReportLabels labels,
  DateTime generatedAt,
  String locale,
) {
  final full =
      '${labels.generatedOn}:${formatGeneratedStamp(generatedAt, locale)}';
  if (full.length <= reportWidth) return full;
  return '${labels.generatedOn}:'
      '${formatGeneratedStampCompact(generatedAt, locale)}';
}

// ---------------------------------------------------------------------
// Pembangun teks dokumen
// ---------------------------------------------------------------------

/// Dua dokumen laporan yang sudah jadi teks.
class ShiftReportDocuments {
  final String summary;
  final String details;

  const ShiftReportDocuments({required this.summary, required this.details});
}

/// Format angka dokumen: rupiah & jumlah poin sama-sama bilangan
/// bulat berpemisah ribuan (satuan mengikuti label barisnya).
String _fmt(int value) => formatRupiah(value);

String get _hr => '-' * reportWidth;
String get _eq => '=' * reportWidth;

String _title(String text) {
  final inner = reportWidth - 4;
  final t = text.length > inner ? text.substring(0, inner) : text;
  final pad = inner - t.length;
  final left = pad ~/ 2;
  return '--${' ' * left}$t${' ' * (pad - left)}--';
}

/// Baris label–nilai: label kiri, nilai rata kanan di kolom 32.
String _row(String label, String value) {
  final maxLabel = reportWidth - value.length - 1;
  final l = label.length > maxLabel
      ? label.substring(0, maxLabel < 0 ? 0 : maxLabel)
      : label;
  return '$l${' ' * (reportWidth - l.length - value.length)}$value';
}

/// Baris tender contoh (`CASH = 3,291,028`): label, tanda =, nilai.
String _tender(String label, String value) {
  const labelWidth = 15;
  final l = label.length > labelWidth
      ? label.substring(0, labelWidth)
      : label.padRight(labelWidth);
  return '$l=${value.padLeft(reportWidth - labelWidth - 1)}';
}

String get _shortRule => '${' ' * (reportWidth - 16)}${'-' * 16}';

String _rightOnly(String value) => value.padLeft(reportWidth);

/// Baris jumlah rincian: teks kiri bebas + jumlah rata kanan.
String _amountLine(String left, String right) {
  if (left.length + 1 + right.length <= reportWidth) {
    return '$left${' ' * (reportWidth - left.length - right.length)}$right';
  }
  return '$left $right';
}

/// Bungkus nama item ke baris-baris ≤32 kolom (kata per kata;
/// kata yang lebih panjang dari selebar kertas dipotong keras).
List<String> _wrapName(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final lines = <String>[];
  var current = '';
  for (final word in words) {
    var w = word;
    while (w.length > reportWidth) {
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      lines.add(w.substring(0, reportWidth));
      w = w.substring(reportWidth);
    }
    if (current.isEmpty) {
      current = w;
    } else if (current.length + 1 + w.length <= reportWidth) {
      current = '$current $w';
    } else {
      lines.add(current);
      current = w;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines.isEmpty ? const [''] : lines;
}

String _categoryDisplay(ShiftReportLabels labels, String category) =>
    category.isEmpty ? labels.otherCategory : category;

/// Susun dua dokumen laporan dari hasil agregasi. [periodLine]
/// dan [periodNote] disusun pemanggil (mode shift / per tanggal).
ShiftReportDocuments buildShiftReportDocuments({
  required ShiftReportLabels labels,
  required String periodLine,
  String? periodNote,
  required ShiftSalesSummary summary,
  required List<MenuSalesGroup> details,
  required DateTime generatedAt,
  required String locale,
  int? openingFloatRp,
  ({int count, int totalRp})? heldInfo,
}) {
  final footer = _generatedFooter(labels, generatedAt, locale);

  // ---------------- Dokumen 1: ringkasan ----------------
  final s = <String>[];
  s.add(_hr);
  s.add(_title(labels.summaryTitle));
  s.add(_hr);
  s.add(periodLine.length > reportWidth
      ? periodLine.substring(0, reportWidth)
      : periodLine);
  if (periodNote != null && periodNote.isNotEmpty) {
    s.add(periodNote.length > reportWidth
        ? periodNote.substring(0, reportWidth)
        : periodNote);
  }
  s.add(_hr);
  s.add(_row(labels.itemQty, _fmt(summary.itemQty)));
  s.add(_row(labels.subTotal, _fmt(summary.grossRp)));
  s.add(_row(labels.discount, '-${_fmt(summary.lineDiscountRp)}'));
  if (summary.orderDiscountRp != 0) {
    s.add(_row(labels.orderDiscount, '-${_fmt(summary.orderDiscountRp)}'));
  }
  if (summary.pointsDiscountRp != 0) {
    s.add(_row(labels.pointsDiscount, '-${_fmt(summary.pointsDiscountRp)}'));
  }
  s.add(_shortRule);
  s.add(_row('*${labels.totalOrder}', _fmt(summary.totalRp)));
  s.add(_row('*${labels.incomeLabel}', _fmt(summary.incomeRp)));
  s.add(_hr);
  // Tender per metode dari total per metode agregasi: tunai
  // dulu, lalu QRIS, lalu metode master lain sesuai abjad.
  final methodKeys = summary.methodTotalsRp.keys.toList()
    ..sort((a, b) {
      int rank(String k) => k == payMethodCash ? 0 : (k == 'QRIS' ? 1 : 2);
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.toLowerCase().compareTo(b.toLowerCase());
    });
  for (final key in methodKeys) {
    final label = key == payMethodCash
        ? labels.cashLabel
        : key == 'QRIS'
            ? labels.qrisLabel
            : key;
    s.add(_tender(label, _fmt(summary.methodTotalsRp[key]!)));
  }
  if (openingFloatRp != null) {
    s.add(_tender(labels.openingFloatLabel, _fmt(openingFloatRp)));
    s.add(
      _tender(
        labels.cashPositionLabel,
        _fmt(openingFloatRp + summary.cashSalesRp),
      ),
    );
  }
  s.add(
    _tender(labels.invoicesLabel, '${summary.invoiceCount} ${labels.invUnit}'),
  );
  s.add(_tender('**VOID', '${summary.voids.count} ${labels.invUnit}'));
  if (heldInfo != null) {
    s.add(
      _tender(
        '**${labels.heldInfoLabel}',
        '${heldInfo.count} ${labels.invUnit}',
      ),
    );
  }
  if (summary.pointsIssued > 0 ||
      summary.pointsRedeemed > 0 ||
      summary.pointsPending > 0) {
    s.add(_hr);
    s.add(_row(labels.pointsIssued, _fmt(summary.pointsIssued)));
    s.add(_row(labels.pointsRedeemed, _fmt(summary.pointsRedeemed)));
    if (summary.pointsPending > 0) {
      s.add(_row(labels.pointsPending, _fmt(summary.pointsPending)));
    }
  }
  s.add(_hr);
  s.add(_row('*${labels.totalOrderInfo}', _fmt(summary.totalRp)));
  for (final cat in summary.categories) {
    final name = _categoryDisplay(labels, cat.category);
    s.add(name.length > reportWidth ? name.substring(0, reportWidth) : name);
    s.add(_row('  ${labels.qtyLabel}', _fmt(cat.itemQty)));
    s.add(_row('  ${labels.subTotal}', _fmt(cat.grossRp)));
    if (cat.lineDiscountRp > 0) {
      s.add(_row('  ${labels.discount}', '-${_fmt(cat.lineDiscountRp)}'));
      s.add(_rightOnly(_fmt(cat.totalRp)));
    }
  }
  if (summary.voids.count > 0) {
    final v = summary.voids;
    s.add(_hr);
    s.add(_row('**${labels.voidInfo}', '(${v.count} ${labels.invUnit})'));
    s.add(_row(labels.voidItemQty, _fmt(v.itemQty)));
    s.add(_row(labels.voidSubTotal, _fmt(v.grossRp)));
    s.add(_row(labels.voidDiscount, '-${_fmt(v.discountRp)}'));
    s.add(_shortRule);
    s.add(_row(labels.voidTotalOrder, _fmt(v.totalRp)));
  }
  // Blok Order Ditahan — pasangan info VOID (permintaan NUX
  // 5 Nov 2026): pesanan yang ditahan di dalam jendela dan
  // masih tertahan saat laporan dibuat.
  if (heldInfo != null && heldInfo.count > 0) {
    s.add(_hr);
    s.add(
      _row('**${labels.heldInfoLabel}', '(${heldInfo.count} ${labels.invUnit})'),
    );
    s.add(_row(labels.heldTotalLabel, _fmt(heldInfo.totalRp)));
  }
  s.add(_eq);
  s.add(footer);
  s.add(_eq);

  // ---------------- Dokumen 2: rincian per item ----------------
  final d = <String>[];
  d.add(_hr);
  d.add(_title(labels.detailsTitle));
  d.add(_hr);
  for (final group in details) {
    d.add(_hr);
    d.add(
      _row(
        _categoryDisplay(labels, group.category),
        labels.menusText(group.entries.length),
      ),
    );
    d.add(_hr);
    for (final entry in group.entries) {
      d.addAll(_wrapName(entry.label));
      d.add(
        _amountLine(
          '${entry.qty.toString().padLeft(5)} x '
          '${_fmt(entry.unitPriceRp).padLeft(7)} =',
          _fmt(entry.grossRp),
        ),
      );
      if (entry.discountRp > 0) {
        d.add(
          _amountLine(
            '  (Disc)${'-${_fmt(entry.discountRp)}'.padLeft(10)} =',
            _fmt(entry.netRp),
          ),
        );
        for (final part in entry.percentParts) {
          d.add(
            '   (${part.percent}%) ${part.units} x -${_fmt(part.perUnitRp)}',
          );
        }
      }
    }
  }
  d.add(_eq);
  d.add(footer);
  d.add(_eq);

  return ShiftReportDocuments(summary: s.join('\n'), details: d.join('\n'));
}
