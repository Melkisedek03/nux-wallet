import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_order_history.dart';
import 'package:nux_wallet/services/store_settings.dart';
import 'package:nux_wallet/utils/format.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:nux_wallet/utils/store_receipt.dart';

StoreReceiptLabels idLabels() => StoreReceiptLabels(
  customerLabel: 'Pelanggan',
  dateLabel: 'Tanggal',
  billNoLabel: 'No. Bill',
  tokenNoLabel: 'No. Token',
  itemHeader: 'Item',
  amountHeader: 'Jumlah',
  discountLabel: 'Diskon',
  orderDiscountLabel: 'Diskon Order',
  grandTotalLabel: 'Bayar',
  cashLabel: 'Tunai',
  changeLabel: 'Kembalian',
  qrisLabel: 'QRIS',
  promoLabel: 'Tanpa pembayaran (promosi)',
  noteWord: 'Cat.',
  pointsDiscountLabel: (p) => 'Diskon poin nusan (${formatRupiah(p)} poin)',
  pointsRuleText: (rate) => '1 nusan = pot. Rp$rate',
);

/// Transaksi contoh lengkap: diskon baris (persen) + diskon
/// order + tukar poin terverifikasi + tunai dengan kembalian +
/// poin diperoleh terbit + nama pelanggan + Bill/Token No.
CompletedOrder richRecord() {
  final base = buildCompletedOrder(
    id: 's1',
    time: DateTime(2026, 11, 3, 13, 45),
    lines: const [
      OrderLine(
        label: 'Kopi Tubruk',
        unitPriceRp: 5000,
        qty: 2,
        discount: Discount.percent(10),
        note: 'tanpa gula',
      ),
      OrderLine(label: 'Roti Bakar', unitPriceRp: 15000, qty: 1),
    ],
    orderDiscount: const Discount.fixed(2000),
    paymentHashHex: 'cafe',
    payMethod: payMethodCash,
    cashReceivedRp: 50000,
    pointsRedeemed: 2000,
    pointsDiscountRp: 2000,
    pointsEarned: 20000,
    pointsIssueStatus: issueStatusIssued,
    customerName: 'Advika Mate',
  );
  return base.withReceiptMeta(billNo: 1, tokenNo: 15);
}

StoreReceiptData richData({StoreSettings settings = StoreSettings.defaults}) {
  return buildStoreReceiptData(
    record: richRecord(),
    settings: settings.copyWith(
      storeAddress: 'Jl. Merdeka No. 1',
      storeCity: 'Jakarta',
    ),
    shopName: 'Kafe Nusantara',
    footerText: 'Terima kasih & silakan berkunjung kembali',
  );
}

void main() {
  group('data struk', () {
    test('angka diturunkan rekonsiliasi: kotor − diskon baris − '
        'diskon order − diskon poin = total akhir', () {
      final data = richData();
      expect(data.subtotalGrossRp, 25000);
      expect(data.lineDiscountRp, 1000);
      expect(data.orderDiscountRp, 2000);
      expect(data.pointsDiscountRp, 2000);
      expect(
        data.subtotalGrossRp -
            data.lineDiscountRp -
            data.orderDiscountRp -
            data.pointsDiscountRp,
        data.grandTotalRp,
      );
      expect(data.grandTotalRp, 20000);
      expect(data.changeRp, 30000);
      expect(data.totalQty, 3);
      expect(data.lineCount, 2);
      expect(data.shopCity, 'Jakarta');
      expect(data.dateText, '03/11/2026');
      expect(data.billNoText, 'INV261103-0001');
      expect(data.showBillNo, isTrue);
      expect(data.showTokenNo, isTrue);
    });

    test('token disembunyikan bila pengaturan mematikannya, '
        'bill hilang bila record tak bernomor', () {
      final hidden = richData(
        settings: StoreSettings.defaults.copyWith(showTokenNumber: false),
      );
      expect(hidden.showTokenNo, isFalse);
      final plain = buildStoreReceiptData(
        record: buildCompletedOrder(
          time: DateTime(2026, 11, 3),
          lines: const [OrderLine(label: 'Teh', unitPriceRp: 3000, qty: 1)],
          orderDiscount: null,
          paymentHashHex: null,
          payMethod: payMethodQris,
        ),
        settings: StoreSettings.defaults,
        shopName: 'Toko',
        footerText: '',
      );
      expect(plain.showBillNo, isFalse);
      expect(plain.showTokenNo, isFalse);
    });
  });

  group('snapshot baris teks struk', () {
    test('transaksi contoh lengkap, kata per kata', () {
      final lines = storeReceiptTextLines(
        buildStoreReceiptElements(richData(), idLabels()),
      );
      expect(lines, [
        '         Kafe Nusantara',
        '       Jl. Merdeka No. 1',
        '            Jakarta',
        '-' * 32,
        'Pelanggan:${' ' * 11}Advika Mate',
        '-' * 32,
        'Tanggal:    03/11/2026',
        'No. Bill:   INV261103-0001',
        'No. Token:  15',
        '-' * 32,
        'Item${' ' * 22}Jumlah',
        '2 Kopi Tubruk${' ' * 11}Rp10.000',
        '  2 x Rp5.000',
        '  (Disc) -Rp1.000 = Rp9.000',
        '  Cat.: tanpa gula',
        '1 Roti Bakar${' ' * 12}Rp15.000',
        '-' * 32,
        '3/2${' ' * 21}Rp25.000',
        'Diskon${' ' * 18}-Rp1.000',
        'Diskon Order${' ' * 12}-Rp2.000',
        'Diskon poin nusan (2.000 poin)',
        '${' ' * 24}-Rp2.000',
        '-' * 32,
        'Bayar${' ' * 19}Rp20.000',
        'Tunai${' ' * 19}Rp50.000',
        'Kembalian${' ' * 15}Rp30.000',
        '1 nusan = pot. Rp1',
        '',
        '     Terima kasih & silakan',
        '       berkunjung kembali',
      ]);
    });

    test('tanpa nama pelanggan tidak ada baris Customer; baris '
        'perolehan poin tidak dicetak walau ada poin tertunda', () {
      final record = buildCompletedOrder(
        time: DateTime(2026, 11, 3, 9, 0),
        lines: const [OrderLine(label: 'Teh', unitPriceRp: 3000, qty: 1)],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: payMethodQris,
        pointsEarned: 3000,
        pointsIssueStatus: issueStatusPending,
      );
      final elements = buildStoreReceiptElements(
        buildStoreReceiptData(
          record: record,
          settings: StoreSettings.defaults,
          shopName: 'Toko',
          footerText: '',
        ),
        idLabels(),
      );
      expect(
        elements.whereType<ReceiptMetaRow>().any(
          (e) => e.label == 'Pelanggan',
        ),
        isFalse,
      );
      final texts = elements
          .whereType<ReceiptTextLine>()
          .map((e) => e.text)
          .toList();
      // Satu-satunya baris kalimat = keterangan nilai potongan;
      // perolehan poin (terbit maupun tertunda) tak dicetak.
      expect(texts, ['1 nusan = pot. Rp1']);
    });
  });

  group('baris item: qty di awal & nama satu baris', () {
    test('receiptItemLineText: qty selalu tampil, nama panjang '
        'terpangkas 20 karakter berakhiran ...', () {
      expect(receiptItemLineText(1, 'Kopi Tubruk'), '1 Kopi Tubruk');
      expect(receiptItemLineText(5, 'Roti Bakar'), '5 Roti Bakar');
      expect(
        receiptItemLineText(12, 'Kopi Tubruk Spesial Gula Aren'),
        '12 Kopi Tubruk Sp...',
      );
    });

    test('baris item nama panjang tetap SATU baris teks, kolom '
        'jumlah tidak terdorong', () {
      final record = buildCompletedOrder(
        time: DateTime(2026, 11, 3, 10, 0),
        lines: const [
          OrderLine(
            label: 'Kopi Tubruk Spesial Gula Aren',
            unitPriceRp: 7000,
            qty: 12,
          ),
        ],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: payMethodCash,
        cashReceivedRp: 84000,
      );
      final elements = buildStoreReceiptElements(
        buildStoreReceiptData(
          record: record,
          settings: StoreSettings.defaults,
          shopName: 'Toko',
          footerText: '',
        ),
        idLabels(),
      );
      final row = elements.whereType<ReceiptItemRow>().single;
      expect(row.name, '12 Kopi Tubruk Sp...');
      final lines = storeReceiptTextLines(elements);
      expect(lines, contains('12 Kopi Tubruk Sp...    Rp84.000'));
    });
  });

  group('penomoran bill per tanggal & format INV', () {
    CompletedOrder paidAt(DateTime t, {bool voided = false, String? era}) {
      final base = buildCompletedOrder(
        time: t,
        lines: const [OrderLine(label: 'X', unitPriceRp: 1000, qty: 1)],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: payMethodCash,
        cashReceivedRp: 1000,
        isVoid: voided,
      );
      if (era == null) return base;
      return CompletedOrder(
        time: base.time,
        lines: base.lines,
        orderDiscount: base.orderDiscount,
        era: era,
        subtotalRp: base.subtotalRp,
        totalDiscountRp: base.totalDiscountRp,
        grandTotalRp: base.grandTotalRp,
        paymentHashHex: base.paymentHashHex,
        isVoid: base.isVoid,
        payMethod: base.payMethod,
        cashReceivedRp: base.cashReceivedRp,
      );
    }

    test('urut dari record lunas era rupiah pada tanggal yang '
        'sama, lintas shift; VOID & era nusan tak dihitung', () {
      final orders = [
        paidAt(DateTime(2026, 11, 2, 20, 0)), // kemarin
        paidAt(DateTime(2026, 11, 3, 8, 30)), // shift pagi
        paidAt(DateTime(2026, 11, 3, 9, 0), voided: true), // VOID
        paidAt(DateTime(2026, 11, 3, 9, 15), era: storeEraNusan),
        paidAt(DateTime(2026, 11, 3, 13, 30)), // shift siang
      ];
      // Dua shift di hari yang sama: urut BERLANJUT (bukan
      // mulai lagi per shift) supaya nomor INV tak ganda.
      expect(nextBillSeqForDate(orders, DateTime(2026, 11, 3, 14, 0)), 3);
      expect(nextBillSeqForDate(orders, DateTime(2026, 11, 2, 21, 0)), 2);
      expect(nextBillSeqForDate(const [], DateTime(2026, 11, 3)), 1);
    });

    test('ganti tanggal kalender: urut kembali ke 1', () {
      final orders = [
        paidAt(DateTime(2026, 11, 3, 23, 55)),
        paidAt(DateTime(2026, 11, 3, 23, 59)),
      ];
      expect(nextBillSeqForDate(orders, DateTime(2026, 11, 4, 0, 5)), 1);
    });

    test('formatBillNo: INV + YYMMDD + urut 4 digit zero-padded, '
        'tumbuh alami di atas 9999', () {
      final d = DateTime(2026, 11, 3, 13, 45);
      expect(formatBillNo(d, 1), 'INV261103-0001');
      // Contoh persis dari permintaan NUX.
      expect(formatBillNo(d, 2), 'INV261103-0002');
      expect(formatBillNo(d, 99), 'INV261103-0099');
      expect(formatBillNo(d, 100), 'INV261103-0100');
      expect(formatBillNo(d, 9999), 'INV261103-9999');
      expect(formatBillNo(d, 10000), 'INV261103-10000');
      expect(
        formatBillNo(DateTime(2027, 1, 5), 7),
        'INV270105-0007',
      );
    });
  });
}
