import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';

/// Seed tersimpan korup: panjangnya bukan 64 byte.
///
/// [path] terisi bila sumbernya berkas biasa era sebelum migrasi
/// (pesan lama menyuruh user menghapus berkas itu); null bila
/// sumbernya simpanan aman (tidak ada berkas yang bisa dihapus —
/// pemulihan hanya lewat frasa backup). [length] adalah panjang
/// byte yang terbaca, atau null bila nilai tersimpan bukan
/// base64 yang sah sehingga panjangnya tidak diketahui.
class SeedCorruptException implements Exception {
  final int? length;
  final String? path;

  const SeedCorruptException({this.length, this.path});
}

/// Penyimpanan seed + frasa dompet di secure storage (Keychain
/// di iOS, Keystore/EncryptedSharedPreferences di Android).
///
/// R1 audit kesiapan mainnet: seed 64 byte + frasa 12 kata
/// tadinya berkas biasa di app support dir — bisa dibaca
/// aplikasi lain, ekstraksi backup, atau perangkat root. Di
/// mainnet dengan dana sungguhan itu berarti dompet kosong.
///
/// Kunci simpanan dibedakan per jaringan: testnet memakai kunci
/// polos, mainnet memakai akhiran `_mainnet` — konvensi yang
/// sama dengan berkas seed lama (`lsp_seed.bin` vs
/// `lsp_seed_mainnet.bin`) dan simpanan offer Bolt12. Pemisahan
/// seed per jaringan (audit A2) dipertahankan: APK mainnet yang
/// menimpa instalasi testnet lahir dengan dompet baru yang
/// bersih, tanpa mewarisi seed testnet.
///
/// Migrasi instalasi lama ([migrateFromPlainFiles]) berjalan
/// setiap kali aplikasi dibuka, sebelum node start: baca berkas
/// biasa → tulis ke simpanan aman → baca balik dan verifikasi
/// byte-per-byte → baru hapus berkas biasa. Idempotent:
/// simpanan aman yang sudah terisi tidak pernah ditimpa dari
/// berkas (berkas adalah sisa lama — dihapus saja). Fail-open:
/// kegagalan apa pun menelan errornya, berkas biasa
/// dipertahankan, aplikasi tetap berjalan darinya, dan migrasi
/// dicoba lagi saat buka berikutnya.
///
/// Catatan: simpanan aman TIDAK ikut backup/pindah perangkat
/// (kunci enkripsinya hidup di Keystore/Keychain perangkat
/// asal). Sesudah migrasi, instalasi di perangkat baru lahir
/// dengan dompet baru — frasa backup 12 kata adalah
/// satu-satunya jalan pemulihan, seperti dompet non-custodial
/// pada umumnya.
class WalletSeedStore {
  /// Kunci simpanan seed (testnet); mainnet = kunci + `_mainnet`.
  static const String seedKey = 'lsp_seed';

  /// Kunci simpanan frasa (testnet); mainnet = kunci + `_mainnet`.
  static const String mnemonicKey = 'wallet_mnemonic';

  /// Akhiran kunci simpanan untuk jaringan mainnet.
  static const String mainnetKeySuffix = '_mainnet';

  /// Nama berkas seed era berkas biasa (tanpa akhiran jaringan).
  static const String _seedFileStem = 'lsp_seed';

  /// Nama berkas frasa era berkas biasa (tanpa akhiran jaringan).
  static const String _mnemonicFileStem = 'wallet_mnemonic';

  final FlutterSecureStorage _secure;
  final Directory _supportDir;
  final bool _isTestnet;

  /// [secureStorage] dan [isTestnet] hanya untuk tes — produksi
  /// memakai default plugin + [AppConfig.isTestnet].
  /// [supportDir] adalah app support dir tempat berkas lama hidup.
  WalletSeedStore({
    FlutterSecureStorage? secureStorage,
    required Directory supportDir,
    bool? isTestnet,
  }) : _secure = secureStorage ?? const FlutterSecureStorage(),
       _supportDir = supportDir,
       _isTestnet = isTestnet ?? AppConfig.isTestnet;

  /// Kunci simpanan [base] untuk jaringan build ini.
  String _key(String base) => _isTestnet ? base : '$base$mainnetKeySuffix';

  /// Nama berkas lama [stem].[ext] untuk jaringan build ini
  /// (akhiran `_mainnet` menempel sebelum ekstensi).
  String _fileName(String stem, String ext) =>
      _isTestnet ? '$stem.$ext' : '${stem}_mainnet.$ext';

  /// Berkas seed lama jaringan ini (hanya migrasi + fallback).
  File get _seedFile =>
      File('${_supportDir.path}/${_fileName(_seedFileStem, 'bin')}');

  /// Berkas frasa lama jaringan ini (hanya migrasi + fallback).
  File get _mnemonicFile =>
      File('${_supportDir.path}/${_fileName(_mnemonicFileStem, 'txt')}');

  /// Pindahkan seed + frasa dari berkas biasa era sebelum
  /// migrasi ke simpanan aman. Idempotent dan fail-open: aman
  /// dipanggil setiap kali aplikasi dibuka; kegagalan apa pun
  /// menelan errornya — berkas biasa dipertahankan, aplikasi
  /// tetap berjalan darinya, dan migrasi dicoba lagi saat buka
  /// berikutnya. TIDAK PERNAH melempar.
  Future<void> migrateFromPlainFiles() async {
    await _migrateSeed();
    await _migrateMnemonic();
  }

  Future<void> _migrateSeed() async {
    try {
      final file = _seedFile;
      if (!await file.exists()) return;
      final plain = await file.readAsBytes();
      if (plain.length == 32) {
        // Berkas mati dari versi awal yang keliru: builder LDK
        // mensyaratkan 64 byte dan selalu menolak 32, jadi tidak
        // pernah ada wallet/dana di bawah seed ini — aman dihapus.
        await file.delete();
        return;
      }
      if (plain.length != 64) {
        // Korup: jangan sentuh — loadSeed akan melempar
        // SeedCorruptException seperti perilaku lama.
        return;
      }
      // Simpanan aman sudah terisi dan sah → simpanan aman
      // otoritatif (migrasi sebelumnya, atau restore sesudah
      // migrasi). Berkas biasa adalah sisa lama — hapus saja,
      // jangan pernah menimpa simpanan aman dari berkas.
      if (await _readSecureSeed() != null) {
        await file.delete();
        return;
      }
      // Tulis → baca balik → verifikasi byte-per-byte → baru
      // hapus berkas biasa. Gagal verifikasi = berkas
      // dipertahankan, migrasi dicoba lagi saat buka berikutnya.
      final encoded = base64Encode(plain);
      await _secure.write(key: _key(seedKey), value: encoded);
      final readBack = await _secure.read(key: _key(seedKey));
      if (readBack != encoded) return;
      await file.delete();
    } catch (_) {
      // Fail-open: berkas biasa dipertahankan; migrasi dicoba
      // lagi saat buka berikutnya.
    }
  }

  Future<void> _migrateMnemonic() async {
    try {
      final file = _mnemonicFile;
      if (!await file.exists()) return;
      final plain = await file.readAsString();
      if (plain.trim().isEmpty) {
        await file.delete();
        return;
      }
      // Simpanan aman sudah terisi → otoritatif; berkas biasa
      // adalah sisa lama (lihat _migrateSeed).
      String? existing;
      try {
        existing = await _secure.read(key: _key(mnemonicKey));
      } catch (_) {
        existing = null;
      }
      if (existing != null && existing.trim().isNotEmpty) {
        await file.delete();
        return;
      }
      await _secure.write(key: _key(mnemonicKey), value: plain);
      final readBack = await _secure.read(key: _key(mnemonicKey));
      if (readBack != plain) return;
      await file.delete();
    } catch (_) {
      // Fail-open — lihat _migrateSeed.
    }
  }

  /// Seed sah dari simpanan aman; null bila belum ada, tidak
  /// terbaca, atau korup. Tidak pernah melempar.
  Future<List<int>?> _readSecureSeed() async {
    try {
      final raw = await _secure.read(key: _key(seedKey));
      if (raw == null) return null;
      return _tryDecodeSeed(raw);
    } catch (_) {
      return null;
    }
  }

  /// Dekode base64 → 64 byte; null bila bukan base64 sah atau
  /// panjangnya bukan 64.
  List<int>? _tryDecodeSeed(String raw) {
    try {
      final decoded = base64Decode(raw);
      return decoded.length == 64 ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Panjang byte nilai base64 [raw]; null bila bukan base64 sah.
  int? _decodedLength(String raw) {
    try {
      return base64Decode(raw).length;
    } catch (_) {
      return null;
    }
  }

  /// Seed dompet (64 byte) jaringan ini; null bila belum ada
  /// dompet. Simpanan aman dibaca dulu; bila tidak terbaca atau
  /// korup, berkas biasa dipakai sebagai fallback (fail-open).
  ///
  /// Melempar [SeedCorruptException] bila satu-satunya salinan
  /// yang ada korup — pemanggil TIDAK BOLEH membuat dompet baru
  /// dalam keadaan itu (seed lama akan tertimpa).
  Future<List<int>?> loadSeed() async {
    bool secureCorrupt = false;
    int? secureCorruptLength;
    try {
      final raw = await _secure.read(key: _key(seedKey));
      if (raw != null) {
        final decoded = _tryDecodeSeed(raw);
        if (decoded != null) return decoded;
        secureCorrupt = true;
        secureCorruptLength = _decodedLength(raw);
      }
    } catch (_) {
      // Baca aman gagal total (Keystore tidak tersedia) — bukan
      // korup, melainkan tidak terbaca; lanjut ke berkas biasa.
    }
    final file = _seedFile;
    if (await file.exists()) {
      final plain = await file.readAsBytes();
      if (plain.length == 64) return plain;
      if (plain.length == 32) {
        // Berkas mati — bukan dompet. Bila simpanan aman korup,
        // laporkan korupnya (jangan lahirkan dompet baru).
        if (secureCorrupt) {
          throw SeedCorruptException(length: secureCorruptLength);
        }
        return null;
      }
      throw SeedCorruptException(length: plain.length, path: file.path);
    }
    if (secureCorrupt) {
      throw SeedCorruptException(length: secureCorruptLength);
    }
    return null;
  }

  /// Frasa dompet jaringan ini; null bila belum ada (dompet
  /// legacy atau belum dibuat). Simpanan aman dulu, berkas
  /// biasa sebagai fallback — validasi kata tetap di pemanggil.
  Future<String?> loadMnemonic() async {
    try {
      final raw = await _secure.read(key: _key(mnemonicKey));
      if (raw != null && raw.trim().isNotEmpty) return raw;
    } catch (_) {
      // Baca aman gagal — lanjut ke berkas biasa.
    }
    final file = _mnemonicFile;
    if (await file.exists()) {
      final text = await file.readAsString();
      if (text.trim().isNotEmpty) return text;
    }
    return null;
  }

  /// Simpan seed dompet (64 byte) ke simpanan aman.
  ///
  /// Bila simpanan aman tidak tersedia (Keystore gagal), seed
  /// ditulis ke berkas biasa sebagai fallback — dompet tetap
  /// berfungsi, dan migrasi berikutnya memindahkannya.
  ///
  /// Bila tulis aman berhasil tetapi baca-baliknya tidak cocok,
  /// melempar [StateError] dan TIDAK menulis berkas biasa:
  /// simpanan aman yang mengembalikan nilai salah jauh lebih
  /// berbahaya daripada gagal simpan (loadSeed mengutamakan
  /// simpanan aman, jadi nilai salah akan dipakai sebagai seed).
  Future<void> saveSeed(List<int> seedBytes) async {
    assert(seedBytes.length == 64, 'Seed harus 64 byte');
    final encoded = base64Encode(seedBytes);
    try {
      await _secure.write(key: _key(seedKey), value: encoded);
    } catch (_) {
      await _seedFile.writeAsBytes(seedBytes, flush: true);
      return;
    }
    String? readBack;
    try {
      readBack = await _secure.read(key: _key(seedKey));
    } catch (_) {
      // Baca balik gagal — tidak tahu apakah tulis berhasil;
      // simpan juga ke berkas biasa supaya seed tidak bergantung
      // pada simpanan yang belum terverifikasi. Migrasi
      // berikutnya membereskannya (simpanan aman sah → berkas
      // dihapus; simpanan aman kosong → berkas dimigrasikan).
      await _seedFile.writeAsBytes(seedBytes, flush: true);
      return;
    }
    if (readBack != encoded) {
      throw StateError(
        'Secure storage read-back mismatch for the wallet seed.',
      );
    }
    await _deletePlainFileQuietly(_seedFile);
  }

  /// Simpan frasa dompet ke simpanan aman. Pola sama dengan
  /// [saveSeed]: fallback berkas biasa bila simpanan aman tidak
  /// tersedia, melempar bila baca-balik tidak cocok.
  Future<void> saveMnemonic(String mnemonic) async {
    try {
      await _secure.write(key: _key(mnemonicKey), value: mnemonic);
    } catch (_) {
      await _mnemonicFile.writeAsString(mnemonic, flush: true);
      return;
    }
    String? readBack;
    try {
      readBack = await _secure.read(key: _key(mnemonicKey));
    } catch (_) {
      await _mnemonicFile.writeAsString(mnemonic, flush: true);
      return;
    }
    if (readBack != mnemonic) {
      throw StateError(
        'Secure storage read-back mismatch for the wallet mnemonic.',
      );
    }
    await _deletePlainFileQuietly(_mnemonicFile);
  }

  /// Hapus seed + frasa jaringan ini dari simpanan aman DAN
  /// sisa berkas biasa (reset dompet). Berkas biasa WAJIB ikut
  /// dihapus — tanpanya, boot berikutnya akan memigrasi ulang
  /// seed lama dan dompet "terhapus" bangkit lagi. Setiap
  /// penghapusan best-effort; tidak pernah melempar.
  Future<void> clearAll() async {
    try {
      await _secure.delete(key: _key(seedKey));
    } catch (_) {}
    try {
      await _secure.delete(key: _key(mnemonicKey));
    } catch (_) {}
    await _deletePlainFileQuietly(_seedFile);
    await _deletePlainFileQuietly(_mnemonicFile);
  }

  Future<void> _deletePlainFileQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
