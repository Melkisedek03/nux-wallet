import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/utils/store_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('rencana migrasi v1 → v2', () {
    test('sudah pernah jalan → rencana kosong apa pun keadaan v1', () {
      final plan = planStoreMigration(
        alreadyDone: true,
        hasOpenLegacyShift: true,
        legacyHeldCount: 5,
        legacyCatalogNonEmpty: true,
      );
      expect(plan, StoreMigrationPlan.none);
      expect(plan.hasActions, isFalse);
      expect(plan.hasNotices, isFalse);
    });

    test('tak ada sisa v1 → rencana kosong (jalan pertama yang bersih)', () {
      final plan = planStoreMigration(
        alreadyDone: false,
        hasOpenLegacyShift: false,
        legacyHeldCount: 0,
        legacyCatalogNonEmpty: false,
      );
      expect(plan, StoreMigrationPlan.none);
      expect(plan.hasActions, isFalse);
    });

    test('shift terbuka + tahan + katalog terisi → semua tercatat', () {
      final plan = planStoreMigration(
        alreadyDone: false,
        hasOpenLegacyShift: true,
        legacyHeldCount: 3,
        legacyCatalogNonEmpty: true,
      );
      expect(plan.closeOpenLegacyShift, isTrue);
      expect(plan.droppedHeldOrders, 3);
      expect(plan.catalogNeedsRefill, isTrue);
      expect(plan.hasActions, isTrue);
      expect(plan.hasNotices, isTrue);
    });

    test('hanya shift terbuka: ada tindakan tetapi tanpa pemberitahuan', () {
      final plan = planStoreMigration(
        alreadyDone: false,
        hasOpenLegacyShift: true,
        legacyHeldCount: 0,
        legacyCatalogNonEmpty: false,
      );
      expect(plan.hasActions, isTrue);
      expect(plan.hasNotices, isFalse);
    });

    test('jumlah tahan negatif dijepit ke 0', () {
      final plan = planStoreMigration(
        alreadyDone: false,
        hasOpenLegacyShift: false,
        legacyHeldCount: -2,
        legacyCatalogNonEmpty: false,
      );
      expect(plan.droppedHeldOrders, 0);
      expect(plan.hasActions, isFalse);
    });
  });

  group('penanda migrasi', () {
    test('roundtrip penanda lewat SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final flag = StoreMigrationFlagStore();
      expect(await flag.isDone(), isFalse);
      await flag.markDone();
      expect(await flag.isDone(), isTrue);
    });
  });
}
