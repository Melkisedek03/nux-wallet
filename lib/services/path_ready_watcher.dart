/// Pengamat "jalur sudah siap" (PR C): mendeteksi channel langsung
/// yang BARU menjadi usable dan menembakkan notifikasi lokal
/// sekali per transaksi pendanaan.
///
/// Kejadian "channel menjadi usable" hanya bisa diamati node
/// sendiri lewat `listChannels` — tidak ada server yang tahu
/// kapan channel langsung menjadi usable (LSP bukan pihak di
/// dalamnya), jadi FCM secara arsitektur tidak bisa mengamati
/// kejadian ini. Pengamat ini tinggal di `main.dart`, menumpang
/// siklus refresh dashboard 5 detik yang sudah ada, dan
/// menembakkan notifikasi LOKAL lewat saluran MethodChannel yang
/// sama dengan layanan latar jembatan — tanpa plugin, tanpa FCM.
///
/// Aturan garis dasar (meniru `_receivedAlertKeys` di main.dart):
/// pemeriksaan pertama hanya mengisi garis dasar TANPA
/// memberitahu — channel yang sudah siap sebelum aplikasi dibuka
/// ditampilkan di layar, bukan dinotifikasi. Yang dinotifikasi
/// hanyalah TRANSISI menjadi usable yang diamati selama aplikasi
/// berjalan.
///
/// Batasan yang jujur: notifikasi hanya menyala selama PROSES
/// hidup. Bila pengguna mengakhiri sesi atau sistem membunuh
/// proses, tidak ada notifikasi — keadaan siap terlihat saat
/// aplikasi dibuka berikutnya.

library;

import 'package:flutter/services.dart';
import 'package:ldk_node/src/generated/api/types.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'offline_mode_utils.dart';

/// Saluran ke layanan latar jembatan (MainActivity) — dipakai
/// juga untuk menembakkan notifikasi sekali-pakai jalur siap.
const MethodChannel _saluranJembatan = MethodChannel('nux_wallet/jembatan');

/// Tembakkan notifikasi sekali-pakai "jalur sudah siap" dengan
/// [judul] dan [isi] yang sudah dilokalisasi di sisi Dart.
/// Gagal-diam: bila pemanggilan platform gagal (mis. di tes),
/// keadaan siap tetap terlihat di layar.
Future<void> postPathReadyNotification({
  required String title,
  required String body,
}) async {
  try {
    await _saluranJembatan.invokeMethod('notifJalurSiap', {
      'judul': title,
      'isi': body,
    });
  } catch (_) {
    // Notifikasi gagal tidak menggagalkan apa pun.
  }
}

/// Status izin notifikasi saat ini: true bila diberikan, false
/// bila ditolak, null bila tidak bisa diperiksa (mis. di tes —
/// pemanggil memperlakukannya sebagai "tidak diketahui" dan
/// menyembunyikan catatan pengingat).
Future<bool?> notificationPermissionGranted() async {
  try {
    return await Permission.notification.isGranted;
  } catch (_) {
    return null;
  }
}

/// Minta izin notifikasi (Android 13+) — dipakai just-in-time
/// saat pengguna mengetuk Buat Jalur. Mengembalikan status
/// sesudah permintaan, atau null bila permintaan tidak bisa
/// dilakukan. Izin BUKAN prasyarat membuat jalur: bila ditolak,
/// kartu "disiapkan" menampilkan catatan pengingat dan keadaan
/// siap tetap terlihat di layar.
Future<PermissionStatus?> requestNotificationPermission() async {
  try {
    return await Permission.notification.request();
  } catch (_) {
    return null;
  }
}

/// Pengamat transisi usable channel langsung. Satu instans hidup
/// selama aplikasi berjalan (dimiliki `main.dart`); keadaan
/// "sudah diberitahu" dipersist supaya pembukaan ulang aplikasi
/// tidak menembakkan ulang notifikasi yang sama.
class PathReadyWatcher {
  static const String _notifiedKey = 'jalur_siap_diberitahu_v1';

  /// TXID pendanaan yang sudah dinotifikasi (dipersist).
  final Set<String> _notifiedTxids = {};

  /// TXID channel usable yang sudah pernah terlihat dalam sesi
  /// ini — garis dasar: yang sudah usable sejak pemeriksaan
  /// pertama tidak dinotifikasi.
  final Set<String> _seenUsableTxids = {};

  /// Apakah pemeriksaan pertama sudah berjalan (garis dasar
  /// sudah terisi).
  bool _primed = false;

  /// Apakah siklus terakhir melihat channel langsung yang sedang
  /// disiapkan — pemanggil memakai ini untuk memutuskan apakah
  /// pengamatan berlanjut sesudah sesi berakhir.
  bool _sawPreparing = false;

  bool get loaded => _loaded;
  bool _loaded = false;

  bool get hasPendingPreparation => _sawPreparing;

  /// Muat himpunan "sudah diberitahu" dari SharedPreferences.
  /// Idempotent; wajib dipanggil sebelum pemeriksaan pertama
  /// (pemanggil di main.dart menunggunya di boot).
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_notifiedKey);
      if (saved != null) _notifiedTxids.addAll(saved);
    } catch (_) {
      // Simpanan gagal baca: mulai dari kosong, garis dasar
      // pemeriksaan pertama tetap melindungi dari notifikasi
      // atas riwayat lama.
    }
    _loaded = true;
  }

  /// Periksa daftar [channels] untuk channel LANGSUNG (lawan
  /// bukan node LSP [lspNodeIdHex]) yang BARU menjadi usable:
  /// mengembalikan channel-channel itu (pemanggil menembakkan
  /// notifikasi + menandai lewat [markNotified]).
  ///
  /// Pemeriksaan pertama hanya mengisi garis dasar dan selalu
  /// mengembalikan daftar kosong. Sebelum [load] selesai,
  /// pemeriksaan dilewati seluruhnya (garis dasar belum aman).
  /// Channel LSP tidak pernah dihitung — di luar cakupan PR C.
  List<ChannelDetails> check(
    List<ChannelDetails> channels,
    String lspNodeIdHex,
  ) {
    if (!_loaded) return const [];
    final lsp = lspNodeIdHex.toLowerCase();
    _sawPreparing = channels.any(
      (c) =>
          c.counterpartyNodeId.hex.toLowerCase() != lsp &&
          isPreparingChannel(c),
    );
    final usableDirect = channels
        .where(
          (c) =>
              c.isUsable &&
              c.counterpartyNodeId.hex.toLowerCase() != lsp &&
              c.fundingTxo != null,
        )
        .toList();
    if (!_primed) {
      _seenUsableTxids.addAll(
        usableDirect.map((c) => c.fundingTxo!.txid.hash),
      );
      _primed = true;
      return const [];
    }
    final fresh = usableDirect
        .where(
          (c) =>
              !_seenUsableTxids.contains(c.fundingTxo!.txid.hash) &&
              !_notifiedTxids.contains(c.fundingTxo!.txid.hash),
        )
        .toList();
    _seenUsableTxids.addAll(
      usableDirect.map((c) => c.fundingTxo!.txid.hash),
    );
    return fresh;
  }

  /// Tandai [txids] sebagai sudah diberitahu (dipersist) supaya
  /// tidak ditembakkan lagi — termasuk sesudah aplikasi dibuka
  /// ulang.
  Future<void> markNotified(Iterable<String> txids) async {
    final baru = txids.where((t) => _notifiedTxids.add(t)).toList();
    if (baru.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_notifiedKey, _notifiedTxids.toList());
    } catch (_) {
      // Gagal tulis hanya berarti notifikasi yang sama bisa
      // terulang pada buka berikutnya — mengganggu, bukan rusak.
    }
  }
}
