import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_database.dart';
import 'package:nux_wallet/services/store_order_history.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Penjualan rupiah contoh untuk uji jurnal. [pointsEarned] &
/// [pointsRedeemed] diteruskan ke builder yang sama dengan yang
/// dipakai layar pembayaran.
CompletedOrder sale({
  required DateTime time,
  int pointsEarned = 0,
  int pointsRedeemed = 0,
  String? pointsRedeemOffer,
  bool isVoid = false,
}) {
  return buildCompletedOrder(
    time: time,
    lines: const [OrderLine(label: 'Kopi', unitPriceRp: 10000, qty: 1)],
    orderDiscount: null,
    paymentHashHex: null,
    pointsRedeemed: pointsRedeemed,
    pointsRedeemOffer: pointsRedeemOffer,
    pointsEarned: pointsEarned,
    pointsIssueStatus: pointsEarned > 0 ? issueStatusPending : issueStatusNone,
    isVoid: isVoid,
  );
}

const offerA = 'lno1offerpelanggana';
const offerB = 'lno1offerpelangganb';

void main() {
  final t = DateTime(2026, 11, 4, 9, 30);

  group('normalizePointsOffer', () {
    test('trim + huruf kecil', () {
      expect(normalizePointsOffer('  LNO1ABC '), 'lno1abc');
      expect(normalizePointsOffer('lno1abc'), 'lno1abc');
      expect(normalizePointsOffer('   '), '');
    });
  });

  group('pointsJournalBalanceFor', () {
    test('riwayat kosong & offer tak dikenal → 0', () {
      expect(pointsJournalBalanceFor(const [], offerA), 0);
      final orders = [
        sale(
          time: t,
          pointsEarned: 50,
        ).withIssueStatus(issueStatusIssued, recipientOffer: offerB),
      ];
      expect(pointsJournalBalanceFor(orders, offerA), 0);
      expect(pointsJournalBalanceFor(orders, ''), 0);
    });

    test('penerbitan terbit ke offer yang sama terakumulasi', () {
      final orders = [
        sale(
          time: t,
          pointsEarned: 50,
        ).withIssueStatus(issueStatusIssued, recipientOffer: offerA),
        sale(
          time: t,
          pointsEarned: 30,
        ).withIssueStatus(issueStatusIssued, recipientOffer: offerA),
      ];
      expect(pointsJournalBalanceFor(orders, offerA), 80);
    });

    test('penerbitan belum issued (tertunda / belum) tidak memberi hak', () {
      final pending = [sale(time: t, pointsEarned: 50)];
      expect(pointsJournalBalanceFor(pending, offerA), 0);
      final waived = [
        sale(
          time: t,
          pointsEarned: 50,
        ).withIssueStatus(issueStatusWaived, recipientOffer: offerA),
      ];
      expect(pointsJournalBalanceFor(waived, offerA), 0);
    });

    test('penerbitan ke invoice sekali pakai (tanpa offer) di luar jurnal', () {
      final orders = [
        sale(time: t, pointsEarned: 50).withIssueStatus(issueStatusIssued),
      ];
      expect(pointsJournalBalanceFor(orders, offerA), 0);
    });

    test('penukaran mendebit; query ternormalisasi cocok', () {
      final orders = [
        sale(
          time: t,
          pointsEarned: 50,
        ).withIssueStatus(issueStatusIssued, recipientOffer: offerA),
        sale(time: t, pointsRedeemed: 20, pointsRedeemOffer: offerA),
      ];
      expect(pointsJournalBalanceFor(orders, offerA), 30);
      expect(pointsJournalBalanceFor(orders, '  LNO1OFFERPELANGGANA '), 30);
    });

    test('record VOID tidak mengkredit maupun mendebit', () {
      final orders = [
        sale(
          time: t,
          pointsEarned: 50,
          isVoid: true,
        ).withIssueStatus(issueStatusIssued, recipientOffer: offerA),
        sale(
          time: t,
          pointsEarned: 50,
        ).withIssueStatus(issueStatusIssued, recipientOffer: offerA),
        sale(
          time: t,
          pointsRedeemed: 20,
          pointsRedeemOffer: offerA,
          isVoid: true,
        ),
      ];
      expect(pointsJournalBalanceFor(orders, offerA), 50);
    });

    test('debit melebihi kredit berlantai 0', () {
      final orders = [
        sale(
          time: t,
          pointsEarned: 10,
        ).withIssueStatus(issueStatusIssued, recipientOffer: offerA),
        sale(time: t, pointsRedeemed: 25, pointsRedeemOffer: offerA),
      ];
      expect(pointsJournalBalanceFor(orders, offerA), 0);
    });
  });

  group('record jurnal (JSON)', () {
    test('kedua offer tersimpan & terbaca kembali utuh', () {
      final order = sale(
        time: t,
        pointsEarned: 50,
        pointsRedeemed: 20,
        pointsRedeemOffer: offerA,
      ).withIssueStatus(issueStatusIssued, recipientOffer: offerB);
      final restored = CompletedOrder.fromJson(order.toJson());
      expect(restored, isNotNull);
      expect(restored!.pointsRecipientOffer, offerB);
      expect(restored.pointsRedeemOffer, offerA);
      expect(restored, order);
    });

    test('JSON lama tanpa field offer terbaca null', () {
      final order = sale(time: t, pointsEarned: 50);
      final json = order.toJson();
      expect(json.containsKey('pointsRecipientOffer'), isFalse);
      expect(json.containsKey('pointsRedeemOffer'), isFalse);
      final restored = CompletedOrder.fromJson(json);
      expect(restored, isNotNull);
      expect(restored!.pointsRecipientOffer, isNull);
      expect(restored.pointsRedeemOffer, isNull);
    });
  });

  group('migrasi skema v1 → v3', () {
    test('basis data v1 ter-upgrade: record lama utuh, jurnal baru '
        'tersimpan & terbaca', () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});
      final tmp = await Directory.systemTemp.createTemp('store_v1');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      final dbPath = p.join(tmp.path, 'store_pos.db');

      // Bangun berkas skema v1 persis seperti onCreate lama
      // (orders TANPA dua kolom jurnal).
      final v1 = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
CREATE TABLE catalog_items(
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  price_rp INTEGER NOT NULL,
  category TEXT NOT NULL DEFAULT '',
  discount_kind TEXT,
  discount_value INTEGER
)''');
            await db.execute('''
CREATE TABLE orders(
  row_key TEXT PRIMARY KEY,
  id TEXT NOT NULL DEFAULT '',
  time_ms INTEGER NOT NULL,
  era TEXT NOT NULL,
  status TEXT NOT NULL,
  subtotal_rp INTEGER NOT NULL,
  total_discount_rp INTEGER NOT NULL,
  grand_total_rp INTEGER NOT NULL,
  payment_hash TEXT,
  pay_method TEXT,
  cash_received_rp INTEGER NOT NULL DEFAULT 0,
  change_rp INTEGER NOT NULL DEFAULT 0,
  points_redeemed INTEGER NOT NULL DEFAULT 0,
  points_discount_rp INTEGER NOT NULL DEFAULT 0,
  points_earned INTEGER NOT NULL DEFAULT 0,
  points_issue_status TEXT NOT NULL DEFAULT 'none',
  points_issue_hash TEXT,
  customer_name TEXT NOT NULL DEFAULT '',
  bill_no INTEGER NOT NULL DEFAULT 0,
  token_no INTEGER NOT NULL DEFAULT 0,
  order_discount_kind TEXT,
  order_discount_value INTEGER,
  shift_opened_ms INTEGER
)''');
            await db.execute('''
CREATE TABLE order_lines(
  order_row_key TEXT NOT NULL,
  seq INTEGER NOT NULL,
  code TEXT,
  label TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT '',
  unit_price_rp INTEGER NOT NULL,
  qty INTEGER NOT NULL,
  discount_kind TEXT,
  discount_value INTEGER,
  note TEXT NOT NULL DEFAULT '',
  PRIMARY KEY(order_row_key, seq)
)''');
            await db.execute('''
CREATE TABLE shifts(
  opened_ms INTEGER PRIMARY KEY,
  closed_ms INTEGER,
  era TEXT NOT NULL DEFAULT 'nusan'
)''');
            await db.execute('''
CREATE TABLE store_kv(
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)''');
          },
        ),
      );
      await v1.insert('orders', {
        'row_key': 'legacy1',
        'id': 'legacy1',
        'time_ms': t.millisecondsSinceEpoch,
        'era': 'rp',
        'status': 'paid',
        'subtotal_rp': 10000,
        'total_discount_rp': 0,
        'grand_total_rp': 10000,
        'points_earned': 50,
        'points_issue_status': 'issued',
      });
      await v1.insert('order_lines', {
        'order_row_key': 'legacy1',
        'seq': 0,
        'label': 'Kopi',
        'unit_price_rp': 10000,
        'qty': 1,
      });
      await v1.close();

      // Buka lewat StoreDatabase produksi: upgrade berjenjang
      // (v2 jurnal, lalu v3 Fase A) jalan sampai versi terkini.
      final storeDb = StoreDatabase(dbPathProvider: () async => dbPath);
      final db = await storeDb.database;
      final versionRows = await db.rawQuery('PRAGMA user_version');
      expect(versionRows.first['user_version'], 3);

      final history = StoreOrderHistoryStore(database: storeDb);
      final loaded = await history.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.pointsEarned, 50);
      // Record era v1 tidak punya identitas jurnal.
      expect(loaded.single.pointsRecipientOffer, isNull);
      expect(loaded.single.pointsRedeemOffer, isNull);

      // Record baru dengan offer jurnal tersimpan & terbaca.
      await history.append(
        sale(
          time: t,
          pointsEarned: 50,
        ).withIssueStatus(issueStatusIssued, recipientOffer: offerA),
      );
      final reloaded = await history.load();
      expect(reloaded, hasLength(2));
      expect(pointsJournalBalanceFor(reloaded, offerA), 50);
      await storeDb.close();
    });
  });
}
