import 'dart:math';

import 'store_database.dart';
import 'store_order_history.dart' show normalizePointsOffer;

/// Pelanggan Mode Toko (permintaan NUX 4 Nov 2026): nama +
/// offer Bolt12 statis milik pelanggan, tersimpan di SQLite
/// (tabel `customers`, skema v4).
///
/// Gunanya di halaman Penyelesaian Pembayaran: kasir memilih
/// pelanggan tersimpan alih-alih memindai kode bayar pelanggan
/// berulang kali — offer yang dipilih menjadi dasar penukaran
/// poin (jurnal) dan sasaran penerbitan poin sesudah lunas.
/// Offer disimpan dalam bentuk ternormalisasi yang sama
/// dengan kunci jurnal poin (trim + huruf kecil), jadi
/// pencocokan jurnal tidak pernah meleset karena format.
class StoreCustomer {
  final String id;
  final String name;

  /// Offer Bolt12 statis pelanggan (ternormalisasi).
  final String offer;
  final DateTime createdAt;

  const StoreCustomer({
    required this.id,
    required this.name,
    required this.offer,
    required this.createdAt,
  });

  StoreCustomer copyWith({String? name, String? offer}) => StoreCustomer(
        id: id,
        name: name ?? this.name,
        offer: offer ?? this.offer,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      other is StoreCustomer &&
      other.id == id &&
      other.name == name &&
      other.offer == offer &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, offer, createdAt);
}

/// Penyimpanan pelanggan di tabel `customers`.
class StoreCustomerStore {
  StoreCustomerStore({StoreDatabase? database})
      : _database = database ?? StoreDatabase.instance;

  final StoreDatabase _database;

  /// Seluruh pelanggan, urut nama.
  Future<List<StoreCustomer>> loadAll() async {
    final db = await _database.database;
    final rows = await db.query('customers', orderBy: 'name ASC');
    return [
      for (final row in rows)
        StoreCustomer(
          id: row['id'] as String,
          name: row['name'] as String,
          offer: row['offer'] as String,
          createdAt:
              DateTime.fromMillisecondsSinceEpoch(row['created_ms'] as int),
        ),
    ];
  }

  /// Tambah pelanggan; offer dinormalisasi di sini supaya
  /// semua jalur masuk (tempel, pindai, ketik) konsisten.
  Future<StoreCustomer> add({
    required String name,
    required String offer,
  }) async {
    final now = DateTime.now();
    final customer = StoreCustomer(
      id: 'cust-${now.millisecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}',
      name: name.trim(),
      offer: normalizePointsOffer(offer),
      createdAt: now,
    );
    final db = await _database.database;
    await db.insert('customers', {
      'id': customer.id,
      'name': customer.name,
      'offer': customer.offer,
      'created_ms': now.millisecondsSinceEpoch,
    });
    return customer;
  }

  Future<void> update(StoreCustomer customer) async {
    final db = await _database.database;
    await db.update(
      'customers',
      {
        'name': customer.name.trim(),
        'offer': normalizePointsOffer(customer.offer),
      },
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _database.database;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }
}
