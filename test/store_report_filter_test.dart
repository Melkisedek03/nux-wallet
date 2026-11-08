import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_report_filter.dart';

void main() {
  group('storeReportWindowFor (filter bersama laporan Mode Toko)', () {
    final now = DateTime(2026, 11, 8, 14, 30);

    test('today = hari kalender penuh', () {
      final w = storeReportWindowFor(
        const StoreReportFilter.preset(StoreReportPeriod.today),
        now: now,
      );
      expect(w.from, DateTime(2026, 11, 8));
      expect(w.to, DateTime(2026, 11, 9));
    });

    test('last7Days bergulir 7×24 jam, ujung atas awal besok', () {
      final w = storeReportWindowFor(
        const StoreReportFilter.preset(StoreReportPeriod.last7Days),
        now: now,
      );
      expect(w.from, DateTime(2026, 11, 1, 14, 30));
      expect(w.to, DateTime(2026, 11, 9));
    });

    test('last30Days bergulir 30×24 jam', () {
      final w = storeReportWindowFor(
        const StoreReportFilter.preset(StoreReportPeriod.last30Days),
        now: now,
      );
      expect(w.from, DateTime(2026, 10, 9, 14, 30));
      expect(w.to, DateTime(2026, 11, 9));
    });

    test('all tanpa batas bawah yang berarti', () {
      final w = storeReportWindowFor(
        const StoreReportFilter.preset(StoreReportPeriod.all),
        now: now,
      );
      expect(w.from, DateTime(2000));
      expect(w.to, DateTime(2026, 11, 9));
    });

    test('custom: hari pertama & terakhir inklusif penuh', () {
      final w = storeReportWindowFor(
        StoreReportFilter(
          StoreReportPeriod.custom,
          customStart: DateTime(2026, 10, 3, 18, 45),
          customEnd: DateTime(2026, 10, 5, 1, 15),
        ),
        now: now,
      );
      expect(w.from, DateTime(2026, 10, 3));
      expect(w.to, DateTime(2026, 10, 6));
    });

    test('custom satu hari = tepat satu hari kalender', () {
      final w = storeReportWindowFor(
        StoreReportFilter(
          StoreReportPeriod.custom,
          customStart: DateTime(2026, 11, 2),
          customEnd: DateTime(2026, 11, 2),
        ),
        now: now,
      );
      expect(w.from, DateTime(2026, 11, 2));
      expect(w.to, DateTime(2026, 11, 3));
    });

    test('custom tanpa tanggal jatuh ke hari ini', () {
      final w = storeReportWindowFor(
        const StoreReportFilter(StoreReportPeriod.custom),
        now: now,
      );
      expect(w.from, DateTime(2026, 11, 8));
      expect(w.to, DateTime(2026, 11, 9));
    });
  });

  group('StoreReportFilter', () {
    test('preset tidak custom; kesetaraan nilai bekerja', () {
      expect(
        const StoreReportFilter.preset(StoreReportPeriod.today).isCustom,
        isFalse,
      );
      expect(
        const StoreReportFilter(StoreReportPeriod.custom).isCustom,
        isTrue,
      );
      expect(
        StoreReportFilter(
          StoreReportPeriod.custom,
          customStart: DateTime(2026, 1, 1),
          customEnd: DateTime(2026, 1, 2),
        ),
        StoreReportFilter(
          StoreReportPeriod.custom,
          customStart: DateTime(2026, 1, 1),
          customEnd: DateTime(2026, 1, 2),
        ),
      );
    });
  });
}
