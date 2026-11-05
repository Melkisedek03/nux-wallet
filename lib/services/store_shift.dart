import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'store_database.dart';

/// Satu shift kasir Mode Toko: dibuka kasir dengan tombol Buka
/// Shift, ditutup dengan Tutup Shift. Semua record pesanan toko
/// (lunas maupun VOID) dicatat di dalam jendela shift yang sedang
/// terbuka — layar Mode Toko menghalangi penyelesaian pesanan di
/// luar shift dan menghalangi penutupan selama masih ada lembar
/// pembayaran yang terbuka, jadi secara konstruksi tidak ada
/// record pesanan "di luar shift".
class StoreShift {
  final DateTime openedAt;
  final DateTime? closedAt;

  /// Era shift: 'nusan' untuk shift yang dibuka Mode Toko v1,
  /// 'rp' untuk v2 (kasir rupiah). Simpanan lama tanpa field ini
  /// terbaca 'nusan'. Migrasi v2 menutup paksa shift 'nusan'
  /// yang masih terbuka; shift baru selalu dibuat ber-era 'rp'.
  final String era;

  /// Stempel operator Fase A: operator yang MEMBUKA shift ini.
  /// '' untuk shift sebelum Fase A. Inilah dasar aturan
  /// "kasir hanya melihat laporan shift-nya sendiri".
  final String operatorId;
  final String operatorName;

  /// Modal awal laci (rupiah tunai) yang diinput kasir saat
  /// membuka shift — permintaan NUX 5 Nov 2026. Hanya
  /// pembayaran TUNAI yang menggerakkan posisi laci dari
  /// angka ini; metode non-tunai tidak memengaruhi modal/
  /// posisi tunai. 0 untuk shift sebelum fitur ini.
  final int openingFloatRp;

  const StoreShift({
    required this.openedAt,
    this.closedAt,
    this.era = 'nusan',
    this.operatorId = '',
    this.operatorName = '',
    this.openingFloatRp = 0,
  });

  bool get isOpen => closedAt == null;

  /// Salinan shift ini dalam keadaan tertutup pada [at].
  StoreShift close(DateTime at) => StoreShift(
        openedAt: openedAt,
        closedAt: at,
        era: era,
        operatorId: operatorId,
        operatorName: operatorName,
        openingFloatRp: openingFloatRp,
      );

  /// Ujung jendela laporan shift ini: waktu tutup, atau [now]
  /// bila shift masih berjalan.
  DateTime windowEnd(DateTime now) => closedAt ?? now;

  /// Apakah [time] jatuh di dalam jendela shift ini —
  /// [openedAt] inklusif, ujung eksklusif (konsisten dengan
  /// konvensi rentang [from, to) agregasi penjualan).
  bool containsTime(DateTime time, {DateTime? now}) {
    if (time.isBefore(openedAt)) return false;
    final end = windowEnd(now ?? DateTime.now());
    return time.isBefore(end);
  }

  Map<String, Object?> toJson() => {
    'openedAtMs': openedAt.millisecondsSinceEpoch,
    'closedAtMs': closedAt?.millisecondsSinceEpoch,
    if (era != 'nusan') 'era': era,
    if (operatorId.isNotEmpty) 'operatorId': operatorId,
    if (operatorName.isNotEmpty) 'operatorName': operatorName,
    if (openingFloatRp != 0) 'openingFloatRp': openingFloatRp,
  };

  /// Baca satu shift; null bila bentuknya tidak sah (waktu buka
  /// wajib ada; waktu tutup, bila ada, tidak boleh mendahului
  /// waktu buka).
  static StoreShift? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final opened = raw['openedAtMs'];
    if (opened is! num) return null;
    final openedAt = DateTime.fromMillisecondsSinceEpoch(opened.toInt());
    final closed = raw['closedAtMs'];
    DateTime? closedAt;
    if (closed is num) {
      closedAt = DateTime.fromMillisecondsSinceEpoch(closed.toInt());
      if (closedAt.isBefore(openedAt)) return null;
    }
    return StoreShift(
      openedAt: openedAt,
      closedAt: closedAt,
      era: raw['era'] == 'rp' ? 'rp' : 'nusan',
      operatorId: raw['operatorId'] is String
          ? raw['operatorId'] as String
          : '',
      operatorName: raw['operatorName'] is String
          ? raw['operatorName'] as String
          : '',
      openingFloatRp: raw['openingFloatRp'] is num
          ? (raw['openingFloatRp'] as num).toInt()
          : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StoreShift &&
      other.openedAt.millisecondsSinceEpoch ==
          openedAt.millisecondsSinceEpoch &&
      other.closedAt?.millisecondsSinceEpoch ==
          closedAt?.millisecondsSinceEpoch &&
      other.era == era &&
      other.operatorId == operatorId &&
      other.operatorName == operatorName &&
      other.openingFloatRp == openingFloatRp;

  @override
  int get hashCode => Object.hash(
    openedAt.millisecondsSinceEpoch,
    closedAt?.millisecondsSinceEpoch,
    era,
    operatorId,
    operatorName,
    openingFloatRp,
  );
}

String encodeShifts(List<StoreShift> shifts) =>
    jsonEncode(shifts.map((s) => s.toJson()).toList());

/// Baca daftar shift dari string simpanan; fail-open seperti
/// store lokal lain: rusak → kosong, entri tak sah dilewati.
List<StoreShift> decodeShifts(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (parsed is! List) return const [];
  final shifts = <StoreShift>[];
  for (final entry in parsed) {
    final shift = StoreShift.fromJson(entry);
    if (shift != null) shifts.add(shift);
  }
  return shifts;
}

/// Shift yang sedang terbuka dalam [shifts] (yang terakhir
/// ber-closedAt null), atau null bila semua tertutup. Secara
/// konstruksi paling banyak satu shift terbuka pada satu waktu.
StoreShift? openShiftIn(List<StoreShift> shifts) {
  for (var i = shifts.length - 1; i >= 0; i--) {
    if (shifts[i].isOpen) return shifts[i];
  }
  return null;
}

/// Tulis seluruh daftar shift sebagai baris tabel shifts lewat
/// [executor]. Dipakai store shift & impor satu-kali.
Future<void> insertShiftRows(
  DatabaseExecutor executor,
  List<StoreShift> shifts,
) async {
  await executor.delete('shifts');
  for (final shift in shifts) {
    await executor.insert('shifts', {
      'opened_ms': shift.openedAt.millisecondsSinceEpoch,
      'closed_ms': shift.closedAt?.millisecondsSinceEpoch,
      'era': shift.era,
      'operator_id': shift.operatorId,
      'operator_name': shift.operatorName,
      'opening_float_rp': shift.openingFloatRp,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

/// Penyimpanan shift Mode Toko di SQLite (store_pos.db, tabel
/// shifts) — sejak migrasi 4 Nov 2026 menggantikan
/// SharedPreferences. Shift yang sedang terbuka adalah baris
/// ber-closed_ms null, sama seperti sebelumnya.
class StoreShiftStore {
  /// Kunci SharedPreferences era lama (sumber impor satu-kali).
  static const String storageKey = 'store_shifts_v1';
  static const int maxRecords = 200;

  StoreShiftStore({StoreDatabase? database})
    : _database = database ?? StoreDatabase.instance;

  final StoreDatabase _database;

  Future<List<StoreShift>> load() async {
    try {
      final db = await _database.database;
      final rows = await db.query('shifts', orderBy: 'opened_ms ASC');
      return [
        for (final row in rows)
          StoreShift(
            openedAt: DateTime.fromMillisecondsSinceEpoch(
              (row['opened_ms'] as num).toInt(),
            ),
            closedAt: row['closed_ms'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (row['closed_ms'] as num).toInt(),
                  )
                : null,
            era: row['era'] == 'rp' ? 'rp' : 'nusan',
            operatorId: row['operator_id'] is String
                ? row['operator_id'] as String
                : '',
            operatorName: row['operator_name'] is String
                ? row['operator_name'] as String
                : '',
            openingFloatRp: row['opening_float_rp'] is num
                ? (row['opening_float_rp'] as num).toInt()
                : 0,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<StoreShift> shifts) async {
    try {
      final trimmed = shifts.length > maxRecords
          ? shifts.sublist(shifts.length - maxRecords)
          : shifts;
      final db = await _database.database;
      await db.transaction((txn) async {
        await insertShiftRows(txn, trimmed);
      });
    } catch (_) {
      // Abaikan — keadaan shift di layar tetap yang berlaku sesi ini.
    }
  }
}
