import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_catalog.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('katalog JSON', () {
    test('roundtrip item dengan dan tanpa diskon bawaan', () {
      final items = [
        const CatalogItem(
          code: '8991001',
          name: 'Kopi Sachet',
          priceNusan: 5000,
        ),
        const CatalogItem(
          code: '8991002',
          name: 'Teh Botol',
          priceNusan: 4000,
          defaultDiscount: Discount.percent(10),
        ),
        const CatalogItem(
          code: 'QR-MANUAL-1',
          name: 'Gula 1kg',
          priceNusan: 15000,
          defaultDiscount: Discount.fixed(1000),
        ),
      ];
      final decoded = decodeCatalog(encodeCatalog(items));
      expect(decoded, items);
    });

    test('string rusak menghasilkan katalog kosong', () {
      expect(decodeCatalog(null), isEmpty);
      expect(decodeCatalog(''), isEmpty);
      expect(decodeCatalog('bukan json'), isEmpty);
      expect(decodeCatalog('{"bukan":"daftar"}'), isEmpty);
    });

    test('entri tak sah dilewati, entri sah tetap terbaca', () {
      final raw = encodeCatalog([
        const CatalogItem(code: 'A', name: 'Sah', priceNusan: 1000),
      ]);
      final tampered =
          '${raw.substring(0, raw.length - 1)},{"code":"","name":"X","priceNusan":5},{"code":"B","name":"Harga Rusak","priceNusan":-3},42]';
      final decoded = decodeCatalog(tampered);
      expect(decoded.length, 1);
      expect(decoded.single.code, 'A');
    });

    test('diskon bawaan rusak dibuang, item tetap sah', () {
      final decoded = decodeCatalog(
        '[{"code":"A","name":"Kopi","priceNusan":5000,"discountKind":"aneh","discountValue":10}]',
      );
      expect(decoded.single.defaultDiscount, isNull);
    });
  });

  group('pencarian kode', () {
    final items = [
      const CatalogItem(code: '8991001', name: 'Kopi', priceNusan: 5000),
      const CatalogItem(code: 'ABC-123', name: 'Teh', priceNusan: 4000),
    ];

    test('ketemu persis, termasuk dengan spasi hasil scan', () {
      expect(findCatalogItemByCode(items, '8991001')?.name, 'Kopi');
      expect(findCatalogItemByCode(items, '  ABC-123 ')?.name, 'Teh');
    });

    test('tidak ketemu menghasilkan null', () {
      expect(findCatalogItemByCode(items, '0000'), isNull);
      expect(findCatalogItemByCode(items, ''), isNull);
      expect(findCatalogItemByCode(const [], '8991001'), isNull);
    });
  });

  group('store', () {
    test('roundtrip lewat SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final store = StoreCatalogStore();
      expect(await store.load(), isEmpty);
      final items = [
        const CatalogItem(code: 'A1', name: 'Kopi', priceNusan: 5000),
      ];
      await store.save(items);
      expect(await store.load(), items);
    });

    test('simpanan rusak dibaca sebagai katalog kosong', () async {
      SharedPreferences.setMockInitialValues({
        StoreCatalogStore.storageKey: '###rusak###',
      });
      expect(await StoreCatalogStore().load(), isEmpty);
    });
  });
}
