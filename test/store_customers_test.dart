import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_catalog.dart';
import 'package:nux_wallet/services/store_customers.dart';
import 'package:nux_wallet/services/store_order_history.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StoreCustomerStore (SQLite uji)', () {
    test('tambah → muat urut nama; offer ternormalisasi', () async {
      final store = StoreCustomerStore(database: newTestStoreDatabase());
      await store.add(name: 'Zahra', offer: '  LNO1ABC  ');
      final budi = await store.add(name: 'Budi', offer: 'lno1def');
      final all = await store.loadAll();
      expect(all.map((c) => c.name), ['Budi', 'Zahra']);
      // Kunci jurnal: trim + huruf kecil.
      expect(all.last.offer, 'lno1abc');

      await store.update(budi.copyWith(name: 'Budi Santoso'));
      await store.delete(budi.id);
      final after = await store.loadAll();
      expect(after.map((c) => c.name), ['Zahra']);
    });
  });

  group('integritas katalog ↔ penjualan', () {
    test('item katalog dihapus sesudah terjual: record penjualan '
        'dan agregatnya TIDAK berubah (snapshot penuh)', () async {
      final db = newTestStoreDatabase();
      final catalog = StoreCatalogStore(database: db);
      final history = StoreOrderHistoryStore(database: db);

      const item = CatalogItem(
        code: 'KOPI01',
        name: 'Kopi Tubruk',
        priceRp: 5000,
        category: 'MINUMAN',
      );
      await catalog.save([item]);

      // Penjualan tercatat dari item itu — baris record adalah
      // snapshot (kode, label, harga, kategori tersalin).
      final sale = buildCompletedOrder(
        id: 'sale-1',
        time: DateTime(2026, 11, 4, 10, 0),
        lines: const [
          OrderLine(
            code: 'KOPI01',
            label: 'Kopi Tubruk',
            unitPriceRp: 5000,
            qty: 2,
            category: 'MINUMAN',
          ),
        ],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: payMethodCash,
        cashReceivedRp: 10000,
      );
      await history.append(sale);

      // Item dihapus dari katalog (keadaan katalog berubah
      // total: diganti item lain berharga beda).
      await catalog.save([
        const CatalogItem(code: 'TEH01', name: 'Teh', priceRp: 3000),
      ]);
      expect((await catalog.load()).map((i) => i.code), ['TEH01']);

      // Record penjualan terbaca PERSIS seperti saat dicatat.
      final loaded = await history.load();
      expect(loaded, hasLength(1));
      expect(loaded.single, sale);
      expect(loaded.single.lines.single.label, 'Kopi Tubruk');
      expect(loaded.single.lines.single.unitPriceRp, 5000);
      expect(loaded.single.lines.single.category, 'MINUMAN');
      expect(loaded.single.grandTotalRp, 10000);
    });
  });
}
