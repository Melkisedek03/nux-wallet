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
/// nusan, "Bayar" sebagai Grand Total, Tunai/Kembalian atau
/// metode QRIS, dan baris ketentuan nilai potongan per poin.
/// Perolehan poin tampil ringkas saja ("+20.000 nusan") di
/// bawah baris pembayaran bila pelanggan memang memperoleh
/// poin — tanpa label & tanpa status terbit (keputusan NUX
/// 4 Nov 2026; status penerbitan hidup di aplikasi).
/// Dan struk WAJIB selalu rekonsiliasi:
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

/// Lebar maksimum teks baris item ("<qty> <nama>") supaya
/// baris item SELALU satu baris dan tidak menggeser kolom
/// jumlah di ketiga keluaran. Batas paling ketat adalah
/// kolom nama cetak kertas: 8 dari 12 kolom pada 58mm
/// terbukti muat 20 karakter (ambang yang sama dengan yang
/// dipakai perender kertas sejak awal).
const storeReceiptItemNameMaxChars = 20;

/// Pangkas [text] menjadi maksimal [max] karakter; bila
/// dipotong, akhiri dengan '...' supaya kasir/pelanggan
/// tahu teksnya terpotong, bukan nama aslinya.
String fitReceiptEllipsis(String text, int max) {
  if (text.length <= max) return text;
  if (max <= 3) return text.substring(0, max);
  return '${text.substring(0, max - 3)}...';
}

/// Teks baris item struk: qty disisipkan di awal sebelum
/// nama ("1 Kopi Tubruk", "5 Roti Bakar" — permintaan NUX
/// 4 Nov 2026), lalu dipangkas ke
/// [storeReceiptItemNameMaxChars].
String receiptItemLineText(int qty, String label) =>
    fitReceiptEllipsis('$qty $label', storeReceiptItemNameMaxChars);

/// ID outlet perangkat: 6 karakter hex pertama node_id
/// ELNUX perangkat ini — identitas cabang yang mengikuti
/// dompet (node_id lahir dari frasa, jadi restore frasa =
/// ID outlet yang sama; ide NUX 4 Nov 2026). Tampil di
/// struk sesudah nomor token: "15/02a3c4".
String outletIdFromNodeId(String nodeId) =>
    nodeId.length <= 6 ? nodeId : nodeId.substring(0, 6);

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

  /// Banner penanda cetak ulang: '*** REPRINT ***'.
  final String reprintBanner;

  /// Label baris waktu cetak ulang: 'Reprint'.
  final String reprintLabel;

  /// Label baris kasir/operator: 'Kasir'.
  final String cashierLabel;

  /// Label baris diskon poin: "Pot. (2.000 nusan)".
  final String Function(int points) pointsDiscountLabel;

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
    required this.reprintBanner,
    required this.reprintLabel,
    required this.cashierLabel,
    required this.pointsDiscountLabel,
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

  /// Baris ketiga kop struk (kota); '' = tanpa baris kota.
  final String shopCity;
  final String customerName;

  /// Tanggal transaksi terformat 'dd/MM/yyyy HH:mm'
  /// (jam:menit disertakan — permintaan NUX 4 Nov 2026).
  final String dateText;

  /// Waktu CETAK ULANG terformat sama seperti [dateText];
  /// null = struk asli (bukan salinan). Bila terisi, pembangun
  /// elemen menyisipkan banner REPRINT + baris waktu ini —
  /// penanda anti-penyalahgunaan salinan nota (permintaan
  /// NUX 4 Nov 2026).
  final String? reprintText;

  /// Nama operator/kasir yang melayani (stempel operator
  /// record); '' = tanpa baris kasir (record sebelum Fase A).
  /// Permintaan NUX 4 Nov 2026: id kasir tampil di struk.
  final String cashierName;
  final int billNo;

  /// Nomor Bill terformat tampil ('INV261103-0002') — dari
  /// [billNo] + tanggal record via [formatBillNo].
  final String billNoText;
  final int tokenNo;

  /// ID outlet perangkat (6 karakter pertama node_id);
  /// '' = tak terbaca — baris token tampil tanpa '/id'.
  final String outletId;
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

  /// Pembayaran efektif record (dari effectivePaymentsOf):
  /// lebih dari satu = struk mencetak satu baris per metode
  /// (split payment); satu/kosong = jalur tampilan lama.
  final List<OrderPayment> paymentLines;
  final int pointsEarned;

  /// Status penerbitan poin record ('issued'/'pending'/…).
  final String pointsIssueStatus;
  final bool pointsEnabled;
  final int redeemRateRp;
  final String footerText;

  const StoreReceiptData({
    required this.shopName,
    required this.shopAddress,
    required this.shopCity,
    required this.customerName,
    required this.dateText,
    required this.billNo,
    required this.billNoText,
    required this.tokenNo,
    required this.outletId,
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
    this.paymentLines = const [],
    required this.pointsEarned,
    required this.pointsIssueStatus,
    required this.pointsEnabled,
    required this.redeemRateRp,
    required this.footerText,
    this.reprintText,
    required this.cashierName,
  });
}

/// Susun data struk dari record penjualan lunas + pengaturan
/// toko. [shopName] adalah nama kop yang sudah diputuskan
/// pemanggil (nama toko, atau panggilan cadangan dari
/// pengaturan printer); [footerText] teks penutup yang sudah
/// diputuskan (pengaturan toko, atau bawaan bahasa aplikasi).
/// Format cap waktu struk: 'dd/MM/yyyy HH:mm'.
String receiptTimestampText(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}/'
    '${t.month.toString().padLeft(2, '0')}/${t.year} '
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

StoreReceiptData buildStoreReceiptData({
  required CompletedOrder record,
  required StoreSettings settings,
  required String shopName,
  required String footerText,
  required String outletId,
  DateTime? reprintAt,
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
  final dateText = receiptTimestampText(t);
  return StoreReceiptData(
    shopName: shopName,
    shopAddress: settings.storeAddress,
    shopCity: settings.storeCity,
    customerName: record.customerName,
    dateText: dateText,
    reprintText:
        reprintAt == null ? null : receiptTimestampText(reprintAt),
    cashierName: record.operatorName,
    billNo: record.billNo,
    billNoText: formatBillNo(t, record.billNo, outletId: outletId),
    tokenNo: record.tokenNo,
    outletId: outletId,
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
    paymentLines: effectivePaymentsOf(record),
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
///
/// Fase B (5 Nov 2026): bila [outletId] terisi (id cabang
/// dari node_id perangkat), formatnya membawa prefix outlet:
/// 'INV-<outlet>-<YYMMDD>-<urut 4>' — nomor unik per cabang
/// walau tanggal & urutnya sama di cabang lain.
String formatBillNo(DateTime time, int seq, {String outletId = ''}) {
  final yy = (time.year % 100).toString().padLeft(2, '0');
  final mm = time.month.toString().padLeft(2, '0');
  final dd = time.day.toString().padLeft(2, '0');
  final seqText = seq.toString().padLeft(4, '0');
  return outletId.isEmpty
      ? 'INV$yy$mm$dd-$seqText'
      : 'INV-$outletId-$yy$mm$dd-$seqText';
}

/// Nomor urut bill berikutnya untuk TANGGAL kalender lokal
/// [date]: jumlah record era rupiah pada tanggal yang sama
/// yang sudah MENGONSUMSI nomor (billNo > 0) + 1. Murni &
/// deterministik dari record yang tersimpan.
///
/// Yang dihitung adalah nomor yang terpakai, BUKAN status
/// lunas saat ini: penjualan yang di-VOID SESUDAH lunas
/// (Fase A) nomornya tetap terhitung — nomor INV tidak boleh
/// dipakai ulang, karena salinan & laporan lama yang membawa
/// nomor itu sudah beredar. VOID pra-lunas tidak bernomor
/// (billNo 0 — ia tidak pernah menjadi struk pelanggan),
/// jadi tidak ikut terhitung.
///
/// Urut berjalan per hari LINTAS shift (menggantikan urut
/// per shift): tanggal kini tertanam di nomor bill, jadi
/// urut per shift akan melahirkan nomor INV yang sama dua
/// kali di hari yang sama — cacat identitas faktur.
int nextBillSeqForDate(List<CompletedOrder> orders, DateTime date) {
  var count = 0;
  for (final order in orders) {
    if (!order.isRupiahEra || order.billNo <= 0) continue;
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

/// Baris item: "<qty> <nama>" kiri (SUDAH terpangkas ≤
/// [storeReceiptItemNameMaxChars] oleh pembangun, jadi
/// selalu satu baris), jumlah (kotor) rata kanan.
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

/// Baris kosong: jeda satu baris — pemisah visual antara
/// keterangan nilai potongan dan footer (permintaan NUX
/// 4 Nov 2026).
class ReceiptSpacer extends StoreReceiptElement {
  const ReceiptSpacer();
}

String _rp(int rp) => 'Rp${formatRupiah(rp)}';

/// Label metode bayar di struk: tunai & QRIS dari label
/// terlokalisasi; metode master lain tampil dengan namanya
/// sendiri persis seperti yang diatur toko.
String _receiptMethodLabel(StoreReceiptLabels labels, String method) =>
    method == payMethodCash
        ? labels.cashLabel
        : method == payMethodQris
            ? labels.qrisLabel
            : method;

/// Kepala baris meta struk untuk perender teks & cetak:
/// "Tanggal:" / "No. Bill:" / "Order/Outlet:" diikuti nilainya.
/// Label + ':' dirapatkan ke kolom 10 (permintaan NUX 4 Nov
/// 2026 — kolom 12 sebelumnya menyisakan spasi terlalu banyak
/// sebelum nilai); label yang sudah ≥ 10 karakter (Order/
/// Outlet) cukup satu spasi.
String receiptMetaHead(String label) {
  final raw = '$label:';
  return raw.length >= 10 ? '$raw ' : raw.padRight(10);
}

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
  if (data.shopCity.isNotEmpty) {
    out.add(ReceiptCenterText(data.shopCity));
  }
  out.add(const ReceiptDashedRule());
  if (data.reprintText != null) {
    // Penanda salinan (permintaan NUX 4 Nov 2026): banner
    // tegas + waktu cetak ulangnya, tepat di bawah kop —
    // salinan tidak boleh bisa berlagak nota asli.
    out.add(ReceiptCenterText(labels.reprintBanner, bold: true));
    out.add(ReceiptMetaRow(labels.reprintLabel, data.reprintText!));
  }
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
    out.add(
      ReceiptMetaRow(
        labels.tokenNoLabel,
        data.outletId.isNotEmpty
            ? '${data.tokenNo}/${data.outletId}'
            : '${data.tokenNo}',
      ),
    );
  }
  if (data.cashierName.isNotEmpty) {
    out.add(ReceiptMetaRow(labels.cashierLabel, data.cashierName));
  }
  out.add(const ReceiptDashedRule());
  out.add(ReceiptItemsHeader(labels.itemHeader, labels.amountHeader));
  for (final item in data.items) {
    out.add(
      ReceiptItemRow(
        receiptItemLineText(item.qty, item.label),
        _rp(item.grossRp),
      ),
    );
    if (item.qty > 1) {
      // Harga satuan gaya nota: "@Rp5.000" (permintaan NUX
      // 4 Nov 2026, menggantikan "2 x Rp5.000").
      out.add(ReceiptItemSub('@${_rp(item.unitPriceRp)}'));
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
  if (data.paymentLines.length > 1) {
    // Split payment: satu baris per metode sejumlah yang
    // DITERAPKAN ke tagihan, lalu kembalian bila ada.
    for (final payment in data.paymentLines) {
      out.add(
        ReceiptRow(
          _receiptMethodLabel(labels, payment.method),
          _rp(payment.amountRp),
        ),
      );
    }
    if (data.changeRp > 0) {
      out.add(ReceiptRow(labels.changeLabel, _rp(data.changeRp)));
    }
  } else if (data.payMethod == payMethodCash) {
    out.add(ReceiptRow(labels.cashLabel, _rp(data.cashReceivedRp)));
    if (data.changeRp > 0) {
      out.add(ReceiptRow(labels.changeLabel, _rp(data.changeRp)));
    }
  } else if (data.payMethod != null) {
    out.add(
      ReceiptRow(
        _receiptMethodLabel(labels, data.payMethod!),
        _rp(data.grandTotalRp),
      ),
    );
  } else {
    out.add(ReceiptRow(labels.promoLabel, _rp(0)));
  }
  if (data.pointsEnabled && data.pointsEarned > 0) {
    // Info perolehan ringkas tepat di bawah baris pembayaran
    // (di bawah Kembalian): "+20.000 nusan" — cukup itu saja,
    // tanpa label dan tanpa status terbit (keputusan NUX
    // 4 Nov 2026).
    out.add(ReceiptTextLine('+${formatRupiah(data.pointsEarned)} nusan'));
  }
  if (data.pointsEnabled) {
    out.add(
      ReceiptTextLine(
        labels.pointsRuleText(formatRupiah(data.redeemRateRp)),
      ),
    );
  }
  if (data.footerText.isNotEmpty) {
    // Jeda satu baris antara keterangan nilai potongan
    // (baris program poin terakhir) dan footer.
    if (data.pointsEnabled) out.add(const ReceiptSpacer());
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
          final line = '${receiptMetaHead(label)}$value';
          out.add(line.length > width ? line.substring(0, width) : line);
        }
      case ReceiptItemsHeader(:final itemLabel, :final amountLabel):
        out.add(_spread(itemLabel, amountLabel, width));
      case ReceiptItemRow(:final name, :final amountText):
        // Selalu SATU baris: nama sudah terpangkas oleh
        // pembangun; pangkas sekali lagi hanya bila jumlah
        // rupiahnya sendiri luar biasa panjang, supaya kolom
        // jumlah tidak pernah terdorong.
        final fitted = fitReceiptEllipsis(
          name,
          width - amountText.length - 1,
        );
        out.add(_spread(fitted, amountText, width));
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
      case ReceiptSpacer():
        out.add('');
    }
  }
  return out;
}
