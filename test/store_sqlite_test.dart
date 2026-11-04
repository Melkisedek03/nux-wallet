import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_catalog.dart';
import 'package:nux_wallet/services/store_database.dart';
import 'package:nux_wallet/services/store_draft.dart';
import 'package:nux_wallet/services/store_hold.dart';
import 'package:nux_wallet/services/store_order_archive.dart';
import 'package:nux_wallet/services/store_order_history.dart';
import 'package:nux_wallet/services/store_settings.dart';
import 'package:nux_wallet/services/store_shift.dart';
import 'package:nux_wallet/services/store_token_counter.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'store_test_db.dart';

CompletedOrder sampleOrder({
  required String id,
  required DateTime time,
  int priceRp = 5000,
}) {
  return buildCompletedOrder(
    id: id,
    time: time,
    lines: [
      OrderLine(code: 'A1', label: 'Kopi', unitPriceRp: priceRp, qty: 1),
    ],
    orderDiscount: null,
    paymentHashHex: 'ab12',
  );
}

void main() {
  group('skema basis data', () {
    test('tabel Mode Toko terbentuk & versi skema 1', () async {
      SharedPreferences.setMockInitialValues({});
      final storeDb = newTestStoreDatabase();
      final db = await storeDb.database;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = {for (final r in tables) r['name'] as String};
      expect(
        names,
        containsAll([
          'catalog_items',
          'orders',
          'order_lines',
          'shifts',
          'store_kv',
        ]),
      );
      final versionRows = await db.rawQuery('PRAGMA user_version');
      expect(versionRows.first['user_version'], 1);
      await storeDb.close();
    });
  });

  group('impor satu-kali dari SharedPreferences', () {
    test(
      'seluruh data pindah (termasuk shift terbuka); impor kedua no-op',
      () async {
        final tmp = await Directory.systemTemp.createTemp('store_import');
        addTearDown(() async {
          try {
            await tmp.delete(recursive: true);
          } catch (_) {}
        });
        final dbPath = p.join(tmp.path, 'store_pos.db');
        StoreDatabase fileDb() =>
            StoreDatabase(dbPathProvider: () async => dbPath);

        final openedAt = DateTime(2026, 11, 3, 8, 0);
        final saleTime = DateTime(2026, 11, 3, 9, 30);
        SharedPreferences.setMockInitialValues({
          StoreCatalogStore.storageKey: encodeCatalog(const [
            CatalogItem(code: 'A1', name: 'Kopi', priceRp: 5000),
          ]),
          StoreOrderHistoryStore.storageKey: encodeOrderHistory([
            sampleOrder(id: 's1', time: saleTime),
          ]),
          StoreShiftStore.storageKey: encodeShifts([
            StoreShift(openedAt: openedAt, era: 'rp'),
          ]),
          HeldOrderStore.storageKey: encodeHeldOrders([
            HeldOrder(
              id: 'h1',
              heldAt: saleTime,
              lines: const [
                OrderLine(label: 'Teh', unitPriceRp: 3000, qty: 1),
              ],
              orderDiscount: null,
            ),
          ]),
          StoreDraftStore.storageKey: encodeDraftOrder(
            HeldOrder(
              id: 'd1',
              heldAt: saleTime,
              lines: const [
                OrderLine(label: 'Roti', unitPriceRp: 7000, qty: 2),
              ],
              orderDiscount: null,
            ),
          ),
          StoreSettingsStore.storageKey: encodeStoreSettings(
            const StoreSettings(storeName: 'Toko Uji'),
          ),
          StoreTokenCounterStore.storageKey: encodeTokenCounter(
            const StoreTokenCounterState(dateKey: '2026-11-03', counter: 7),
          ),
        });

        final db1 = fileDb();
        expect(
          await StoreCatalogStore(database: db1).load(),
          hasLength(1),
        );
        final history = await StoreOrderHistoryStore(database: db1).load();
        expect(history, hasLength(1));
        expect(history.single.id, 's1');
        expect(history.single.lines.single.label, 'Kopi');
        final shifts = await StoreShiftStore(database: db1).load();
        expect(shifts, hasLength(1));
        expect(shifts.single.isOpen, isTrue);
        expect(shifts.single.openedAt, openedAt);
        expect(await HeldOrderStore(database: db1).load(), hasLength(1));
        final draft = await StoreDraftStore(database: db1).load();
        expect(draft?.lines.single.label, 'Roti');
        expect(
          (await StoreSettingsStore(database: db1).load()).storeName,
          'Toko Uji',
        );
        expect(
          (await StoreTokenCounterStore(database: db1).load()).counter,
          7,
        );
        await db1.close();

        // Ubah isi SharedPreferences: buka basis data yang sama
        // TIDAK boleh mengimpor ulang / menggandakan apa pun.
        SharedPreferences.setMockInitialValues({});
        final db2 = fileDb();
        expect(
          await StoreOrderHistoryStore(database: db2).load(),
          hasLength(1),
        );
        expect(await StoreCatalogStore(database: db2).load(), hasLength(1));
        expect(await StoreShiftStore(database: db2).load(), hasLength(1));
        await db2.close();
      },
    );
  });

  group('transaksi pelunasan', () {
    test(
      'recordSettledSale: bill & token tercap, draf bersih, atomik',
      () async {
        SharedPreferences.setMockInitialValues({});
        final db = newTestStoreDatabase();
        final history = StoreOrderHistoryStore(database: db);
        final draftStore = StoreDraftStore(database: db);
        final tokenStore = StoreTokenCounterStore(database: db);

        await draftStore.save(
          lines: const [OrderLine(label: 'Kopi', unitPriceRp: 5000, qty: 1)],
          orderDiscount: null,
        );
        expect(await draftStore.load(), isNotNull);

        final shiftOpened = DateTime(2026, 11, 3, 8, 0);
        final first = await history.recordSettledSale(
          sampleOrder(id: 's1', time: DateTime.now()),
          stampMeta: true,
          issueToken: true,
          shiftOpenedMs: shiftOpened.millisecondsSinceEpoch,
        );
        expect(first.billNo, 1);
        expect(first.tokenNo, 1);
        expect(first.shiftOpenedMs, shiftOpened.millisecondsSinceEpoch);
        // Draf dibersihkan di transaksi yang sama.
        expect(await draftStore.load(), isNull);
        // Penghitung token ikut maju di transaksi yang sama.
        expect((await tokenStore.load()).counter, 1);

        final second = await history.recordSettledSale(
          sampleOrder(id: 's2', time: DateTime.now()),
          stampMeta: true,
          issueToken: true,
        );
        expect(second.billNo, 2);
        expect(second.tokenNo, 2);

        final loaded = await history.load();
        expect(loaded.map((o) => o.id), ['s1', 's2']);
        expect(loaded.first.billNo, 1);
      },
    );

    test('recordSettledSale tanpa cap: nomor tetap 0, record tersimpan',
        () async {
      SharedPreferences.setMockInitialValues({});
      final db = newTestStoreDatabase();
      final history = StoreOrderHistoryStore(database: db);
      final settled = await history.recordSettledSale(
        sampleOrder(id: 's1', time: DateTime.now()),
        stampMeta: false,
        issueToken: false,
      );
      expect(settled.billNo, 0);
      expect(settled.tokenNo, 0);
      expect(await history.load(), hasLength(1));
    });
  });

  group('arsip overflow riwayat', () {
    test(
      'record ke-(batas+1) terarsip ke berkas & hilang dari aktif',
      () async {
        SharedPreferences.setMockInitialValues({});
        final tmp = await Directory.systemTemp.createTemp('store_archive');
        addTearDown(() async {
          try {
            await tmp.delete(recursive: true);
          } catch (_) {}
        });
        final archive = StoreOrderArchive(dirProvider: () async => tmp);
        final history = StoreOrderHistoryStore(
          database: newTestStoreDatabase(),
          archive: archive,
          maxRecordsOverride: 3,
        );
        for (var i = 1; i <= 4; i++) {
          await history.append(
            sampleOrder(
              id: 's$i',
              time: DateTime(2026, 11, 3, 8).add(Duration(minutes: i)),
            ),
          );
        }
        final active = await history.load();
        expect(active.map((o) => o.id), ['s2', 's3', 's4']);
        final archived = await archive.loadArchived();
        expect(archived.map((o) => o.id), ['s1']);
      },
    );

    test('tulis arsip gagal → record TETAP aktif (tidak dihapus)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final tmp = await Directory.systemTemp.createTemp('store_archive_x');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      // Direktori arsip diarahkan ke sebuah BERKAS — menulis
      // berkas arsip di dalamnya pasti gagal.
      final blocker = File(p.join(tmp.path, 'blocker'));
      await blocker.writeAsString('x');
      final badArchive = StoreOrderArchive(
        dirProvider: () async => Directory(blocker.path),
      );
      final history = StoreOrderHistoryStore(
        database: newTestStoreDatabase(),
        archive: badArchive,
        maxRecordsOverride: 3,
      );
      for (var i = 1; i <= 4; i++) {
        await history.append(
          sampleOrder(
            id: 's$i',
            time: DateTime(2026, 11, 3, 8).add(Duration(minutes: i)),
          ),
        );
      }
      // Tidak ada yang terhapus: kegagalan arsip menahan record.
      expect(await history.load(), hasLength(4));
    });
  });
}
