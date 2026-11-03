import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Satu shift kasir Mode Toko: dibuka kasir dengan tombol Buka
/// Shift, ditutup dengan Tutup Shift. Semua record pesanan toko
/// (lunas maupun VOID) dicatat di dalam jendela shift yang sedang
/// terbuka — layar Mode Toko menghalangi pembuatan kode bayar di
/// luar shift dan menghalangi penutupan selama masih ada invoice
/// menunggu, jadi secara konstruksi tidak ada record pesanan
/// "di luar shift".
class StoreShift {
  final DateTime openedAt;
  final DateTime? closedAt;

  const StoreShift({required this.openedAt, this.closedAt});

  bool get isOpen => closedAt == null;

  /// Salinan shift ini dalam keadaan tertutup pada [at].
  StoreShift close(DateTime at) => StoreShift(openedAt: openedAt, closedAt: at);

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
    return StoreShift(openedAt: openedAt, closedAt: closedAt);
  }

  @override
  bool operator ==(Object other) =>
      other is StoreShift &&
      other.openedAt.millisecondsSinceEpoch ==
          openedAt.millisecondsSinceEpoch &&
      other.closedAt?.millisecondsSinceEpoch ==
          closedAt?.millisecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
    openedAt.millisecondsSinceEpoch,
    closedAt?.millisecondsSinceEpoch,
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

/// Penyimpanan shift Mode Toko di SharedPreferences.
class StoreShiftStore {
  static const String storageKey = 'store_shifts_v1';
  static const int maxRecords = 200;

  Future<List<StoreShift>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeShifts(prefs.getString(storageKey));
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<StoreShift> shifts) async {
    try {
      final trimmed = shifts.length > maxRecords
          ? shifts.sublist(shifts.length - maxRecords)
          : shifts;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encodeShifts(trimmed));
    } catch (_) {
      // Abaikan — keadaan shift di layar tetap yang berlaku sesi ini.
    }
  }
}
