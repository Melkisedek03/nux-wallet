/// Himpunan "dalam pembukaan" (PR C): ID channel yang dikembalikan
/// `openChannelToPeer` saat pengguna menekan Buat Jalur, disimpan
/// (memori + SharedPreferences) sampai channel-nya muncul di
/// `listChannels`.
///
/// Ini menutup jendela negosiasi — detik-detik saat `fundingTxo`
/// masih null dan channel belum terlihat di daftar — supaya tombol
/// Buat Jalur tidak muncul kembali di sisi pendana sesudah
/// pembukaan terkirim. Begitu channel-nya muncul di daftar,
/// channel itu sendiri yang membawa keadaannya (disiapkan/siap),
/// jadi entrinya dihapus.
///
/// Kuncinya adalah `userChannelId` LOKAL (hex dari byte-nya):
/// `channelId` TIDAK stabil — berubah sekali seumur channel
/// (binding types.dart:376-382) — jadi tidak boleh dipakai sebagai
/// kunci. Entri juga mengingat peer tujuannya: himpunan ini hanya
/// berlaku untuk peer itu (pengguna bisa membuka ke peer lain
/// sesudahnya, dan entri lama tidak boleh membuat kartu peer baru
/// menampilkan "disiapkan").

library;

import 'package:ldk_node/src/generated/api/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bentuk hex `userChannelId` — kunci stabil untuk himpunan ini.
/// Equality `UserChannelId` sendiri tidak bisa diandalkan antar
/// instans (membandingkan identitas `Uint8List`), jadi byte-nya
/// di-hex-kan menjadi string.
String userChannelIdHex(UserChannelId id) =>
    id.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Simpanan entri dalam-pembukaan: `userChannelId` hex →
/// ID node peer (hex, huruf kecil).
class OpeningPathsStore {
  static const String _key = 'buat_jalur_dalam_pembukaan_v1';

  final Map<String, String> _entries = {};

  bool get loaded => _loaded;
  bool _loaded = false;

  /// Muat entri dari SharedPreferences. Idempotent.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_key);
      if (saved != null) {
        for (final raw in saved) {
          final parts = raw.split('|');
          if (parts.length == 2 &&
              parts[0].isNotEmpty &&
              parts[1].isNotEmpty) {
            _entries[parts[1]] = parts[0].toLowerCase();
          }
        }
      }
    } catch (_) {
      // Simpanan gagal baca: mulai dari kosong — jendela
      // negosiasi hanya tertutup kurang rapat.
    }
    _loaded = true;
  }

  /// Catat pembukaan baru ke [peerNodeIdHex] dengan ID
  /// [userChannelId] yang dikembalikan node. Menunggu [load] dulu
  /// bila belum dimuat — tanpa itu simpanan lama bisa tertimpa
  /// oleh peta yang baru berisi entri ini.
  Future<void> noteOpened({
    required String peerNodeIdHex,
    required UserChannelId userChannelId,
  }) async {
    if (!_loaded) await load();
    _entries[userChannelIdHex(userChannelId)] = peerNodeIdHex.toLowerCase();
    await _persist();
  }

  /// Apakah ada pembukaan yang sedang berjalan ke
  /// [peerNodeIdHex] (perbandingan tidak peka huruf).
  bool hasOpeningFor(String peerNodeIdHex) {
    final peer = peerNodeIdHex.toLowerCase();
    return _entries.values.any((p) => p == peer);
  }

  /// Pangkas entri yang channel-nya sudah muncul di [channels]:
  /// sejak saat itu channel itu sendiri yang membawa keadaannya.
  /// Entri yang channel-nya tidak kunjung muncul dipertahankan —
  /// itulah jendela negosiasi yang ditutup himpunan ini.
  Future<void> prune(List<ChannelDetails> channels) async {
    if (!_loaded) await load();
    if (_entries.isEmpty) return;
    final visible = channels
        .map((c) => userChannelIdHex(c.userChannelId))
        .toSet();
    final removed = _entries.keys.where(visible.contains).toList();
    if (removed.isEmpty) return;
    for (final id in removed) {
      _entries.remove(id);
    }
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _key,
        _entries.entries.map((e) => '${e.value}|${e.key}').toList(),
      );
    } catch (_) {
      // Gagal tulis hanya berarti entri tidak selamat dari
      // mulai ulang aplikasi — jendela negosiasi hanya
      // tertutup kurang rapat.
    }
  }
}
