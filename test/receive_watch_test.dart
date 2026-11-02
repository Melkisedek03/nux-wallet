import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/utils/receive_watch.dart';

void main() {
  group('receiveWatcherShouldRun', () {
    test('semua tertutup: pengawas berhenti', () {
      expect(
        receiveWatcherShouldRun(
          invoicePending: false,
          staticPanelOpen: false,
          celebrating: false,
        ),
        isFalse,
      );
    });

    test('invoice Bolt11 pending: pengawas berjalan', () {
      expect(
        receiveWatcherShouldRun(
          invoicePending: true,
          staticPanelOpen: false,
          celebrating: false,
        ),
        isTrue,
      );
    });

    test('panel Kode Bayar Statis terbuka: pengawas berjalan', () {
      expect(
        receiveWatcherShouldRun(
          invoicePending: false,
          staticPanelOpen: true,
          celebrating: false,
        ),
        isTrue,
      );
    });

    test('jendela perayaan: pengawas tetap berjalan', () {
      // Pembayaran kedua yang tiba di tengah perayaan harus
      // tertangkap dan menggantikan panel — pengawas tidak boleh
      // sudah mati saat itu.
      expect(
        receiveWatcherShouldRun(
          invoicePending: false,
          staticPanelOpen: false,
          celebrating: true,
        ),
        isTrue,
      );
    });

    test('kombinasi apa pun yang tidak kosong: berjalan', () {
      expect(
        receiveWatcherShouldRun(
          invoicePending: true,
          staticPanelOpen: true,
          celebrating: true,
        ),
        isTrue,
      );
      expect(
        receiveWatcherShouldRun(
          invoicePending: false,
          staticPanelOpen: true,
          celebrating: true,
        ),
        isTrue,
      );
    });
  });

  group('receiveCelebrationDuration', () {
    test('jeda tampil panel sukses positif dan masuk akal', () {
      expect(receiveCelebrationDuration, greaterThan(Duration.zero));
      expect(receiveCelebrationDuration,
          lessThanOrEqualTo(const Duration(seconds: 15)));
    });
  });
}
