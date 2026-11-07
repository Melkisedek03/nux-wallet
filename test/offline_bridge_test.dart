import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/offline_bridge.dart';

void main() {
  group('offlineResumeBackoff', () {
    test('tumbuh mengganda dari 2 detik', () {
      expect(offlineResumeBackoff(0), const Duration(seconds: 2));
      expect(offlineResumeBackoff(1), const Duration(seconds: 4));
      expect(offlineResumeBackoff(2), const Duration(seconds: 8));
      expect(offlineResumeBackoff(3), const Duration(seconds: 16));
    });

    test('mentok di 30 detik untuk percobaan besar', () {
      expect(offlineResumeBackoff(4), const Duration(seconds: 30));
      expect(offlineResumeBackoff(10), const Duration(seconds: 30));
    });
  });
}
