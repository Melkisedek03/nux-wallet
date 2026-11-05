import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/store_database.dart';
import 'package:nux_wallet/services/store_order_history.dart';
import 'package:nux_wallet/services/store_settings.dart';
import 'package:nux_wallet/services/store_shift.dart';
import 'package:nux_wallet/utils/rupiah_input.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';
import 'package:nux_wallet/utils/store_receipt.dart';
import 'package:nux_wallet/utils/store_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store_test_db.dart';

/// Batch 5 Nov 2026: split payment, master metode bayar,
/// modal awal shift, Fase B (prefix outlet), dan format
/// nominal saat mengetik.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('split payment', () {
    test('record split: JSON pulang-pergi utuh', () {
      final record = buildCompletedOrder(
        id: 'split-1',
        time: DateTime(2026, 11, 5, 10, 0),
        lines: const [
          OrderLine(label: 'Paket', unitPriceRp: 100000, qty: 1),
        ],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: payMethodSplit,
        payments: const [
          OrderPayment(method: 'QRIS', amountRp: 50000),
          OrderPayment(method: payMethodCash, amountRp: 50000),
        ],
        cashReceivedRp: 60000,
        changeRp: 10000,
      );
      expect(record.grandTotalRp, 100000);
      expect(record.changeRp, 10000);
      final restored = CompletedOrder.fromJson(record.toJson());
      expect(restored, record);
      expect(restored!.payments, hasLength(2));
    });

    test('record lama terpetakan ke pembayaran efektif', () {
      final cash = buildCompletedOrder(
        time: DateTime(2026, 11, 5, 9, 0),
        lines: const [OrderLine(label: 'A', unitPriceRp: 7000, qty: 1)],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: payMethodCash,
        cashReceivedRp: 10000,
      );
      expect(effectivePaymentsOf(cash), const [
        OrderPayment(method: payMethodCash, amountRp: 7000),
      ]);
      expect(cashAppliedRpOf(cash), 7000);

      final named = buildCompletedOrder(
        time: DateTime(2026, 11, 5, 9, 30),
        lines: const [OrderLine(label: 'B', unitPriceRp: 3000, qty: 1)],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: 'DANA',
      );
      expect(effectivePaymentsOf(named), const [
        OrderPayment(method: 'DANA', amountRp: 3000),
      ]);
      expect(cashAppliedRpOf(named), 0);
    });

    test('agregasi: total per metode, income, tunai laci', () {
      final from = DateTime(2026, 11, 5);
      final to = from.add(const Duration(days: 1));
      final split = buildCompletedOrder(
        time: DateTime(2026, 11, 5, 10, 0),
        lines: const [
          OrderLine(label: 'Paket', unitPriceRp: 100000, qty: 1),
        ],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: payMethodSplit,
        payments: const [
          OrderPayment(method: 'QRIS', amountRp: 50000),
          OrderPayment(method: payMethodCash, amountRp: 50000),
        ],
      );
      final dana = buildCompletedOrder(
        time: DateTime(2026, 11, 5, 11, 0),
        lines: const [OrderLine(label: 'B', unitPriceRp: 3000, qty: 1)],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: 'DANA',
      );
      final summary = aggregateShiftSales([split, dana], from: from, to: to);
      expect(summary.methodTotalsRp[payMethodCash], 50000);
      expect(summary.methodTotalsRp['QRIS'], 50000);
      expect(summary.methodTotalsRp['DANA'], 3000);
      expect(summary.incomeRp, 103000);
      expect(summary.cashSalesRp, 50000);
      expect(summary.promoCount, 0);
    });
  });

  group('basis data v5', () {
    test('payments & modal shift pulang-pergi lewat SQLite', () async {
      SharedPreferences.setMockInitialValues({});
      final StoreDatabase storeDb = newTestStoreDatabase();
      final db = await storeDb.database;
      final record = buildCompletedOrder(
        id: 'split-db',
        time: DateTime(2026, 11, 5, 10, 0),
        lines: const [
          OrderLine(label: 'Paket', unitPriceRp: 100000, qty: 1),
        ],
        orderDiscount: null,
        paymentHashHex: null,
        payMethod: payMethodSplit,
        payments: const [
          OrderPayment(method: 'DANA', amountRp: 40000),
          OrderPayment(method: payMethodCash, amountRp: 60000),
        ],
        cashReceivedRp: 60000,
      );
      await insertCompletedOrder(db, record);
      final loaded = await loadCompletedOrders(db);
      expect(loaded.single, record);

      final shift = StoreShift(
        openedAt: DateTime(2026, 11, 5, 8, 0),
        era: storeEraRupiah,
        openingFloatRp: 200000,
      );
      await insertShiftRows(db, [shift]);
      final shifts = await StoreShiftStore(database: storeDb).load();
      expect(shifts.single.openingFloatRp, 200000);
      await storeDb.close();
    });
  });

  group('pengaturan: metode bayar & telegram', () {
    test('pulang-pergi JSON + normalisasi duplikat', () {
      final settings = StoreSettings(
        paymentMethods: const ['QRIS', 'DANA'],
        telegramBotToken: '123:abc',
        telegramChatId: '-100123',
      );
      final restored = StoreSettings.fromJson(settings.toJson());
      expect(restored, settings);
      expect(restored.telegramConfigured, isTrue);
      expect(
        normalizePaymentMethods([' qris ', 'QRIS', '', 'OVO', 'ovo']),
        ['qris', 'OVO'],
      );
      expect(StoreSettings.defaults.paymentMethods, ['QRIS', 'DANA', 'OVO']);
      expect(StoreSettings.defaults.telegramConfigured, isFalse);
    });
  });

  group('Fase B & format nominal', () {
    test('nomor bill membawa prefix outlet bila ada', () {
      final t = DateTime(2026, 11, 5, 9, 30);
      expect(formatBillNo(t, 7), 'INV261105-0007');
      expect(
        formatBillNo(t, 7, outletId: '02a3c4'),
        'INV-02a3c4-261105-0007',
      );
    });

    test('format saat mengetik mengelompokkan ribuan', () {
      const formatter = RupiahAmountFormatter();
      final result = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: '100000'),
      );
      expect(result.text, '100.000');
      expect(parseRupiahAmount('Rp 1.250.500'), 1250500);
      expect(formatRupiahInput(50000), '50.000');
      expect(formatRupiahInput(50000, thousandsSep: ','), '50,000');
    });
  });
}
