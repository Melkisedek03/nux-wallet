import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/utils/receive_watch.dart';

void main() {
  group('receiveWatcherShouldRun', () {
    test('layar aktif: pengawas berjalan', () {
      // Semantik baru (temuan lapangan NUX 3 Nov 2026): pengawas
      // bersenjata selama layar Terima aktif — pembayaran offer
      // yang tiba saat QR kode statis tidak ditampilkan pun harus
      // tertangkap dan terayakan, bukan hanya berbunyi di
      // dashboard.
      expect(receiveWatcherShouldRun(screenActive: true), isTrue);
    });

    test('layar sudah ditutup: pengawas berhenti', () {
      // Antrean event milik bersama satu node — layar yang sudah
      // tidak aktif tidak boleh mengurasnya.
      expect(receiveWatcherShouldRun(screenActive: false), isFalse);
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
