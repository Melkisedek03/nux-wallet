import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_draft.dart';
import 'package:nux_wallet/services/store_hold.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<OrderLine> sampleLines() => const [
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
];

void main() {
  group('keputusan keluar Mode Toko', () {
    test('pesanan kosong → keluar bebas tanpa dialog', () {
      expect(
        storeExitDecisionFor(const []),
        StoreExitDecision.leaveFreely,
      );
    });

    test('pesanan terisi → wajib konfirmasi tahan-otomatis', () {
      expect(
        storeExitDecisionFor(sampleLines()),
        StoreExitDecision.confirmHoldAndLeave,
      );
    });
  });

  group('draf pesanan (jaring pengaman background)', () {
    test('roundtrip serialisasi draf: simpan → muat identik', () {
      final draft = buildHeldOrder(
        now: DateTime(2026, 11, 4, 0, 40),
        lines: sampleLines(),
        orderDiscount: const Discount.fixed(1000),
      );
      final restored = decodeDraftOrder(encodeDraftOrder(draft));
      expect(restored, draft);
      expect(restored!.lines, sampleLines());
      expect(restored.orderDiscount, const Discount.fixed(1000));
    });

    test('slot kosong / isi rusak → null, bukan pesanan hantu', () {
      expect(decodeDraftOrder(null), isNull);
      expect(decodeDraftOrder(''), isNull);
      expect(decodeDraftOrder('bukan json'), isNull);
      expect(decodeDraftOrder('{"id":"","heldAtMs":1,"lines":[]}'), isNull);
    });

    test('roundtrip lewat SharedPreferences + clear mengosongkan', () async {
      SharedPreferences.setMockInitialValues({});
      final store = StoreDraftStore();
      expect(await store.load(), isNull);
      await store.save(
        lines: sampleLines(),
        orderDiscount: const Discount.percent(5),
      );
      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.lines, sampleLines());
      expect(loaded.orderDiscount, const Discount.percent(5));
      await store.clear();
      expect(await store.load(), isNull);
    });

    test('pesanan kosong tidak pernah tersimpan sebagai draf', () async {
      SharedPreferences.setMockInitialValues({});
      final store = StoreDraftStore();
      await store.save(lines: const [], orderDiscount: null);
      expect(await store.load(), isNull);
    });

    test('draf baru menimpa draf lama (slot tunggal)', () async {
      SharedPreferences.setMockInitialValues({});
      final store = StoreDraftStore();
      await store.save(lines: sampleLines(), orderDiscount: null);
      const newer = [
        OrderLine(label: 'Teh', unitPriceRp: 3000, qty: 1),
      ];
      await store.save(lines: newer, orderDiscount: null);
      final loaded = await store.load();
      expect(loaded!.lines, newer);
    });
  });

  group('tahan otomatis memakai jalur yang sama dengan manual', () {
    test('entri dari buildHeldOrder utuh lewat daftar tahan', () {
      // Tombol manual & pagar keluar sama-sama menyusun entri
      // lewat buildHeldOrder lalu menyimpannya ke HeldOrderStore;
      // entri itu harus terbaca kembali persis dari daftar tahan
      // (dan karena itu bisa dilanjutkan dari daftar Ditahan).
      final held = buildHeldOrder(
        now: DateTime(2026, 11, 4, 0, 45),
        lines: sampleLines(),
        orderDiscount: const Discount.fixed(500),
      );
      expect(decodeHeldOrders(encodeHeldOrders([held])), [held]);
      // Id & waktu berasal dari jam yang diberikan pemanggil.
      expect(held.id, '${DateTime(2026, 11, 4, 0, 45).microsecondsSinceEpoch}');
      expect(held.heldAt, DateTime(2026, 11, 4, 0, 45));
      // Baris disalin, bukan dirujuk: mengubah daftar sumber
      // sesudahnya tidak mengubah entri tahan.
      final source = sampleLines().toList();
      final held2 = buildHeldOrder(
        now: DateTime(2026, 11, 4, 0, 46),
        lines: source,
        orderDiscount: null,
      );
      source.clear();
      expect(held2.lines.length, 2);
    });
  });
}
