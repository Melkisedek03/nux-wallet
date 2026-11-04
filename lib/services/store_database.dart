import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'store_catalog.dart';
import 'store_order_history.dart';
import 'store_shift.dart';

/// Basis data SQLite Mode Toko (keputusan NUX 4 Nov 2026):
/// SATU berkas `store_pos.db` di direktori dokumen aplikasi
/// menjadi rumah baru seluruh data transaksional toko —
/// katalog, pesanan + barisnya, dan shift sebagai tabel
/// relasional; pengaturan, daftar tahan, draf, dan penghitung
/// token sebagai baris kunci-nilai JSON di `store_kv` (bentuk
/// snapshot murni — serialisasinya tidak berubah dari era
/// SharedPreferences, jadi perilaku & formatnya persis sama).
///
/// Dibuka LAZY pada pemakaian store pertama (tidak ada
/// perubahan di main()); skema berversi lewat `user_version`
/// sqflite. Saat pertama dibuka, data SharedPreferences era
/// sebelumnya DIIMPOR satu kali dalam satu transaksi (lihat
/// [_importFromSharedPreferencesOnce]).
class StoreDatabase {
  StoreDatabase({Future<String> Function()? dbPathProvider})
    : _dbPathProvider = dbPathProvider;

  /// Instans produksi yang dipakai semua store Mode Toko.
  static final StoreDatabase instance = StoreDatabase();

  /// Nama berkas basis data di direktori dokumen aplikasi.
  static const String dbFileName = 'store_pos.db';

  /// Kunci penanda impor satu-kali di tabel store_kv.
  static const String importMarkerKey = 'sp_sqlite_import_done';

  final Future<String> Function()? _dbPathProvider;
  Future<Database>? _opening;

  /// Basis data yang sudah terbuka (membuka + mengimpor pada
  /// panggilan pertama). Kegagalan buka DIBIARKAN melempar ke
  /// pemanggil — store pemanggil yang memutuskan fail-open
  /// seperti pola lama mereka.
  Future<Database> get database => _opening ??= _open();

  Future<String> _defaultDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, dbFileName);
  }

  Future<Database> _open() async {
    final path = await (_dbPathProvider?.call() ?? _defaultDbPath());
    final db = await openDatabase(
      path,
      version: 2,
      onUpgrade: (db, oldVersion, newVersion) async {
        // v2: kolom jurnal poin pada orders — offer penerima
        // penerbitan & offer penukaran (penukaran model jurnal
        // membaca saldo dari dua kolom ini). Nullable; record
        // lama terbaca null (di luar jurnal).
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE orders ADD COLUMN points_recipient_offer TEXT',
          );
          await db.execute(
            'ALTER TABLE orders ADD COLUMN points_redeem_offer TEXT',
          );
        }
      },
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
  points_recipient_offer TEXT,
  points_redeem_offer TEXT,
  customer_name TEXT NOT NULL DEFAULT '',
  bill_no INTEGER NOT NULL DEFAULT 0,
  token_no INTEGER NOT NULL DEFAULT 0,
  order_discount_kind TEXT,
  order_discount_value INTEGER,
  shift_opened_ms INTEGER
)''');
        await db.execute(
          'CREATE INDEX idx_orders_time ON orders(time_ms)',
        );
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
    );
    await _importFromSharedPreferencesOnce(db);
    return db;
  }

  /// Tutup basis data (dipakai test; produksi tidak menutup —
  /// umur basis data = umur proses aplikasi).
  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) {
      final db = await opening;
      await db.close();
    }
  }

  /// Impor SATU KALI dari SharedPreferences era sebelumnya,
  /// dalam SATU transaksi: katalog v2, riwayat pesanan, shift
  /// (termasuk yang masih terbuka — ia baris biasa di tabel),
  /// dan salinan mentah JSON pengaturan / daftar tahan / draf /
  /// penghitung token ke store_kv (formatnya sama, jadi salin
  /// apa adanya tanpa tafsir ulang). Penanda impor ditulis di
  /// transaksi yang sama — kegagalan di tengah berarti impor
  /// belum terjadi dan akan dicoba lagi pada buka berikutnya;
  /// keberhasilan berarti tidak pernah impor ulang. Data
  /// SharedPreferences lama SENGAJA tidak dihapus pada versi
  /// ini (jaring pengaman), tetapi tidak lagi dibaca untuk
  /// Mode Toko sesudah impor.
  Future<void> _importFromSharedPreferencesOnce(Database db) async {
    if (await storeKvGet(db, importMarkerKey) == '1') return;
    await db.transaction((txn) async {
      if (await storeKvGet(txn, importMarkerKey) == '1') return;
      final prefs = await SharedPreferences.getInstance();
      // Katalog & riwayat & shift: decode dengan pembaca lama
      // yang sama, tulis sebagai baris relasional.
      final catalog = decodeCatalog(
        prefs.getString(StoreCatalogStore.storageKey),
      );
      await insertCatalogRows(txn, catalog);
      final orders = decodeOrderHistory(
        prefs.getString(StoreOrderHistoryStore.storageKey),
      );
      for (var i = 0; i < orders.length; i++) {
        await insertCompletedOrder(txn, orders[i], rowKey: 'import:$i');
      }
      final shifts = decodeShifts(prefs.getString(StoreShiftStore.storageKey));
      await insertShiftRows(txn, shifts);
      // Snapshot JSON: salin mentah bila ada.
      for (final key in storeKvSnapshotKeys) {
        final raw = prefs.getString(key);
        if (raw != null) await storeKvSet(txn, key, raw);
      }
      await storeKvSet(txn, importMarkerKey, '1');
    });
  }
}

/// Kunci-kunci SharedPreferences lama yang isinya snapshot JSON
/// dan pindah apa adanya ke tabel store_kv saat impor.
const List<String> storeKvSnapshotKeys = [
  'store_settings_v1',
  'store_held_orders_v2',
  'store_draft_order_v1',
  'store_token_counter_v1',
];

// ---------------------------------------------------------------------
// Pembantu kunci-nilai store_kv (dipakai semua store snapshot).
// ---------------------------------------------------------------------

Future<String?> storeKvGet(DatabaseExecutor executor, String key) async {
  final rows = await executor.query(
    'store_kv',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: [key],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  final value = rows.first['value'];
  return value is String ? value : null;
}

Future<void> storeKvSet(
  DatabaseExecutor executor,
  String key,
  String value,
) async {
  await executor.insert('store_kv', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> storeKvDelete(DatabaseExecutor executor, String key) async {
  await executor.delete('store_kv', where: 'key = ?', whereArgs: [key]);
}
