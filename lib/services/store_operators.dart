import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'store_database.dart';

/// Operator Mode Toko & log audit — Fase A peran (keputusan
/// NUX 4 Nov 2026: gas Fase A; (a) aksi sensitif wajib PIN
/// admin, (b) kasir hanya melihat laporan shift-nya sendiri,
/// (c) PIN 6 digit).
///
/// Model akuntabilitas, bukan benteng: PIN disimpan sebagai
/// hash SHA-256 bergaram acak per operator (tidak pernah teks
/// polos), setiap penjualan & shift membawa stempel operator
/// yang sedang login, dan kejadian penting masuk log audit
/// append-only. Orang yang memegang perangkat secara fisik
/// tetap bisa mengutak-atik berkas basis data — kekuatan
/// sistem ini ada pada jejak yang tertinggal, bukan pada
/// larangan semata.

/// Peran operator: pemilik/admin toko.
const storeRoleOwner = 'owner';

/// Peran operator: kasir.
const storeRoleCashier = 'cashier';

/// Panjang PIN operator (keputusan NUX: 6 digit).
const storePinLength = 6;

/// Apakah [pin] berbentuk PIN sah: tepat 6 digit angka.
bool isValidStorePin(String pin) =>
    pin.length == storePinLength &&
    pin.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

/// Garam acak baru untuk hash PIN (16 byte, hex).
String newStorePinSalt() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Hash PIN bergaram: SHA-256 atas "<salt>:<pin>".
String hashStorePin(String pin, String salt) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();

/// Verifikasi PIN terhadap garam + hash tersimpan.
bool verifyStorePin(String pin, String salt, String expectedHash) {
  final actual = hashStorePin(pin, salt);
  if (actual.length != expectedHash.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
  }
  return diff == 0;
}

/// Satu akun operator Mode Toko.
class StoreOperator {
  final String id;
  final String name;

  /// [storeRoleOwner] atau [storeRoleCashier].
  final String role;
  final bool active;
  final DateTime createdAt;

  const StoreOperator({
    required this.id,
    required this.name,
    required this.role,
    required this.active,
    required this.createdAt,
  });

  bool get isOwner => role == storeRoleOwner;

  StoreOperator copyWith({String? name, String? role, bool? active}) =>
      StoreOperator(
        id: id,
        name: name ?? this.name,
        role: role ?? this.role,
        active: active ?? this.active,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      other is StoreOperator &&
      other.id == id &&
      other.name == name &&
      other.role == role &&
      other.active == active &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, role, active, createdAt);
}

/// Penyimpanan akun operator di tabel `operators` (SQLite).
class StoreOperatorStore {
  StoreOperatorStore({StoreDatabase? database})
      : _database = database ?? StoreDatabase.instance;

  final StoreDatabase _database;

  StoreOperator _fromRow(Map<String, Object?> row) => StoreOperator(
        id: row['id'] as String,
        name: row['name'] as String,
        role: row['role'] as String,
        active: (row['active'] as int) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_ms'] as int),
      );

  /// Seluruh operator (termasuk nonaktif), urut waktu buat.
  Future<List<StoreOperator>> loadAll() async {
    final db = await _database.database;
    final rows = await db.query('operators', orderBy: 'created_ms ASC');
    return rows.map(_fromRow).toList();
  }

  /// Buat operator baru dengan PIN yang sudah divalidasi
  /// bentuknya oleh pemanggil. Id lahir dari waktu + acak —
  /// cukup unik untuk satu perangkat.
  Future<StoreOperator> create({
    required String name,
    required String role,
    required String pin,
  }) async {
    final now = DateTime.now();
    final salt = newStorePinSalt();
    final id =
        'op-${now.millisecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}';
    final op = StoreOperator(
      id: id,
      name: name.trim(),
      role: role,
      active: true,
      createdAt: now,
    );
    final db = await _database.database;
    await db.insert('operators', {
      'id': op.id,
      'name': op.name,
      'role': op.role,
      'pin_salt': salt,
      'pin_hash': hashStorePin(pin, salt),
      'active': 1,
      'created_ms': now.millisecondsSinceEpoch,
    });
    return op;
  }

  /// Verifikasi PIN untuk SATU operator; null bila operator
  /// tidak ada/nonaktif atau PIN salah.
  Future<StoreOperator?> verifyPin(String operatorId, String pin) async {
    final db = await _database.database;
    final rows = await db.query(
      'operators',
      where: 'id = ? AND active = 1',
      whereArgs: [operatorId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final ok = verifyStorePin(
      pin,
      row['pin_salt'] as String,
      row['pin_hash'] as String,
    );
    return ok ? _fromRow(row) : null;
  }

  /// Verifikasi PIN terhadap SEMUA owner aktif — jalur
  /// override admin di tempat (supervisor mengetik PIN-nya
  /// tanpa mengganti sesi kasir). Mengembalikan owner yang
  /// PIN-nya cocok; null bila tidak ada yang cocok.
  Future<StoreOperator?> verifyAnyOwnerPin(String pin) async {
    final db = await _database.database;
    final rows = await db.query(
      'operators',
      where: 'role = ? AND active = 1',
      whereArgs: [storeRoleOwner],
    );
    for (final row in rows) {
      if (verifyStorePin(
        pin,
        row['pin_salt'] as String,
        row['pin_hash'] as String,
      )) {
        return _fromRow(row);
      }
    }
    return null;
  }

  /// Perbarui nama/peran/status aktif operator.
  Future<void> update(StoreOperator op) async {
    final db = await _database.database;
    await db.update(
      'operators',
      {
        'name': op.name,
        'role': op.role,
        'active': op.active ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [op.id],
    );
  }

  /// Ganti PIN operator (garam & hash baru).
  Future<void> setPin(String operatorId, String newPin) async {
    final salt = newStorePinSalt();
    final db = await _database.database;
    await db.update(
      'operators',
      {'pin_salt': salt, 'pin_hash': hashStorePin(newPin, salt)},
      where: 'id = ?',
      whereArgs: [operatorId],
    );
  }
}

/// Satu baris log audit Mode Toko.
class StoreAuditEntry {
  final int seq;
  final DateTime time;

  /// Operator yang tercatat melakukan/mengalami kejadian
  /// ('' = sebelum ada operator, mis. pembuatan owner pertama
  /// dicatat atas nama owner itu sendiri sesudah dibuat).
  final String operatorId;
  final String operatorName;

  /// Jenis kejadian: 'login', 'logout', 'operator_created',
  /// 'operator_updated', 'shift_open', 'shift_close',
  /// 'admin_override', 'sale_void', 'pin_changed'.
  final String action;

  /// Rincian bebas (mis. nomor bill + alasan VOID, nama aksi
  /// yang di-override + penyetuju).
  final String detail;

  const StoreAuditEntry({
    required this.seq,
    required this.time,
    required this.operatorId,
    required this.operatorName,
    required this.action,
    required this.detail,
  });
}

/// Aksi audit yang dikenal (hindari salah ketik di pemanggil).
class StoreAuditAction {
  static const login = 'login';
  static const logout = 'logout';
  static const operatorCreated = 'operator_created';
  static const operatorUpdated = 'operator_updated';
  static const pinChanged = 'pin_changed';
  static const shiftOpen = 'shift_open';
  static const shiftClose = 'shift_close';
  static const adminOverride = 'admin_override';
  static const saleVoid = 'sale_void';
}

/// Log audit append-only (dari aplikasi): baris hanya pernah
/// ditambah & dibaca, tidak ada jalur ubah/hapus.
class StoreAuditStore {
  StoreAuditStore({StoreDatabase? database})
      : _database = database ?? StoreDatabase.instance;

  final StoreDatabase _database;

  /// Tambahkan satu baris audit. Kegagalan ditelan diam-diam:
  /// audit tidak boleh menggagalkan aksi bisnis yang sedang
  /// berjalan (penjualan tetap sah walau baris lognya gagal).
  Future<void> append({
    required StoreOperator? operator,
    required String action,
    String detail = '',
  }) async {
    try {
      final db = await _database.database;
      await db.insert('audit_log', {
        'time_ms': DateTime.now().millisecondsSinceEpoch,
        'operator_id': operator?.id ?? '',
        'operator_name': operator?.name ?? '',
        'action': action,
        'detail': detail,
      });
    } catch (_) {
      // Abaikan — lihat dokumentasi metode.
    }
  }

  /// Baris audit terbaru di depan (untuk penampil log).
  Future<List<StoreAuditEntry>> load({int limit = 300}) async {
    final db = await _database.database;
    final rows = await db.query(
      'audit_log',
      orderBy: 'seq DESC',
      limit: limit,
    );
    return rows
        .map(
          (row) => StoreAuditEntry(
            seq: row['seq'] as int,
            time: DateTime.fromMillisecondsSinceEpoch(row['time_ms'] as int),
            operatorId: row['operator_id'] as String,
            operatorName: row['operator_name'] as String,
            action: row['action'] as String,
            detail: row['detail'] as String,
          ),
        )
        .toList();
  }
}
