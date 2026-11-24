import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/utils/privacy_policy.dart';

void main() {
  group('isScrolledToBottom', () {
    test('di tengah halaman: belum bawah', () {
      expect(
        isScrolledToBottom(
          scrollTop: 100,
          clientHeight: 800,
          scrollHeight: 5000,
        ),
        isFalse,
      );
    });

    test('persis di bawah: bawah', () {
      expect(
        isScrolledToBottom(
          scrollTop: 4200,
          clientHeight: 800,
          scrollHeight: 5000,
        ),
        isTrue,
      );
    });

    test('dalam ambang 24px dari bawah: bawah (toleransi pembulatan)', () {
      expect(
        isScrolledToBottom(
          scrollTop: 4180,
          clientHeight: 800,
          scrollHeight: 5000,
        ),
        isTrue,
      );
    });

    test('lebih dari ambang di atas bawah: belum bawah', () {
      expect(
        isScrolledToBottom(
          scrollTop: 4100,
          clientHeight: 800,
          scrollHeight: 5000,
        ),
        isFalse,
      );
    });

    test('konten muat tanpa guliran: langsung bawah', () {
      expect(
        isScrolledToBottom(
          scrollTop: 0,
          clientHeight: 800,
          scrollHeight: 600,
        ),
        isTrue,
      );
    });
  });

  group('privacyPolicyUrlFor', () {
    test('id → halaman Indonesia', () {
      expect(privacyPolicyUrlFor('id'), privacyPolicyUrlId);
    });

    test('en → halaman Inggris', () {
      expect(privacyPolicyUrlFor('en'), privacyPolicyUrlEn);
    });

    test('bahasa lain → halaman Inggris (fallback)', () {
      expect(privacyPolicyUrlFor('fr'), privacyPolicyUrlEn);
    });
  });
}
