/// Info pasar baca-saja untuk seksi Info Pasar tab Jelajah.
///
/// Harga NUX berasal dari API datafeed publik qutrade.io (keputusan
/// tim 8 Nov 2026): candle HARIAN pair NUX/USDT dari endpoint
/// TradingView UDF mereka. Token resolusinya nonstandar — "1D",
/// bukan "D" (dengan "D" server menjawab "exit"). Pasar NUX tipis,
/// jadi candle harian adalah butir yang andal: harga terakhir =
/// penutupan candle terakhir, perubahan 24 jam = perubahan antar
/// dua penutupan harian terakhir.
///
/// qutrade tidak memiliki pair IDR, jadi tampilan rupiah memakai
/// kurs USDT/IDR dari ticker publik Indodax — murni kurs konversi;
/// sumber harga NUX tetap qutrade.
///
/// Statistik jaringan berasal dari electrs publik milik tim
/// (tinggi blok terkini). Semua pengambilan bersifat independen dan
/// tidak pernah melempar ke UI: bila harga tidak tersedia, pemanggil
/// menerima null dan seksi disembunyikan dengan anggun.

library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Parse deret penutupan dari respons UDF /history yang sudah
/// di-decode. Respons "no_data"/"error" atau bentuk tak dikenal
/// menghasilkan daftar kosong.
List<double> parseUdfCloses(Object? json) {
  if (json is! Map) return const [];
  if (json['s'] != 'ok') return const [];
  final t = json['t'];
  final c = json['c'];
  if (t is! List || c is! List) return const [];
  final hasil = <double>[];
  final n = t.length < c.length ? t.length : c.length;
  for (var i = 0; i < n; i++) {
    final nilai = c[i];
    if (nilai is num) hasil.add(nilai.toDouble());
  }
  return hasil;
}

/// Parse kurs USDT/IDR terakhir dari ticker publik Indodax
/// ({"ticker": {"last": "18054", ...}}). Null bila bentuknya
/// tidak dikenal atau nilainya tidak positif.
double? parseUsdtIdrRate(Object? json) {
  if (json is! Map) return null;
  final ticker = json['ticker'];
  if (ticker is! Map) return null;
  final last = ticker['last'];
  final nilai = last is num ? last.toDouble() : double.tryParse('$last');
  if (nilai == null || nilai <= 0) return null;
  return nilai;
}

/// Parse tinggi blok dari REST electrs (teks polos berisi angka).
int? parseTipHeight(String body) {
  final nilai = int.tryParse(body.trim());
  return (nilai != null && nilai > 0) ? nilai : null;
}

/// Potret info pasar pada satu saat.
class NuxMarketInfo {
  const NuxMarketInfo({
    required this.lastUsdt,
    required this.fetchedAt,
    this.prevCloseUsdt,
    this.usdtIdrRate,
    this.blockHeight,
  });

  /// Harga penutupan terakhir NUX/USDT di qutrade.
  final double lastUsdt;

  /// Penutupan harian sebelumnya — dasar perubahan 24 jam.
  final double? prevCloseUsdt;

  /// Kurs USDT/IDR (Indodax) saat pengambilan, bila tersedia.
  final double? usdtIdrRate;

  /// Tinggi blok terkini dari electrs tim, bila tersedia.
  final int? blockHeight;

  /// Kapan data ini diambil dari sumbernya.
  final DateTime fetchedAt;

  /// Perubahan persen antar dua penutupan harian terakhir;
  /// null bila penutupan sebelumnya tidak ada.
  double? get changePct {
    final prev = prevCloseUsdt;
    if (prev == null || prev <= 0) return null;
    return (lastUsdt - prev) / prev * 100;
  }

  /// Harga dalam rupiah (harga USDT × kurs), bila kurs tersedia.
  double? get priceIdr {
    final kurs = usdtIdrRate;
    if (kurs == null) return null;
    return lastUsdt * kurs;
  }
}

/// Pengambil + cache info pasar. Cache 5 menit di SharedPreferences:
/// membuka tab berulang tidak menghantam sumber publik, dan cap
/// waktu cache selalu jujur (layar menampilkannya sebagai waktu
/// pembaruan, bukan menyamarkannya sebagai data segar).
class MarketInfoService {
  static const Duration cacheUmur = Duration(minutes: 5);

  static const String _kLast = 'jelajah_market_last_usdt';
  static const String _kPrev = 'jelajah_market_prev_usdt';
  static const String _kKurs = 'jelajah_market_usdt_idr';
  static const String _kTinggi = 'jelajah_market_block_height';
  static const String _kWaktu = 'jelajah_market_fetched_at_ms';

  /// Muat info pasar: cache segar dipakai langsung; selain itu ambil
  /// dari jaringan. Null bila harga tidak tersedia dari jaringan
  /// maupun cache (seksi Info Pasar disembunyikan).
  Future<NuxMarketInfo?> muat({bool paksaSegar = false}) async {
    if (!paksaSegar) {
      final cache = await _dariCache();
      if (cache != null &&
          DateTime.now().difference(cache.fetchedAt) < cacheUmur) {
        return cache;
      }
    }
    final segar = await _ambilDariJaringan();
    if (segar != null) {
      await _simpanCache(segar);
      return segar;
    }
    return _dariCache();
  }

  Future<NuxMarketInfo?> _ambilDariJaringan() async {
    final hasil = await Future.wait<Object?>([
      _ambilCandle(),
      _ambilKurs(),
      _ambilTinggiBlok(),
    ]);
    final closes = hasil[0] as List<double>?;
    if (closes == null || closes.isEmpty) return null;
    return NuxMarketInfo(
      lastUsdt: closes.last,
      prevCloseUsdt: closes.length >= 2 ? closes[closes.length - 2] : null,
      usdtIdrRate: hasil[1] as double?,
      blockHeight: hasil[2] as int?,
      fetchedAt: DateTime.now(),
    );
  }

  Future<List<double>?> _ambilCandle() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final from = now - const Duration(days: 10).inSeconds;
      final uri = Uri.parse('${AppConfig.qutradeDatafeedBase}/history')
          .replace(queryParameters: {
        'symbol': 'NUX_USDT',
        'resolution': '1D',
        'from': '$from',
        'to': '$now',
        'countback': '3',
      });
      final respons =
          await http.get(uri).timeout(const Duration(seconds: 12));
      if (respons.statusCode != 200) return null;
      return parseUdfCloses(jsonDecode(respons.body));
    } catch (_) {
      return null;
    }
  }

  Future<double?> _ambilKurs() async {
    try {
      final respons = await http
          .get(Uri.parse(AppConfig.usdtIdrTickerUrl))
          .timeout(const Duration(seconds: 12));
      if (respons.statusCode != 200) return null;
      return parseUsdtIdrRate(jsonDecode(respons.body));
    } catch (_) {
      return null;
    }
  }

  Future<int?> _ambilTinggiBlok() async {
    try {
      final respons = await http
          .get(Uri.parse('${AppConfig.electrsRestBase}/blocks/tip/height'))
          .timeout(const Duration(seconds: 12));
      if (respons.statusCode != 200) return null;
      return parseTipHeight(respons.body);
    } catch (_) {
      return null;
    }
  }

  Future<void> _simpanCache(NuxMarketInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kLast, info.lastUsdt);
      if (info.prevCloseUsdt != null) {
        await prefs.setDouble(_kPrev, info.prevCloseUsdt!);
      }
      if (info.usdtIdrRate != null) {
        await prefs.setDouble(_kKurs, info.usdtIdrRate!);
      }
      if (info.blockHeight != null) {
        await prefs.setInt(_kTinggi, info.blockHeight!);
      }
      await prefs.setInt(
          _kWaktu, info.fetchedAt.millisecondsSinceEpoch);
    } catch (_) {
      // Cache gagal tulis tidak menggagalkan data yang sudah di tangan.
    }
  }

  Future<NuxMarketInfo?> _dariCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getDouble(_kLast);
      final waktuMs = prefs.getInt(_kWaktu);
      if (last == null || waktuMs == null) return null;
      return NuxMarketInfo(
        lastUsdt: last,
        prevCloseUsdt: prefs.getDouble(_kPrev),
        usdtIdrRate: prefs.getDouble(_kKurs),
        blockHeight: prefs.getInt(_kTinggi),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(waktuMs),
      );
    } catch (_) {
      return null;
    }
  }
}
