import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'lsp_service.dart';

/// Validasi bentuk string offer Bolt12.
///
/// Offer Bolt12 adalah string bech32m berawalan `lno1` (seragam di
/// semua rantai; identitas Nusacoin dibawa field chain hash di
/// dalamnya, bukan awalannya). Dari spike 2 Nov 2026 panjangnya
/// ±1.150 karakter. Batas bawah di sini sengaja longgar — tujuannya
/// hanya menolak string rusak/terpotong/salah tempel, bukan
/// menegakkan panjang persis yang bisa berubah antar versi node.
bool isValidStaticOffer(String? value) {
  if (value == null) return false;
  final v = value.trim();
  return v.startsWith('lno1') && v.length >= 200 && !v.contains(RegExp(r'\s'));
}

/// Langkah berikutnya untuk memastikan offer statis tersedia.
enum StaticOfferStep {
  /// Offer tersimpan masih sah — pakai itu, jangan buat baru.
  /// Offer adalah identitas bayar yang dibagikan ke pembayar;
  /// membuatnya ulang tanpa sebab mengganti kode yang sudah
  /// beredar.
  useStored,

  /// Belum ada peer tersambung: pembuatan offer pasti gagal
  /// (blinded path butuh peer), jadi tunda — coba lagi nanti
  /// sesudah node tersambung ke LSP.
  waitForPeer,

  /// Buat offer baru lewat node lalu simpan.
  createNew,
}

/// Pilih langkah offer statis dari keadaan simpanan + koneksi.
StaticOfferStep decideStaticOfferStep({
  required bool hasStoredOffer,
  required int connectedPeers,
}) {
  if (hasStoredOffer) return StaticOfferStep.useStored;
  if (connectedPeers <= 0) return StaticOfferStep.waitForPeer;
  return StaticOfferStep.createNew;
}

/// Penyimpanan offer statis di SharedPreferences.
///
/// Pola sama seperti SavedInvoiceStore/LspProfileStore: semua
/// kegagalan baca dianggap "tidak ada simpanan" (fail-open) dan
/// kegagalan tulis ditelan — offer bisa dibuat ulang kapan pun,
/// jadi simpanan ini murni penstabil kode bayar antar sesi, bukan
/// sumber kebenaran dana.
///
/// Deskripsi adalah BAGIAN dari offer (tertulis di dalamnya),
/// jadi simpanan mencatat deskripsi yang dipakai saat offer
/// dibuat: offer hanya dipakai ulang bila deskripsinya masih
/// sama dengan yang diminta pemanggil. User boleh memasang
/// label kustom ([customDescriptionKey]); menggantinya membuat
/// offer lama gugur dan offer baru dibuat dengan label baru
/// (permintaan NUX 4 Nov 2026: QR Bolt12 bisa di-custom, tidak
/// diset = bawaan).
///
/// Offer terikat JARINGAN (R2 audit kesiapan mainnet): offer
/// mengandung identitas node + chain hash jaringannya, jadi
/// offer testnet tidak boleh tersaji sebagai kode bayar statis
/// mainnet bila APK mainnet dipasang di atas instalasi testnet
/// (paket sama, SharedPreferences sama, seed/node baru).
/// Kunci simpanan dibedakan per jaringan: testnet memakai kunci
/// polos, mainnet memakai akhiran `_mainnet` — konvensi yang
/// sama dengan berkas seed (`lsp_seed.bin` vs
/// `lsp_seed_mainnet.bin`). Simpanan testnet yang sudah ada
/// tetap berlaku tanpa migrasi (belum ada build mainnet yang
/// pernah dibagikan ke user, jadi kunci polos hanya pernah
/// ditulis build testnet), sementara build mainnet membaca slot
/// kosong dan membuat offer baru untuk nodenya. Label kustom
/// mengikuti ikatan yang sama: label testnet tidak terbawa ke
/// offer mainnet.
///
/// Sengaja BUKAN ikatan node ID (pola OnchainAddressStore):
/// jalur simpanan [Bolt12OfferService.ensureOffer] dirancang
/// tidak menyentuh node sama sekali — offer tersimpan tetap
/// tampil saat node sedang mati — sementara `ownNodeId()`
/// melempar bila node belum berjalan, jadi memverifikasi node ID
/// akan merusak jaminan itu. Jaringan adalah konstanta
/// waktu-build, sehingga pemeriksaan ini total tanpa menyentuh
/// node. Yang tidak dicakup: pemulihan dompet dari frasa lain
/// DI jaringan yang sama (node ID berganti, jaringan tetap)
/// masih menyajikan offer lama — pembayaran ke sana gagal aman
/// (tidak ada dana berpindah) dan user bisa membuat ulang lewat
/// editor label.
class Bolt12OfferStore {
  /// Kunci dasar (testnet). Kunci mainnet = kunci dasar +
  /// [mainnetKeySuffix]; lihat [_key].
  static const String storageKey = 'bolt12_static_offer';

  /// Deskripsi yang dipakai saat offer tersimpan dibuat.
  static const String offerDescriptionKey = 'bolt12_offer_for_description';

  /// Label kustom pilihan user; absen/kosong = label bawaan.
  static const String customDescriptionKey = 'bolt12_offer_custom_label';

  /// Akhiran kunci simpanan untuk jaringan mainnet.
  static const String mainnetKeySuffix = '_mainnet';

  final bool _isTestnet;

  /// [isTestnet] hanya untuk tes — produksi selalu memakai
  /// [AppConfig.isTestnet].
  Bolt12OfferStore({bool? isTestnet})
    : _isTestnet = isTestnet ?? AppConfig.isTestnet;

  /// Kunci simpanan [base] untuk jaringan build ini.
  String _key(String base) => _isTestnet ? base : '$base$mainnetKeySuffix';

  /// Muat offer tersimpan jaringan ini; null bila belum ada,
  /// bentuknya tidak sah lagi (mis. simpanan dari versi lama),
  /// atau simpanan milik jaringan lain — pemanggil akan membuat
  /// ulang dalam kasus itu.
  Future<String?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(storageKey));
      return isValidStaticOffer(raw) ? raw!.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Deskripsi yang dipakai saat offer tersimpan dibuat; null
  /// bila tidak tercatat (simpanan era sebelum pencatatan —
  /// diperlakukan sebagai cocok: offer warisan itu lahir dari
  /// label bawaan, dan perubahan label selalu lewat editor
  /// yang menghapus offer tersimpan secara eksplisit).
  Future<String?> loadOfferDescription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key(offerDescriptionKey));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String offer, {required String forDescription}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(storageKey), offer.trim());
      await prefs.setString(_key(offerDescriptionKey), forDescription);
    } catch (_) {
      // Abaikan — offer sesi ini tetap tampil; pembuatan ulang di
      // sesi berikut hanya mengganti kode, bukan dana.
    }
  }

  /// Hapus offer tersimpan (label berubah): offer berikutnya
  /// dibuat ulang dengan deskripsi yang berlaku.
  Future<void> clearOffer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(storageKey));
      await prefs.remove(_key(offerDescriptionKey));
    } catch (_) {
      // Abaikan — ketidaksesuaian deskripsi tetap memicu
      // pembuatan ulang pada ensureOffer berikutnya.
    }
  }

  /// Label kustom user jaringan ini; null bila tidak dipasang.
  Future<String?> loadCustomDescription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(customDescriptionKey))?.trim();
      return raw == null || raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  /// Pasang label kustom (null/teks kosong = kembali bawaan).
  Future<void> saveCustomDescription(String? description) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trimmed = description?.trim() ?? '';
      if (trimmed.isEmpty) {
        await prefs.remove(_key(customDescriptionKey));
      } else {
        await prefs.setString(_key(customDescriptionKey), trimmed);
      }
    } catch (_) {
      // Abaikan — label sesi berikut jatuh ke simpanan lama.
    }
  }
}

/// Hasil satu usaha memastikan offer statis tersedia.
enum StaticOfferOutcome {
  /// Offer siap ditampilkan (dari simpanan atau baru dibuat).
  ready,

  /// Belum ada peer tersambung — pembuatan ditunda, bukan gagal.
  needsPeer,

  /// Node menolak/gagal membuat offer (detail teknis tidak
  /// diteruskan ke UI; layar menampilkan pesan ramah baku).
  failed,
}

class StaticOfferResult {
  final StaticOfferOutcome outcome;
  final String? offer;

  const StaticOfferResult(this.outcome, [this.offer]);
}

/// Orkestrasi offer statis layar Terima: pakai simpanan bila ada,
/// tunda dengan sopan bila node belum punya peer, buat + simpan
/// bila keduanya siap. Tidak pernah melempar — semua kegagalan
/// dipetakan ke [StaticOfferOutcome], supaya boot dan layar tidak
/// pernah tersangkut oleh fitur tambahan ini.
class Bolt12OfferService {
  final LspService _lspService;
  final Bolt12OfferStore _store;

  Bolt12OfferService(this._lspService, {Bolt12OfferStore? store})
    : _store = store ?? Bolt12OfferStore();

  Future<StaticOfferResult> ensureOffer({
    required String defaultDescription,
  }) async {
    // Deskripsi berlaku diputuskan DI SINI dari label kustom
    // tersimpan — bukan dipercayakan ke perhitungan pemanggil.
    // Pemanggil (layar Terima) bisa saja berjalan sebelum label
    // kustom selesai dimuat ke state-nya, dan satu panggilan yang
    // lolos dengan deskripsi bawaan akan membuang offer berlabel
    // kustom lalu menimpanya dengan offer bawaan, padahal label
    // tersimpannya sendiri utuh (temuan lapangan NUX 10 Nov
    // 2026). Pemanggil hanya menyerahkan teks bawaan bahasa
    // aplikasi; label kustom selalu dibaca segar dari simpanan.
    final description =
        await _store.loadCustomDescription() ?? defaultDescription;
    var stored = await _store.load();
    // Offer tersimpan hanya sah untuk deskripsi yang sama:
    // label berubah (kustom dipasang/diubah/dihapus) → offer
    // lama gugur, dibuat ulang dengan deskripsi berlaku.
    // Deskripsi tak tercatat (simpanan warisan) dianggap
    // cocok — lihat loadOfferDescription.
    if (stored != null) {
      final recorded = await _store.loadOfferDescription();
      if (recorded != null && recorded != description) stored = null;
    }
    var peers = 0;
    if (stored == null) {
      try {
        peers = await _lspService.connectedPeerCount();
      } catch (_) {
        return const StaticOfferResult(StaticOfferOutcome.failed);
      }
    }
    final step = decideStaticOfferStep(
      hasStoredOffer: stored != null,
      connectedPeers: peers,
    );
    switch (step) {
      case StaticOfferStep.useStored:
        return StaticOfferResult(StaticOfferOutcome.ready, stored);
      case StaticOfferStep.waitForPeer:
        return const StaticOfferResult(StaticOfferOutcome.needsPeer);
      case StaticOfferStep.createNew:
        try {
          final offer = await _lspService.createStaticOffer(
            description: description,
          );
          if (!isValidStaticOffer(offer)) {
            return const StaticOfferResult(StaticOfferOutcome.failed);
          }
          final trimmed = offer.trim();
          await _store.save(trimmed, forDescription: description);
          return StaticOfferResult(StaticOfferOutcome.ready, trimmed);
        } catch (_) {
          return const StaticOfferResult(StaticOfferOutcome.failed);
        }
    }
  }
}
