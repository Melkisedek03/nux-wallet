import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'store_test_db.dart';

void main() {
  group('pengaturan toko', () {
    test('bawaan sesuai keputusan: poin aktif, Rp1.000 → 1.000 poin, '
        'nilai potong Rp1, tanpa batas maks', () {
      const s = StoreSettings.defaults;
      expect(s.storeName, '');
      expect(s.pointsEnabled, isTrue);
      expect(s.earnStepRp, 1000);
      expect(s.earnPointsPerStep, 1000);
      expect(s.redeemRateRp, 1);
      expect(s.maxRedeemPercent, isNull);
    });

    test('roundtrip JSON utuh termasuk batas maks terisi', () {
      const s = StoreSettings(
        storeName: 'Fotokopi Mentari',
        pointsEnabled: false,
        earnStepRp: 5000,
        earnPointsPerStep: 250,
        redeemRateRp: 2,
        maxRedeemPercent: 30,
      );
      expect(decodeStoreSettings(encodeStoreSettings(s)), s);
      // Tanpa batas maks juga roundtrip (kunci tidak ditulis).
      const noCap = StoreSettings(storeName: 'Toko A');
      expect(decodeStoreSettings(encodeStoreSettings(noCap)), noCap);
    });

    test('decode rusak → bawaan; field rusak → bawaan per field', () {
      expect(decodeStoreSettings(null), StoreSettings.defaults);
      expect(decodeStoreSettings('bukan json'), StoreSettings.defaults);
      expect(decodeStoreSettings('{"x":1}'), StoreSettings.defaults);
      // Satu field sah + sisanya rusak: yang sah dipertahankan.
      final partial = decodeStoreSettings(
        '{"storeName":"Toko B","earnStepRp":-5,"earnPointsPerStep":50,'
        '"redeemRateRp":0,"maxRedeemPercent":250}',
      );
      expect(partial.storeName, 'Toko B');
      expect(partial.earnStepRp, 1000); // negatif → bawaan
      expect(partial.earnPointsPerStep, 50);
      expect(partial.redeemRateRp, 1); // 0 → bawaan
      expect(partial.maxRedeemPercent, isNull); // di luar 1–100 → kosong
    });

    test('copyWith dapat mengosongkan batas maks secara eksplisit', () {
      const s = StoreSettings(maxRedeemPercent: 25);
      expect(s.copyWith(maxRedeemPercent: 40).maxRedeemPercent, 40);
      expect(s.copyWith(clearMaxRedeemPercent: true).maxRedeemPercent, isNull);
      // copyWith biasa tidak menyentuh batas maks.
      expect(s.copyWith(storeName: 'X').maxRedeemPercent, 25);
    });

    test('field struk baru: bawaan alamat kosong, token tampil, '
        'footer bawaan; roundtrip utuh', () {
      const d = StoreSettings.defaults;
      expect(d.storeAddress, '');
      expect(d.showTokenNumber, isTrue);
      expect(d.receiptFooterText, '');
      const s = StoreSettings(
        storeName: 'Kafe Nusantara',
        storeAddress: 'Jl. Merdeka No. 1',
        storeCity: 'Jakarta',
        showTokenNumber: false,
        receiptFooterText: 'Makasih, sampai jumpa!',
      );
      expect(decodeStoreSettings(encodeStoreSettings(s)), s);
    });

    test('simpanan lama tanpa field struk baru → bawaan per field', () {
      final legacy = decodeStoreSettings(
        '{"storeName":"Toko Lama","pointsEnabled":false,'
        '"earnStepRp":2000,"earnPointsPerStep":10,"redeemRateRp":1}',
      );
      expect(legacy.storeName, 'Toko Lama');
      expect(legacy.storeAddress, '');
      expect(legacy.showTokenNumber, isTrue);
      expect(legacy.receiptFooterText, '');
    });

    test('store roundtrip lewat SharedPreferences + fail-open', () async {
      SharedPreferences.setMockInitialValues({});
      final store = StoreSettingsStore(database: newTestStoreDatabase());
      expect(await store.load(), StoreSettings.defaults);
      const s = StoreSettings(storeName: 'Toko C', earnStepRp: 2000);
      await store.save(s);
      expect(await store.load(), s);
      SharedPreferences.setMockInitialValues({
        StoreSettingsStore.storageKey: '###rusak###',
      });
      expect(await StoreSettingsStore(database: newTestStoreDatabase()).load(), StoreSettings.defaults);
    });
  });
}
