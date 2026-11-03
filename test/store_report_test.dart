import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_order_history.dart';
import 'package:nux_wallet/services/store_shift.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:nux_wallet/utils/store_report.dart';

/// Label Inggris meniru contoh PoS NUX untuk uji snapshot.
ShiftReportLabels exampleLabels() => ShiftReportLabels(
  summaryTitle: 'SELECTED REPORT',
  detailsTitle: 'MENU SALES DETAILS',
  itemQty: 'Item Qty',
  subTotal: 'Sub Total',
  discount: 'Discount',
  orderDiscount: 'Order Discount',
  totalOrder: 'Total ORDER',
  totalOrderInfo: 'Total ORDER Info',
  invoicesLabel: '#Invoices',
  invUnit: 'inv.',
  voidInfo: 'VOID Info',
  voidItemQty: 'VOID Item Qty',
  voidSubTotal: 'VOID Sub Total',
  voidDiscount: 'VOID Discount',
  voidTotalOrder: 'VOID Total ORDER',
  qtyLabel: 'Qty',
  otherCategory: 'OTHER',
  generatedOn: 'Rpt.generated on',
  menusText: (count) => '$count menu(s)',
);

/// Tiga pesanan contoh: dua lunas (satu berdiskon order), satu VOID.
List<CompletedOrder> fixture() => [
  buildCompletedOrder(
    time: DateTime(2026, 11, 2, 23, 10),
    lines: const [
      OrderLine(
        label: 'Amplop Grandia',
        unitPriceNusan: 11000,
        qty: 1,
        category: 'MENTARI',
      ),
      OrderLine(
        label: 'Fotocopy (Hitam Putih)',
        unitPriceNusan: 300,
        qty: 723,
        category: 'MENTARI',
      ),
      OrderLine(
        label: 'Fotocopy (Hitam Putih)',
        unitPriceNusan: 300,
        qty: 76,
        category: 'MENTARI',
        discount: Discount.percent(14),
      ),
    ],
    orderDiscount: null,
    paymentHashHex: 'aa',
  ),
  buildCompletedOrder(
    time: DateTime(2026, 11, 3, 6, 40),
    lines: const [
      OrderLine(
        label: 'Jasa Jilid',
        unitPriceNusan: 1000,
        qty: 1,
        category: 'MENTARI',
      ),
      OrderLine(
        label: 'Jasa Jilid',
        unitPriceNusan: 3000,
        qty: 1,
        category: 'MENTARI',
      ),
      OrderLine(
        label: 'Jasa Jilid',
        unitPriceNusan: 3000,
        qty: 4,
        category: 'MENTARI',
        discount: Discount.percent(14),
      ),
      OrderLine(label: 'Item Bebas', unitPriceNusan: 50000, qty: 1),
    ],
    orderDiscount: const Discount.fixed(2000),
    paymentHashHex: 'bb',
  ),
  buildCompletedOrder(
    time: DateTime(2026, 11, 3, 7, 0),
    lines: const [
      OrderLine(
        label: 'Klip',
        unitPriceNusan: 1500,
        qty: 3,
        category: 'MENTARI',
      ),
    ],
    orderDiscount: null,
    paymentHashHex: 'cc',
    isVoid: true,
  ),
];

final _from = DateTime(2026, 11, 2, 22, 24);
final _to = DateTime(2026, 11, 3, 7, 55);

void main() {
  group('agregasi shift', () {
    test('angka ringkasan + rekonsiliasi diskon dua tingkat', () {
      final s = aggregateShiftSales(fixture(), from: _from, to: _to);
      expect(s.invoiceCount, 2);
      expect(s.itemQty, 807);
      expect(s.grossNusan, 316700);
      expect(s.lineDiscountNusan, 4872);
      expect(s.orderDiscountNusan, 2000);
      expect(s.totalNusan, 309828);
      // Rekonsiliasi jujur: Sub Total − Diskon Baris − Diskon
      // Order = Total ORDER.
      expect(
        s.grossNusan - s.lineDiscountNusan - s.orderDiscountNusan,
        s.totalNusan,
      );
    });

    test('per kategori: bernama dulu, tanpa kategori terakhir', () {
      final s = aggregateShiftSales(fixture(), from: _from, to: _to);
      expect(s.categories.length, 2);
      final mentari = s.categories.first;
      expect(mentari.category, 'MENTARI');
      expect(mentari.itemQty, 806);
      expect(mentari.grossNusan, 266700);
      expect(mentari.lineDiscountNusan, 4872);
      expect(mentari.totalNusan, 261828);
      final other = s.categories.last;
      expect(other.category, '');
      expect(other.itemQty, 1);
      expect(other.grossNusan, 50000);
      expect(other.lineDiscountNusan, 0);
    });

    test('blok VOID terpisah dari angka penjualan', () {
      final s = aggregateShiftSales(fixture(), from: _from, to: _to);
      expect(s.voids.count, 1);
      expect(s.voids.itemQty, 3);
      expect(s.voids.grossNusan, 4500);
      expect(s.voids.discountNusan, 0);
      expect(s.voids.totalNusan, 4500);
    });

    test('aggregateSales (v1) melompati record VOID', () {
      final r = aggregateSales(fixture(), from: _from, to: _to);
      expect(r.transactionCount, 2);
      expect(r.grossNusan, 316700);
      expect(r.discountNusan, 3192 + 3680);
      expect(r.netNusan, 309828);
    });
  });

  group('rincian per item', () {
    test('pengelompokan (label, harga) + diskon persen sebagian unit', () {
      final groups = aggregateMenuDetails(fixture(), from: _from, to: _to);
      expect(groups.length, 2);
      final mentari = groups.first;
      expect(mentari.category, 'MENTARI');
      expect(mentari.entries.length, 4);

      // Fotocopy: 799 unit total, hanya 76 terdiskon 14% —
      // meniru persis contoh NUX (799 x 300, Disc -3.192,
      // (14%) 76 x -42).
      final fotocopy = mentari.entries[1];
      expect(fotocopy.label, 'Fotocopy (Hitam Putih)');
      expect(fotocopy.qty, 799);
      expect(fotocopy.grossNusan, 239700);
      expect(fotocopy.discountNusan, 3192);
      expect(fotocopy.netNusan, 236508);
      expect(fotocopy.percentParts, const [
        PercentDiscountPart(percent: 14, units: 76, perUnitNusan: 42),
      ]);

      // Item sama pada harga berbeda = entri terpisah, urut harga.
      final jilid = mentari.entries.where((e) => e.label == 'Jasa Jilid');
      expect(jilid.map((e) => e.unitPriceNusan), [1000, 3000]);
      final jilid3000 = jilid.last;
      expect(jilid3000.qty, 5);
      expect(jilid3000.discountNusan, 1680);
      expect(jilid3000.percentParts, const [
        PercentDiscountPart(percent: 14, units: 4, perUnitNusan: 420),
      ]);

      // Item VOID tidak masuk rincian penjualan.
      expect(
        groups.expand((g) => g.entries).any((e) => e.label == 'Klip'),
        isFalse,
      );
    });
  });

  group('jendela per tanggal', () {
    test('record dipotong tepat di batas tengah malam lokal', () {
      final orders = [
        buildCompletedOrder(
          time: DateTime(2026, 11, 3, 23, 59, 59),
          lines: const [
            OrderLine(label: 'Kopi', unitPriceNusan: 5000, qty: 1),
          ],
          orderDiscount: null,
          paymentHashHex: 'a',
        ),
        buildCompletedOrder(
          time: DateTime(2026, 11, 4, 0, 0, 0),
          lines: const [
            OrderLine(label: 'Kopi', unitPriceNusan: 5000, qty: 2),
          ],
          orderDiscount: null,
          paymentHashHex: 'b',
        ),
      ];
      final day3 = aggregateShiftSales(
        orders,
        from: DateTime(2026, 11, 3),
        to: DateTime(2026, 11, 4),
      );
      expect(day3.invoiceCount, 1);
      expect(day3.itemQty, 1);
      final day4 = aggregateShiftSales(
        orders,
        from: DateTime(2026, 11, 4),
        to: DateTime(2026, 11, 5),
      );
      expect(day4.invoiceCount, 1);
      expect(day4.itemQty, 2);
    });

    test('countShiftsInWindow menghitung shift yang bersinggungan', () {
      final shifts = [
        StoreShift(
          openedAt: DateTime(2026, 11, 2, 22, 24),
          closedAt: DateTime(2026, 11, 3, 6, 0),
        ),
        StoreShift(openedAt: DateTime(2026, 11, 3, 8, 0)),
      ];
      final now = DateTime(2026, 11, 3, 12, 0);
      expect(
        countShiftsInWindow(
          shifts,
          from: DateTime(2026, 11, 3),
          to: DateTime(2026, 11, 4),
          now: now,
        ),
        2,
      );
      expect(
        countShiftsInWindow(
          shifts,
          from: DateTime(2026, 11, 5),
          to: DateTime(2026, 11, 6),
          now: now,
        ),
        0,
      );
    });
  });

  group('format periode', () {
    test('shift berjalan meniru contoh; tertutup menampilkan jam tutup', () {
      expect(
        formatShiftPeriod(
          openedAt: DateTime(2026, 11, 2, 22, 24),
          closedAt: null,
          locale: 'en',
          stillOpenWord: 'Still Open',
        ),
        'Mon,2 Nov 22:24-...(Still Open)',
      );
      expect(
        formatShiftPeriod(
          openedAt: DateTime(2026, 11, 2, 22, 24),
          closedAt: DateTime(2026, 11, 2, 23, 5),
          locale: 'en',
          stillOpenWord: 'Still Open',
        ),
        'Mon,2 Nov 22:24-23:05',
      );
    });

    test('periode Indonesia dipersingkat agar muat 32 kolom', () {
      final line = formatShiftPeriod(
        openedAt: DateTime(2026, 11, 2, 22, 24),
        closedAt: null,
        locale: 'id',
        stillOpenWord: 'Masih Berjalan',
      );
      expect(line.length, lessThanOrEqualTo(32));
      expect(line, 'Sen,2 Nov 22:24-(Masih Berjalan)');
    });
  });

  group('snapshot dokumen', () {
    test('kedua dokumen persis format contoh', () {
      final summary = aggregateShiftSales(fixture(), from: _from, to: _to);
      final details = aggregateMenuDetails(fixture(), from: _from, to: _to);
      final docs = buildShiftReportDocuments(
        labels: exampleLabels(),
        periodLine: formatShiftPeriod(
          openedAt: _from,
          closedAt: null,
          locale: 'en',
          stillOpenWord: 'Still Open',
        ),
        summary: summary,
        details: details,
        generatedAt: DateTime(2026, 11, 3, 7, 55),
        locale: 'en',
      );

      final expectedSummary = [
        '--------------------------------',
        '--      SELECTED REPORT       --',
        '--------------------------------',
        'Mon,2 Nov 22:24-...(Still Open)',
        '--------------------------------',
        'Item Qty                     807',
        'Sub Total                316.700',
        'Discount                  -4.872',
        'Order Discount            -2.000',
        '                ----------------',
        '*Total ORDER             309.828',
        '--------------------------------',
        'LIGHTNING      =         309.828',
        '#Invoices      =          2 inv.',
        '**VOID         =          1 inv.',
        '--------------------------------',
        '*Total ORDER Info        309.828',
        'MENTARI',
        '  Qty                        806',
        '  Sub Total              266.700',
        '  Discount                -4.872',
        '                         261.828',
        'OTHER',
        '  Qty                          1',
        '  Sub Total               50.000',
        '--------------------------------',
        '**VOID Info             (1 inv.)',
        'VOID Item Qty                  3',
        'VOID Sub Total             4.500',
        'VOID Discount                 -0',
        '                ----------------',
        'VOID Total ORDER           4.500',
        '================================',
        "Rpt.generated on:03 Nov'26 07:55",
        '================================',
      ].join('\n');
      expect(docs.summary, expectedSummary);

      final expectedDetails = [
        '--------------------------------',
        '--     MENU SALES DETAILS     --',
        '--------------------------------',
        '--------------------------------',
        'MENTARI                4 menu(s)',
        '--------------------------------',
        'Amplop Grandia',
        '    1 x  11.000 =         11.000',
        'Fotocopy (Hitam Putih)',
        '  799 x     300 =        239.700',
        '  (Disc)    -3.192 =     236.508',
        '   (14%) 76 x -42',
        'Jasa Jilid',
        '    1 x   1.000 =          1.000',
        'Jasa Jilid',
        '    5 x   3.000 =         15.000',
        '  (Disc)    -1.680 =      13.320',
        '   (14%) 4 x -420',
        '--------------------------------',
        'OTHER                  1 menu(s)',
        '--------------------------------',
        'Item Bebas',
        '    1 x  50.000 =         50.000',
        '================================',
        "Rpt.generated on:03 Nov'26 07:55",
        '================================',
      ].join('\n');
      expect(docs.details, expectedDetails);

      // Semua baris kedua dokumen muat lebar kertas 58mm.
      for (final line in docs.summary.split('\n')) {
        expect(line.length, lessThanOrEqualTo(32), reason: line);
      }
      for (final line in docs.details.split('\n')) {
        expect(line.length, lessThanOrEqualTo(32), reason: line);
      }
    });
  });
}
