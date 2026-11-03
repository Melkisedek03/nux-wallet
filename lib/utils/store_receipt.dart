/// Model struk pelanggan Mode Toko v2 — SATU sumber kebenaran
/// tampilan struk untuk tiga keluaran yang harus tampil sama:
/// cetak kertas 58mm (PrintService.printStoreReceipt), gambar
/// JPG untuk dibagikan, dan pratinjau struk di layar.
///
/// Layout mengikuti contoh struk yang disetujui NUX (3 Nov
/// 2026): kop nama+alamat toko di tengah, garis putus-putus,
/// meta Customer/Date/Bill No/Token No, tabel Item/Amount,
/// baris hitung "{qty}/{baris}" berperan sebagai Subtotal,
/// "Grand Total" besar di bawah, footer ucapan di tengah.
///
/// Yang TIDAK dikorbankan oleh layout itu (pedoman miniPOS §4
/// tetap wajib): baris diskon (baris/order), baris diskon poin
/// nusan, TOTAL BAYAR sebagai Grand Total, Tunai/Kembalian atau
/// metode QRIS, "Poin nusan diperoleh", dan baris ketentuan
/// nilai potongan per poin. Dan struk WAJIB selalu rekonsiliasi:
/// Σ item (kotor) − diskon baris − diskon order − diskon poin
/// = Grand Total (cacat contoh — Grand Total tak sama dengan
/// jumlah item — tidak ditiru).
library;

import '../services/store_order_history.dart';
import '../services/store_settings.dart';
import 'format.dart';

/// Lebar struk teks (kolom monospace, kertas 58mm) — sama
/// dengan lebar dokumen laporan shift.
const storeReceiptWidth = 32;

/// Label teks struk, diisi layar dari l10n bahasa aplikasi.
/// Struktur & tata letak tetap; yang mengikuti bahasa hanya
/// labelnya (pola yang sama dengan ShiftReportLabels).
class StoreReceiptLabels {
  final String customerLabel;
  final String dateLabel;
  final String billNoLabel;
  final String tokenNoLabel;
  final String itemHeader;
  final String amountHeader;
  final String discountLabel;
  final String orderDiscountLabel;
  final String grandTotalLabel;
  final String cashLabel;
  final String changeLabel;
  final String qrisLabel;
  final String promoLabel;
  final String noteWord;

  /// Label baris diskon poin: "Diskon poin nusan (2.000 poin)".
  final String Function(int points) pointsDiscountLabel;

  /// Baris perolehan poin (sudah diterbitkan / belum).
  final String Function(int points) pointsEarnedText;
  final String Function(int points) pointsPendingText;

  /// Baris ketentuan nilai potongan: menerima nilai per poin
  /// yang SUDAH terformat ("1.000"), mengembalikan kalimat
  /// lengkapnya.
  final String Function(String rateFormatted) pointsRuleText;

  const StoreReceiptLabels({
    required this.customerLabel,
    required this.dateLabel,
    required this.billNoLabel,
    required this.tokenNoLabel,
    required this.itemHeader,
    required this.amountHeader,
    required this.discountLabel,
    required this.orderDiscountLabel,
    required this.grandTotalLabel,
    required this.cashLabel,
    required this.changeLabel,
    required this.qrisLabel,
    required this.promoLabel,
    required this.noteWord,
    required this.pointsDiscountLabel,
    required this.pointsEarnedText,
    required this.pointsPendingText,
    required this.pointsRuleText,
  });
}

/// Satu item pada struk: angka dari baris pesanan apa adanya —
/// [grossRp] adalah harga × qty SEBELUM diskon baris (jumlah
/// item-item inilah yang rekonsiliasi ke baris Subtotal).
class StoreReceiptItem {
  final String label;
  final int qty;
  final int unitPriceRp;
  final int grossRp;
  final int discountRp;
  final String note;

  const StoreReceiptItem({
    required this.label,
    required this.qty,
    required this.unitPriceRp,
    required this.grossRp,
    required this.discountRp,
    required this.note,
  });

  int get netRp => grossRp - discountRp;
}

/// Data struk lengkap satu transaksi lunas — dibangun murni
/// dari record penjualan + pengaturan toko oleh
/// [buildStoreReceiptData]; tiga keluaran membaca data ini.
class StoreReceiptData {
  final String shopName;
  final String shopAddress;
  final String customerName;

  /// Tanggal transaksi terformat 'dd/MM/yyyy' (gaya contoh).
  final String dateText;
  final int billNo;

  /// Nomor Bill terformat tampil ('INV261103-0002') — dari
  /// [billNo] + tanggal record via [formatBillNo].
  final String billNoText;
  final int tokenNo;
  final bool showBillNo;
  final bool showTokenNo;
  final List<StoreReceiptItem> items;

  /// Σ qty semua baris & jumlah baris — pasangan "{qty}/{baris}"
  /// pada baris hitung yang berperan sebagai Subtotal.
  final int totalQty;
  final int lineCount;

  /// Σ harga × qty sebelum diskon apa pun (nilai baris hitung).
  final int subtotalGrossRp;
  final int lineDiscountRp;
  final int orderDiscountRp;
  final int pointsRedeemed;
  final int pointsDiscountRp;
  final int grandTotalRp;
  final String? payMethod;
  final int cashReceivedRp;
  final int changeRp;
  final int pointsEarned;

  /// Status penerbitan poin record ('issued'/'pending'/…).
  final String pointsIssueStatus;
  final bool pointsEnabled;
  final int redeemRateRp;
  final String footerText;

  const StoreReceiptData({
    required this.shopName,
    required this.shopAddress,
    required this.customerName,
    required this.dateText,
    required this.billNo,
    required this.billNoText,
    required this.tokenNo,
    required this.showBillNo,
    required this.showTokenNo,
    required this.items,
    required this.totalQty,
    required this.lineCount,
    required this.subtotalGrossRp,
    required this.lineDiscountRp,
    required this.orderDiscountRp,
    required this.pointsRedeemed,
    required this.pointsDiscountRp,
    required this.grandTotalRp,
    required this.payMethod,
    required this.cashReceivedRp,
    required this.changeRp,
    required this.pointsEarned,
    required this.pointsIssueStatus,
    required this.pointsEnabled,
    required this.redeemRateRp,
    required this.footerText,
  });
}

/// Susun data struk dari record penjualan lunas + pengaturan
/// toko. [shopName] adalah nama kop yang sudah diputuskan
/// pemanggil (nama toko, atau panggilan cadangan dari
/// pengaturan printer); [footerText] teks penutup yang sudah
/// diputuskan (pengaturan toko, atau bawaan bahasa aplikasi).
StoreReceiptData buildStoreReceiptData({
  required CompletedOrder record,
  required StoreSettings settings,
  required String shopName,
  required String footerText,
}) {
  final items = [
    for (final line in record.lines)
      StoreReceiptItem(
        label: line.label,
        qty: line.qty,
        unitPriceRp: line.unitPriceRp,
        grossRp: line.lineGrossRp,
        discountRp: line.lineDiscountRp,
        note: line.note,
      ),
  ];
  final gross = items.fold(0, (s, i) => s + i.grossRp);
  final lineDiscount = items.fold(0, (s, i) => s + i.discountRp);
  // Diskon order = total diskon record − diskon baris − diskon
  // poin (record menyimpan total gabungannya; sisanya adalah
  // bagian diskon order — penurunan yang sama dengan laporan).
  var orderDiscount =
      record.totalDiscountRp - lineDiscount - record.pointsDiscountRp;
  if (orderDiscount < 0) orderDiscount = 0;
  final t = record.time;
  final dateText =
      '${t.day.toString().padLeft(2, '0')}/'
      '${t.month.toString().padLeft(2, '0')}/${t.year}';
  return StoreReceiptData(
    shopName: shopName,
    shopAddress: settings.storeAddress,
    customerName: record.customerName,
    dateText: dateText,
    billNo: record.billNo,
    billNoText: formatBillNo(t, record.billNo),
    tokenNo: record.tokenNo,
    showBillNo: record.billNo > 0,
    showTokenNo: settings.showTokenNumber && record.tokenNo > 0,
    items: items,
    totalQty: items.fold(0, (s, i) => s + i.qty),
    lineCount: items.length,
    subtotalGrossRp: gross,
    lineDiscountRp: lineDiscount,
    orderDiscountRp: orderDiscount,
    pointsRedeemed: record.pointsRedeemed,
    pointsDiscountRp: record.pointsDiscountRp,
    grandTotalRp: record.grandTotalRp,
    payMethod: record.payMethod,
    cashReceivedRp: record.cashReceivedRp,
    changeRp: record.changeRp,
    pointsEarned: record.pointsEarned,
    pointsIssueStatus: record.pointsIssueStatus,
    pointsEnabled: settings.pointsEnabled,
    redeemRateRp: settings.redeemRateRp,
    footerText: footerText,
  );
}

/// Format tampil Nomor Bill: 'INV' + tanggal transaksi
/// YYMMDD + '-' + nomor urut 4 digit zero-padded. Urut di
/// atas 9999 tumbuh alami menjadi 5 digit dst — tidak
/// terpotong. Murni: [time] adalah timestamp record, [seq]
/// nomor urut per tanggal yang tersimpan di record.
/// Contoh (dari permintaan NUX): 3 Nov 2026 urut 2 →
/// 'INV261103-0002'.
String formatBillNo(DateTime time, int seq) {
  final yy = (time.year % 100).toString().padLeft(2, '0');
  final mm = time.month.toString().padLeft(2, '0');
  final dd = time.day.toString().padLeft(2, '0');
  return 'INV$yy$mm$dd-${seq.toString().padLeft(4, '0')}';
}

/// Nomor urut bill berikutnya untuk TANGGAL kalender lokal
/// [date]: jumlah record LUNAS era rupiah pada tanggal yang
/// sama + 1. Murni & deterministik dari record yang
/// tersimpan — VOID tidak bernomor (ia tidak pernah menjadi
/// struk pelanggan).
///
/// Urut berjalan per hari LINTAS shift (menggantikan urut
/// per shift): tanggal kini tertanam di nomor bill, jadi
/// urut per shift akan melahirkan nomor INV yang sama dua
/// kali di hari yang sama — cacat identitas faktur.
int nextBillSeqForDate(List<CompletedOrder> orders, DateTime date) {
  var count = 0;
  for (final order in orders) {
    if (!order.isRupiahEra || order.isVoid) continue;
    final t = order.time;
    if (t.year != date.year || t.month != date.month || t.day != date.day) {
      continue;
    }
    count++;
  }
  return count + 1;
}

// ---------------------------------------------------------------------
// Elemen struk (urutan tampilan bersama tiga keluaran)
// ---------------------------------------------------------------------

/// Satu elemen tampilan struk. Ketiga perender (ESC/POS, teks
/// 32 kolom, widget pratinjau) menerjemahkan urutan elemen yang
/// sama ini dengan gaya masing-masing.
sealed class StoreReceiptElement {
  const StoreReceiptElement();
}

/// Teks rata tengah (kop, footer); [big] = penekanan terbesar
/// elemen teks biasa (nama toko).
class ReceiptCenterText extends StoreReceiptElement {
  final String text;
  final bool bold;
  final bool big;
  const ReceiptCenterText(this.text, {this.bold = false, this.big = false});
}

/// Garis putus-putus pemisah selebar struk.
class ReceiptDashedRule extends StoreReceiptElement {
  const ReceiptDashedRule();
}

/// Baris meta "Label: nilai". [spread] true = nilai rata kanan
/// (baris Customer ala contoh); false = nilai mengikuti kolom
/// tetap sesudah label (Date/Bill No/Token No ala contoh).
class ReceiptMetaRow extends StoreReceiptElement {
  final String label;
  final String value;
  final bool spread;
  const ReceiptMetaRow(this.label, this.value, {this.spread = false});
}

/// Kepala tabel item: "Item" kiri tebal, "Amount" kanan tebal.
class ReceiptItemsHeader extends StoreReceiptElement {
  final String itemLabel;
  final String amountLabel;
  const ReceiptItemsHeader(this.itemLabel, this.amountLabel);
}

/// Baris item: nama kiri, jumlah (kotor) rata kanan.
class ReceiptItemRow extends StoreReceiptElement {
  final String name;
  final String amountText;
  const ReceiptItemRow(this.name, this.amountText);
}

/// Baris penjelas menjorok di bawah item (qty × harga, rincian
/// diskon baris, catatan).
class ReceiptItemSub extends StoreReceiptElement {
  final String text;
  const ReceiptItemSub(this.text);
}

/// Baris label–jumlah biasa: baris hitung Subtotal, diskon,
/// tender (Tunai/Kembalian/QRIS).
class ReceiptRow extends StoreReceiptElement {
  final String label;
  final String amountText;
  final bool bold;
  const ReceiptRow(this.label, this.amountText, {this.bold = false});
}

/// Baris Grand Total: penekanan terbesar pada struk.
class ReceiptGrandTotal extends StoreReceiptElement {
  final String label;
  final String amountText;
  const ReceiptGrandTotal(this.label, this.amountText);
}

/// Baris kalimat penuh rata kiri (perolehan poin, ketentuan
/// nilai potongan).
class ReceiptTextLine extends StoreReceiptElement {
  final String text;
  const ReceiptTextLine(this.text);
}

String _rp(int rp) => 'Rp${formatRupiah(rp)}';

/// Susun urutan elemen struk dari [data] + [labels] — urutan
/// ini yang dirender ketiga keluaran, kata per kata sama.
List<StoreReceiptElement> buildStoreReceiptElements(
  StoreReceiptData data,
  StoreReceiptLabels labels,
) {
  final out = <StoreReceiptElement>[];
  out.add(ReceiptCenterText(data.shopName, bold: true, big: true));
  if (data.shopAddress.isNotEmpty) {
    out.add(ReceiptCenterText(data.shopAddress));
  }
  out.add(const ReceiptDashedRule());
  if (data.customerName.isNotEmpty) {
    out.add(
      ReceiptMetaRow(labels.customerLabel, data.customerName, spread: true),
    );
    out.add(const ReceiptDashedRule());
  }
  out.add(ReceiptMetaRow(labels.dateLabel, data.dateText));
  if (data.showBillNo) {
    out.add(ReceiptMetaRow(labels.billNoLabel, data.billNoText));
  }
  if (data.showTokenNo) {
    out.add(ReceiptMetaRow(labels.tokenNoLabel, '${data.tokenNo}'));
  }
  out.add(const ReceiptDashedRule());
  out.add(ReceiptItemsHeader(labels.itemHeader, labels.amountHeader));
  for (final item in data.items) {
    out.add(ReceiptItemRow(item.label, _rp(item.grossRp)));
    if (item.qty > 1) {
      out.add(ReceiptItemSub('${item.qty} x ${_rp(item.unitPriceRp)}'));
    }
    if (item.discountRp > 0) {
      out.add(
        ReceiptItemSub('(Disc) -${_rp(item.discountRp)} = ${_rp(item.netRp)}'),
      );
    }
    if (item.note.isNotEmpty) {
      out.add(ReceiptItemSub('${labels.noteWord}: ${item.note}'));
    }
  }
  out.add(const ReceiptDashedRule());
  // Baris hitung berperan sebagai Subtotal (jangan gandakan).
  out.add(
    ReceiptRow(
      '${data.totalQty}/${data.lineCount}',
      _rp(data.subtotalGrossRp),
      bold: true,
    ),
  );
  if (data.lineDiscountRp > 0) {
    out.add(ReceiptRow(labels.discountLabel, '-${_rp(data.lineDiscountRp)}'));
  }
  if (data.orderDiscountRp > 0) {
    out.add(
      ReceiptRow(labels.orderDiscountLabel, '-${_rp(data.orderDiscountRp)}'),
    );
  }
  if (data.pointsDiscountRp > 0) {
    out.add(
      ReceiptRow(
        labels.pointsDiscountLabel(data.pointsRedeemed),
        '-${_rp(data.pointsDiscountRp)}',
      ),
    );
  }
  out.add(const ReceiptDashedRule());
  out.add(ReceiptGrandTotal(labels.grandTotalLabel, _rp(data.grandTotalRp)));
  if (data.payMethod == payMethodCash) {
    out.add(ReceiptRow(labels.cashLabel, _rp(data.cashReceivedRp)));
    if (data.changeRp > 0) {
      out.add(ReceiptRow(labels.changeLabel, _rp(data.changeRp)));
    }
  } else if (data.payMethod == payMethodQris) {
    out.add(ReceiptRow(labels.qrisLabel, _rp(data.grandTotalRp)));
  } else {
    out.add(ReceiptRow(labels.promoLabel, _rp(0)));
  }
  if (data.pointsEnabled && data.pointsEarned > 0) {
    out.add(
      ReceiptTextLine(
        data.pointsIssueStatus == issueStatusIssued
            ? labels.pointsEarnedText(data.pointsEarned)
            : labels.pointsPendingText(data.pointsEarned),
      ),
    );
  }
  if (data.pointsEnabled) {
    out.add(
      ReceiptTextLine(
        labels.pointsRuleText(formatRupiah(data.redeemRateRp)),
      ),
    );
  }
  if (data.footerText.isNotEmpty) {
    out.add(ReceiptCenterText(data.footerText));
  }
  return out;
}

// ---------------------------------------------------------------------
// Render teks 32 kolom (snapshot uji + dasar pratinjau teks)
// ---------------------------------------------------------------------

String _centered(String text, int width) {
  final t = text.length > width ? text.substring(0, width) : text;
  final pad = (width - t.length) ~/ 2;
  return '${' ' * pad}$t';
}

String _spread(String label, String value, int width) {
  if (label.length + 1 + value.length > width) {
    return '$label $value'.substring(0, width);
  }
  return '$label${' ' * (width - label.length - value.length)}$value';
}

/// Bungkus teks ke baris-baris ≤ [width] (kata per kata; kata
/// yang lebih panjang dipotong keras) dengan [indent] di awal
/// tiap baris hasil.
List<String> _wrap(String text, int width, {String indent = ''}) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final lines = <String>[];
  var current = indent;
  for (final word in words) {
    var w = word;
    while (w.length > width - indent.length) {
      if (current.trim().isNotEmpty) {
        lines.add(current);
        current = indent;
      }
      final room = width - indent.length;
      lines.add('$indent${w.substring(0, room)}');
      w = w.substring(room);
    }
    if (current == indent) {
      current = '$indent$w';
    } else if (current.length + 1 + w.length <= width) {
      current = '$current $w';
    } else {
      lines.add(current);
      current = '$indent$w';
    }
  }
  if (current.trim().isNotEmpty || lines.isEmpty) lines.add(current);
  return lines;
}

/// Render elemen struk menjadi baris teks monospace
/// [storeReceiptWidth] kolom — bentuk kanonis struk untuk uji
/// snapshot dan pemeriksaan cepat.
List<String> storeReceiptTextLines(List<StoreReceiptElement> elements) {
  const width = storeReceiptWidth;
  final out = <String>[];
  for (final e in elements) {
    switch (e) {
      case ReceiptCenterText(:final text):
        out.addAll(_wrap(text, width).map((l) => _centered(l, width)));
      case ReceiptDashedRule():
        out.add('-' * width);
      case ReceiptMetaRow(:final label, :final value, :final spread):
        if (spread) {
          out.add(_spread('$label:', value, width));
        } else {
          final head = '$label:'.padRight(12);
          out.add(
            '$head$value'.length > width
                ? '$head$value'.substring(0, width)
                : '$head$value',
          );
        }
      case ReceiptItemsHeader(:final itemLabel, :final amountLabel):
        out.add(_spread(itemLabel, amountLabel, width));
      case ReceiptItemRow(:final name, :final amountText):
        if (name.length + 1 + amountText.length <= width) {
          out.add(_spread(name, amountText, width));
        } else {
          out.addAll(_wrap(name, width));
          out.add(amountText.padLeft(width));
        }
      case ReceiptItemSub(:final text):
        out.addAll(_wrap(text, width, indent: '  '));
      case ReceiptRow(:final label, :final amountText):
        if (label.length + 1 + amountText.length <= width) {
          out.add(_spread(label, amountText, width));
        } else {
          // Label panjang (mis. diskon poin): label dulu,
          // jumlah rata kanan di baris berikut — sama dengan
          // perilaku cetak kertas.
          out.addAll(_wrap(label, width));
          out.add(amountText.padLeft(width));
        }
      case ReceiptGrandTotal(:final label, :final amountText):
        out.add(_spread(label, amountText, width));
      case ReceiptTextLine(:final text):
        out.addAll(_wrap(text, width));
    }
  }
  return out;
}
