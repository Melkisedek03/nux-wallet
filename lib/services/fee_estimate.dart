/// Perkiraan biaya on-chain untuk pembukaan jalur (PR C) — diambil
/// dari REST electrs publik milik tim (host yang sama dengan tinggi
/// blok tab Jelajah, `market_info.dart`).
///
/// Fakta dasarnya: tidak ada API perkiraan biaya untuk pembukaan
/// channel. `openChannel` di binding tidak menerima feerate —
/// estimator internal LDK yang menentukan; `PaymentDetails` tidak
/// membawa field biaya. Jadi biaya PASTI tidak bisa diketahui
/// sebelum node merakit transaksi pendanaan. Rancangan PR C
/// menjawabnya dua tahap:
///
/// - Sebelum konfirmasi: PERKIRAAN berlabel dari endpoint
///   `/fee-estimates` Esplora (tarif sat/vB per target konfirmasi)
///   × 250 vB (asumsi konservatif ukuran transaksi pendanaan;
///   pendanaan 1-input tipikal ±150 vB), dibulatkan ke atas.
/// - Sesudah siaran: angka PASTI dari field `fee` endpoint
///   `/tx/{txid}`, begitu konfirmasi pertama tercatat.
///
/// Semua pengambilan gagal-terbuka (null): pemanggil menampilkan
/// "dihitung saat pengiriman" dan memakai cadangan tetap untuk
/// pemeriksaan saldo. Parse-nya murni dan diuji unit.

library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Asumsi ukuran transaksi pendanaan dalam vB — pendanaan 1-input
/// tipikal ±150 vB; 250 vB memberi ruang untuk masukan kedua.
const int assumedFundingTxVsizeVb = 250;

/// Cadangan biaya tetap (nusan) bila perkiraan gagal diambil:
/// ±10× biaya pendanaan lapangan yang teramati (531 dan 724 nusan).
final BigInt feeEstimateFallbackReserveSats = BigInt.from(5000);

/// Batas waktu pengambilan perkiraan biaya — dialog konfirmasi
/// tidak boleh menggantung lama menunggu jaringan.
const Duration feeEstimateTimeout = Duration(seconds: 5);

/// Parse respons `/fee-estimates` Esplora yang sudah di-decode
/// (`{"1": 1.0, "2": 1.0, ...}` — kunci target blok sebagai
/// string, nilai tarif sat/vB). Mengembalikan peta target → tarif,
/// atau null bila responsnya bukan peta atau tidak ada satu pun
/// entri yang sah.
Map<int, double>? parseFeeEstimates(Object? json) {
  if (json is! Map) return null;
  final hasil = <int, double>{};
  for (final entry in json.entries) {
    final target = int.tryParse('${entry.key}');
    final nilai = entry.value;
    final rate = nilai is num ? nilai.toDouble() : null;
    if (target == null || rate == null || rate <= 0 || !rate.isFinite) {
      continue;
    }
    hasil[target] = rate;
  }
  return hasil.isEmpty ? null : hasil;
}

/// Pilih tarif untuk [target] konfirmasi dari [rates]: target
/// persis bila ada; bila tidak, target TERDEKAT (selisih absolut
/// terkecil). Bila dua target sama dekatnya, yang LEBIH KECIL
/// yang dipilih — target lebih kecil berarti tarif lebih tinggi,
/// jadi perkiraannya konservatif (lebih aman untuk pemeriksaan
/// saldo). Null bila peta kosong.
double? pickFeeRate(Map<int, double> rates, {int target = 6}) {
  if (rates.isEmpty) return null;
  final exact = rates[target];
  if (exact != null) return exact;
  var bestTarget = rates.keys.first;
  for (final t in rates.keys) {
    final jarak = (t - target).abs();
    final jarakTerbaik = (bestTarget - target).abs();
    if (jarak < jarakTerbaik ||
        (jarak == jarakTerbaik && t < bestTarget)) {
      bestTarget = t;
    }
  }
  return rates[bestTarget];
}

/// Perkiraan biaya pendanaan (nusan utuh) dari [rateSatPerVb]:
/// tarif × [assumedFundingTxVsizeVb], dibulatkan KE ATAS.
/// Null bila tarifnya tidak positif atau tidak berhingga.
BigInt? estimateFundingFeeSats(
  double rateSatPerVb, {
  int assumedVsizeVb = assumedFundingTxVsizeVb,
}) {
  if (rateSatPerVb <= 0 || !rateSatPerVb.isFinite) return null;
  return BigInt.from((rateSatPerVb * assumedVsizeVb).ceil());
}

/// Parse biaya transaksi (nusan utuh) dari respons `/tx/{txid}`
/// electrs yang sudah di-decode — field `fee`-nya. Null bila
/// field-nya tidak ada atau bukan angka.
BigInt? parseTxFee(Object? json) {
  if (json is! Map) return null;
  final fee = json['fee'];
  if (fee is! num || fee < 0) return null;
  return BigInt.from(fee.toInt());
}

/// Pengambil perkiraan + biaya pasti. Klien HTTP bisa disuntik
/// (tes) — bawaan memakai klien baru.
class FeeEstimateService {
  FeeEstimateService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Perkiraan biaya pendanaan (nusan utuh) dari tarif live
  /// `/fee-estimates` target 6 konfirmasi. Null bila pengambilan
  /// atau parse-nya gagal — pemanggil memakai cadangan tetap.
  Future<BigInt?> estimateFundingFee() async {
    try {
      final respons = await _client
          .get(Uri.parse('${AppConfig.electrsRestBase}/fee-estimates'))
          .timeout(feeEstimateTimeout);
      if (respons.statusCode != 200) return null;
      final rates = parseFeeEstimates(jsonDecode(respons.body));
      if (rates == null) return null;
      final rate = pickFeeRate(rates);
      if (rate == null) return null;
      return estimateFundingFeeSats(rate);
    } catch (_) {
      return null;
    }
  }

  /// Biaya pasti (nusan utuh) transaksi [txid] dari field `fee`
  /// endpoint `/tx/{txid}`. Null bila pengambilan atau parse-nya
  /// gagal — pemanggil menyembunyikan baris biayanya.
  Future<BigInt?> fetchFundingFee(String txid) async {
    try {
      final respons = await _client
          .get(Uri.parse('${AppConfig.electrsRestBase}/tx/$txid'))
          .timeout(feeEstimateTimeout);
      if (respons.statusCode != 200) return null;
      return parseTxFee(jsonDecode(respons.body));
    } catch (_) {
      return null;
    }
  }
}
