import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/store_mode_logic.dart';

/// Satu produk di katalog lokal Mode Toko.
///
/// [code] adalah isi barcode/QR produk apa adanya (EAN, UPC,
/// Code128, QR — pemindai aplikasi tidak membatasi format), [name]
/// nama tampil untuk kasir, [priceNusan] harga satuan dalam nusan
/// bulat. [defaultDiscount] diskon bawaan produk (persen atau
/// nominal, boleh null): otomatis terisi ke baris pesanan saat
/// produk ditambahkan, dan kasir tetap bisa mengubahnya di baris.
class CatalogItem {
  final String code;
  final String name;
  final int priceNusan;
  final Discount? defaultDiscount;

  /// Kategori produk untuk pengelompokan laporan penjualan
  /// (mis. "MENTARI"). Kosong = tanpa kategori → item masuk
  /// kelompok LAINNYA di laporan. Item simpanan lama tanpa field
  /// ini terbaca sebagai kategori kosong (kompatibel mundur).
  final String category;

  const CatalogItem({
    required this.code,
    required this.name,
    required this.priceNusan,
    this.defaultDiscount,
    this.category = '',
  });

  Map<String, Object?> toJson() => {
    'code': code,
    'name': name,
    'priceNusan': priceNusan,
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
    final price = raw['priceNusan'];
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
      priceNusan: price.toInt(),
      defaultDiscount: discount,
      category: category is String ? category.trim() : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogItem &&
      other.code == code &&
      other.name == name &&
      other.priceNusan == priceNusan &&
      other.defaultDiscount == defaultDiscount &&
      other.category == category;

  @override
  int get hashCode =>
      Object.hash(code, name, priceNusan, defaultDiscount, category);
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

/// Penyimpanan katalog Mode Toko di SharedPreferences.
///
/// Pola sama seperti Bolt12OfferStore/SavedInvoiceStore: kegagalan
/// baca dianggap "katalog kosong" (fail-open) dan kegagalan tulis
/// ditelan — katalog adalah data kasir yang bisa dibangun ulang,
/// bukan sumber kebenaran dana.
class StoreCatalogStore {
  static const String storageKey = 'store_catalog_items_v1';

  Future<List<CatalogItem>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeCatalog(prefs.getString(storageKey));
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<CatalogItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encodeCatalog(items));
    } catch (_) {
      // Abaikan — katalog sesi ini tetap tampil.
    }
  }
}
