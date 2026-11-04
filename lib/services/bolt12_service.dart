import 'package:shared_preferences/shared_preferences.dart';

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
class Bolt12OfferStore {
  static const String storageKey = 'bolt12_static_offer';

  /// Deskripsi yang dipakai saat offer tersimpan dibuat.
  static const String offerDescriptionKey = 'bolt12_offer_for_description';

  /// Label kustom pilihan user; absen/kosong = label bawaan.
  static const String customDescriptionKey = 'bolt12_offer_custom_label';

  /// Muat offer tersimpan; null bila belum ada atau bentuknya
  /// tidak sah lagi (mis. simpanan dari versi lama) — pemanggil
  /// akan membuat ulang dalam kasus itu.
  Future<String?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
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
      return prefs.getString(offerDescriptionKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String offer, {required String forDescription}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, offer.trim());
      await prefs.setString(offerDescriptionKey, forDescription);
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
      await prefs.remove(storageKey);
      await prefs.remove(offerDescriptionKey);
    } catch (_) {
      // Abaikan — ketidaksesuaian deskripsi tetap memicu
      // pembuatan ulang pada ensureOffer berikutnya.
    }
  }

  /// Label kustom user; null bila tidak dipasang.
  Future<String?> loadCustomDescription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(customDescriptionKey)?.trim();
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
        await prefs.remove(customDescriptionKey);
      } else {
        await prefs.setString(customDescriptionKey, trimmed);
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

  Future<StaticOfferResult> ensureOffer({required String description}) async {
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
