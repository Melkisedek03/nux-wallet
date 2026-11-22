/// Progres konfirmasi deposit on-chain untuk halaman Dompet
/// On-chain — jawaban atas celah yang ditemukan saat uji build
/// 115: deposit masuk tidak punya indikator progres di mana pun
/// (tidak ada "x/6 konfirmasi", tidak ada notifikasi kedatangan,
/// tidak ada deteksi latar belakang). Yang ada hanya chip
/// "Menunggu" di baris Aktivitas dan bunyi CoinAlert saat
/// pembayaran berbalik Succeeded.
///
/// Dua sumber data, keduanya sudah ada — tanpa perubahan binding:
///
/// - Tinggi konfirmasi berasal dari NODE: `PaymentKind_Onchain`
///   membawa `status: ConfirmationStatus` — `Confirmed{height}`
///   atau `Unconfirmed` (ldk-node `src/payment/store.rs`,
///   dihitung di `src/wallet/mod.rs` dari posisi rantai BDK).
///   Otoritatif, tanpa panggilan jaringan per pembayaran.
/// - Tinggi ujung berasal dari REST electrs
///   (`GET /blocks/tip/height`, parser `parseTipHeight` yang
///   sama dengan tab Jelajah): binding tidak mengekspos tinggi
///   ujung. Gagal-terbuka — bila pengambilan gagal, baris
///   deposit tetap tampil tanpa angka konfirmasi.
///
/// Ambang 6 konfirmasi adalah ambang yang sama dengan yang
/// dipakai chip riwayat: pembayaran on-chain berstatus Succeeded
/// begitu `cur_height >= confirmation_height + ANTI_REORG_DELAY
/// - 1` dengan ANTI_REORG_DELAY = 6 (ldk-node
/// `src/wallet/mod.rs:166`). Rumus konfirmasi mengikuti LDK:
/// `tip - confirmationHeight + 1`, dicap di 6 untuk tampilan.
///
/// Jangan samakan "terkonfirmasi" (6 konfirmasi) dengan "bisa
/// dipakai" (1 konfirmasi, `trusted_spendable` BDK): deposit
/// masuk baris "Siap pakai" di 1 konfirmasi, tetapi baris
/// progresnya tetap tampil sampai 6/6 — dua ambang yang berbeda
/// untuk dua pertanyaan yang berbeda.

library;

import 'package:http/http.dart' as http;
import 'package:ldk_node/src/generated/api/types.dart';

import '../config.dart';
import 'market_info.dart';

/// Ambang konfirmasi deposit (ANTI_REORG_DELAY = 6): di titik
/// ini pembayaran berstatus Succeeded dan baris progresnya
/// hilang — catatan riwayat yang tersisa.
const int depositConfirmationsRequired = 6;

/// Batas waktu pengambilan tinggi ujung — refresh halaman tidak
/// boleh menggantung lama menunggu jaringan.
const Duration depositTipTimeout = Duration(seconds: 5);

/// Satu deposit masuk yang belum mencapai ambang konfirmasi.
class PendingDeposit {
  const PendingDeposit({
    required this.txid,
    required this.amountSats,
    required this.confirmations,
  });

  /// Txid deposit (urutan tampil, sama seperti daemon/electrs).
  final String txid;

  /// Jumlah deposit dalam nusan utuh.
  final BigInt amountSats;

  /// Konfirmasi yang sudah dicapai (0..6), atau null bila tinggi
  /// ujung tidak diketahui sehingga hitungannya tidak bisa
  /// dibuat (transaksi terkonfirmasi + pengambilan ujung gagal).
  final int? confirmations;
}

/// Hitung konfirmasi dari [status] konfirmasi node dan tinggi
/// ujung [tipHeight]:
/// - belum terkonfirmasi → 0 (tinggi ujung tidak dibutuhkan);
/// - terkonfirmasi + ujung diketahui → `tip - height + 1`,
///   dicap ke rentang 0..6 (ujung yang tertinggal dari tinggi
///   konfirmasi — tepi reorg — memberi 0, bukan negatif);
/// - terkonfirmasi + ujung tidak diketahui → null.
int? depositConfirmations({
  required ConfirmationStatus status,
  required int? tipHeight,
}) {
  return switch (status) {
    ConfirmationStatus_Unconfirmed() => 0,
    ConfirmationStatus_Confirmed(:final height) =>
      tipHeight == null
          ? null
          : (tipHeight - height + 1).clamp(0, depositConfirmationsRequired),
  };
}

/// Saring pembayaran masuk on-chain yang masih menunggu dari
/// [payments]: jenis on-chain, arah masuk, status menunggu.
/// Status node yang dipakai sebagai penyaring — node membalik
/// status ke Succeeded tepat di 6 konfirmasi, jadi penyaring ini
/// dan cap 6/6 tidak pernah berselisih. Urutan riwayat
/// dipertahankan (terbaru di depan).
List<PaymentDetails> pendingDepositPayments(List<PaymentDetails> payments) {
  return payments
      .where(
        (p) =>
            p.kind is PaymentKind_Onchain &&
            p.direction == PaymentDirection.inbound &&
            p.status == PaymentStatus.pending,
      )
      .toList();
}

/// Bangun daftar deposit tertunda dari riwayat [payments] dan
/// tinggi ujung [tipHeight]. Pembayaran tanpa jumlah dilewati
/// (on-chain selalu membawa jumlah; tanpa itu baris tidak bisa
/// dirender dengan jujur).
List<PendingDeposit> pendingDeposits(
  List<PaymentDetails> payments,
  int? tipHeight,
) {
  final hasil = <PendingDeposit>[];
  for (final p in pendingDepositPayments(payments)) {
    final kind = p.kind as PaymentKind_Onchain;
    final amountMsat = p.amountMsat;
    if (amountMsat == null) continue;
    hasil.add(
      PendingDeposit(
        txid: kind.txid.hash,
        // On-chain memakai nusan utuh (msat kelipatan 1000).
        amountSats: amountMsat ~/ BigInt.from(1000),
        confirmations: depositConfirmations(
          status: kind.status,
          tipHeight: tipHeight,
        ),
      ),
    );
  }
  return hasil;
}

/// Pengambil tinggi blok ujung dari REST electrs. Klien HTTP bisa
/// disuntik (tes) — bawaan memakai klien baru.
///
/// Catatan: PR #44 (terbuka, belum merge saat PR ini ditulis)
/// menambah `fetchTipHeight` yang sama ke FeeEstimateService.
/// Duplikasi satu metode ini disengaja — kedua PR dibangun dari
/// main yang sama dan tidak boleh saling bergantung; penyatuan
/// adalah tindak lanjut sepele sesudah keduanya merge.
class DepositProgressService {
  DepositProgressService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// Tinggi blok ujung dari `/blocks/tip/height`. Null bila
  /// pengambilan atau parse-nya gagal — pemanggil menampilkan
  /// baris deposit tanpa angka konfirmasi.
  Future<int?> fetchTipHeight() async {
    try {
      final respons = await _client
          .get(Uri.parse('${AppConfig.electrsRestBase}/blocks/tip/height'))
          .timeout(depositTipTimeout);
      if (respons.statusCode != 200) return null;
      return parseTipHeight(respons.body);
    } catch (_) {
      return null;
    }
  }
}
