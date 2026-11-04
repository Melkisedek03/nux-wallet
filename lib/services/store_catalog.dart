import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../utils/store_mode_logic.dart';
import 'store_database.dart';

/// Satu produk di katalog lokal Mode Toko.
///
/// [code] adalah isi barcode/QR produk apa adanya (EAN, UPC,
/// Code128, QR — pemindai aplikasi tidak membatasi format), [name]
/// nama tampil untuk kasir, [priceRp] harga satuan dalam rupiah
/// bulat (v2: seluruh harga Mode Toko berdenominasi rupiah). [defaultDiscount] diskon bawaan produk (persen atau
/// nominal, boleh null): otomatis terisi ke baris pesanan saat
/// produk ditambahkan, dan kasir tetap bisa mengubahnya di baris.
class CatalogItem {
  final String code;
  final String name;
  final int priceRp;
  final Discount? defaultDiscount;

  /// Kategori produk untuk pengelompokan laporan penjualan
  /// (mis. "MENTARI"). Kosong = tanpa kategori → item masuk
  /// kelompok LAINNYA di laporan. Item simpanan lama tanpa field
  /// ini terbaca sebagai kategori kosong (kompatibel mundur).
  final String category;

  const CatalogItem({
    required this.code,
    required this.name,
    required this.priceRp,
    this.defaultDiscount,
    this.category = '',
  });

  Map<String, Object?> toJson() => {
    'code': code,
    'name': name,
    'priceRp': priceRp,
    if (category.isNotEmpty) 'category': category,
    if (defaultDiscount != null) ...{
      'discountKind': defaultDiscount!.kind.name,
      'discountValue': defaultDiscount!.value,
    },
  };

  /// Baca satu item dari JSON; null bila bentuknya tidak sah
  /// (kode/nama kosong, harga bukan bilangan >= 0). Diskon bawaan
  /// yang rusak dibuang saja (item tetap sah tanpa diskon) —
  /// diskon adalah pelengkap, bukan identitas produk.
  static CatalogItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final code = raw['code'];
    final name = raw['name'];
    // Kunci v2 'priceRp'; 'priceNusan' hanya cadangan baca untuk
    // simpanan uji lama — store produksi v2 adalah kunci baru.
    final price = raw['priceRp'] ?? raw['priceNusan'];
    if (code is! String || code.trim().isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;
    if (price is! num || price < 0 || price != price.roundToDouble()) {
      return null;
    }
    Discount? discount;
    final kind = raw['discountKind'];
    final value = raw['discountValue'];
    if (value is num && value > 0) {
      discount = switch (kind) {
        'percent' => Discount.percent(value > 100 ? 100 : value.toInt()),
        'fixed' => Discount.fixed(value.toInt()),
        _ => null,
      };
    }
    final category = raw['category'];
    return CatalogItem(
      code: code.trim(),
      name: name.trim(),
      priceRp: price.toInt(),
      defaultDiscount: discount,
      category: category is String ? category.trim() : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogItem &&
      other.code == code &&
      other.name == name &&
      other.priceRp == priceRp &&
      other.defaultDiscount == defaultDiscount &&
      other.category == category;

  @override
  int get hashCode =>
      Object.hash(code, name, priceRp, defaultDiscount, category);
}

/// Serialkan katalog ke string JSON untuk simpanan lokal.
String encodeCatalog(List<CatalogItem> items) =>
    jsonEncode(items.map((i) => i.toJson()).toList());

/// Baca katalog dari string JSON simpanan. Fail-open seperti store
/// lokal lain di aplikasi: string rusak/bukan daftar → katalog
/// kosong; entri yang bentuknya tidak sah dilewati satu-satu,
/// bukan menggagalkan seluruh katalog.
List<CatalogItem> decodeCatalog(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (parsed is! List) return const [];
  final items = <CatalogItem>[];
  for (final entry in parsed) {
    final item = CatalogItem.fromJson(entry);
    if (item != null) items.add(item);
  }
  return items;
}

/// Cari produk dari isi scan (kode dibandingkan persis sesudah
/// trim — pemindai mengembalikan rawValue apa adanya). Null bila
/// kode belum terdaftar; pemanggil wajib menyampaikan itu ke kasir
/// dan menawarkan pendaftaran cepat, bukan mengabaikannya.
CatalogItem? findCatalogItemByCode(List<CatalogItem> items, String code) {
  final needle = code.trim();
  if (needle.isEmpty) return null;
  for (final item in items) {
    if (item.code == needle) return item;
  }
  return null;
}

/// Daftar kategori yang sudah ada di katalog — bahan saran
/// isian field Kategori di lembar Kelola, supaya kasir tidak
/// mengetik ulang dan ejaan kategori seragam antar produk
/// (kategori adalah kunci pengelompokan laporan). Unik sesudah
/// trim, tak peka huruf besar/kecil (bentuk pertama yang
/// ditemukan yang dipertahankan), kosong dilewati, urut abjad
/// tak peka huruf besar/kecil.
List<String> catalogCategories(List<CatalogItem> items) {
  final seen = <String>{};
  final categories = <String>[];
  for (final item in items) {
    final category = item.category.trim();
    if (category.isEmpty) continue;
    if (seen.add(category.toLowerCase())) categories.add(category);
  }
  categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return categories;
}

/// Saring katalog untuk kolom cari kasir: item lolos bila NAMA
/// atau KODE-nya mengandung [query] (sesudah trim, tak peka huruf
/// besar/kecil, cocok sebagian — bukan harus persis seperti
/// pencarian scan). Query kosong/spasi saja → seluruh katalog
/// apa adanya (urutan asli dipertahankan).
List<CatalogItem> filterCatalogItems(List<CatalogItem> items, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return items;
  return [
    for (final item in items)
      if (item.name.toLowerCase().contains(needle) ||
          item.code.toLowerCase().contains(needle))
        item,
  ];
}

/// Tulis seluruh katalog sebagai baris tabel catalog_items
/// lewat [executor] — urutan daftar dipertahankan lewat urutan
/// tulis (rowid). Dipakai store katalog & impor satu-kali.
Future<void> insertCatalogRows(
  DatabaseExecutor executor,
  List<CatalogItem> items,
) async {
  await executor.delete('catalog_items');
  for (final item in items) {
    await executor.insert('catalog_items', {
      'code': item.code,
      'name': item.name,
      'price_rp': item.priceRp,
      'category': item.category,
      'discount_kind': item.defaultDiscount?.kind.name,
      'discount_value': item.defaultDiscount?.value,
    });
  }
}

/// Penyimpanan katalog Mode Toko di SQLite (store_pos.db,
/// tabel catalog_items) — sejak migrasi 4 Nov 2026
/// menggantikan SharedPreferences.
///
/// Kegagalan baca dianggap "katalog kosong" (fail-open) dan
/// kegagalan tulis ditelan — katalog adalah data kasir yang
/// bisa dibangun ulang, bukan sumber kebenaran dana.
class StoreCatalogStore {
  /// Kunci SharedPreferences era lama (sumber impor satu-kali).
  static const String storageKey = 'store_catalog_items_v2';

  StoreCatalogStore({StoreDatabase? database})
    : _database = database ?? StoreDatabase.instance;

  final StoreDatabase _database;

  Future<List<CatalogItem>> load() async {
    try {
      final db = await _database.database;
      final rows = await db.query('catalog_items', orderBy: 'rowid ASC');
      return [
        for (final row in rows)
          CatalogItem(
            code: row['code'] as String,
            name: row['name'] as String,
            priceRp: (row['price_rp'] as num).toInt(),
            category: row['category'] is String
                ? row['category'] as String
                : '',
            defaultDiscount: switch (row['discount_kind']) {
              'percent' when row['discount_value'] is num =>
                Discount.percent(
                  (row['discount_value'] as num).toInt() > 100
                      ? 100
                      : (row['discount_value'] as num).toInt(),
                ),
              'fixed' when row['discount_value'] is num =>
                Discount.fixed((row['discount_value'] as num).toInt()),
              _ => null,
            },
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<CatalogItem> items) async {
    try {
      final db = await _database.database;
      await db.transaction((txn) async {
        await insertCatalogRows(txn, items);
      });
    } catch (_) {
      // Abaikan — katalog sesi ini tetap tampil.
    }
  }
}
