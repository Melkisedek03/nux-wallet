import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Penghitung nomor TOKEN antrean harian Mode Toko ("Token No"
/// pada struk): nomor urut yang mulai dari 1 setiap tanggal
/// kalender lokal baru dan naik SEKALI per transaksi lunas.
///
/// Berbeda dengan Bill No (urut di dalam shift, diturunkan dari
/// record), Token No adalah penghitung persisten kecil miliknya
/// sendiri — tamu membacanya sebagai nomor antrean hari itu,
/// apa pun shift-nya. Keadaannya hanya {tanggal, counter}.
class StoreTokenCounterState {
  /// Kunci tanggal lokal 'yyyy-MM-dd' milik [counter].
  final String dateKey;

  /// Nomor token terakhir yang sudah diterbitkan pada [dateKey].
  final int counter;

  const StoreTokenCounterState({this.dateKey = '', this.counter = 0});

  static const empty = StoreTokenCounterState();

  Map<String, Object?> toJson() => {'dateKey': dateKey, 'counter': counter};

  /// Baca keadaan dari JSON; bentuk tak sah → keadaan kosong
  /// (penghitung mulai lagi dari 1 — nomor antrean bukan fakta
  /// keuangan, jadi fail-open di sini aman).
  static StoreTokenCounterState fromJson(Object? raw) {
    if (raw is! Map) return empty;
    final key = raw['dateKey'];
    final counter = raw['counter'];
    if (key is! String || counter is! num || counter < 0) return empty;
    return StoreTokenCounterState(dateKey: key, counter: counter.toInt());
  }

  @override
  bool operator ==(Object other) =>
      other is StoreTokenCounterState &&
      other.dateKey == dateKey &&
      other.counter == counter;

  @override
  int get hashCode => Object.hash(dateKey, counter);
}

/// Kunci tanggal lokal untuk penghitung token: 'yyyy-MM-dd'.
String tokenDateKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// Hasil memajukan penghitung token untuk satu transaksi lunas.
class TokenAdvance {
  /// Keadaan baru yang harus disimpan.
  final StoreTokenCounterState state;

  /// Nomor token yang diterbitkan untuk transaksi ini.
  final int issued;

  const TokenAdvance({required this.state, required this.issued});
}

/// Majukan penghitung untuk [now] — fungsi MURNI: tanggal
/// berubah (atau keadaan kosong) → nomor mulai lagi dari 1;
/// tanggal sama → counter + 1.
TokenAdvance advanceTokenCounter({
  required StoreTokenCounterState state,
  required DateTime now,
}) {
  final today = tokenDateKey(now);
  final next = state.dateKey == today ? state.counter + 1 : 1;
  return TokenAdvance(
    state: StoreTokenCounterState(dateKey: today, counter: next),
    issued: next,
  );
}

String encodeTokenCounter(StoreTokenCounterState state) =>
    jsonEncode(state.toJson());

StoreTokenCounterState decodeTokenCounter(String? raw) {
  if (raw == null || raw.trim().isEmpty) return StoreTokenCounterState.empty;
  Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return StoreTokenCounterState.empty;
  }
  return StoreTokenCounterState.fromJson(parsed);
}

/// Penyimpanan penghitung token di SharedPreferences.
class StoreTokenCounterStore {
  static const String storageKey = 'store_token_counter_v1';

  Future<StoreTokenCounterState> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeTokenCounter(prefs.getString(storageKey));
    } catch (_) {
      return StoreTokenCounterState.empty;
    }
  }

  Future<void> save(StoreTokenCounterState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encodeTokenCounter(state));
    } catch (_) {
      // Abaikan — nomor sesi ini tetap diterbitkan ke kasir.
    }
  }

  /// Ambil nomor token berikutnya untuk [now] dan simpan
  /// keadaan barunya. Dipanggil tepat sekali per transaksi
  /// lunas yang struknya menampilkan nomor token.
  Future<int> next(DateTime now) async {
    final advance = advanceTokenCounter(state: await load(), now: now);
    await save(advance.state);
    return advance.issued;
  }
}
