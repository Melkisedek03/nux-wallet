import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/payment_notes.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hashA =
    'aaaaaaaabbbbbbbbccccccccddddddddeeeeeeeeffffffff0000000011111111';
const _hashB =
    '2222222233333333444444445555555566666666777777778888888899999999';

void main() {
  group('resolveInvoiceDescription', () {
    test('catatan terisi (dengan spasi tepi) menang atas bawaan', () {
      expect(
        resolveInvoiceDescription(
            note: '  untuk SPP November  ', fallback: 'Terima 5.000'),
        'untuk SPP November',
      );
    });

    test('catatan kosong/spasi saja → teks bawaan', () {
      expect(resolveInvoiceDescription(note: '', fallback: 'Terima 5.000'),
          'Terima 5.000');
      expect(resolveInvoiceDescription(note: '   ', fallback: 'Terima 5.000'),
          'Terima 5.000');
    });
  });

  group('encode/decodePaymentNotes', () {
    test('pulang-pergi utuh', () {
      final notes = {_hashA: 'untuk SPP', _hashB: 'bayar kopi'};
      expect(decodePaymentNotes(encodePaymentNotes(notes)), notes);
    });

    test('masukan rusak → peta kosong', () {
      expect(decodePaymentNotes(null), isEmpty);
      expect(decodePaymentNotes(''), isEmpty);
      expect(decodePaymentNotes('{bukan json'), isEmpty);
      expect(decodePaymentNotes('[1,2,3]'), isEmpty);
      expect(decodePaymentNotes('"teks"'), isEmpty);
    });

    test('entri tidak sah dibuang, entri sah bertahan', () {
      final raw = encodePaymentNotes({
        _hashA: 'catatan sah',
        'pendek': 'kunci bukan hash',
        _hashB: '',
      });
      expect(decodePaymentNotes(raw), {_hashA: 'catatan sah'});
    });
  });

  group('PaymentNoteStore', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('simpan lalu muat; perbarui hash yang sama menimpa', () async {
      final store = PaymentNoteStore();
      await store.save(_hashA, '  untuk SPP  ');
      await store.save(_hashB, 'bayar kopi');
      await store.save(_hashA, 'untuk SPP November');
      final all = await store.loadAll();
      expect(all, {_hashA: 'untuk SPP November', _hashB: 'bayar kopi'});
    });

    test('catatan kosong & hash tidak sah tidak disimpan', () async {
      final store = PaymentNoteStore();
      await store.save(_hashA, '   ');
      await store.save('bukan-hash', 'teks');
      expect(await store.loadAll(), isEmpty);
    });

    test('simpanan rusak terbaca sebagai kosong', () async {
      SharedPreferences.setMockInitialValues(
          {PaymentNoteStore.storageKey: '{rusak'});
      expect(await PaymentNoteStore().loadAll(), isEmpty);
    });
  });
}
