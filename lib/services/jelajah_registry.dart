/// Registri direktori toko untuk tab Jelajah.
///
/// Sumbernya satu berkas JSON statis terkurasi tim di
/// [AppConfig.jelajahRegistryUrl] — tanpa server khusus, tanpa akun
/// pengguna, tanpa pelacakan. Tim meninjau setiap entri sebelum masuk
/// berkas (kurasi adalah pagar kepercayaannya); toko terdaftar atas
/// persetujuan pemiliknya (opt-in), karena offer Bolt12 statis dan
/// keterangan lokasi di dalamnya memang diterbitkan untuk dibagikan.
///
/// Prinsip kegagalan mengikuti [UpdateService]: pengambilan yang gagal
/// (jaringan mati, JSON rusak) tidak melempar error ke UI — pemanggil
/// menerima salinan cache terakhir, atau daftar kosong bila belum
/// pernah ada cache.
///
/// Direktori ini murni informasi: tidak ada tombol bayar di kartu toko.
/// Pembayaran belanja tetap rupiah sesuai pedoman Mode Toko; entri
/// hanya menandai toko yang menjalankan program poin (lencana), dan
/// satu-satunya tindakan adalah menyalin offer — penanganan data
/// netral yang setara menyalin alamat di layar Terima.

library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Satu entri toko di direktori Jelajah.
class JelajahStore {
  const JelajahStore({
    required this.id,
    required this.name,
    required this.offer,
    this.city = '',
    this.area = '',
    this.addressNote = '',
    this.hours = '',
    this.note = '',
    this.pointsProgram = false,
  });

  /// Penanda stabil dan unik (kurasi tim), mis. "toko-berkah-01".
  final String id;

  /// Nama toko, dari nama toko Mode Toko miliknya.
  final String name;

  /// Offer Bolt12 statis toko (untuk disalin, bukan untuk dibayar
  /// dari direktori).
  final String offer;

  /// Kota (teks bebas) — dasar saringan wilayah manual, tanpa GPS.
  final String city;

  /// Keterangan lokasi kasar, mis. "Malioboro".
  final String area;

  /// Petunjuk manusiawi, mis. "Sebelah utara pasar".
  final String addressNote;

  /// Jam buka (teks bebas), mis. "08.00–21.00".
  final String hours;

  /// Barang/jasa utama, satu baris.
  final String note;

  /// true bila toko menjalankan program poin Mode Toko.
  final bool pointsProgram;

  /// Parse satu entri; null bila kolom wajib (id/name/offer) tidak
  /// terpenuhi — entri rusak dilewati, bukan menggagalkan seluruh
  /// registri.
  static JelajahStore? dariJson(Object? json) {
    if (json is! Map) return null;
    String teks(String kunci) {
      final nilai = json[kunci];
      return nilai is String ? nilai.trim() : '';
    }

    final id = teks('id');
    final name = teks('name');
    final offer = teks('offer');
    if (id.isEmpty || name.isEmpty || offer.isEmpty) return null;
    return JelajahStore(
      id: id,
      name: name,
      offer: offer,
      city: teks('city'),
      area: teks('area'),
      addressNote: teks('addressNote'),
      hours: teks('hours'),
      note: teks('note'),
      pointsProgram: json['pointsProgram'] == true,
    );
  }
}

/// Parse isi berkas registri (JSON yang sudah di-decode): array entri.
/// Entri tidak valid dilewati; id duplikat hanya diambil yang pertama.
List<JelajahStore> parseJelajahRegistry(Object? json) {
  if (json is! List) return const [];
  final hasil = <JelajahStore>[];
  final terlihat = <String>{};
  for (final entri in json) {
    final toko = JelajahStore.dariJson(entri);
    if (toko == null) continue;
    if (!terlihat.add(toko.id)) continue;
    hasil.add(toko);
  }
  return hasil;
}

/// Daftar kota yang benar-benar memiliki toko, terurut alfabet —
/// dasar pilihan saringan wilayah manual di layar Jelajah.
List<String> jelajahCities(List<JelajahStore> stores) {
  final kota = <String>{};
  for (final toko in stores) {
    if (toko.city.isNotEmpty) kota.add(toko.city);
  }
  return kota.toList()..sort();
}

/// Saring direktori menurut kota (null = semua kota) dan kata cari
/// (mencocokkan nama, catatan barang/jasa, dan area; abaikan huruf
/// besar/kecil). Urutan berkas dipertahankan (kurasi tim).
List<JelajahStore> filterJelajahStores(
  List<JelajahStore> stores, {
  String? city,
  String query = '',
}) {
  final kata = query.trim().toLowerCase();
  return stores.where((toko) {
    if (city != null && toko.city != city) return false;
    if (kata.isEmpty) return true;
    return toko.name.toLowerCase().contains(kata) ||
        toko.note.toLowerCase().contains(kata) ||
        toko.area.toLowerCase().contains(kata);
  }).toList();
}

/// Hasil muat registri: daftar toko + kapan data ini diambil dari
/// sumbernya (null bila belum pernah berhasil diambil).
class JelajahRegistryResult {
  const JelajahRegistryResult({required this.stores, this.fetchedAt});

  final List<JelajahStore> stores;
  final DateTime? fetchedAt;

  bool get isEmpty => stores.isEmpty;
}

/// Pengambil + cache registri Jelajah.
///
/// Cache disimpan sebagai JSON mentah + cap waktu di SharedPreferences
/// agar direktori tetap tampil saat offline, lengkap dengan cap waktu
/// datanya (data basi tidak pernah disajikan sebagai data segar).
class JelajahRegistryService {
  static const String _kunciJson = 'jelajah_registry_json';
  static const String _kunciWaktu = 'jelajah_registry_fetched_at_ms';

  /// Muat registri: ambil dari jaringan; bila gagal, pakai cache.
  /// Tidak pernah melempar — kegagalan total menghasilkan daftar
  /// kosong tanpa cap waktu.
  Future<JelajahRegistryResult> muat() async {
    final segar = await _ambilDariJaringan();
    if (segar != null) return segar;
    final cache = await _dariCache();
    return cache ?? const JelajahRegistryResult(stores: []);
  }

  Future<JelajahRegistryResult?> _ambilDariJaringan() async {
    try {
      final respons = await http
          .get(Uri.parse(AppConfig.jelajahRegistryUrl))
          .timeout(const Duration(seconds: 12));
      if (respons.statusCode != 200) return null;
      final toko = parseJelajahRegistry(jsonDecode(respons.body));
      final waktu = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kunciJson, respons.body);
      await prefs.setInt(_kunciWaktu, waktu.millisecondsSinceEpoch);
      return JelajahRegistryResult(stores: toko, fetchedAt: waktu);
    } catch (_) {
      return null;
    }
  }

  Future<JelajahRegistryResult?> _dariCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mentah = prefs.getString(_kunciJson);
      final waktuMs = prefs.getInt(_kunciWaktu);
      if (mentah == null || waktuMs == null) return null;
      return JelajahRegistryResult(
        stores: parseJelajahRegistry(jsonDecode(mentah)),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(waktuMs),
      );
    } catch (_) {
      return null;
    }
  }
}
