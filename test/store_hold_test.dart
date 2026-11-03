import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_hold.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

HeldOrder sample({
  String id = 'h1',
  DateTime? heldAt,
  List<OrderLine>? lines,
  Discount? orderDiscount,
}) {
  return HeldOrder(
    id: id,
    heldAt: heldAt ?? DateTime(2026, 11, 3, 12, 30),
    lines:
        lines ??
        const [
          OrderLine(
            code: 'A1',
            label: 'Kopi',
            unitPriceRp: 5000,
            qty: 2,
            category: 'MINUMAN',
            discount: Discount.percent(10),
            note: 'tanpa gula',
          ),
          OrderLine(label: 'Item Bebas', unitPriceRp: 2000, qty: 1),
        ],
    orderDiscount: orderDiscount,
  );
}

void main() {
  group('pesanan ditahan JSON', () {
    test('roundtrip utuh: baris + diskon baris + catatan + diskon order', () {
      final orders = [
        sample(orderDiscount: const Discount.fixed(1000)),
        sample(id: 'h2', heldAt: DateTime(2026, 11, 3, 13, 5)),
      ];
      expect(decodeHeldOrders(encodeHeldOrders(orders)), orders);
    });

    test('total & qty entri dihitung dari fungsi pesanan yang sama', () {
      final held = sample(orderDiscount: const Discount.fixed(1000));
      // Baris: Kopi 10.000 −10% = 9.000; Bebas 2.000; subtotal
      // 11.000 − diskon order 1.000 = 10.000.
      expect(held.grandTotalRp, 10000);
      expect(held.totalQty, 3);
    });

    test('simpan rusak fail-open; entri tak sah dilewati satu-satu', () {
      expect(decodeHeldOrders('bukan json'), isEmpty);
      expect(decodeHeldOrders(null), isEmpty);
      expect(decodeHeldOrders('{"bukan":"daftar"}'), isEmpty);
      final raw = encodeHeldOrders([sample()]);
      final tampered =
          '${raw.substring(0, raw.length - 1)},{"id":"","heldAtMs":1,"lines":[{"label":"X","unitPriceRp":5,"qty":1}]},{"id":"h9","heldAtMs":1,"lines":[]}]';
      final decoded = decodeHeldOrders(tampered);
      expect(decoded.length, 1);
      expect(decoded.single.id, 'h1');
    });
  });

  group('store tahan', () {
    test('roundtrip lewat SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final store = HeldOrderStore();
      expect(await store.load(), isEmpty);
      final orders = [sample(), sample(id: 'h2')];
      await store.save(orders);
      expect(await store.load(), orders);
    });

    test('simpanan rusak dibaca sebagai daftar kosong', () async {
      SharedPreferences.setMockInitialValues({
        HeldOrderStore.storageKey: '###rusak###',
      });
      expect(await HeldOrderStore().load(), isEmpty);
    });

    test('batas 50 entri: yang tertua dibuang, terbaru dipertahankan', () async {
      SharedPreferences.setMockInitialValues({});
      final store = HeldOrderStore();
      final many = [
        for (var i = 0; i < 55; i++)
          sample(
            id: 'h$i',
            heldAt: DateTime(2026, 11, 3).add(Duration(minutes: i)),
          ),
      ];
      await store.save(many);
      final loaded = await store.load();
      expect(loaded.length, HeldOrderStore.maxRecords);
      expect(loaded.first.id, 'h5');
      expect(loaded.last.id, 'h54');
    });
  });
}
