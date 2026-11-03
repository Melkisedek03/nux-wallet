import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan Toko Mode Toko v2: identitas toko untuk struk dan
/// parameter program poin nusan milik toko ini.
///
/// Mengikuti pedoman miniPOS tim: nilai potongan per poin adalah
/// KEBIJAKAN DISKON toko sendiri (bukan kurs), perolehan poin
/// hanya lahir dari transaksi rupiah yang lunas, dan program
/// poin dapat dimatikan tanpa mematikan fungsi kasir rupiah.
///
/// Bawaan (keputusan NUX 3 Nov 2026): kelipatan Rp1.000 memberi
/// 1.000 poin; nilai potongan 1 poin = Rp1; tanpa batas maksimum
/// diskon poin per transaksi; program poin aktif.
class StoreSettings {
  /// Nama toko untuk kop struk; '' = tanpa nama (kop struk
  /// memakai bingkai bawaan printer).
  final String storeName;

  /// Program poin aktif? Bila mati, Mode Toko adalah kasir
  /// rupiah murni: tidak ada tukar poin, tidak ada terbit poin.
  final bool pointsEnabled;

  /// Kelipatan rupiah untuk perolehan poin: tiap [earnStepRp]
  /// rupiah yang dibayar memberi [earnPointsPerStep] poin.
  final int earnStepRp;
  final int earnPointsPerStep;

  /// Nilai potongan per poin (rupiah) saat poin ditukar —
  /// parameter diskon toko, ditampilkan persis dengan label itu.
  final int redeemRateRp;

  /// Batas maksimum diskon poin per transaksi, persen dari total
  /// (sesudah diskon biasa, sebelum diskon poin); null = tanpa
  /// batas selain sisa tagihan itu sendiri.
  final int? maxRedeemPercent;

  /// Baris kedua kop struk (alamat toko), tampil di tengah tepat
  /// di bawah nama toko; '' = tanpa baris alamat.
  final String storeAddress;

  /// Tampilkan nomor token (antrean harian) pada struk? Bawaan
  /// tampil — mengikuti contoh struk yang dipakai kasir.
  final bool showTokenNumber;

  /// Teks penutup struk toko (footer ucapan); '' = teks bawaan
  /// bahasa aplikasi ("Terima kasih & silakan berkunjung
  /// kembali" / "Thank You & Visit Again").
  final String receiptFooterText;

  const StoreSettings({
    this.storeName = '',
    this.pointsEnabled = true,
    this.earnStepRp = 1000,
    this.earnPointsPerStep = 1000,
    this.redeemRateRp = 1,
    this.maxRedeemPercent,
    this.storeAddress = '',
    this.showTokenNumber = true,
    this.receiptFooterText = '',
  });

  static const defaults = StoreSettings();

  StoreSettings copyWith({
    String? storeName,
    bool? pointsEnabled,
    int? earnStepRp,
    int? earnPointsPerStep,
    int? redeemRateRp,
    int? maxRedeemPercent,
    bool clearMaxRedeemPercent = false,
    String? storeAddress,
    bool? showTokenNumber,
    String? receiptFooterText,
  }) => StoreSettings(
    storeName: storeName ?? this.storeName,
    pointsEnabled: pointsEnabled ?? this.pointsEnabled,
    earnStepRp: earnStepRp ?? this.earnStepRp,
    earnPointsPerStep: earnPointsPerStep ?? this.earnPointsPerStep,
    redeemRateRp: redeemRateRp ?? this.redeemRateRp,
    maxRedeemPercent: clearMaxRedeemPercent
        ? null
        : (maxRedeemPercent ?? this.maxRedeemPercent),
    storeAddress: storeAddress ?? this.storeAddress,
    showTokenNumber: showTokenNumber ?? this.showTokenNumber,
    receiptFooterText: receiptFooterText ?? this.receiptFooterText,
  );

  Map<String, Object?> toJson() => {
    'storeName': storeName,
    'pointsEnabled': pointsEnabled,
    'earnStepRp': earnStepRp,
    'earnPointsPerStep': earnPointsPerStep,
    'redeemRateRp': redeemRateRp,
    'maxRedeemPercent': maxRedeemPercent,
    'storeAddress': storeAddress,
    'showTokenNumber': showTokenNumber,
    'receiptFooterText': receiptFooterText,
  };

  /// Baca pengaturan dari JSON; field yang hilang/tak sah jatuh
  /// ke bawaannya SATU-SATU (satu field rusak tidak membuang
  /// seluruh pengaturan toko). Angka penyebut divalidasi:
  /// kelipatan & nilai potong harus > 0, poin per kelipatan
  /// >= 0 (0 = perolehan dimatikan tanpa mematikan penukaran),
  /// batas persen hanya sah pada 1–100.
  static StoreSettings fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    final name = raw['storeName'];
    final enabled = raw['pointsEnabled'];
    final step = raw['earnStepRp'];
    final perStep = raw['earnPointsPerStep'];
    final rate = raw['redeemRateRp'];
    final maxPct = raw['maxRedeemPercent'];
    final address = raw['storeAddress'];
    final showToken = raw['showTokenNumber'];
    final footer = raw['receiptFooterText'];
    return StoreSettings(
      storeName: name is String ? name.trim() : '',
      pointsEnabled: enabled is bool ? enabled : true,
      earnStepRp: step is num && step > 0 ? step.toInt() : 1000,
      earnPointsPerStep: perStep is num && perStep >= 0
          ? perStep.toInt()
          : 1000,
      redeemRateRp: rate is num && rate > 0 ? rate.toInt() : 1,
      maxRedeemPercent: maxPct is num && maxPct >= 1 && maxPct <= 100
          ? maxPct.toInt()
          : null,
      // Field struk baru: simpanan lama tanpa field ini jatuh ke
      // bawaannya (alamat kosong, token tampil, footer bawaan).
      storeAddress: address is String ? address.trim() : '',
      showTokenNumber: showToken is bool ? showToken : true,
      receiptFooterText: footer is String ? footer.trim() : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StoreSettings &&
      other.storeName == storeName &&
      other.pointsEnabled == pointsEnabled &&
      other.earnStepRp == earnStepRp &&
      other.earnPointsPerStep == earnPointsPerStep &&
      other.redeemRateRp == redeemRateRp &&
      other.maxRedeemPercent == maxRedeemPercent &&
      other.storeAddress == storeAddress &&
      other.showTokenNumber == showTokenNumber &&
      other.receiptFooterText == receiptFooterText;

  @override
  int get hashCode => Object.hash(
    storeName,
    pointsEnabled,
    earnStepRp,
    earnPointsPerStep,
    redeemRateRp,
    maxRedeemPercent,
    storeAddress,
    showTokenNumber,
    receiptFooterText,
  );
}

String encodeStoreSettings(StoreSettings settings) =>
    jsonEncode(settings.toJson());

/// Baca pengaturan dari string simpanan; fail-open seperti store
/// lokal lain: rusak/bukan peta → pengaturan bawaan.
StoreSettings decodeStoreSettings(String? raw) {
  if (raw == null || raw.trim().isEmpty) return StoreSettings.defaults;
  Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return StoreSettings.defaults;
  }
  return StoreSettings.fromJson(parsed);
}

/// Penyimpanan pengaturan toko di SharedPreferences.
class StoreSettingsStore {
  static const String storageKey = 'store_settings_v1';

  Future<StoreSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeStoreSettings(prefs.getString(storageKey));
    } catch (_) {
      return StoreSettings.defaults;
    }
  }

  Future<void> save(StoreSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encodeStoreSettings(settings));
    } catch (_) {
      // Abaikan — pengaturan sesi ini tetap berlaku di layar.
    }
  }
}
