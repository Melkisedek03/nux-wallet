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
  pointsDiscount: 'Points Discount',
  totalOrder: 'Total ORDER',
  totalOrderInfo: 'Total ORDER Info',
  invoicesLabel: '#Invoices',
  invUnit: 'inv.',
  cashLabel: 'CASH',
  qrisLabel: 'QRIS',
  incomeLabel: 'Income',
  openingFloatLabel: 'Opening Float',
  cashPositionLabel: 'Cash Position',
  heldInfoLabel: 'Held Info',
  heldTotalLabel: 'Held Total ORDER',
  pointsIssued: 'Points Issued',
  pointsPending: 'Points Pending',
  pointsRedeemed: 'Points Redeemed',
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

/// Tiga pesanan contoh: dua lunas (order1 TUNAI, order2 QRIS
/// berdiskon order), satu VOID.
List<CompletedOrder> fixture() => [
  buildCompletedOrder(
    time: DateTime(2026, 11, 2, 23, 10),
    lines: const [
      OrderLine(
        label: 'Amplop Grandia',
        unitPriceRp: 11000,
        qty: 1,
        category: 'MENTARI',
      ),
      OrderLine(
        label: 'Fotocopy (Hitam Putih)',
        unitPriceRp: 300,
        qty: 723,
        category: 'MENTARI',
      ),
      OrderLine(
        label: 'Fotocopy (Hitam Putih)',
        unitPriceRp: 300,
        qty: 76,
        category: 'MENTARI',
        discount: Discount.percent(14),
      ),
    ],
    orderDiscount: null,
    paymentHashHex: 'aa',
    payMethod: payMethodCash,
  ),
  buildCompletedOrder(
    time: DateTime(2026, 11, 3, 6, 40),
    lines: const [
      OrderLine(
        label: 'Jasa Jilid',
        unitPriceRp: 1000,
        qty: 1,
        category: 'MENTARI',
      ),
      OrderLine(
        label: 'Jasa Jilid',
        unitPriceRp: 3000,
        qty: 1,
        category: 'MENTARI',
      ),
      OrderLine(
        label: 'Jasa Jilid',
        unitPriceRp: 3000,
        qty: 4,
        category: 'MENTARI',
        discount: Discount.percent(14),
      ),
      OrderLine(label: 'Item Bebas', unitPriceRp: 50000, qty: 1),
    ],
    orderDiscount: const Discount.fixed(2000),
    paymentHashHex: 'bb',
    payMethod: payMethodQris,
  ),
  buildCompletedOrder(
    time: DateTime(2026, 11, 3, 7, 0),
    lines: const [
      OrderLine(
        label: 'Klip',
        unitPriceRp: 1500,
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
      expect(s.grossRp, 316700);
      expect(s.lineDiscountRp, 4872);
      expect(s.orderDiscountRp, 2000);
      expect(s.pointsDiscountRp, 0);
      expect(s.totalRp, 309828);
      // Rekonsiliasi jujur: Sub Total − Diskon Baris − Diskon
      // Order − Diskon Poin = Total ORDER.
      expect(
        s.grossRp - s.lineDiscountRp - s.orderDiscountRp - s.pointsDiscountRp,
        s.totalRp,
      );
    });

    test('tender terpisah TUNAI & QRIS dari metode record', () {
      final s = aggregateShiftSales(fixture(), from: _from, to: _to);
      expect(s.cashCount, 1);
      expect(s.cashTotalRp, 247508);
      expect(s.qrisCount, 1);
      expect(s.qrisTotalRp, 62320);
      expect(s.promoCount, 0);
    });

    test('per kategori: bernama dulu, tanpa kategori terakhir', () {
      final s = aggregateShiftSales(fixture(), from: _from, to: _to);
      expect(s.categories.length, 2);
      final mentari = s.categories.first;
      expect(mentari.category, 'MENTARI');
      expect(mentari.itemQty, 806);
      expect(mentari.grossRp, 266700);
      expect(mentari.lineDiscountRp, 4872);
      expect(mentari.totalRp, 261828);
      final other = s.categories.last;
      expect(other.category, '');
      expect(other.itemQty, 1);
      expect(other.grossRp, 50000);
      expect(other.lineDiscountRp, 0);
    });

    test('blok VOID terpisah dari angka penjualan', () {
      final s = aggregateShiftSales(fixture(), from: _from, to: _to);
      expect(s.voids.count, 1);
      expect(s.voids.itemQty, 3);
      expect(s.voids.grossRp, 4500);
      expect(s.voids.discountRp, 0);
      expect(s.voids.totalRp, 4500);
    });

    test('aggregateSales melompati record VOID', () {
      final r = aggregateSales(fixture(), from: _from, to: _to);
      expect(r.transactionCount, 2);
      expect(r.grossRp, 316700);
      expect(r.discountRp, 3192 + 3680);
      expect(r.netRp, 309828);
    });

    test('agregat poin: terbit, tertunda, ditukar — terpisah dari rupiah', () {
      final orders = [
        buildCompletedOrder(
          time: DateTime(2026, 11, 3, 9, 0),
          lines: const [OrderLine(label: 'Kopi', unitPriceRp: 10000, qty: 1)],
          orderDiscount: null,
          paymentHashHex: 'p1',
          payMethod: payMethodCash,
          pointsRedeemed: 2000,
          pointsDiscountRp: 2000,
          pointsEarned: 3000,
          pointsIssueStatus: issueStatusIssued,
        ),
        buildCompletedOrder(
          time: DateTime(2026, 11, 3, 10, 0),
          lines: const [OrderLine(label: 'Teh', unitPriceRp: 5000, qty: 1)],
          orderDiscount: null,
          paymentHashHex: null,
          payMethod: payMethodQris,
          pointsEarned: 1500,
          pointsIssueStatus: issueStatusPending,
        ),
      ];
      final s = aggregateShiftSales(
        orders,
        from: DateTime(2026, 11, 3),
        to: DateTime(2026, 11, 4),
      );
      expect(s.pointsDiscountRp, 2000);
      // Diskon poin TIDAK tercampur ke diskon order.
      expect(s.orderDiscountRp, 0);
      expect(s.totalRp, 13000);
      expect(
        s.grossRp - s.lineDiscountRp - s.orderDiscountRp - s.pointsDiscountRp,
        s.totalRp,
      );
      expect(s.pointsIssued, 3000);
      expect(s.pointsPending, 1500);
      expect(s.pointsRedeemed, 2000);
      expect(s.cashTotalRp, 8000);
      expect(s.qrisTotalRp, 5000);

      // Dokumen memuat baris diskon poin + blok poin.
      final docs = buildShiftReportDocuments(
        labels: exampleLabels(),
        periodLine: 'Tue, 3 Nov 2026',
        summary: s,
        details: aggregateMenuDetails(
          orders,
          from: DateTime(2026, 11, 3),
          to: DateTime(2026, 11, 4),
        ),
        generatedAt: DateTime(2026, 11, 3, 21, 0),
        locale: 'en',
      );
      expect(docs.summary, contains('Points Discount'));
      expect(docs.summary, contains('-2.000'));
      expect(docs.summary, contains('Points Issued'));
      expect(docs.summary, contains('Points Redeemed'));
      expect(docs.summary, contains('Points Pending'));
      for (final line in docs.summary.split('\n')) {
        expect(line.length, lessThanOrEqualTo(32), reason: line);
      }
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
      expect(fotocopy.grossRp, 239700);
      expect(fotocopy.discountRp, 3192);
      expect(fotocopy.netRp, 236508);
      expect(fotocopy.percentParts, const [
        PercentDiscountPart(percent: 14, units: 76, perUnitRp: 42),
      ]);

      // Item sama pada harga berbeda = entri terpisah, urut harga.
      final jilid = mentari.entries.where((e) => e.label == 'Jasa Jilid');
      expect(jilid.map((e) => e.unitPriceRp), [1000, 3000]);
      final jilid3000 = jilid.last;
      expect(jilid3000.qty, 5);
      expect(jilid3000.discountRp, 1680);
      expect(jilid3000.percentParts, const [
        PercentDiscountPart(percent: 14, units: 4, perUnitRp: 420),
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
          lines: const [OrderLine(label: 'Kopi', unitPriceRp: 5000, qty: 1)],
          orderDiscount: null,
          paymentHashHex: 'a',
        ),
        buildCompletedOrder(
          time: DateTime(2026, 11, 4, 0, 0, 0),
          lines: const [OrderLine(label: 'Kopi', unitPriceRp: 5000, qty: 2)],
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
    test('jam sampai detik; shift berjalan & tertutup tampil penuh', () {
      expect(
        formatShiftPeriod(
          openedAt: DateTime(2026, 11, 2, 22, 24, 35),
          closedAt: null,
          locale: 'en',
          stillOpenWord: 'Still Open',
        ),
        'Mon,2 Nov 22:24:35-(Still Open)',
      );
      expect(
        formatShiftPeriod(
          openedAt: DateTime(2026, 11, 2, 22, 24, 35),
          closedAt: DateTime(2026, 11, 2, 23, 5, 41),
          locale: 'en',
          stillOpenWord: 'Still Open',
        ),
        'Mon,2 Nov 22:24:35-23:05:41',
      );
    });

    test('periode Indonesia dipersingkat agar muat 32 kolom', () {
      final line = formatShiftPeriod(
        openedAt: DateTime(2026, 11, 2, 22, 24, 35),
        closedAt: null,
        locale: 'id',
        stillOpenWord: 'Masih Berjalan',
      );
      expect(line.length, lessThanOrEqualTo(32));
      expect(line, '2 Nov 22:24:35-(Masih Berjalan)');
    });

    test('dengan detik tetap muat 32 kolom: hari 2 digit & lintas hari',
        () {
      // Shift berjalan, tanggal 2 digit, kedua bahasa.
      final openEn = formatShiftPeriod(
        openedAt: DateTime(2026, 11, 12, 22, 24, 35),
        closedAt: null,
        locale: 'en',
        stillOpenWord: 'Still Open',
      );
      expect(openEn, 'Thu,12 Nov 22:24:35-(Still Open)');
      expect(openEn.length, lessThanOrEqualTo(32));
      final openId = formatShiftPeriod(
        openedAt: DateTime(2026, 11, 12, 22, 24, 35),
        closedAt: null,
        locale: 'id',
        stillOpenWord: 'Masih Berjalan',
      );
      expect(openId, '12 Nov 22:24:35-(Masih Berjalan)');
      expect(openId.length, lessThanOrEqualTo(32));
      // Shift tertutup melewati tengah malam: tanggal tutup ikut.
      final crossDay = formatShiftPeriod(
        openedAt: DateTime(2026, 11, 12, 22, 24, 35),
        closedAt: DateTime(2026, 11, 13, 1, 2, 3),
        locale: 'en',
        stillOpenWord: 'Still Open',
      );
      expect(crossDay, '12 Nov 22:24:35-13 Nov 01:02:03');
      expect(crossDay.length, lessThanOrEqualTo(32));
    });

    test('cap footer sampai detik', () {
      expect(
        formatGeneratedStamp(DateTime(2026, 11, 3, 7, 55, 12), 'en'),
        "03 Nov'26 07:55:12",
      );
      // Varian ringkas (tanpa tahun) untuk baris footer yang sempit.
      expect(
        formatGeneratedStampCompact(DateTime(2026, 11, 3, 7, 55, 12), 'en'),
        '03 Nov 07:55:12',
      );
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
        generatedAt: DateTime(2026, 11, 3, 7, 55, 12),
        locale: 'en',
      );

      final expectedSummary = [
        '--------------------------------',
        '--      SELECTED REPORT       --',
        '--------------------------------',
        'Mon,2 Nov 22:24:00-(Still Open)',
        '--------------------------------',
        'Item Qty                     807',
        'Sub Total                316.700',
        'Discount                  -4.872',
        'Order Discount            -2.000',
        '                ----------------',
        '*Total ORDER             309.828',
        '*Income                  309.828',
        '--------------------------------',
        'CASH           =         247.508',
        'QRIS           =          62.320',
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
        "Rpt.generated on:03 Nov 07:55:12",
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
        "Rpt.generated on:03 Nov 07:55:12",
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

  group('produk terlaris (aggregateProductSales)', () {
    CompletedOrder order(
      DateTime time,
      List<OrderLine> lines, {
      bool isVoid = false,
    }) => buildCompletedOrder(
      time: time,
      lines: lines,
      orderDiscount: null,
      paymentHashHex: 'xx',
      payMethod: payMethodCash,
      isVoid: isVoid,
    );

    final from = DateTime(2026, 11, 1);
    final to = DateTime(2026, 12, 1);

    test('kelompok menurut kode lintas pesanan, label dari yang terbaru',
        () {
      final entries = aggregateProductSales(
        [
          order(DateTime(2026, 11, 5, 9), const [
            OrderLine(
                code: 'PRD-001',
                label: 'Kopi Sachet',
                unitPriceRp: 5000,
                qty: 2),
          ]),
          order(DateTime(2026, 11, 6, 9), const [
            OrderLine(
                code: 'PRD-001',
                label: 'Kopi Sachet Baru',
                unitPriceRp: 6000,
                qty: 3),
          ]),
        ],
        from: from,
        to: to,
      );
      expect(entries, hasLength(1));
      expect(entries.single.code, 'PRD-001');
      expect(entries.single.label, 'Kopi Sachet Baru');
      expect(entries.single.qty, 5);
      expect(entries.single.grossRp, 2 * 5000 + 3 * 6000);
      expect(entries.single.netRp, entries.single.grossRp);
    });

    test('baris tanpa kode berkelompok menurut label', () {
      final entries = aggregateProductSales(
        [
          order(DateTime(2026, 11, 5), const [
            OrderLine(label: 'Item Bebas', unitPriceRp: 1000, qty: 1),
            OrderLine(label: 'Item Bebas', unitPriceRp: 2000, qty: 2),
          ]),
        ],
        from: from,
        to: to,
      );
      expect(entries, hasLength(1));
      expect(entries.single.code, '');
      expect(entries.single.qty, 3);
    });

    test('VOID dan di luar jendela tidak dihitung; diskon baris masuk net',
        () {
      final entries = aggregateProductSales(
        [
          order(DateTime(2026, 11, 5), const [
            OrderLine(
                code: 'A',
                label: 'Teh',
                unitPriceRp: 10000,
                qty: 2,
                discount: Discount.percent(10)),
          ]),
          order(
            DateTime(2026, 11, 5),
            const [
              OrderLine(
                  code: 'A', label: 'Teh', unitPriceRp: 10000, qty: 99),
            ],
            isVoid: true,
          ),
          order(DateTime(2026, 10, 1), const [
            OrderLine(
                code: 'A', label: 'Teh', unitPriceRp: 10000, qty: 50),
          ]),
        ],
        from: from,
        to: to,
      );
      expect(entries, hasLength(1));
      expect(entries.single.qty, 2);
      expect(entries.single.grossRp, 20000);
      expect(entries.single.discountRp, 2000);
      expect(entries.single.netRp, 18000);
    });

    test('urutan: qty desc, seri → net desc, seri lagi → nama; limit', () {
      final orders = [
        order(DateTime(2026, 11, 5), const [
          OrderLine(code: 'B', label: 'Beta', unitPriceRp: 9000, qty: 4),
          OrderLine(code: 'A', label: 'Alfa', unitPriceRp: 5000, qty: 4),
          OrderLine(code: 'C', label: 'Ceri', unitPriceRp: 1000, qty: 9),
        ]),
      ];
      final entries = aggregateProductSales(orders, from: from, to: to);
      expect(entries.map((e) => e.label), ['Ceri', 'Beta', 'Alfa']);
      final top2 = aggregateProductSales(orders, from: from, to: to, limit: 2);
      expect(top2.map((e) => e.label), ['Ceri', 'Beta']);
    });

    test('tanpa penjualan pada jendela → daftar kosong', () {
      expect(
        aggregateProductSales(const [], from: from, to: to),
        isEmpty,
      );
    });

    test('sort byName: abjad tak peka huruf, bukan urutan qty', () {
      final orders = [
        order(DateTime(2026, 11, 5), const [
          OrderLine(code: 'C', label: 'ceri', unitPriceRp: 1000, qty: 9),
          OrderLine(code: 'B', label: 'Beta', unitPriceRp: 9000, qty: 4),
          OrderLine(code: 'A', label: 'alfa', unitPriceRp: 5000, qty: 1),
        ]),
      ];
      final entries = aggregateProductSales(
        orders,
        from: from,
        to: to,
        sort: ProductSalesSort.byName,
      );
      expect(entries.map((e) => e.label), ['alfa', 'Beta', 'ceri']);
      // Bawaan tetap byQty (perilaku Produk Terlaris tidak berubah).
      final ranked = aggregateProductSales(orders, from: from, to: to);
      expect(ranked.map((e) => e.label), ['ceri', 'Beta', 'alfa']);
    });
  });

  group('laporan pembayaran (aggregatePaymentsByDay)', () {
    CompletedOrder sale({
      required DateTime time,
      required int totalRp,
      required int? shiftOpenedMs,
      bool isVoid = false,
    }) => CompletedOrder(
      time: time,
      lines: const [
        OrderLine(label: 'X', unitPriceRp: 1000, qty: 1),
      ],
      orderDiscount: null,
      era: storeEraRupiah,
      subtotalRp: totalRp,
      totalDiscountRp: 0,
      grandTotalRp: totalRp,
      paymentHashHex: 'xx',
      isVoid: isVoid,
      shiftOpenedMs: shiftOpenedMs,
    );

    StoreShift shift(DateTime openedAt, {DateTime? closedAt}) =>
        StoreShift(openedAt: openedAt, closedAt: closedAt, era: 'rp');

    final from = DateTime(2026, 11, 1);
    final to = DateTime(2026, 12, 1);

    test('shift lewat tengah malam tercatat di tanggal BUKA-nya', () {
      final night = shift(
        DateTime(2026, 11, 7, 22),
        closedAt: DateTime(2026, 11, 8, 2),
      );
      final ms = night.openedAt.millisecondsSinceEpoch;
      final days = aggregatePaymentsByDay(
        [
          sale(time: DateTime(2026, 11, 7, 23), totalRp: 50000, shiftOpenedMs: ms),
          sale(time: DateTime(2026, 11, 8, 1), totalRp: 30000, shiftOpenedMs: ms),
        ],
        [night],
        from: from,
        to: to,
      );
      expect(days, hasLength(1));
      expect(days.single.day, DateTime(2026, 11, 7));
      expect(days.single.totalRp, 80000);
      expect(days.single.invoiceCount, 2);
    });

    test('subtotal hari = gabungan shift hari itu; tanggal terbaru dulu',
        () {
      final s1 = shift(DateTime(2026, 11, 8, 8));
      final s2 = shift(DateTime(2026, 11, 8, 16));
      final s0 = shift(DateTime(2026, 11, 6, 9));
      int msOf(StoreShift s) => s.openedAt.millisecondsSinceEpoch;
      final days = aggregatePaymentsByDay(
        [
          sale(time: DateTime(2026, 11, 8, 9), totalRp: 10000, shiftOpenedMs: msOf(s1)),
          sale(time: DateTime(2026, 11, 8, 17), totalRp: 20000, shiftOpenedMs: msOf(s2)),
          sale(time: DateTime(2026, 11, 6, 10), totalRp: 7000, shiftOpenedMs: msOf(s0)),
        ],
        [s2, s0, s1], // urutan masukan acak
        from: from,
        to: to,
      );
      expect(days.map((d) => d.day), [DateTime(2026, 11, 8), DateTime(2026, 11, 6)]);
      expect(days.first.totalRp, 30000);
      // Dalam satu tanggal: shift urut jam buka menaik.
      expect(
        days.first.shifts.map((e) => e.shift.openedAt),
        [s1.openedAt, s2.openedAt],
      );
    });

    test('jendela menyaring menurut jam buka; VOID & tanpa shift diabaikan; shift kosong tak tampil',
        () {
      final before = shift(DateTime(2026, 10, 31, 23));
      final inside = shift(DateTime(2026, 11, 10, 8));
      final empty = shift(DateTime(2026, 11, 11, 8));
      int msOf(StoreShift s) => s.openedAt.millisecondsSinceEpoch;
      final days = aggregatePaymentsByDay(
        [
          sale(time: DateTime(2026, 11, 1, 1), totalRp: 99000, shiftOpenedMs: msOf(before)),
          sale(time: DateTime(2026, 11, 10, 9), totalRp: 15000, shiftOpenedMs: msOf(inside)),
          sale(time: DateTime(2026, 11, 10, 10), totalRp: 99000, shiftOpenedMs: msOf(inside), isVoid: true),
          sale(time: DateTime(2026, 11, 10, 11), totalRp: 99000, shiftOpenedMs: null),
        ],
        [before, inside, empty],
        from: from,
        to: to,
      );
      expect(days, hasLength(1));
      expect(days.single.day, DateTime(2026, 11, 10));
      expect(days.single.shifts, hasLength(1));
      expect(days.single.totalRp, 15000);
      expect(days.single.invoiceCount, 1);
    });
  });
}
