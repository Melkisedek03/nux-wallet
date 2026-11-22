import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/bolt12_service.dart';
import 'package:nux_wallet/services/lsp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offer contoh berbentuk sah: awalan lno1 + panjang di kisaran
/// offer asli (±1.150 karakter dari spike). Isi sesudah awalan
/// tidak divalidasi di lapisan ini — parse sesungguhnya urusan
/// node saat offer dipakai pembayar.
final _offerContoh = 'lno1${'a' * 1100}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isValidStaticOffer', () {
    test('offer lno1 panjang diterima', () {
      expect(isValidStaticOffer(_offerContoh), isTrue);
    });

    test('spasi di pinggir ditoleransi (trim)', () {
      expect(isValidStaticOffer('  $_offerContoh  '), isTrue);
    });

    test('yang bukan offer ditolak', () {
      expect(isValidStaticOffer(null), isFalse);
      expect(isValidStaticOffer(''), isFalse);
      expect(isValidStaticOffer('lntn1invoicebolt11biasa'), isFalse);
      expect(isValidStaticOffer('lno1pendek'), isFalse);
      expect(isValidStaticOffer('lno1${'a' * 300} ada spasi'), isFalse);
    });
  });

  group('decideStaticOfferStep', () {
    test('simpanan ada → pakai simpanan, berapa pun peer-nya', () {
      expect(
        decideStaticOfferStep(hasStoredOffer: true, connectedPeers: 0),
        StaticOfferStep.useStored,
      );
      expect(
        decideStaticOfferStep(hasStoredOffer: true, connectedPeers: 3),
        StaticOfferStep.useStored,
      );
    });

    test('tanpa simpanan + tanpa peer → tunda', () {
      expect(
        decideStaticOfferStep(hasStoredOffer: false, connectedPeers: 0),
        StaticOfferStep.waitForPeer,
      );
    });

    test('tanpa simpanan + ada peer → buat baru', () {
      expect(
        decideStaticOfferStep(hasStoredOffer: false, connectedPeers: 1),
        StaticOfferStep.createNew,
      );
    });
  });

  group('Bolt12OfferStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('simpan → muat kembali utuh', () async {
      final store = Bolt12OfferStore();
      expect(await store.load(), isNull);
      await store.save(_offerContoh, forDescription: 'uji');
      expect(await store.load(), _offerContoh);
      expect(await store.loadOfferDescription(), 'uji');
    });

    test('label kustom: pasang, baca, hapus; clearOffer membuang '
        'offer + deskripsinya', () async {
      final store = Bolt12OfferStore();
      expect(await store.loadCustomDescription(), isNull);
      await store.saveCustomDescription('  Toko Berkah  ');
      expect(await store.loadCustomDescription(), 'Toko Berkah');
      await store.saveCustomDescription('');
      expect(await store.loadCustomDescription(), isNull);

      await store.save(_offerContoh, forDescription: 'uji');
      await store.clearOffer();
      expect(await store.load(), isNull);
      expect(await store.loadOfferDescription(), isNull);
    });

    test('simpanan rusak dianggap tidak ada', () async {
      SharedPreferences.setMockInitialValues({
        Bolt12OfferStore.storageKey: 'bukan-offer',
      });
      expect(await Bolt12OfferStore().load(), isNull);
    });
  });

  group('Bolt12OfferStore: ikatan jaringan (R2)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('offer testnet tidak terbaca build mainnet, dan sebaliknya', () async {
      final testnet = Bolt12OfferStore(isTestnet: true);
      final mainnet = Bolt12OfferStore(isTestnet: false);
      await testnet.save(_offerContoh, forDescription: 'uji');
      expect(await testnet.load(), _offerContoh);
      expect(await testnet.loadOfferDescription(), 'uji');
      expect(await mainnet.load(), isNull);
      expect(await mainnet.loadOfferDescription(), isNull);

      await mainnet.save(_offerContoh, forDescription: 'uji');
      expect(await mainnet.load(), _offerContoh);
      expect(await mainnet.loadOfferDescription(), 'uji');
      // Slot testnet tetap utuh — tiap jaringan punya simpanan
      // sendiri, bukan satu slot yang ditimpa bergantian.
      expect(await testnet.load(), _offerContoh);
    });

    test('label kustom mengikuti ikatan jaringan yang sama', () async {
      final testnet = Bolt12OfferStore(isTestnet: true);
      final mainnet = Bolt12OfferStore(isTestnet: false);
      await testnet.saveCustomDescription('Toko Berkah');
      expect(await testnet.loadCustomDescription(), 'Toko Berkah');
      expect(await mainnet.loadCustomDescription(), isNull);

      await mainnet.saveCustomDescription('Toko Utama');
      expect(await mainnet.loadCustomDescription(), 'Toko Utama');
      expect(await testnet.loadCustomDescription(), 'Toko Berkah');
    });

    test('clearOffer hanya membuang slot jaringannya sendiri', () async {
      final testnet = Bolt12OfferStore(isTestnet: true);
      final mainnet = Bolt12OfferStore(isTestnet: false);
      await testnet.save(_offerContoh, forDescription: 'uji');
      await mainnet.save(_offerContoh, forDescription: 'uji');
      await testnet.clearOffer();
      expect(await testnet.load(), isNull);
      expect(await testnet.loadOfferDescription(), isNull);
      expect(await mainnet.load(), _offerContoh);
      expect(await mainnet.loadOfferDescription(), 'uji');
    });

    test('simpanan lama (kunci polos) tetap berlaku di testnet', () async {
      // Kunci polos adalah kunci testnet (konvensi berkas seed):
      // simpanan yang ditulis build lama — yang hanya pernah
      // ada sebagai testnet — tetap terbaca tanpa migrasi.
      SharedPreferences.setMockInitialValues({
        Bolt12OfferStore.storageKey: _offerContoh,
        Bolt12OfferStore.offerDescriptionKey: 'uji',
      });
      expect(await Bolt12OfferStore(isTestnet: true).load(), _offerContoh);
      expect(await Bolt12OfferStore(isTestnet: false).load(), isNull);
    });

    test('kunci mainnet = kunci dasar + akhiran _mainnet', () async {
      final mainnet = Bolt12OfferStore(isTestnet: false);
      await mainnet.save(_offerContoh, forDescription: 'uji');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(
          '${Bolt12OfferStore.storageKey}'
          '${Bolt12OfferStore.mainnetKeySuffix}',
        ),
        _offerContoh,
      );
      expect(prefs.getString(Bolt12OfferStore.storageKey), isNull);
    });
  });

  group('Bolt12OfferService.ensureOffer', () {
    test('dari simpanan: ready tanpa menyentuh node', () async {
      SharedPreferences.setMockInitialValues({
        Bolt12OfferStore.storageKey: _offerContoh,
      });
      // LspService belum init (node mati): jalur simpanan tidak
      // boleh menyentuhnya sama sekali.
      final service = Bolt12OfferService(LspService());
      final result = await service.ensureOffer(defaultDescription: 'uji');
      expect(result.outcome, StaticOfferOutcome.ready);
      expect(result.offer, _offerContoh);
    });

    test('tanpa simpanan + node mati: failed, tidak melempar', () async {
      SharedPreferences.setMockInitialValues({});
      final service = Bolt12OfferService(LspService());
      final result = await service.ensureOffer(defaultDescription: 'uji');
      expect(result.outcome, StaticOfferOutcome.failed);
      expect(result.offer, isNull);
    });

    test('label kustom berubah dari yang tercatat: offer simpanan '
        'TIDAK dipakai ulang (label berubah = offer baru)', () async {
      SharedPreferences.setMockInitialValues({
        Bolt12OfferStore.storageKey: _offerContoh,
        Bolt12OfferStore.offerDescriptionKey: 'label lama',
        Bolt12OfferStore.customDescriptionKey: 'label baru',
      });
      final service = Bolt12OfferService(LspService());
      // Node mati: bila offer lama dipakai ulang hasilnya akan
      // ready; yang benar adalah usaha buat baru → failed.
      final result =
          await service.ensureOffer(defaultDescription: 'bawaan');
      expect(result.outcome, StaticOfferOutcome.failed);
      expect(result.offer, isNull);
    });

    test('REGRESI 10 Nov 2026: label kustom utuh di simpanan — '
        'panggilan berteks bawaan TIDAK menimpa offer berlabel',
        () async {
      // Persis bug lapangan: offer tersimpan lahir dari label
      // kustom, label itu masih tersimpan, tetapi pemanggil hanya
      // menyerahkan teks bawaan (state labelnya belum termuat).
      // Service wajib memutuskan deskripsi dari simpanan label,
      // jadi offer berlabel tetap dipakai ulang.
      SharedPreferences.setMockInitialValues({
        Bolt12OfferStore.storageKey: _offerContoh,
        Bolt12OfferStore.offerDescriptionKey: 'Toko Berkah',
        Bolt12OfferStore.customDescriptionKey: 'Toko Berkah',
      });
      final service = Bolt12OfferService(LspService());
      final result =
          await service.ensureOffer(defaultDescription: 'Terima NUX');
      expect(result.outcome, StaticOfferOutcome.ready);
      expect(result.offer, _offerContoh);
    });

    test('tanpa label kustom: offer tercatat berteks bawaan '
        'dipakai ulang', () async {
      SharedPreferences.setMockInitialValues({
        Bolt12OfferStore.storageKey: _offerContoh,
        Bolt12OfferStore.offerDescriptionKey: 'Terima NUX',
      });
      final service = Bolt12OfferService(LspService());
      final result =
          await service.ensureOffer(defaultDescription: 'Terima NUX');
      expect(result.outcome, StaticOfferOutcome.ready);
      expect(result.offer, _offerContoh);
    });

    test('REGRESI R2: offer testnet tersimpan TIDAK dipakai ulang '
        'build mainnet', () async {
      // Skenario audit: APK mainnet dipasang di atas instalasi
      // testnet — simpanan testnet masih ada di SharedPreferences
      // yang sama. Build mainnet tidak boleh menyajikannya.
      SharedPreferences.setMockInitialValues({
        Bolt12OfferStore.storageKey: _offerContoh,
        Bolt12OfferStore.offerDescriptionKey: 'uji',
      });
      final service = Bolt12OfferService(
        LspService(),
        store: Bolt12OfferStore(isTestnet: false),
      );
      // Node mati: bila offer testnet dipakai ulang hasilnya
      // ready; yang benar adalah usaha buat baru → failed.
      final result = await service.ensureOffer(defaultDescription: 'uji');
      expect(result.outcome, StaticOfferOutcome.failed);
      expect(result.offer, isNull);
    });

    test('offer mainnet tersimpan dipakai ulang build mainnet', () async {
      SharedPreferences.setMockInitialValues({
        '${Bolt12OfferStore.storageKey}'
                '${Bolt12OfferStore.mainnetKeySuffix}':
            _offerContoh,
        '${Bolt12OfferStore.offerDescriptionKey}'
                '${Bolt12OfferStore.mainnetKeySuffix}':
            'uji',
      });
      final service = Bolt12OfferService(
        LspService(),
        store: Bolt12OfferStore(isTestnet: false),
      );
      final result = await service.ensureOffer(defaultDescription: 'uji');
      expect(result.outcome, StaticOfferOutcome.ready);
      expect(result.offer, _offerContoh);
    });
  });
}
