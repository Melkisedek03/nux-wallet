/// Info pasar baca-saja untuk seksi Info Pasar tab Jelajah.
///
/// Harga NUX berasal dari ticker publik CoinPaprika: SATU panggilan
/// kuotasi langsung NUX/IDR
/// (https://api.coinpaprika.com/v1/tickers/nux-nusacoin?quotes=IDR).
/// Respons yang sama membawa perubahan 24 jam bergulir
/// (`quotes.IDR.percent_change_24h`), jadi tampilan perubahan
/// tetap ada tanpa sumber kedua.
///
/// Catatan semantik: angka 24 jam ini adalah perubahan persen
/// bergulir 24 jam dari CoinPaprika — BUKAN selisih antar dua
/// penutupan candle harian seperti desain dua hop lama (candle
/// qutrade NUX/USDT + kurs Indodax USDT/IDR, keputusan tim 8 Nov
/// 2026). Satu hop berarti satu titik gagal lebih sedikit: harga
/// rupiah tidak lagi mati bila salah satu dari dua sumber lama
/// tidak terjangkau.
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

/// Parse harga IDR + perubahan 24 jam dari respons ticker
/// CoinPaprika yang sudah di-decode
/// ({"quotes": {"IDR": {"price": 62.62,
/// "percent_change_24h": 0.99, ...}}}). Null bila bentuknya tidak
/// dikenal atau harganya tidak positif; perubahan 24 jam boleh
/// absen (null) tanpa menggagalkan harga.
({double priceIdr, double? changePct})? parseCoinpaprikaTicker(Object? json) {
  if (json is! Map) return null;
  final quotes = json['quotes'];
  if (quotes is! Map) return null;
  final idr = quotes['IDR'];
  if (idr is! Map) return null;
  final harga = idr['price'];
  final nilai = harga is num ? harga.toDouble() : double.tryParse('$harga');
  if (nilai == null || nilai <= 0) return null;
  final perubahan = idr['percent_change_24h'];
  final persen = perubahan is num
      ? perubahan.toDouble()
      : double.tryParse('$perubahan');
  return (priceIdr: nilai, changePct: persen);
}

/// Parse tinggi blok dari REST electrs (teks polos berisi angka).
int? parseTipHeight(String body) {
  final nilai = int.tryParse(body.trim());
  return (nilai != null && nilai > 0) ? nilai : null;
}

/// Potret info pasar pada satu saat.
class NuxMarketInfo {
  const NuxMarketInfo({
    required this.priceIdr,
    required this.fetchedAt,
    this.changePct,
    this.blockHeight,
  });

  /// Harga NUX dalam rupiah (kuotasi langsung IDR CoinPaprika).
  final double priceIdr;

  /// Perubahan persen 24 jam bergulir dari CoinPaprika; null bila
  /// respons tidak menyertakannya.
  final double? changePct;

  /// Tinggi blok terkini dari electrs tim, bila tersedia.
  final int? blockHeight;

  /// Kapan data ini diambil dari sumbernya.
  final DateTime fetchedAt;
}

/// Pengambil + cache info pasar. Cache 5 menit di SharedPreferences:
/// membuka tab berulang tidak menghantam sumber publik, dan cap
/// waktu cache selalu jujur (layar menampilkannya sebagai waktu
/// pembaruan, bukan menyamarkannya sebagai data segar).
class MarketInfoService {
  static const Duration cacheUmur = Duration(minutes: 5);

  static const String _kHarga = 'jelajah_market_price_idr';
  static const String _kPerubahan = 'jelajah_market_change_pct';
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
      _ambilTicker(),
      _ambilTinggiBlok(),
    ]);
    final ticker = hasil[0] as ({double priceIdr, double? changePct})?;
    if (ticker == null) return null;
    return NuxMarketInfo(
      priceIdr: ticker.priceIdr,
      changePct: ticker.changePct,
      blockHeight: hasil[1] as int?,
      fetchedAt: DateTime.now(),
    );
  }

  Future<({double priceIdr, double? changePct})?> _ambilTicker() async {
    try {
      final respons = await http
          .get(Uri.parse(AppConfig.coinpaprikaTickerUrl))
          .timeout(const Duration(seconds: 12));
      if (respons.statusCode != 200) return null;
      return parseCoinpaprikaTicker(jsonDecode(respons.body));
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
      await prefs.setDouble(_kHarga, info.priceIdr);
      if (info.changePct != null) {
        await prefs.setDouble(_kPerubahan, info.changePct!);
      }
      if (info.blockHeight != null) {
        await prefs.setInt(_kTinggi, info.blockHeight!);
      }
      await prefs.setInt(_kWaktu, info.fetchedAt.millisecondsSinceEpoch);
    } catch (_) {
      // Cache gagal tulis tidak menggagalkan data yang sudah di tangan.
    }
  }

  Future<NuxMarketInfo?> _dariCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final harga = prefs.getDouble(_kHarga);
      final waktuMs = prefs.getInt(_kWaktu);
      if (harga == null || waktuMs == null) return null;
      return NuxMarketInfo(
        priceIdr: harga,
        changePct: prefs.getDouble(_kPerubahan),
        blockHeight: prefs.getInt(_kTinggi),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(waktuMs),
      );
    } catch (_) {
      return null;
    }
  }
}
