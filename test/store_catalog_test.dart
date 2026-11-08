import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_catalog.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'store_test_db.dart';

void main() {
  group('katalog JSON', () {
    test('roundtrip item dengan dan tanpa diskon bawaan', () {
      final items = [
        const CatalogItem(
          code: '8991001',
          name: 'Kopi Sachet',
          priceRp: 5000,
        ),
        const CatalogItem(
          code: '8991002',
          name: 'Teh Botol',
          priceRp: 4000,
          defaultDiscount: Discount.percent(10),
        ),
        const CatalogItem(
          code: 'QR-MANUAL-1',
          name: 'Gula 1kg',
          priceRp: 15000,
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
        const CatalogItem(code: 'A', name: 'Sah', priceRp: 1000),
      ]);
      final tampered =
          '${raw.substring(0, raw.length - 1)},{"code":"","name":"X","priceRp":5},{"code":"B","name":"Harga Rusak","priceRp":-3},42]';
      final decoded = decodeCatalog(tampered);
      expect(decoded.length, 1);
      expect(decoded.single.code, 'A');
    });

    test('JSON lama berkunci priceNusan tetap terbaca (fallback baca)', () {
      final decoded = decodeCatalog(
        '[{"code":"A","name":"Kopi","priceNusan":5000}]',
      );
      expect(decoded.single.priceRp, 5000);
    });

    test('diskon bawaan rusak dibuang, item tetap sah', () {
      final decoded = decodeCatalog(
        '[{"code":"A","name":"Kopi","priceRp":5000,"discountKind":"aneh","discountValue":10}]',
      );
      expect(decoded.single.defaultDiscount, isNull);
    });
  });

  group('pencarian kode', () {
    final items = [
      const CatalogItem(code: '8991001', name: 'Kopi', priceRp: 5000),
      const CatalogItem(code: 'ABC-123', name: 'Teh', priceRp: 4000),
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

  group('saring katalog (kolom cari kasir)', () {
    final items = [
      const CatalogItem(code: '8991001', name: 'Kopi Sachet', priceRp: 5000),
      const CatalogItem(code: '8991002', name: 'Teh Botol', priceRp: 4000),
      const CatalogItem(code: 'QR-GULA', name: 'Gula 1kg', priceRp: 15000),
    ];

    test('query kosong atau spasi saja mengembalikan seluruh katalog', () {
      expect(filterCatalogItems(items, ''), items);
      expect(filterCatalogItems(items, '   '), items);
    });

    test('cocok nama, tak peka huruf besar/kecil, boleh sebagian', () {
      expect(filterCatalogItems(items, 'kopi').single.name, 'Kopi Sachet');
      expect(filterCatalogItems(items, 'TEH').single.name, 'Teh Botol');
      expect(filterCatalogItems(items, 'gula').single.name, 'Gula 1kg');
    });

    test('cocok kode, termasuk potongan kode', () {
      expect(filterCatalogItems(items, '899100'), hasLength(2));
      expect(filterCatalogItems(items, 'qr-gula').single.name, 'Gula 1kg');
    });

    test('tidak ada yang cocok menghasilkan daftar kosong', () {
      expect(filterCatalogItems(items, 'susu'), isEmpty);
      expect(filterCatalogItems(const [], 'kopi'), isEmpty);
    });
  });

  group('kategori yang sudah ada (saran isian)', () {
    CatalogItem withCategory(String code, String category) => CatalogItem(
      code: code,
      name: 'Item $code',
      priceRp: 1000,
      category: category,
    );

    test('unik sesudah trim & tak peka huruf besar/kecil, urut abjad', () {
      final items = [
        withCategory('A', 'Minuman'),
        withCategory('B', ' makanan '),
        withCategory('C', 'MINUMAN'),
        withCategory('D', 'Alat Tulis'),
        withCategory('E', ''),
        withCategory('F', '   '),
      ];
      // Bentuk pertama yang menang ('Minuman', bukan 'MINUMAN');
      // urut abjad tak peka huruf: Alat Tulis < makanan < Minuman.
      expect(catalogCategories(items), ['Alat Tulis', 'makanan', 'Minuman']);
    });

    test('katalog tanpa kategori menghasilkan daftar kosong', () {
      expect(
        catalogCategories([
          const CatalogItem(code: 'A', name: 'Kopi', priceRp: 5000),
        ]),
        isEmpty,
      );
      expect(catalogCategories(const []), isEmpty);
    });
  });

  group('store', () {
    test('roundtrip lewat basis data SQLite', () async {
      SharedPreferences.setMockInitialValues({});
      final store = StoreCatalogStore(database: newTestStoreDatabase());
      expect(await store.load(), isEmpty);
      final items = [
        const CatalogItem(code: 'A1', name: 'Kopi', priceRp: 5000),
      ];
      await store.save(items);
      expect(await store.load(), items);
    });

    test('simpanan rusak dibaca sebagai katalog kosong', () async {
      SharedPreferences.setMockInitialValues({
        StoreCatalogStore.storageKey: '###rusak###',
      });
      expect(await StoreCatalogStore(database: newTestStoreDatabase()).load(), isEmpty);
    });
  });

  group('kode bawaan & kewajiban kode (keputusan NUX 8 Nov 2026)', () {
    CatalogItem item(String code) =>
        CatalogItem(code: code, name: 'Produk $code', priceRp: 1000);

    test('katalog kosong → PRD-001', () {
      expect(suggestCatalogCode(const []), 'PRD-001');
    });

    test('nomor berikutnya dari PRD terbesar, bukan dari jumlah item', () {
      expect(
        suggestCatalogCode([item('PRD-001'), item('PRD-007')]),
        'PRD-008',
      );
    });

    test('kode di luar pola (barcode asli) tidak ikut dihitung', () {
      expect(
        suggestCatalogCode([item('8991001'), item('QR-MANUAL-1')]),
        'PRD-001',
      );
    });

    test('pola tak peka huruf besar/kecil', () {
      expect(suggestCatalogCode([item('prd-003')]), 'PRD-004');
    });

    test('kandidat yang sudah dipakai dilompati', () {
      // PRD-010 terbaca sebagai nomor 10; kandidat dari hitungan
      // lain tidak boleh menabrak kode yang sudah ada.
      expect(
        suggestCatalogCode([item('PRD-001'), item('PRD-002')]),
        'PRD-003',
      );
    });

    test('kode kosong/spasi ditolak sebagai empty', () {
      expect(catalogCodeError(const [], ''), CatalogCodeError.empty);
      expect(catalogCodeError(const [], '   '), CatalogCodeError.empty);
    });

    test('kode ganda ditolak sebagai duplicate', () {
      final items = [item('PRD-001'), item('8991001')];
      expect(
        catalogCodeError(items, '8991001'),
        CatalogCodeError.duplicate,
      );
    });

    test('kode sendiri saat ubah bukan duplikat (ownIndex)', () {
      final items = [item('PRD-001'), item('8991001')];
      expect(catalogCodeError(items, '8991001', ownIndex: 1), isNull);
      expect(
        catalogCodeError(items, 'PRD-001', ownIndex: 1),
        CatalogCodeError.duplicate,
      );
    });

    test('kode baru yang sah lolos', () {
      final items = [item('PRD-001')];
      expect(catalogCodeError(items, '8991001'), isNull);
      expect(catalogCodeError(items, suggestCatalogCode(items)), isNull);
    });
  });

  group('filterCatalogByCategory (saringan kategori kasir)', () {
    const items = [
      CatalogItem(code: 'A', name: 'Kopi', priceRp: 5000, category: 'DRINK'),
      CatalogItem(code: 'B', name: 'Roti', priceRp: 8000, category: 'FOOD'),
      CatalogItem(code: 'C', name: 'Teh', priceRp: 4000, category: 'drink'),
      CatalogItem(code: 'D', name: 'Bebas', priceRp: 1000),
    ];

    test('null/kosong → semua item', () {
      expect(filterCatalogByCategory(items, null), items);
      expect(filterCatalogByCategory(items, '  '), items);
    });

    test('kategori sama (tak peka huruf) saja yang lolos', () {
      final drink = filterCatalogByCategory(items, 'DRINK');
      expect(drink.map((i) => i.code), ['A', 'C']);
      expect(filterCatalogByCategory(items, 'food').single.code, 'B');
      expect(filterCatalogByCategory(items, 'LAINNYA'), isEmpty);
    });
  });
}
