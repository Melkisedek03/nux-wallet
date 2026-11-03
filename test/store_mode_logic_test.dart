import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/utils/store_mode_logic.dart';

void main() {
  group('keypad', () {
    test('digit menambahkan di kanan', () {
      var v = 0;
      v = keypadPressDigit(v, 1);
      v = keypadPressDigit(v, 2);
      v = keypadPressDigit(v, 3);
      expect(v, 123);
    });

    test('00 pada nilai 0 tetap 0, pada nilai lain menambah dua nol', () {
      expect(keypadPressDoubleZero(0), 0);
      expect(keypadPressDoubleZero(5), 500);
    });

    test('hapus membuang digit kanan, bersih lewat nilai 0', () {
      expect(keypadBackspace(123), 12);
      expect(keypadBackspace(7), 0);
      expect(keypadBackspace(0), 0);
    });

    test('jumlah cepat menambah dan terpotong di plafon', () {
      expect(keypadQuickAdd(1000, 5000), 6000);
      expect(
        keypadQuickAdd(storeKeypadMaxNusan - 10, 50000),
        storeKeypadMaxNusan,
      );
    });

    test('digit melewati plafon 9 digit diabaikan', () {
      expect(keypadPressDigit(99999999, 9), 999999999);
      expect(keypadPressDigit(999999999, 9), 999999999);
      expect(keypadPressDoubleZero(99999999), 99999999);
    });
  });

  group('pesanan', () {
    OrderLine free(int amount, {int qty = 1}) =>
        OrderLine(label: 'Item Bebas', unitPriceNusan: amount, qty: qty);

    test('tambah produk berkode sama menggabung qty', () {
      var lines = orderAddProduct(
        const [],
        code: 'A1',
        label: 'Kopi',
        unitPriceNusan: 5000,
      );
      lines = orderAddProduct(
        lines,
        code: 'A1',
        label: 'Kopi',
        unitPriceNusan: 5000,
      );
      lines = orderAddProduct(
        lines,
        code: 'B2',
        label: 'Teh',
        unitPriceNusan: 3000,
      );
      expect(lines.length, 2);
      expect(lines[0].qty, 2);
      expect(orderGrandTotalNusan(lines, null), 13000);
    });

    test('tambah bebas: nominal sama menggabung, beda jadi baris baru', () {
      var lines = orderAddFreeAmount(
        const [],
        label: 'Item Bebas',
        amountNusan: 7000,
      );
      lines = orderAddFreeAmount(lines, label: 'Item Bebas', amountNusan: 7000);
      lines = orderAddFreeAmount(lines, label: 'Item Bebas', amountNusan: 2000);
      expect(lines.length, 2);
      expect(lines[0].qty, 2);
      expect(orderGrandTotalNusan(lines, null), 16000);
      // Nominal 0 tidak menambah apa pun.
      expect(
        orderAddFreeAmount(lines, label: 'Item Bebas', amountNusan: 0),
        lines,
      );
      expect(free(1).qty, 1);
    });

    test('qty +/− dan hapus; kurang sampai 0 membuang baris', () {
      var lines = orderAddProduct(
        const [],
        code: 'A1',
        label: 'Kopi',
        unitPriceNusan: 5000,
      );
      lines = orderChangeQty(lines, 0, 1);
      expect(lines.single.qty, 2);
      lines = orderChangeQty(lines, 0, -1);
      expect(lines.single.qty, 1);
      lines = orderChangeQty(lines, 0, -1);
      expect(lines, isEmpty);
      // Indeks di luar jangkauan aman.
      expect(orderChangeQty(lines, 3, 1), lines);
      expect(orderRemoveLine(lines, 0), lines);
    });
  });

  group('label item bebas', () {
    test('judul kustom terisi menjadi label baris (sesudah trim)', () {
      expect(
        resolveFreeItemLabel('  Jasa Fotokopi  ', fallbackLabel: 'Item Bebas'),
        'Jasa Fotokopi',
      );
    });

    test('judul kosong atau spasi saja jatuh ke label baku', () {
      expect(resolveFreeItemLabel('', fallbackLabel: 'Item Bebas'), 'Item Bebas');
      expect(
        resolveFreeItemLabel('   ', fallbackLabel: 'Item Bebas'),
        'Item Bebas',
      );
    });

    test('judul berbeda membentuk baris berbeda, judul sama menggabung', () {
      var lines = orderAddFreeAmount(
        const [],
        label: resolveFreeItemLabel('Parkir', fallbackLabel: 'Item Bebas'),
        amountNusan: 2000,
      );
      lines = orderAddFreeAmount(
        lines,
        label: resolveFreeItemLabel('Parkir', fallbackLabel: 'Item Bebas'),
        amountNusan: 2000,
      );
      lines = orderAddFreeAmount(
        lines,
        label: resolveFreeItemLabel('', fallbackLabel: 'Item Bebas'),
        amountNusan: 2000,
      );
      expect(lines.length, 2);
      expect(lines[0].label, 'Parkir');
      expect(lines[0].qty, 2);
      expect(lines[1].label, 'Item Bebas');
    });
  });

  group('diskon', () {
    test('persen dibulatkan ke bawah ke nusan bulat', () {
      // 10% dari 4.975 = 497,5 → 497.
      expect(discountAmountFor(4975, const Discount.percent(10)), 497);
      expect(discountAmountFor(5000, const Discount.percent(10)), 500);
    });

    test('nominal dibatasi sebesar nilai yang didiskon', () {
      expect(discountAmountFor(3000, const Discount.fixed(5000)), 3000);
      expect(discountAmountFor(3000, const Discount.fixed(1200)), 1200);
    });

    test('persen 100 = seluruh nilai; diskon kosong = 0', () {
      expect(discountAmountFor(3000, const Discount.percent(100)), 3000);
      expect(discountAmountFor(3000, null), 0);
      expect(discountAmountFor(3000, const Discount.percent(0)), 0);
      expect(discountAmountFor(0, const Discount.percent(50)), 0);
    });

    test('diskon baris persen dan nominal masuk ke total baris', () {
      final pct = OrderLine(
        label: 'Kopi',
        unitPriceNusan: 5000,
        qty: 2,
        discount: const Discount.percent(10),
      );
      expect(pct.lineGrossNusan, 10000);
      expect(pct.lineDiscountNusan, 1000);
      expect(pct.lineTotalNusan, 9000);
      final fix = OrderLine(
        label: 'Teh',
        unitPriceNusan: 3000,
        qty: 1,
        discount: const Discount.fixed(4500),
      );
      expect(fix.lineTotalNusan, 0);
    });

    test('diskon bawaan katalog terisi ke baris dan bisa dihapus', () {
      var lines = orderAddProduct(
        const [],
        code: 'A1',
        label: 'Kopi',
        unitPriceNusan: 5000,
        defaultDiscount: const Discount.percent(20),
      );
      expect(lines.single.discount, const Discount.percent(20));
      expect(lines.single.lineTotalNusan, 4000);
      // Tambah lagi: qty naik, diskon baris dipertahankan.
      lines = orderAddProduct(
        lines,
        code: 'A1',
        label: 'Kopi',
        unitPriceNusan: 5000,
        defaultDiscount: const Discount.percent(50),
      );
      expect(lines.single.qty, 2);
      expect(lines.single.discount, const Discount.percent(20));
      // Kasir menghapus diskon di baris.
      lines = orderSetLineDiscount(lines, 0, null);
      expect(lines.single.discount, isNull);
      expect(lines.single.lineTotalNusan, 10000);
    });

    test('susunan hitung: diskon baris → subtotal → diskon order', () {
      final lines = [
        const OrderLine(
          label: 'Kopi',
          unitPriceNusan: 5000,
          qty: 2,
          discount: Discount.percent(10), // −1.000
        ),
        const OrderLine(label: 'Teh', unitPriceNusan: 3000, qty: 1),
      ];
      expect(orderGrossNusan(lines), 13000);
      expect(orderSubtotalNusan(lines), 12000);
      // Diskon order 25% dihitung dari subtotal 12.000 → 3.000.
      expect(orderDiscountAmountNusan(lines, const Discount.percent(25)), 3000);
      expect(orderTotalDiscountNusan(lines, const Discount.percent(25)), 4000);
      expect(orderGrandTotalNusan(lines, const Discount.percent(25)), 9000);
      // Diskon order nominal.
      expect(orderGrandTotalNusan(lines, const Discount.fixed(2000)), 10000);
    });

    test('total akhir berlantai 0 dan tidak pernah negatif', () {
      final lines = [
        const OrderLine(label: 'Teh', unitPriceNusan: 3000, qty: 1),
      ];
      expect(orderGrandTotalNusan(lines, const Discount.fixed(999999)), 0);
      expect(orderGrandTotalNusan(lines, const Discount.percent(100)), 0);
    });
  });

  group('keypad mode qty (pengali)', () {
    test('digit menyusun pengali di kanan', () {
      var v = 0;
      v = qtyMultiplierPressDigit(v, 1);
      v = qtyMultiplierPressDigit(v, 2);
      expect(v, 12);
      // Digit pertama dari 0 langsung menjadi pengali itu.
      expect(qtyMultiplierPressDigit(0, 2), 2);
    });

    test('pengali terpotong di plafon 999', () {
      var v = 0;
      for (final d in [9, 9, 9, 9]) {
        v = qtyMultiplierPressDigit(v, d);
      }
      expect(v, storeMaxQtyMultiplier);
      expect(qtyMultiplierPressDigit(99, 9), 999);
      expect(qtyMultiplierPressDigit(999, 1), 999);
    });

    test('00 mengikuti aturan nominal tetapi plafonnya pengali', () {
      expect(qtyMultiplierPressDoubleZero(0), 0);
      expect(qtyMultiplierPressDoubleZero(5), 500);
      expect(qtyMultiplierPressDoubleZero(50), 50); // 5000 > 999 diabaikan
    });

    test('tambah produk dengan qty pengali menggabung per kode', () {
      var lines = orderAddProduct(
        const [],
        code: 'A1',
        label: 'Kopi',
        unitPriceNusan: 5000,
        qty: 2,
      );
      expect(lines.single.qty, 2);
      lines = orderAddProduct(
        lines,
        code: 'A1',
        label: 'Kopi',
        unitPriceNusan: 5000,
        qty: 3,
      );
      expect(lines.single.qty, 5);
      expect(orderGrandTotalNusan(lines, null), 25000);
      // Tanpa parameter qty tetap 1 (perilaku lama).
      lines = orderAddProduct(
        lines,
        code: 'B2',
        label: 'Teh',
        unitPriceNusan: 3000,
      );
      expect(lines.last.qty, 1);
    });
  });

  group('catatan baris', () {
    test('pasang, ganti (trim), dan hapus catatan', () {
      var lines = orderAddProduct(
        const [],
        code: 'A1',
        label: 'Kopi',
        unitPriceNusan: 5000,
      );
      lines = orderSetLineNote(lines, 0, '  tanpa gula  ');
      expect(lines.single.note, 'tanpa gula');
      lines = orderSetLineNote(lines, 0, 'less sugar');
      expect(lines.single.note, 'less sugar');
      lines = orderSetLineNote(lines, 0, '   ');
      expect(lines.single.note, '');
      // Indeks di luar jangkauan aman.
      expect(orderSetLineNote(lines, 5, 'x'), lines);
    });

    test('catatan ikut equality baris', () {
      const a = OrderLine(label: 'Kopi', unitPriceNusan: 5000, qty: 1);
      const b = OrderLine(
        label: 'Kopi',
        unitPriceNusan: 5000,
        qty: 1,
        note: 'tanpa gula',
      );
      expect(a == b, isFalse);
      expect(b.copyWith(note: ''), a);
    });

    test('baris rincian struk: item, qty × harga = total, catatan', () {
      final detail = orderReceiptDetailLines(
        const [
          OrderLine(
            label: 'Kopi',
            unitPriceNusan: 5000,
            qty: 2,
            discount: Discount.percent(10),
            note: 'tanpa gula',
          ),
          OrderLine(label: 'Teh', unitPriceNusan: 3000, qty: 1),
        ],
        formatNusan: (n) => n.toString(),
        noteWord: 'Catatan',
      );
      expect(detail, [
        'Kopi',
        // Total baris SESUDAH diskon baris (10.000 − 1.000).
        '  2 x 5000 = 9000',
        '  Catatan: tanpa gula',
        'Teh',
        '  1 x 3000 = 3000',
      ]);
    });
  });

  group('ringkasan sesi', () {
    test('akumulator menjumlah transaksi dan msat', () {
      var s = StoreSessionSummary.empty;
      s = s.recordSale(BigInt.from(4975000));
      s = s.recordSale(BigInt.from(3000000));
      expect(s.saleCount, 2);
      expect(s.totalMsat, BigInt.from(7975000));
    });
  });

  group('breakpoint layout', () {
    test('di bawah 720 satu kolom, 720 ke atas dua panel', () {
      expect(storeModeUsesTwoPanels(719), isFalse);
      expect(storeModeUsesTwoPanels(720), isTrue);
      expect(storeModeUsesTwoPanels(1280), isTrue);
      expect(storeModeUsesTwoPanels(360), isFalse);
    });
  });
}
