import 'dart:convert';

import 'store_database.dart';

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

  /// Baris ketiga kop struk (kota toko), tampil di tengah tepat
  /// di bawah alamat; '' = tanpa baris kota. Kop struk utuh
  /// disiapkan tiga baris: nama + alamat + kota (permintaan
  /// NUX 4 Nov 2026).
  final String storeCity;

  /// Tampilkan nomor token (antrean harian) pada struk? Bawaan
  /// tampil — mengikuti contoh struk yang dipakai kasir.
  final bool showTokenNumber;

  /// Teks penutup struk toko (footer ucapan); '' = teks bawaan
  /// bahasa aplikasi, dua baris ("Terima Kasih" / "Silakan
  /// berkunjung kembali"; EN "Thank You" / "Please Visit
  /// Again") — baris baru eksplisit supaya printer 58mm tidak
  /// membungkus ulang dan memotong kata di tengah.
  final String receiptFooterText;

  /// Ambang diskon manual (persen dari basisnya) yang masih
  /// boleh diterapkan kasir sendiri; di atas ini dialog PIN
  /// admin wajib tampil sebelum diskon diterapkan (Fase A,
  /// keputusan NUX 4 Nov 2026). Bawaan 50%.
  final int adminDiscountThresholdPercent;

  /// Master metode bayar NON-TUNAI toko (permintaan NUX
  /// 5 Nov 2026): nama-nama yang ditawarkan dropdown halaman
  /// pembayaran sesudah Tunai. Bawaan QRIS/DANA/OVO; owner
  /// bebas menambah/menghapus dari Pengaturan Toko. Tunai
  /// tidak termasuk daftar ini — ia selalu tersedia.
  final List<String> paymentMethods;

  /// Token bot Telegram (dari BotFather) + id chat tujuan
  /// untuk fitur Kirim Laporan via Telegram: laporan shift
  /// terkirim otomatis saat shift ditutup, langsung dari
  /// aplikasi lewat Bot API (tanpa server perantara).
  /// Keduanya kosong = fitur mati. Hanya admin yang bisa
  /// mengubahnya (layar Pengaturan memang bergerbang PIN).
  final String telegramBotToken;
  final String telegramChatId;

  const StoreSettings({
    this.storeName = '',
    this.pointsEnabled = true,
    this.earnStepRp = 1000,
    this.earnPointsPerStep = 1000,
    this.redeemRateRp = 1,
    this.maxRedeemPercent,
    this.storeAddress = '',
    this.storeCity = '',
    this.showTokenNumber = true,
    this.receiptFooterText = '',
    this.adminDiscountThresholdPercent = 50,
    this.paymentMethods = defaultPaymentMethods,
    this.telegramBotToken = '',
    this.telegramChatId = '',
  });

  /// Metode bayar non-tunai bawaan toko baru.
  static const List<String> defaultPaymentMethods = ['QRIS', 'DANA', 'OVO'];

  /// Fitur Telegram siap pakai bila kedua isian terisi.
  bool get telegramConfigured =>
      telegramBotToken.trim().isNotEmpty && telegramChatId.trim().isNotEmpty;

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
    String? storeCity,
    bool? showTokenNumber,
    String? receiptFooterText,
    int? adminDiscountThresholdPercent,
    List<String>? paymentMethods,
    String? telegramBotToken,
    String? telegramChatId,
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
    storeCity: storeCity ?? this.storeCity,
    showTokenNumber: showTokenNumber ?? this.showTokenNumber,
    receiptFooterText: receiptFooterText ?? this.receiptFooterText,
    adminDiscountThresholdPercent:
        adminDiscountThresholdPercent ?? this.adminDiscountThresholdPercent,
    paymentMethods: paymentMethods ?? this.paymentMethods,
    telegramBotToken: telegramBotToken ?? this.telegramBotToken,
    telegramChatId: telegramChatId ?? this.telegramChatId,
  );

  Map<String, Object?> toJson() => {
    'storeName': storeName,
    'pointsEnabled': pointsEnabled,
    'earnStepRp': earnStepRp,
    'earnPointsPerStep': earnPointsPerStep,
    'redeemRateRp': redeemRateRp,
    'maxRedeemPercent': maxRedeemPercent,
    'storeAddress': storeAddress,
    'storeCity': storeCity,
    'showTokenNumber': showTokenNumber,
    'receiptFooterText': receiptFooterText,
    'adminDiscountThresholdPercent': adminDiscountThresholdPercent,
    'paymentMethods': paymentMethods,
    if (telegramBotToken.isNotEmpty) 'telegramBotToken': telegramBotToken,
    if (telegramChatId.isNotEmpty) 'telegramChatId': telegramChatId,
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
    final city = raw['storeCity'];
    final showToken = raw['showTokenNumber'];
    final footer = raw['receiptFooterText'];
    final adminPct = raw['adminDiscountThresholdPercent'];
    final methods = raw['paymentMethods'];
    final tgToken = raw['telegramBotToken'];
    final tgChat = raw['telegramChatId'];
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
      storeCity: city is String ? city.trim() : '',
      showTokenNumber: showToken is bool ? showToken : true,
      receiptFooterText: footer is String ? footer.trim() : '',
      // Ambang diskon admin Fase A: sah pada 0–100 (0 = semua
      // diskon manual wajib PIN admin; 100 = praktis bebas).
      adminDiscountThresholdPercent:
          adminPct is num && adminPct >= 0 && adminPct <= 100
              ? adminPct.toInt()
              : 50,
      // Master metode bayar: daftar nama tak kosong, duplikat
      // (peka huruf besar/kecil) dibuang; bukan daftar → bawaan.
      paymentMethods: methods is List
          ? normalizePaymentMethods([
              for (final m in methods)
                if (m is String) m,
            ])
          : defaultPaymentMethods,
      telegramBotToken: tgToken is String ? tgToken.trim() : '',
      telegramChatId: tgChat is String ? tgChat.trim() : '',
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
      other.storeCity == storeCity &&
      other.showTokenNumber == showTokenNumber &&
      other.receiptFooterText == receiptFooterText &&
      other.adminDiscountThresholdPercent ==
          adminDiscountThresholdPercent &&
      other.telegramBotToken == telegramBotToken &&
      other.telegramChatId == telegramChatId &&
      _stringListEquals(other.paymentMethods, paymentMethods);

  @override
  int get hashCode => Object.hash(
    storeName,
    pointsEnabled,
    earnStepRp,
    earnPointsPerStep,
    redeemRateRp,
    maxRedeemPercent,
    storeAddress,
    storeCity,
    showTokenNumber,
    receiptFooterText,
    adminDiscountThresholdPercent,
    telegramBotToken,
    telegramChatId,
    Object.hashAll(paymentMethods),
  );
}

/// Normalisasi master metode bayar: trim, buang kosong &
/// duplikat (tak peka huruf besar/kecil), maksimal 20 nama.
/// Daftar kosong SAH (toko hanya menerima tunai + tidak ada
/// dropdown non-tunai) — keputusan owner, bukan kerusakan.
List<String> normalizePaymentMethods(List<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final name in raw) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) continue;
    if (!seen.add(trimmed.toLowerCase())) continue;
    out.add(trimmed);
    if (out.length >= 20) break;
  }
  return out;
}

bool _stringListEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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

/// Penyimpanan pengaturan toko di SQLite (store_pos.db, tabel
/// store_kv — pengaturan adalah snapshot JSON murni, jadi
/// bentuk simpanannya tidak berubah dari era
/// SharedPreferences; hanya mesinnya yang pindah).
class StoreSettingsStore {
  static const String storageKey = 'store_settings_v1';

  StoreSettingsStore({StoreDatabase? database})
    : _database = database ?? StoreDatabase.instance;

  final StoreDatabase _database;

  Future<StoreSettings> load() async {
    try {
      final db = await _database.database;
      return decodeStoreSettings(await storeKvGet(db, storageKey));
    } catch (_) {
      return StoreSettings.defaults;
    }
  }

  Future<void> save(StoreSettings settings) async {
    try {
      final db = await _database.database;
      await storeKvSet(db, storageKey, encodeStoreSettings(settings));
    } catch (_) {
      // Abaikan — pengaturan sesi ini tetap berlaku di layar.
    }
  }
}
