import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_operators.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // Impor satu-kali basis data membaca SharedPreferences.
    SharedPreferences.setMockInitialValues({});
  });

  group('PIN murni', () {
    test('format: tepat 6 digit angka', () {
      expect(isValidStorePin('123456'), isTrue);
      expect(isValidStorePin('12345'), isFalse);
      expect(isValidStorePin('1234567'), isFalse);
      expect(isValidStorePin('12a456'), isFalse);
      expect(isValidStorePin(''), isFalse);
    });

    test('hash bergaram: benar cocok, salah/beda garam tidak', () {
      final salt = newStorePinSalt();
      final hash = hashStorePin('112233', salt);
      expect(verifyStorePin('112233', salt, hash), isTrue);
      expect(verifyStorePin('112234', salt, hash), isFalse);
      expect(verifyStorePin('112233', newStorePinSalt(), hash), isFalse);
      // Garam acak: dua garam tidak (praktis) pernah sama.
      expect(newStorePinSalt(), isNot(newStorePinSalt()));
    });
  });

  group('StoreOperatorStore (SQLite uji)', () {
    test('buat → verifikasi PIN sendiri & PIN owner mana pun', () async {
      final store = StoreOperatorStore(database: newTestStoreDatabase());
      final owner = await store.create(
        name: 'Bu Rina',
        role: storeRoleOwner,
        pin: '112233',
      );
      final cashier = await store.create(
        name: 'Sari',
        role: storeRoleCashier,
        pin: '445566',
      );
      expect(owner.isOwner, isTrue);
      expect(cashier.isOwner, isFalse);

      expect((await store.verifyPin(owner.id, '112233'))?.id, owner.id);
      expect(await store.verifyPin(owner.id, '000000'), isNull);
      expect(await store.verifyPin(cashier.id, '112233'), isNull);

      // Override admin: PIN owner cocok, PIN kasir tidak.
      expect((await store.verifyAnyOwnerPin('112233'))?.id, owner.id);
      expect(await store.verifyAnyOwnerPin('445566'), isNull);
      expect(await store.verifyAnyOwnerPin('999999'), isNull);

      final all = await store.loadAll();
      expect(all.map((o) => o.name), ['Bu Rina', 'Sari']);
    });

    test('nonaktif → PIN tidak lagi berlaku; ganti PIN bekerja',
        () async {
      final store = StoreOperatorStore(database: newTestStoreDatabase());
      final op = await store.create(
        name: 'Sari',
        role: storeRoleCashier,
        pin: '445566',
      );
      await store.setPin(op.id, '121212');
      expect(await store.verifyPin(op.id, '445566'), isNull);
      expect((await store.verifyPin(op.id, '121212'))?.id, op.id);

      await store.update(op.copyWith(active: false));
      expect(await store.verifyPin(op.id, '121212'), isNull);
      final loaded = await store.loadAll();
      expect(loaded.single.active, isFalse);
    });
  });

  group('StoreAuditStore (SQLite uji)', () {
    test('append lalu load: terbaru di depan, operator tercatat',
        () async {
      final db = newTestStoreDatabase();
      final operators = StoreOperatorStore(database: db);
      final audit = StoreAuditStore(database: db);
      final owner = await operators.create(
        name: 'Bu Rina',
        role: storeRoleOwner,
        pin: '112233',
      );
      await audit.append(
        operator: owner,
        action: StoreAuditAction.login,
      );
      await audit.append(
        operator: owner,
        action: StoreAuditAction.saleVoid,
        detail: 'INV261104-0007 — salah input',
      );
      final entries = await audit.load();
      expect(entries.length, 2);
      expect(entries.first.action, StoreAuditAction.saleVoid);
      expect(entries.first.detail, contains('INV261104-0007'));
      expect(entries.first.operatorName, 'Bu Rina');
      expect(entries.last.action, StoreAuditAction.login);
    });
  });
}
