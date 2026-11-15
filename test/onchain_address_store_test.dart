import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/onchain_address_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OnchainAddressStore', () {
    test('kosong → null', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await OnchainAddressStore().load(nodeId: '02aa'),
        isNull,
      );
    });

    test('simpan lalu muat untuk node yang sama', () async {
      SharedPreferences.setMockInitialValues({});
      final store = OnchainAddressStore();
      await store.save(address: 'nu1qalamat1', nodeId: '02aa');
      expect(await store.load(nodeId: '02aa'), 'nu1qalamat1');
    });

    test('simpanan milik dompet lain tidak berlaku', () async {
      SharedPreferences.setMockInitialValues({});
      final store = OnchainAddressStore();
      await store.save(address: 'nu1qalamat1', nodeId: '02aa');
      expect(await store.load(nodeId: '02bb'), isNull);
    });

    test('simpan ulang mengganti alamat tampil', () async {
      SharedPreferences.setMockInitialValues({});
      final store = OnchainAddressStore();
      await store.save(address: 'nu1qalamat1', nodeId: '02aa');
      await store.save(address: 'nu1qalamat2', nodeId: '02aa');
      expect(await store.load(nodeId: '02aa'), 'nu1qalamat2');
    });

    test('alamat kosong tidak disimpan', () async {
      SharedPreferences.setMockInitialValues({});
      final store = OnchainAddressStore();
      await store.save(address: '   ', nodeId: '02aa');
      expect(await store.load(nodeId: '02aa'), isNull);
    });
  });
}
