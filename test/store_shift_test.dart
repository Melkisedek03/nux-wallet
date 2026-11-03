import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_catalog.dart';
import 'package:nux_wallet/services/store_order_history.dart';
import 'package:nux_wallet/services/store_shift.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('model shift', () {
    test('roundtrip JSON shift terbuka dan tertutup', () {
      final shifts = [
        StoreShift(
          openedAt: DateTime(2026, 11, 2, 22, 24),
          closedAt: DateTime(2026, 11, 3, 6, 0),
        ),
        StoreShift(openedAt: DateTime(2026, 11, 3, 8, 0)),
      ];
      expect(decodeShifts(encodeShifts(shifts)), shifts);
    });

    test('bentuk tak sah ditolak; simpanan rusak fail-open', () {
      // closedAt mendahului openedAt → tidak sah.
      expect(
        StoreShift.fromJson({'openedAtMs': 2000, 'closedAtMs': 1000}),
        isNull,
      );
      expect(StoreShift.fromJson({'closedAtMs': 1000}), isNull);
      expect(decodeShifts('bukan json'), isEmpty);
      expect(decodeShifts(null), isEmpty);
    });

    test('openShiftIn mengambil shift terbuka terakhir', () {
      final closed = StoreShift(
        openedAt: DateTime(2026, 11, 1, 8),
        closedAt: DateTime(2026, 11, 1, 16),
      );
      final open = StoreShift(openedAt: DateTime(2026, 11, 2, 8));
      expect(openShiftIn([closed, open]), open);
      expect(openShiftIn([closed]), isNull);
      expect(openShiftIn(const []), isNull);
    });

    test('jendela shift: openedAt inklusif, closedAt eksklusif', () {
      final shift = StoreShift(
        openedAt: DateTime(2026, 11, 2, 22, 24),
        closedAt: DateTime(2026, 11, 3, 6, 0),
      );
      expect(shift.containsTime(DateTime(2026, 11, 2, 22, 24)), isTrue);
      expect(shift.containsTime(DateTime(2026, 11, 2, 22, 23)), isFalse);
      expect(shift.containsTime(DateTime(2026, 11, 3, 5, 59)), isTrue);
      expect(shift.containsTime(DateTime(2026, 11, 3, 6, 0)), isFalse);
    });

    test('invariant: record pesanan selalu di dalam jendela shiftnya', () {
      // Penegasan alur NUX: tidak ada record "di luar shift" —
      // record yang dicatat saat shift terbuka (sesudah buka,
      // sebelum tutup yang terhalang invoice menunggu) selalu
      // jatuh di dalam jendela shift itu.
      final shift = StoreShift(
        openedAt: DateTime(2026, 11, 2, 22, 24),
        closedAt: DateTime(2026, 11, 3, 6, 0),
      );
      final order = buildCompletedOrder(
        time: DateTime(2026, 11, 3, 1, 15),
        lines: const [
          OrderLine(label: 'Kopi', unitPriceRp: 5000, qty: 1),
        ],
        orderDiscount: null,
        paymentHashHex: 'ab',
      );
      expect(shift.containsTime(order.time), isTrue);
      final outside = buildCompletedOrder(
        time: DateTime(2026, 11, 3, 6, 30),
        lines: order.lines,
        orderDiscount: null,
        paymentHashHex: 'cd',
      );
      expect(shift.containsTime(outside.time), isFalse);
    });

    test('store simpan + muat lewat SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final store = StoreShiftStore();
      await store.save([
        StoreShift(openedAt: DateTime(2026, 11, 2, 22, 24)),
      ]);
      final loaded = await store.load();
      expect(loaded.length, 1);
      expect(loaded.single.isOpen, isTrue);
    });
  });

  group('kompatibilitas mundur data v1', () {
    test('record lama tanpa status/kategori terbaca lunas + kategori kosong', () {
      // Bentuk persis simpanan Mode Toko v1 (commit 3d4ab8a6):
      // tanpa field 'status' di record dan tanpa 'category' di
      // baris.
      const raw =
          '[{"timeMs":1793800000000,'
          '"lines":[{"code":"A1","label":"Kopi","unitPriceNusan":5000,'
          '"qty":2,"discount":{"kind":null,"value":null}}],'
          '"orderDiscount":{"kind":null,"value":null},'
          '"subtotalNusan":10000,"totalDiscountNusan":0,'
          '"grandTotalNusan":10000,"paymentHashHex":"ab12"}]';
      final orders = decodeOrderHistory(raw);
      expect(orders.length, 1);
      expect(orders.single.isVoid, isFalse);
      expect(orders.single.lines.single.category, '');
    });

    test('roundtrip record VOID + kategori baris', () {
      final order = buildCompletedOrder(
        time: DateTime(2026, 11, 3, 7, 0),
        lines: const [
          OrderLine(
            code: 'K1',
            label: 'Klip',
            unitPriceRp: 1500,
            qty: 3,
            category: 'MENTARI',
          ),
        ],
        orderDiscount: null,
        paymentHashHex: 'ef',
        isVoid: true,
      );
      final decoded = decodeOrderHistory(encodeOrderHistory([order]));
      expect(decoded, [order]);
      expect(decoded.single.isVoid, isTrue);
      expect(decoded.single.lines.single.category, 'MENTARI');
    });

    test('item katalog lama tanpa kategori terbaca kategori kosong', () {
      const raw =
          '[{"code":"A1","name":"Kopi","priceNusan":5000}]';
      final items = decodeCatalog(raw);
      expect(items.length, 1);
      expect(items.single.category, '');
    });

    test('roundtrip item katalog berkategori', () {
      const items = [
        CatalogItem(
          code: 'A1',
          name: 'Kopi',
          priceRp: 5000,
          category: 'MENTARI',
        ),
        CatalogItem(code: 'B2', name: 'Teh', priceRp: 4000),
      ];
      expect(decodeCatalog(encodeCatalog(items)), items);
    });
  });
  group('era shift', () {
    test('era rp roundtrip; shift lama tanpa era terbaca nusan', () {
      final rp = StoreShift(openedAt: DateTime(2026, 11, 3, 8), era: 'rp');
      expect(rp.era, 'rp');
      expect(decodeShifts(encodeShifts([rp])), [rp]);
      final legacy = StoreShift.fromJson({'openedAtMs': 1793865600000});
      expect(legacy, isNotNull);
      expect(legacy!.era, 'nusan');
      // close() mempertahankan era.
      expect(rp.close(DateTime(2026, 11, 3, 20)).era, 'rp');
    });
  });
}
