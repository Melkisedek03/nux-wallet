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
      expect(keypadQuickAdd(storeKeypadMaxRp - 10, 50000), storeKeypadMaxRp);
    });

    test('digit melewati plafon rupiah 8 digit diabaikan', () {
      expect(keypadPressDigit(9999999, 9), 99999999);
      expect(keypadPressDigit(99999999, 9), 99999999);
      expect(keypadPressDoubleZero(9999999), 9999999);
    });
  });

  group('pesanan', () {
    OrderLine free(int amount, {int qty = 1}) =>
        OrderLine(label: 'Item Bebas', unitPriceRp: amount, qty: qty);

    test('tambah produk berkode sama menggabung qty', () {
      var lines = orderAddProduct(
        const [],
        code: 'A1',
        label: 'Kopi',
        unitPriceRp: 5000,
      );
      lines = orderAddProduct(
        lines,
        code: 'A1',
        label: 'Kopi',
        unitPriceRp: 5000,
      );
      lines = orderAddProduct(
        lines,
        code: 'B2',
        label: 'Teh',
        unitPriceRp: 3000,
      );
      expect(lines.length, 2);
      expect(lines[0].qty, 2);
      expect(orderGrandTotalRp(lines, null), 13000);
    });

    test('tambah bebas: nominal sama menggabung, beda jadi baris baru', () {
      var lines = orderAddFreeAmount(
        const [],
        label: 'Item Bebas',
        amountRp: 7000,
      );
      lines = orderAddFreeAmount(lines, label: 'Item Bebas', amountRp: 7000);
      lines = orderAddFreeAmount(lines, label: 'Item Bebas', amountRp: 2000);
      expect(lines.length, 2);
      expect(lines[0].qty, 2);
      expect(orderGrandTotalRp(lines, null), 16000);
      // Nominal 0 tidak menambah apa pun.
      expect(orderAddFreeAmount(lines, label: 'Item Bebas', amountRp: 0), lines);
      expect(free(1).qty, 1);
    });

    test('tambah bebas dengan pengali: baris baru & gabungan ikut qty', () {
      // Pengali tertunda berlaku untuk item bebas seperti katalog
      // (temuan lapangan NUX 3 Nov 2026).
      var lines = orderAddFreeAmount(
        const [],
        label: 'Item Bebas',
        amountRp: 7000,
        qty: 3,
      );
      expect(lines.single.qty, 3);
      // Baris yang sama menggabung sebesar pengali juga.
      lines = orderAddFreeAmount(
        lines,
        label: 'Item Bebas',
        amountRp: 7000,
        qty: 2,
      );
      expect(lines.single.qty, 5);
      expect(orderGrandTotalRp(lines, null), 35000);
      // qty < 1 dinormalkan ke 1.
      lines = orderAddFreeAmount(
        lines,
        label: 'Item Bebas',
        amountRp: 2000,
        qty: 0,
      );
      expect(lines.length, 2);
      expect(lines[1].qty, 1);
    });

    test('qty +/− dan hapus; kurang sampai 0 membuang baris', () {
      var lines = orderAddProduct(
        const [],
        code: 'A1',
        label: 'Kopi',
        unitPriceRp: 5000,
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
        amountRp: 2000,
      );
      lines = orderAddFreeAmount(
        lines,
        label: resolveFreeItemLabel('Parkir', fallbackLabel: 'Item Bebas'),
        amountRp: 2000,
      );
      lines = orderAddFreeAmount(
        lines,
        label: resolveFreeItemLabel('', fallbackLabel: 'Item Bebas'),
        amountRp: 2000,
      );
      expect(lines.length, 2);
      expect(lines[0].label, 'Parkir');
      expect(lines[0].qty, 2);
      expect(lines[1].label, 'Item Bebas');
    });
  });

  group('diskon', () {
    test('persen dibulatkan ke bawah ke rupiah bulat', () {
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
        unitPriceRp: 5000,
        qty: 2,
        discount: const Discount.percent(10),
      );
      expect(pct.lineGrossRp, 10000);
      expect(pct.lineDiscountRp, 1000);
      expect(pct.lineTotalRp, 9000);
      final fix = OrderLine(
        label: 'Teh',
        unitPriceRp: 3000,
        qty: 1,
        discount: const Discount.fixed(4500),
      );
      expect(fix.lineTotalRp, 0);
    });

    test('diskon bawaan katalog terisi ke baris dan bisa dihapus', () {
      var lines = orderAddProduct(
        const [],
        code: 'A1',
        label: 'Kopi',
        unitPriceRp: 5000,
        defaultDiscount: const Discount.percent(20),
      );
      expect(lines.single.discount, const Discount.percent(20));
      expect(lines.single.lineTotalRp, 4000);
      // Tambah lagi: qty naik, diskon baris dipertahankan.
      lines = orderAddProduct(
        lines,
        code: 'A1',
        label: 'Kopi',
        unitPriceRp: 5000,
        defaultDiscount: const Discount.percent(50),
      );
      expect(lines.single.qty, 2);
      expect(lines.single.discount, const Discount.percent(20));
      // Kasir menghapus diskon di baris.
      lines = orderSetLineDiscount(lines, 0, null);
      expect(lines.single.discount, isNull);
      expect(lines.single.lineTotalRp, 10000);
    });

    test('susunan hitung: diskon baris → subtotal → diskon order', () {
      final lines = [
        const OrderLine(
          label: 'Kopi',
          unitPriceRp: 5000,
          qty: 2,
          discount: Discount.percent(10), // −1.000
        ),
        const OrderLine(label: 'Teh', unitPriceRp: 3000, qty: 1),
      ];
      expect(orderGrossRp(lines), 13000);
      expect(orderSubtotalRp(lines), 12000);
      // Diskon order 25% dihitung dari subtotal 12.000 → 3.000.
      expect(orderDiscountAmountRp(lines, const Discount.percent(25)), 3000);
      expect(orderTotalDiscountRp(lines, const Discount.percent(25)), 4000);
      expect(orderGrandTotalRp(lines, const Discount.percent(25)), 9000);
      // Diskon order nominal.
      expect(orderGrandTotalRp(lines, const Discount.fixed(2000)), 10000);
    });

    test('total akhir berlantai 0 dan tidak pernah negatif', () {
      final lines = [const OrderLine(label: 'Teh', unitPriceRp: 3000, qty: 1)];
      expect(orderGrandTotalRp(lines, const Discount.fixed(999999)), 0);
      expect(orderGrandTotalRp(lines, const Discount.percent(100)), 0);
    });

    test('diskon poin terverifikasi mengurangi total sesudah diskon biasa', () {
      final lines = [const OrderLine(label: 'Teh', unitPriceRp: 9000, qty: 1)];
      expect(orderGrandTotalRp(lines, null, pointsDiscountRp: 4000), 5000);
      // Diskon poin melebihi sisa tetap berlantai 0.
      expect(orderGrandTotalRp(lines, null, pointsDiscountRp: 99999), 0);
    });
  });

  group('poin perolehan (model per kelipatan)', () {
    test('floor per kelipatan kali poin per kelipatan', () {
      expect(
        pointsEarnedFor(paidRp: 2500, stepRp: 1000, pointsPerStep: 1000),
        2000,
      );
      expect(
        pointsEarnedFor(paidRp: 3000, stepRp: 1000, pointsPerStep: 1000),
        3000,
      );
      expect(
        pointsEarnedFor(paidRp: 999, stepRp: 1000, pointsPerStep: 1000),
        0,
      );
      expect(
        pointsEarnedFor(paidRp: 10500, stepRp: 5000, pointsPerStep: 250),
        500,
      );
    });

    test('transaksi Rp0 (promosi) memperoleh 0 poin', () {
      expect(pointsEarnedFor(paidRp: 0, stepRp: 1000, pointsPerStep: 1000), 0);
    });

    test('parameter tak sah menghasilkan 0, bukan error', () {
      expect(pointsEarnedFor(paidRp: 5000, stepRp: 0, pointsPerStep: 1000), 0);
      expect(pointsEarnedFor(paidRp: 5000, stepRp: 1000, pointsPerStep: 0), 0);
      expect(pointsEarnedFor(paidRp: -5, stepRp: 1000, pointsPerStep: 1000), 0);
    });
  });

  group('poin penukaran (diskon rupiah)', () {
    test('nilai potong = poin × nilai per poin', () {
      expect(
        pointsDiscountRpFor(
          points: 500,
          rateRpPerPoint: 1,
          remainingRp: 10000,
          totalRp: 10000,
        ),
        500,
      );
      expect(
        pointsDiscountRpFor(
          points: 100,
          rateRpPerPoint: 5,
          remainingRp: 10000,
          totalRp: 10000,
        ),
        500,
      );
    });

    test('dijepit sisa tagihan — tidak pernah melebihi yang harus dibayar', () {
      expect(
        pointsDiscountRpFor(
          points: 20000,
          rateRpPerPoint: 1,
          remainingRp: 10000,
          totalRp: 10000,
        ),
        10000,
      );
    });

    test('batas maks persen dari total menjepit lebih dulu', () {
      // Plafon 10% × 10.000 = 1.000 < sisa 10.000.
      expect(
        pointsDiscountRpFor(
          points: 5000,
          rateRpPerPoint: 1,
          remainingRp: 10000,
          totalRp: 10000,
          maxPercent: 10,
        ),
        1000,
      );
    });

    test('poin/nilai tak sah menghasilkan 0', () {
      expect(
        pointsDiscountRpFor(
          points: 0,
          rateRpPerPoint: 1,
          remainingRp: 10000,
          totalRp: 10000,
        ),
        0,
      );
      expect(
        pointsDiscountRpFor(
          points: 500,
          rateRpPerPoint: 0,
          remainingRp: 10000,
          totalRp: 10000,
        ),
        0,
      );
      expect(
        pointsDiscountRpFor(
          points: 500,
          rateRpPerPoint: 1,
          remainingRp: 0,
          totalRp: 10000,
        ),
        0,
      );
    });

    test('poin maksimum yang berguna = floor plafon / nilai per poin', () {
      expect(
        maxRedeemablePoints(
          remainingRp: 10000,
          totalRp: 10000,
          rateRpPerPoint: 1,
        ),
        10000,
      );
      expect(
        maxRedeemablePoints(
          remainingRp: 10000,
          totalRp: 10000,
          rateRpPerPoint: 3,
        ),
        3333,
      );
      expect(
        maxRedeemablePoints(
          remainingRp: 10000,
          totalRp: 10000,
          rateRpPerPoint: 1,
          maxPercent: 10,
        ),
        1000,
      );
      expect(
        maxRedeemablePoints(
          remainingRp: 10000,
          totalRp: 10000,
          rateRpPerPoint: 0,
        ),
        0,
      );
    });
  });

  group('tunai', () {
    test('kembalian = diterima − harus dibayar', () {
      expect(cashChangeRp(receivedRp: 50000, dueRp: 47500), 2500);
      expect(cashChangeRp(receivedRp: 47500, dueRp: 47500), 0);
      // Kurang bayar = kembalian negatif (belum lunas).
      expect(cashChangeRp(receivedRp: 40000, dueRp: 47500), -7500);
    });

    test('bisa lunas hanya bila diterima menutupi sisa', () {
      expect(cashCanSettle(receivedRp: 47500, dueRp: 47500), isTrue);
      expect(cashCanSettle(receivedRp: 50000, dueRp: 47500), isTrue);
      expect(cashCanSettle(receivedRp: 47499, dueRp: 47500), isFalse);
      expect(cashCanSettle(receivedRp: 0, dueRp: 0), isTrue);
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
        unitPriceRp: 5000,
        qty: 2,
      );
      expect(lines.single.qty, 2);
      lines = orderAddProduct(
        lines,
        code: 'A1',
        label: 'Kopi',
        unitPriceRp: 5000,
        qty: 3,
      );
      expect(lines.single.qty, 5);
      expect(orderGrandTotalRp(lines, null), 25000);
      // Tanpa parameter qty tetap 1 (perilaku lama).
      lines = orderAddProduct(lines, code: 'B2', label: 'Teh', unitPriceRp: 3000);
      expect(lines.last.qty, 1);
    });
  });

  group('catatan baris', () {
    test('pasang, ganti (trim), dan hapus catatan', () {
      var lines = orderAddProduct(
        const [],
        code: 'A1',
        label: 'Kopi',
        unitPriceRp: 5000,
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
      const a = OrderLine(label: 'Kopi', unitPriceRp: 5000, qty: 1);
      const b = OrderLine(
        label: 'Kopi',
        unitPriceRp: 5000,
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
            unitPriceRp: 5000,
            qty: 2,
            discount: Discount.percent(10),
            note: 'tanpa gula',
          ),
          OrderLine(label: 'Teh', unitPriceRp: 3000, qty: 1),
        ],
        formatRp: (n) => n.toString(),
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
    test('akumulator menjumlah transaksi dan rupiah', () {
      var s = StoreSessionSummary.empty;
      s = s.recordSale(4975);
      s = s.recordSale(3000);
      expect(s.saleCount, 2);
      expect(s.totalRp, 7975);
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
