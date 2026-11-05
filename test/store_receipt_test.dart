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
  tokenNoLabel: 'Order/Outlet',
  itemHeader: 'Item',
  amountHeader: 'Jumlah',
  discountLabel: 'Diskon Item',
  orderDiscountLabel: 'Diskon Order',
  grandTotalLabel: 'Bayar',
  cashLabel: 'Tunai',
  changeLabel: 'Kembalian',
  qrisLabel: 'QRIS',
  promoLabel: 'Tanpa pembayaran (promosi)',
  noteWord: 'Cat.',
  reprintBanner: '*** REPRINT ***',
  reprintLabel: 'Reprint',
  cashierLabel: 'Kasir',
  pointsDiscountLabel: (p) => 'Pot. (${formatRupiah(p)} nusan)',
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

StoreReceiptData richData({
  StoreSettings settings = StoreSettings.defaults,
  DateTime? reprintAt,
  String footerText = 'Terima Kasih\nSilakan berkunjung kembali',
}) {
  return buildStoreReceiptData(
    record: richRecord(),
    settings: settings.copyWith(
      storeAddress: 'Jl. Merdeka No. 1',
      storeCity: 'Jakarta',
    ),
    shopName: 'Kafe Nusantara',
    footerText: footerText,
    outletId: '02a3c4',
    reprintAt: reprintAt,
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
      expect(data.dateText, '03/11/2026 13:45');
      expect(data.outletId, '02a3c4');
      expect(data.billNoText, 'INV-02a3c4-261103-0001');
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
        outletId: '',
      );
      expect(plain.showBillNo, isFalse);
      expect(plain.showTokenNo, isFalse);
    });

    test('reprintAt mengisi reprintText; tanpa itu null', () {
      final reprinted = richData(reprintAt: DateTime(2026, 11, 4, 20, 15));
      expect(reprinted.reprintText, '04/11/2026 20:15');
      expect(richData().reprintText, isNull);
    });

    test('receiptMetaHead: kolom 10, label panjang satu spasi', () {
      expect(receiptMetaHead('Tanggal'), 'Tanggal:  ');
      expect(receiptMetaHead('No. Bill'), 'No. Bill: ');
      expect(receiptMetaHead('Order/Outlet'), 'Order/Outlet: ');
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
        'Tanggal:  03/11/2026 13:45',
        'No. Bill: INV-02a3c4-261103-0001',
        'Order/Outlet: 15/02a3c4',
        '-' * 32,
        'Item${' ' * 22}Jumlah',
        '2 Kopi Tubruk${' ' * 11}Rp10.000',
        '  @Rp5.000',
        '  (Disc) -Rp1.000 = Rp9.000',
        '  Cat.: tanpa gula',
        '1 Roti Bakar${' ' * 12}Rp15.000',
        '-' * 32,
        '3/2${' ' * 21}Rp25.000',
        'Diskon Item${' ' * 13}-Rp1.000',
        'Diskon Order${' ' * 12}-Rp2.000',
        'Pot. (2.000 nusan)${' ' * 6}-Rp2.000',
        '-' * 32,
        'Bayar${' ' * 19}Rp20.000',
        'Tunai${' ' * 19}Rp50.000',
        'Kembalian${' ' * 15}Rp30.000',
        '+20.000 nusan',
        '1 nusan = pot. Rp1',
        '',
        '          Terima Kasih',
        '   Silakan berkunjung kembali',
      ]);
    });

    test('footer dua baris: tiap baris elemen tengah sendiri, '
        'tidak dibungkus ulang', () {
      final elements = buildStoreReceiptElements(richData(), idLabels());
      final centers = elements.whereType<ReceiptCenterText>().toList();
      expect(centers[centers.length - 2].text, 'Terima Kasih');
      expect(centers.last.text, 'Silakan berkunjung kembali');
      final lines = storeReceiptTextLines(elements);
      expect(lines[lines.length - 2], '          Terima Kasih');
      expect(lines.last, '   Silakan berkunjung kembali');
    });

    test('footer satu baris (isian toko lama) tetap dibungkus '
        'kata per kata seperti sebelumnya', () {
      final lines = storeReceiptTextLines(
        buildStoreReceiptElements(
          richData(footerText: 'Terima kasih & silakan berkunjung kembali'),
          idLabels(),
        ),
      );
      expect(lines[lines.length - 2], '     Terima kasih & silakan');
      expect(lines.last, '       berkunjung kembali');
    });

    test('salinan reprint: banner + waktu cetak ulang tepat '
        'di bawah kop, sebelum Pelanggan', () {
      final lines = storeReceiptTextLines(
        buildStoreReceiptElements(
          richData(reprintAt: DateTime(2026, 11, 4, 20, 15)),
          idLabels(),
        ),
      );
      // Kop 3 baris + garis, lalu banner terpusat & baris
      // Reprint, baru blok Pelanggan seperti struk asli.
      expect(lines[3], '-' * 32);
      expect(lines[4], '        *** REPRINT ***');
      expect(lines[5], 'Reprint:  04/11/2026 20:15');
      expect(lines[6], 'Pelanggan:${' ' * 11}Advika Mate');
      // Struk asli (tanpa reprintAt) tidak punya banner.
      final original = storeReceiptTextLines(
        buildStoreReceiptElements(richData(), idLabels()),
      );
      expect(original.any((l) => l.contains('REPRINT')), isFalse);
    });

    test('baris Kasir tampil dari stempel operator record, '
        'tepat sesudah Order/Outlet; tanpa stempel tidak ada', () {
      final stamped = buildCompletedOrder(
        time: DateTime(2026, 11, 3, 9, 0),
        lines: const [OrderLine(label: 'Teh', unitPriceRp: 3000, qty: 1)],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: payMethodCash,
        cashReceivedRp: 3000,
        operatorId: 'op-1',
        operatorName: 'Sari',
      ).withReceiptMeta(billNo: 1, tokenNo: 15);
      List<String> linesFor(CompletedOrder r) => storeReceiptTextLines(
            buildStoreReceiptElements(
              buildStoreReceiptData(
                record: r,
                settings: StoreSettings.defaults,
                shopName: 'Toko',
                footerText: '',
                outletId: '02a3c4',
              ),
              idLabels(),
            ),
          );
      final lines = linesFor(stamped);
      final tokenIdx = lines.indexWhere((l) => l.startsWith('Order/Outlet'));
      expect(tokenIdx, greaterThanOrEqualTo(0));
      expect(lines[tokenIdx + 1], 'Kasir:    Sari');
      // Record tanpa stempel operator (era sebelum Fase A):
      // tidak ada baris Kasir sama sekali.
      final unstamped = buildCompletedOrder(
        time: DateTime(2026, 11, 3, 9, 0),
        lines: const [OrderLine(label: 'Teh', unitPriceRp: 3000, qty: 1)],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: payMethodCash,
        cashReceivedRp: 3000,
      ).withReceiptMeta(billNo: 1, tokenNo: 15);
      expect(
        linesFor(unstamped).any((l) => l.startsWith('Kasir')),
        isFalse,
      );
    });

    test('tanpa nama pelanggan tidak ada baris Customer; info '
        'perolehan ringkas tampil walau poin tertunda', () {
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
          outletId: '',
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
      // Baris kalimat = info perolehan ringkas (tanpa status,
      // walau poinnya tertunda) + keterangan nilai potongan.
      expect(texts, ['+3.000 nusan', '1 nusan = pot. Rp1']);
    });
  });

  group('ID outlet dari node_id', () {
    test('6 karakter pertama node_id; string pendek apa adanya', () {
      expect(
        outletIdFromNodeId(
          '02a3c442a933b1f0a630d56151e84a19f17b662541b2e305a3878b825'
          '5c572981a',
        ),
        '02a3c4',
      );
      expect(outletIdFromNodeId('02ab'), '02ab');
      expect(outletIdFromNodeId(''), '');
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
          outletId: '',
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
    CompletedOrder paidAt(
      DateTime t, {
      bool voided = false,
      String? era,
      int billNo = 0,
    }) {
      final base = buildCompletedOrder(
        time: t,
        lines: const [OrderLine(label: 'X', unitPriceRp: 1000, qty: 1)],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: payMethodCash,
        cashReceivedRp: 1000,
        isVoid: voided,
      );
      final numbered = billNo > 0 ? base.withReceiptMeta(billNo: billNo) : base;
      if (era == null) return numbered;
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
        billNo: billNo,
      );
    }

    test('urut dari nomor yang terpakai pada tanggal yang sama, '
        'lintas shift; VOID pra-lunas & era nusan tak dihitung', () {
      final orders = [
        paidAt(DateTime(2026, 11, 2, 20, 0), billNo: 1), // kemarin
        paidAt(DateTime(2026, 11, 3, 8, 30), billNo: 1), // pagi
        // VOID pra-lunas: tidak pernah bernomor.
        paidAt(DateTime(2026, 11, 3, 9, 0), voided: true),
        paidAt(DateTime(2026, 11, 3, 9, 15), era: storeEraNusan),
        paidAt(DateTime(2026, 11, 3, 13, 30), billNo: 2), // siang
      ];
      // Dua shift di hari yang sama: urut BERLANJUT (bukan
      // mulai lagi per shift) supaya nomor INV tak ganda.
      expect(nextBillSeqForDate(orders, DateTime(2026, 11, 3, 14, 0)), 3);
      expect(nextBillSeqForDate(orders, DateTime(2026, 11, 2, 21, 0)), 2);
      expect(nextBillSeqForDate(const [], DateTime(2026, 11, 3)), 1);
    });

    test('VOID sesudah lunas: nomornya tetap terhitung — INV '
        'tidak dipakai ulang', () {
      final orders = [
        paidAt(DateTime(2026, 11, 3, 8, 30), billNo: 1),
        paidAt(DateTime(2026, 11, 3, 9, 0), billNo: 2).markVoid(),
        paidAt(DateTime(2026, 11, 3, 13, 30), billNo: 3),
      ];
      expect(nextBillSeqForDate(orders, DateTime(2026, 11, 3, 14, 0)), 4);
    });

    test('ganti tanggal kalender: urut kembali ke 1', () {
      final orders = [
        paidAt(DateTime(2026, 11, 3, 23, 55), billNo: 1),
        paidAt(DateTime(2026, 11, 3, 23, 59), billNo: 2),
      ];
      expect(nextBillSeqForDate(orders, DateTime(2026, 11, 4, 0, 5)), 1);
    });

    test('formatBillNo: INV + YYMMDD + urut 4 digit zero-padded, '
        'tumbuh alami di atas 9999', () {
      final d = DateTime(2026, 11, 3, 13, 45);
      expect(formatBillNo(d, 1), 'INV261103-0001');
      // Fase B: prefix outlet dari node_id perangkat.
      expect(
        formatBillNo(d, 1, outletId: '02a3c4'),
        'INV-02a3c4-261103-0001',
      );
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
