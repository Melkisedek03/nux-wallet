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
      await store.save(_offerContoh);
      expect(await store.load(), _offerContoh);
    });

    test('simpanan rusak dianggap tidak ada', () async {
      SharedPreferences.setMockInitialValues({
        Bolt12OfferStore.storageKey: 'bukan-offer',
      });
      expect(await Bolt12OfferStore().load(), isNull);
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
      final result = await service.ensureOffer(description: 'uji');
      expect(result.outcome, StaticOfferOutcome.ready);
      expect(result.offer, _offerContoh);
    });

    test('tanpa simpanan + node mati: failed, tidak melempar', () async {
      SharedPreferences.setMockInitialValues({});
      final service = Bolt12OfferService(LspService());
      final result = await service.ensureOffer(description: 'uji');
      expect(result.outcome, StaticOfferOutcome.failed);
      expect(result.offer, isNull);
    });
  });
}
