import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_order_history.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

CompletedOrder sample({
  required DateTime time,
  List<OrderLine>? lines,
  Discount? orderDiscount,
  String? hash = 'ab12',
}) {
  return buildCompletedOrder(
    time: time,
    lines:
        lines ??
        const [
          OrderLine(
            code: 'A1',
            label: 'Kopi',
            unitPriceNusan: 5000,
            qty: 2,
            discount: Discount.percent(10),
          ),
          OrderLine(label: 'Item Bebas', unitPriceNusan: 2000, qty: 1),
        ],
    orderDiscount: orderDiscount,
    paymentHashHex: hash,
  );
}

void main() {
  group('record penjualan', () {
    test('buildCompletedOrder menghitung angka dari fungsi yang sama', () {
      final order = sample(
        time: DateTime(2026, 11, 3, 9, 30),
        orderDiscount: const Discount.fixed(1000),
      );
      // Baris: Kopi 10.000 −10% = 9.000; Bebas 2.000. Subtotal 11.000.
      expect(order.subtotalNusan, 11000);
      // Total diskon: baris 1.000 + order 1.000.
      expect(order.totalDiscountNusan, 2000);
      expect(order.grandTotalNusan, 10000);
    });

    test('roundtrip JSON utuh', () {
      final orders = [
        sample(time: DateTime(2026, 11, 3, 9, 30)),
        sample(
          time: DateTime(2026, 11, 3, 10, 5),
          orderDiscount: const Discount.percent(5),
          hash: null,
        ),
      ];
      expect(decodeOrderHistory(encodeOrderHistory(orders)), orders);
    });

    test('simpan rusak fail-open; record tak sah dilewati', () {
      expect(decodeOrderHistory('bukan json'), isEmpty);
      expect(decodeOrderHistory(null), isEmpty);
      final raw = encodeOrderHistory([sample(time: DateTime(2026, 11, 3))]);
      final tampered =
          '${raw.substring(0, raw.length - 1)},{"timeMs":1,"lines":[]}]';
      expect(decodeOrderHistory(tampered).length, 1);
    });

    test('catatan baris ikut tersimpan dan terbaca kembali', () {
      final order = sample(
        time: DateTime(2026, 11, 3, 9, 30),
        lines: const [
          OrderLine(
            code: 'A1',
            label: 'Kopi',
            unitPriceNusan: 5000,
            qty: 1,
            note: 'tanpa gula',
          ),
        ],
      );
      final decoded = decodeOrderHistory(encodeOrderHistory([order]));
      expect(decoded.single.lines.single.note, 'tanpa gula');
      expect(decoded, [order]);
    });

    test('record lama tanpa field note terbaca catatan kosong', () {
      // JSON mentah persis bentuk record sebelum ada fitur
      // catatan (baris tanpa kunci "note").
      const legacy =
          '[{"timeMs":1793865600000,"lines":[{"code":"A1","label":"Kopi","unitPriceNusan":5000,"qty":2,"category":"","discount":{"kind":null,"value":null}}],"orderDiscount":{"kind":null,"value":null},"subtotalNusan":10000,"totalDiscountNusan":0,"grandTotalNusan":10000,"paymentHashHex":"ab12","status":"paid"}]';
      final decoded = decodeOrderHistory(legacy);
      expect(decoded.length, 1);
      expect(decoded.single.lines.single.note, '');
      expect(decoded.single.grandTotalNusan, 10000);
    });

    test('store append + load lewat SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final store = StoreOrderHistoryStore();
      await store.append(sample(time: DateTime(2026, 11, 3, 9)));
      await store.append(sample(time: DateTime(2026, 11, 3, 10)));
      final loaded = await store.load();
      expect(loaded.length, 2);
      expect(loaded.first.grandTotalNusan, 11000);
    });
  });

  group('agregasi laporan', () {
    final day = DateTime(2026, 11, 3);
    List<CompletedOrder> fixture() => [
      sample(
        time: DateTime(2026, 11, 3, 9, 15),
      ), // subtotal 11.000, grand 11.000
      sample(
        time: DateTime(2026, 11, 3, 13, 40),
        lines: const [
          OrderLine(code: 'A1', label: 'Kopi', unitPriceNusan: 5000, qty: 1),
          OrderLine(label: 'Item Bebas', unitPriceNusan: 3000, qty: 2),
        ],
        orderDiscount: const Discount.fixed(1000),
      ), // kotor 11.000, subtotal 11.000, grand 10.000
      sample(time: DateTime(2026, 11, 4, 8, 0)), // hari lain
    ];

    test('rekap satu hari: transaksi, kotor, diskon, bersih', () {
      final report = aggregateSales(
        fixture(),
        from: day,
        to: day.add(const Duration(days: 1)),
      );
      expect(report.transactionCount, 2);
      expect(report.grossNusan, 12000 + 11000);
      // Diskon: order1 baris 1.000; order2 order 1.000.
      expect(report.discountNusan, 2000);
      expect(report.netNusan, 11000 + 10000);
    });

    test('per item teragregasi per label, nilai sesudah diskon baris', () {
      final report = aggregateSales(
        fixture(),
        from: day,
        to: day.add(const Duration(days: 1)),
      );
      final kopi = report.perItem.firstWhere((i) => i.label == 'Kopi');
      expect(kopi.qty, 3);
      // 9.000 (sesudah diskon baris 10%) + 5.000.
      expect(kopi.netNusan, 14000);
      final bebas = report.perItem.firstWhere((i) => i.label == 'Item Bebas');
      expect(bebas.qty, 3);
      expect(bebas.netNusan, 2000 + 6000);
      // Urut nilai menurun: Kopi duluan.
      expect(report.perItem.first.label, 'Kopi');
    });

    test('catatan baris tidak memecah agregasi per item', () {
      final orders = [
        sample(
          time: DateTime(2026, 11, 3, 9, 0),
          lines: const [
            OrderLine(
              label: 'Kopi',
              unitPriceNusan: 5000,
              qty: 1,
              note: 'tanpa gula',
            ),
          ],
        ),
        sample(
          time: DateTime(2026, 11, 3, 10, 0),
          lines: const [
            OrderLine(
              label: 'Kopi',
              unitPriceNusan: 5000,
              qty: 2,
              note: 'gula sedikit',
            ),
          ],
        ),
      ];
      final report = aggregateSales(
        orders,
        from: day,
        to: day.add(const Duration(days: 1)),
      );
      // Satu entri 'Kopi' walau catatannya berbeda-beda.
      expect(report.perItem.length, 1);
      expect(report.perItem.single.qty, 3);
      expect(report.perItem.single.netNusan, 15000);
    });

    test('rentang kosong menghasilkan nol semua', () {
      final report = aggregateSales(
        fixture(),
        from: DateTime(2026, 12, 1),
        to: DateTime(2026, 12, 2),
      );
      expect(report.transactionCount, 0);
      expect(report.grossNusan, 0);
      expect(report.netNusan, 0);
      expect(report.perItem, isEmpty);
    });

    test('batas rentang: from inklusif, to eksklusif', () {
      final orders = [
        sample(time: DateTime(2026, 11, 3, 0, 0)),
        sample(time: DateTime(2026, 11, 4, 0, 0)),
      ];
      final report = aggregateSales(
        orders,
        from: DateTime(2026, 11, 3),
        to: DateTime(2026, 11, 4),
      );
      expect(report.transactionCount, 1);
    });
  });
}
