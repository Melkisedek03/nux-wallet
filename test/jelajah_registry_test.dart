import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/jelajah_registry.dart';

/// Uji logika murni registri Jelajah: parse berkas direktori
/// (entri rusak dilewati, duplikat dibuang), daftar kota, dan
/// penyaringan kota + kata cari.
void main() {
  List<dynamic> berkasContoh() => [
        {
          'id': 'toko-berkah-01',
          'name': 'Berkah Cell',
          'city': 'Yogyakarta',
          'area': 'Malioboro',
          'addressNote': 'Sebelah utara pasar',
          'hours': '08.00–21.00',
          'offer': 'lno1berkah',
          'note': 'Pulsa, token listrik, kopi',
          'pointsProgram': true,
        },
        {
          'id': 'warung-sederhana-01',
          'name': 'Warung Sederhana',
          'city': 'Solo',
          'offer': 'lno1warung',
          'note': 'Nasi rames, es teh',
        },
      ];

  group('parseJelajahRegistry', () {
    test('format lengkap ter-parse semua field', () {
      final toko = parseJelajahRegistry(berkasContoh());
      expect(toko, hasLength(2));
      expect(toko.first.name, 'Berkah Cell');
      expect(toko.first.city, 'Yogyakarta');
      expect(toko.first.area, 'Malioboro');
      expect(toko.first.pointsProgram, isTrue);
      expect(toko.last.pointsProgram, isFalse);
      expect(toko.last.hours, '');
    });

    test('bukan array menghasilkan daftar kosong', () {
      expect(parseJelajahRegistry(null), isEmpty);
      expect(parseJelajahRegistry({'stores': []}), isEmpty);
      expect(parseJelajahRegistry('teks'), isEmpty);
    });

    test('entri tanpa kolom wajib dilewati, bukan menggagalkan', () {
      final toko = parseJelajahRegistry([
        {'id': 'x', 'name': 'Tanpa Offer'},
        {'name': 'Tanpa Id', 'offer': 'lno1x'},
        {'id': 'ok-01', 'name': 'Toko Sah', 'offer': 'lno1ok'},
        'bukan peta',
      ]);
      expect(toko, hasLength(1));
      expect(toko.single.id, 'ok-01');
    });

    test('id duplikat hanya diambil yang pertama', () {
      final toko = parseJelajahRegistry([
        {'id': 'sama', 'name': 'Pertama', 'offer': 'lno1a'},
        {'id': 'sama', 'name': 'Kedua', 'offer': 'lno1b'},
      ]);
      expect(toko, hasLength(1));
      expect(toko.single.name, 'Pertama');
    });
  });

  group('jelajahCities', () {
    test('unik, tanpa kota kosong, terurut alfabet', () {
      final toko = parseJelajahRegistry([
        {'id': '1', 'name': 'A', 'offer': 'o1', 'city': 'Solo'},
        {'id': '2', 'name': 'B', 'offer': 'o2', 'city': 'Yogyakarta'},
        {'id': '3', 'name': 'C', 'offer': 'o3', 'city': 'Solo'},
        {'id': '4', 'name': 'D', 'offer': 'o4'},
      ]);
      expect(jelajahCities(toko), ['Solo', 'Yogyakarta']);
    });
  });

  group('filterJelajahStores', () {
    final toko = parseJelajahRegistry(berkasContoh());

    test('tanpa saringan mengembalikan semua', () {
      expect(filterJelajahStores(toko), hasLength(2));
    });

    test('saring menurut kota', () {
      final hasil = filterJelajahStores(toko, city: 'Solo');
      expect(hasil.single.name, 'Warung Sederhana');
    });

    test('kata cari mencocokkan nama, catatan, dan area', () {
      expect(filterJelajahStores(toko, query: 'berkah'), hasLength(1));
      expect(filterJelajahStores(toko, query: 'KOPI'), hasLength(1));
      expect(filterJelajahStores(toko, query: 'malioboro'), hasLength(1));
      expect(filterJelajahStores(toko, query: 'tidak-ada'), isEmpty);
    });

    test('kota dan kata cari berlaku bersamaan', () {
      expect(
        filterJelajahStores(toko, city: 'Yogyakarta', query: 'kopi'),
        hasLength(1),
      );
      expect(
        filterJelajahStores(toko, city: 'Solo', query: 'kopi'),
        isEmpty,
      );
    });
  });
}
