import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/privacy_consent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PrivacyConsentStore', () {
    test('baru: belum menyetujui', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await PrivacyConsentStore.isAccepted(), isFalse);
    });

    test('setuju → tercatat dan terbaca', () async {
      SharedPreferences.setMockInitialValues({});
      await PrivacyConsentStore.setAccepted();
      expect(await PrivacyConsentStore.isAccepted(), isTrue);
    });

    test('nilai lama yang bukan bool: belum menyetujui', () async {
      SharedPreferences.setMockInitialValues({
        PrivacyConsentStore.key: 'bukan-bool',
      });
      expect(await PrivacyConsentStore.isAccepted(), isFalse);
    });
  });
}
