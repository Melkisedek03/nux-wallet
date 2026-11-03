/// Agregasi + pembangun teks laporan penjualan Mode Toko,
/// mengikuti format contoh PoS NUX (3 Nov 2026): dua dokumen
/// teks monospace 32 kolom (selebar kertas 58mm) — Dokumen 1
/// ringkasan ("SELECTED REPORT") dan Dokumen 2 rincian per item
/// ("MENU SALES DETAILS").
///
/// Semua fungsi di sini murni: laporan hanya disusun dari record
/// tersimpan (StoreOrderHistoryStore) untuk satu jendela waktu —
/// jendela shift (buka→tutup) atau satu hari kalender lokal.
/// Angka yang tidak ada di record tidak dikarang: pesanan sebelum
/// fitur VOID ada terbaca lunas, sesuai simpanan mereka.
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
  final String totalOrder;
  final String totalOrderInfo;
  final String invoicesLabel;
  final String invUnit;
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
    required this.totalOrder,
    required this.totalOrderInfo,
    required this.invoicesLabel,
    required this.invUnit,
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
  final int grossNusan;

  /// Σ diskon baris kategori ini saja (diskon order tidak
  /// dialokasikan per kategori — ia potongan tingkat pesanan).
  final int lineDiscountNusan;

  const CategorySales({
    required this.category,
    required this.itemQty,
    required this.grossNusan,
    required this.lineDiscountNusan,
  });

  int get totalNusan => grossNusan - lineDiscountNusan;

  @override
  bool operator ==(Object other) =>
      other is CategorySales &&
      other.category == category &&
      other.itemQty == itemQty &&
      other.grossNusan == grossNusan &&
      other.lineDiscountNusan == lineDiscountNusan;

  @override
  int get hashCode =>
      Object.hash(category, itemQty, grossNusan, lineDiscountNusan);
}

/// Rekap pesanan batal (VOID) dalam jendela laporan.
class VoidSalesSummary {
  final int count;
  final int itemQty;

  /// Σ harga × qty baris pesanan batal sebelum diskon.
  final int grossNusan;

  /// Σ seluruh diskon pesanan batal (baris + order), supaya
  /// Sub Total − Discount = Total ORDER rekonsiliasi di blok VOID.
  final int discountNusan;

  /// Σ total akhir pesanan batal (yang tidak jadi dibayar).
  final int totalNusan;

  const VoidSalesSummary({
    required this.count,
    required this.itemQty,
    required this.grossNusan,
    required this.discountNusan,
    required this.totalNusan,
  });

  static const empty = VoidSalesSummary(
    count: 0,
    itemQty: 0,
    grossNusan: 0,
    discountNusan: 0,
    totalNusan: 0,
  );

  @override
  bool operator ==(Object other) =>
      other is VoidSalesSummary &&
      other.count == count &&
      other.itemQty == itemQty &&
      other.grossNusan == grossNusan &&
      other.discountNusan == discountNusan &&
      other.totalNusan == totalNusan;

  @override
  int get hashCode =>
      Object.hash(count, itemQty, grossNusan, discountNusan, totalNusan);
}

/// Semua angka Dokumen 1 untuk satu jendela.
///
/// Rekonsiliasi yang dijamin: [grossNusan] (Sub Total) −
/// [lineDiscountNusan] − [orderDiscountNusan] = [totalNusan]
/// (Total ORDER) — diskon order ditampilkan terpisah dan tidak
/// dialokasikan per item/kategori.
class ShiftSalesSummary {
  /// Jumlah pesanan lunas (invoice terbayar) dalam jendela.
  final int invoiceCount;
  final int itemQty;

  /// Σ harga × qty sebelum diskon apa pun.
  final int grossNusan;

  /// Σ diskon baris.
  final int lineDiscountNusan;

  /// Σ diskon order yang sungguh terpakai.
  final int orderDiscountNusan;

  /// Σ total akhir yang sungguh dibayar.
  final int totalNusan;

  /// Per kategori: bernama dulu (abjad), tanpa kategori terakhir.
  final List<CategorySales> categories;
  final VoidSalesSummary voids;

  const ShiftSalesSummary({
    required this.invoiceCount,
    required this.itemQty,
    required this.grossNusan,
    required this.lineDiscountNusan,
    required this.orderDiscountNusan,
    required this.totalNusan,
    required this.categories,
    required this.voids,
  });
}

int _compareCategoryNames(String a, String b) {
  if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// Agregasi murni record pesanan untuk jendela [from] inklusif
/// sampai [to] eksklusif. Pesanan lunas masuk angka penjualan;
/// pesanan VOID hanya masuk blok VOID.
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
  var total = 0;
  final catQty = <String, int>{};
  final catGross = <String, int>{};
  final catDiscount = <String, int>{};
  var vCount = 0;
  var vQty = 0;
  var vGross = 0;
  var vDiscount = 0;
  var vTotal = 0;

  for (final order in orders) {
    if (order.time.isBefore(from) || !order.time.isBefore(to)) continue;
    var oQty = 0;
    var oGross = 0;
    for (final line in order.lines) {
      oQty += line.qty;
      oGross += line.lineGrossNusan;
    }
    if (order.isVoid) {
      vCount++;
      vQty += oQty;
      vGross += oGross;
      vDiscount += order.totalDiscountNusan;
      vTotal += order.grandTotalNusan;
      continue;
    }
    invoiceCount++;
    itemQty += oQty;
    gross += oGross;
    lineDiscount += order.lines.fold(0, (s, l) => s + l.lineDiscountNusan);
    // Diskon order yang sungguh terpakai = subtotal − total akhir.
    orderDiscount += order.subtotalNusan - order.grandTotalNusan;
    total += order.grandTotalNusan;
    for (final line in order.lines) {
      catQty[line.category] = (catQty[line.category] ?? 0) + line.qty;
      catGross[line.category] =
          (catGross[line.category] ?? 0) + line.lineGrossNusan;
      catDiscount[line.category] =
          (catDiscount[line.category] ?? 0) + line.lineDiscountNusan;
    }
  }

  final categories =
      catQty.keys
          .map(
            (c) => CategorySales(
              category: c,
              itemQty: catQty[c]!,
              grossNusan: catGross[c]!,
              lineDiscountNusan: catDiscount[c]!,
            ),
          )
          .toList()
        ..sort((a, b) => _compareCategoryNames(a.category, b.category));

  return ShiftSalesSummary(
    invoiceCount: invoiceCount,
    itemQty: itemQty,
    grossNusan: gross,
    lineDiscountNusan: lineDiscount,
    orderDiscountNusan: orderDiscount,
    totalNusan: total,
    categories: categories,
    voids: VoidSalesSummary(
      count: vCount,
      itemQty: vQty,
      grossNusan: vGross,
      discountNusan: vDiscount,
      totalNusan: vTotal,
    ),
  );
}

// ---------------------------------------------------------------------
// Agregasi rincian per item (Dokumen 2)
// ---------------------------------------------------------------------

/// Rincian diskon persen pada sebagian/semua unit satu entri
/// rincian: [units] unit terdiskon [percent]%, potongan per unit
/// [perUnitNusan] = floor(harga × persen / 100) — konsisten
/// dengan aturan diskon Mode Toko.
class PercentDiscountPart {
  final int percent;
  final int units;
  final int perUnitNusan;

  const PercentDiscountPart({
    required this.percent,
    required this.units,
    required this.perUnitNusan,
  });

  @override
  bool operator ==(Object other) =>
      other is PercentDiscountPart &&
      other.percent == percent &&
      other.units == units &&
      other.perUnitNusan == perUnitNusan;

  @override
  int get hashCode => Object.hash(percent, units, perUnitNusan);
}

/// Satu entri Dokumen 2: semua baris lunas dengan (kategori,
/// label, harga satuan) yang sama teragregasi jadi satu entri —
/// item yang sama pada harga berbeda tampil sebagai entri
/// terpisah, persis contoh NUX.
class MenuSalesEntry {
  final String category;
  final String label;
  final int unitPriceNusan;
  final int qty;
  final int grossNusan;

  /// Σ diskon baris (persen + nominal) entri ini — angka dari
  /// record, bukan hitungan ulang.
  final int discountNusan;
  final List<PercentDiscountPart> percentParts;

  const MenuSalesEntry({
    required this.category,
    required this.label,
    required this.unitPriceNusan,
    required this.qty,
    required this.grossNusan,
    required this.discountNusan,
    required this.percentParts,
  });

  int get netNusan => grossNusan - discountNusan;
}

/// Rincian satu kategori: daftar entri urut label lalu harga.
class MenuSalesGroup {
  final String category;
  final List<MenuSalesEntry> entries;

  const MenuSalesGroup({required this.category, required this.entries});
}

/// Agregasi murni rincian per item untuk jendela [from, to).
/// Hanya pesanan LUNAS; baris VOID tidak masuk rincian penjualan.
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
    if (order.isVoid) continue;
    if (order.time.isBefore(from) || !order.time.isBefore(to)) continue;
    for (final line in order.lines) {
      final key =
          '${line.category}\u0000${line.label}\u0000${line.unitPriceNusan}';
      meta[key] = (line.category, line.label, line.unitPriceNusan);
      accQty[key] = (accQty[key] ?? 0) + line.qty;
      accGross[key] = (accGross[key] ?? 0) + line.lineGrossNusan;
      accDiscount[key] = (accDiscount[key] ?? 0) + line.lineDiscountNusan;
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
                perUnitNusan: (price * e.key) ~/ 100,
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
            unitPriceNusan: price,
            qty: accQty[key]!,
            grossNusan: accGross[key]!,
            discountNusan: accDiscount[key]!,
            percentParts: parts,
          ),
        );
  }

  final categories = byCategory.keys.toList()
    ..sort(_compareCategoryNames);
  return [
    for (final category in categories)
      MenuSalesGroup(
        category: category,
        entries: byCategory[category]!
          ..sort((a, b) {
            final byLabel = a.label.toLowerCase().compareTo(
              b.label.toLowerCase(),
            );
            return byLabel != 0
                ? byLabel
                : a.unitPriceNusan.compareTo(b.unitPriceNusan);
          }),
      ),
  ];
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

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Baris periode mode shift, meniru contoh:
/// `Wed,26 Mar 22:24-...(Still Open)`; shift tertutup menampilkan
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
      '${_month(openedAt, locale)} ${_hhmm(openedAt)}';
  final startShort =
      '${openedAt.day} ${_month(openedAt, locale)} ${_hhmm(openedAt)}';
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
      ? _hhmm(closedAt)
      : '${closedAt.day} ${_month(closedAt, locale)} ${_hhmm(closedAt)}';
  final full = '$start-$end';
  if (full.length <= reportWidth) return full;
  final short = '$startShort-$end';
  return short.length <= reportWidth ? short : short.substring(0, reportWidth);
}

/// Baris periode mode per tanggal: tanggalnya saja,
/// mis. `Wed, 26 Mar 2026`.
String formatDayPeriod({required DateTime day, required String locale}) =>
    '${_weekday(day, locale)}, ${day.day} ${_month(day, locale)} ${day.year}';

/// Cap waktu footer laporan, meniru contoh: `03 Nov'26 07:55`.
String formatGeneratedStamp(DateTime t, String locale) {
  final yy = (t.year % 100).toString().padLeft(2, '0');
  return '${t.day.toString().padLeft(2, '0')} ${_month(t, locale)}\'$yy '
      '${_hhmm(t)}';
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

String _fmt(int nusan) => formatNusan(BigInt.from(nusan) * BigInt.from(1000));

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

String get _shortRule =>
    '${' ' * (reportWidth - 16)}${'-' * 16}';

String _rightOnly(String value) =>
    value.padLeft(reportWidth);

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
}) {
  final footer = '${labels.generatedOn}:${formatGeneratedStamp(generatedAt, locale)}';

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
  s.add(_row(labels.subTotal, _fmt(summary.grossNusan)));
  s.add(_row(labels.discount, '-${_fmt(summary.lineDiscountNusan)}'));
  if (summary.orderDiscountNusan != 0) {
    s.add(_row(labels.orderDiscount, '-${_fmt(summary.orderDiscountNusan)}'));
  }
  s.add(_shortRule);
  s.add(_row('*${labels.totalOrder}', _fmt(summary.totalNusan)));
  s.add(_hr);
  s.add(_tender('LIGHTNING', _fmt(summary.totalNusan)));
  s.add(
    _tender(labels.invoicesLabel, '${summary.invoiceCount} ${labels.invUnit}'),
  );
  s.add(_tender('**VOID', '${summary.voids.count} ${labels.invUnit}'));
  s.add(_hr);
  s.add(_row('*${labels.totalOrderInfo}', _fmt(summary.totalNusan)));
  for (final cat in summary.categories) {
    final name = _categoryDisplay(labels, cat.category);
    s.add(name.length > reportWidth ? name.substring(0, reportWidth) : name);
    s.add(_row('  ${labels.qtyLabel}', _fmt(cat.itemQty)));
    s.add(_row('  ${labels.subTotal}', _fmt(cat.grossNusan)));
    if (cat.lineDiscountNusan > 0) {
      s.add(_row('  ${labels.discount}', '-${_fmt(cat.lineDiscountNusan)}'));
      s.add(_rightOnly(_fmt(cat.totalNusan)));
    }
  }
  if (summary.voids.count > 0) {
    final v = summary.voids;
    s.add(_hr);
    s.add(_row('**${labels.voidInfo}', '(${v.count} ${labels.invUnit})'));
    s.add(_row(labels.voidItemQty, _fmt(v.itemQty)));
    s.add(_row(labels.voidSubTotal, _fmt(v.grossNusan)));
    s.add(_row(labels.voidDiscount, '-${_fmt(v.discountNusan)}'));
    s.add(_shortRule);
    s.add(_row(labels.voidTotalOrder, _fmt(v.totalNusan)));
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
          '${_fmt(entry.unitPriceNusan).padLeft(7)} =',
          _fmt(entry.grossNusan),
        ),
      );
      if (entry.discountNusan > 0) {
        d.add(
          _amountLine(
            '  (Disc)${'-${_fmt(entry.discountNusan)}'.padLeft(10)} =',
            _fmt(entry.netNusan),
          ),
        );
        for (final part in entry.percentParts) {
          d.add(
            '   (${part.percent}%) ${part.units} x -${_fmt(part.perUnitNusan)}',
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
