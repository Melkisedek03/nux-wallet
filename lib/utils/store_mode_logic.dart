/// Logika murni Mode Toko v2 (PoS kasir): keypad, daftar baris
/// pesanan, hitungan rupiah, dan hitungan poin loyalitas.
///
/// Semua di file ini bebas efek samping dan teruji unit — layar
/// Mode Toko (store_mode_screen.dart) hanya menyambungkan hasil
/// keputusan di sini ke widget dan ke node.
///
/// KERANGKA HUKUM (Pedoman miniPOS tim, 3 Nov 2026): rupiah
/// adalah alat pembayaran; nusan adalah POIN loyalitas. Karena
/// itu seluruh nominal belanja di file ini berdenominasi RUPIAH
/// bulat, dan "poin" (satuannya nusan) hanya muncul pada dua
/// hitungan loyalitas: perolehan poin dari rupiah yang dibayar,
/// dan potongan rupiah dari penukaran poin. Tidak ada hitungan
/// di sini yang melunasi belanja dengan poin.
///
/// Satu sumber kebenaran nominal penjualan adalah DAFTAR BARIS
/// pesanan: keypad hanya pengisi satu baris "item bebas", tombol
/// jumlah cepat hanya menambah nilai keypad, dan total akhir
/// selalu [orderGrandTotalRp] dari baris-baris itu.
library;

/// Penanda era record/shift Mode Toko: 'nusan' = era v1 (kasir
/// nusan, sebelum pivot), 'rp' = era v2 (kasir rupiah). Laporan
/// v2 HANYA membaca record era 'rp' — dua era tidak pernah
/// dicampur dalam satu angka laporan.
const storeEraNusan = 'nusan';
const storeEraRupiah = 'rp';

/// Lebar (dp) minimal untuk layout dua panel Mode Toko: di bawah
/// ini satu kolom (kasir di atas, status/QR di bawah, boleh
/// scroll); di atasnya dua panel berdampingan (kiri kasir, kanan
/// QR + status + ringkasan selalu terlihat) — pola tablet
/// landscape dari desain yang disetujui NUX 2 Nov 2026.
const storeModeTwoPanelBreakpoint = 720.0;

/// Haruskah Mode Toko memakai layout dua panel pada [width] dp?
bool storeModeUsesTwoPanels(double width) =>
    width >= storeModeTwoPanelBreakpoint;

/// Plafon nominal keypad (rupiah): Rp99.999.999 — jauh di atas
/// harga & uang tunai ritel UMKM mana pun, dan menahan nominal
/// yang jelas-jelas salah ketik sebelum jadi pesanan/pembayaran.
const storeKeypadMaxRp = 99999999;

/// Tekan satu digit (0–9) pada keypad: digit ditambahkan di kanan.
/// Tekanan yang melewati [storeKeypadMaxRp] diabaikan.
int keypadPressDigit(int current, int digit) {
  final next = current * 10 + digit;
  return next > storeKeypadMaxRp ? current : next;
}

/// Tekan "00" pada keypad: dua nol sekaligus. Pada nilai 0 tetap 0
/// (tidak ada "00" yatim di tampilan); melewati plafon diabaikan.
int keypadPressDoubleZero(int current) {
  if (current == 0) return 0;
  final next = current * 100;
  return next > storeKeypadMaxRp ? current : next;
}

/// Hapus satu digit paling kanan; pada 0 tetap 0.
int keypadBackspace(int current) => current ~/ 10;

/// Tombol jumlah cepat: MENAMBAH [quick] ke nilai keypad saat ini,
/// terpotong di [storeKeypadMaxRp].
int keypadQuickAdd(int current, int quick) {
  final next = current + quick;
  return next > storeKeypadMaxRp ? storeKeypadMaxRp : next;
}

/// Plafon pengali qty keypad mode Qty: 999 — pesanan toko ritel
/// tidak pernah butuh pengali lebih besar dari itu, dan angka
/// yang lebih besar hampir pasti salah ketuk.
const storeMaxQtyMultiplier = 999;

/// Tekan satu digit (0–9) pada keypad mode Qty: digit ditambahkan
/// di kanan nilai pengali. Tekanan yang melewati
/// [storeMaxQtyMultiplier] diabaikan. Nilai 0 berarti "belum
/// diatur" — pengali efektifnya 1 (lihat layar kasir).
int qtyMultiplierPressDigit(int current, int digit) {
  final next = current * 10 + digit;
  return next > storeMaxQtyMultiplier ? current : next;
}

/// Tekan "00" pada keypad mode Qty: dua nol sekaligus, aturan
/// sama seperti nominal ([keypadPressDoubleZero]) tetapi dengan
/// plafon pengali.
int qtyMultiplierPressDoubleZero(int current) {
  if (current == 0) return 0;
  final next = current * 100;
  return next > storeMaxQtyMultiplier ? current : next;
}

/// Bentuk diskon — kasir memilih salah satu per pemakaian.
enum DiscountKind {
  /// Persen dari nilai yang didiskon (0–100).
  percent,

  /// Nominal rupiah tetap.
  fixed,
}

/// Satu diskon: persen ATAU nominal, tidak pernah keduanya.
/// Dipakai seragam di tiga tempat: bawaan produk katalog, baris
/// pesanan, dan diskon order — aturan hitungnya satu ([discountAmountFor]).
class Discount {
  final DiscountKind kind;

  /// Persen (0–100) bila [kind] persen; rupiah bila nominal.
  final int value;

  const Discount.percent(int percent)
    : kind = DiscountKind.percent,
      value = percent;

  const Discount.fixed(int rp) : kind = DiscountKind.fixed, value = rp;

  @override
  bool operator ==(Object other) =>
      other is Discount && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// Besaran potongan (rupiah bulat) dari [discount] atas [baseRp].
///
/// Aturan angka Mode Toko: semua hitung di domain rupiah bulat;
/// persen dibulatkan ke BAWAH (floor(base × persen / 100));
/// nominal dibatasi maksimal sebesar nilai yang didiskon;
/// hasilnya tidak pernah negatif dan tidak pernah melebihi
/// [baseRp]. Diskon null/nol → 0.
int discountAmountFor(int baseRp, Discount? discount) {
  if (discount == null || baseRp <= 0 || discount.value <= 0) return 0;
  return switch (discount.kind) {
    DiscountKind.percent =>
      discount.value >= 100 ? baseRp : (baseRp * discount.value) ~/ 100,
    DiscountKind.fixed => discount.value >= baseRp ? baseRp : discount.value,
  };
}

/// Satu baris pesanan Mode Toko.
///
/// Baris produk katalog membawa [code] (isi barcode/QR produk)
/// supaya scan/ketuk berulang menggabung ke baris yang sama; baris
/// bebas (dari keypad) [code]-nya null dan menggabung hanya bila
/// label + harga satuannya sama persis. Semua harga dalam RUPIAH.
class OrderLine {
  final String? code;
  final String label;
  final int unitPriceRp;
  final int qty;

  /// Kategori produk saat baris dibuat (snapshot dari katalog;
  /// '' = tanpa kategori → kelompok LAINNYA di laporan). Baris
  /// bebas selalu ''. Perubahan kategori di katalog belakangan
  /// tidak mengubah baris yang sudah ada — laporan membaca
  /// snapshot ini, bukan keadaan katalog terbaru.
  final String category;

  /// Diskon baris ini (persen atau nominal), null = tanpa diskon.
  /// Untuk baris produk, awalnya terisi dari diskon bawaan katalog
  /// lalu bebas diubah/dihapus kasir di baris.
  final Discount? discount;

  /// Catatan khusus kasir untuk baris ini (mis. "tanpa gula",
  /// "bungkus terpisah") — teks bebas singkat, '' = tanpa catatan.
  /// Tampil di bawah label baris di layar kasir dan tercetak di
  /// struk pelanggan di bawah itemnya. Catatan TIDAK ikut
  /// pengelompokan laporan (kelompok tetap (kategori, label,
  /// harga satuan)) dan tidak memengaruhi hitungan apa pun.
  final String note;

  const OrderLine({
    this.code,
    required this.label,
    required this.unitPriceRp,
    required this.qty,
    this.category = '',
    this.discount,
    this.note = '',
  });

  /// Harga × qty sebelum diskon baris.
  int get lineGrossRp => unitPriceRp * qty;

  /// Potongan baris ini (rupiah).
  int get lineDiscountRp => discountAmountFor(lineGrossRp, discount);

  /// Yang dibayar pembeli untuk baris ini: bruto − diskon baris.
  int get lineTotalRp => lineGrossRp - lineDiscountRp;

  OrderLine copyWith({
    int? qty,
    Discount? discount,
    bool clearDiscount = false,
    String? note,
  }) => OrderLine(
    code: code,
    label: label,
    unitPriceRp: unitPriceRp,
    qty: qty ?? this.qty,
    category: category,
    discount: clearDiscount ? null : (discount ?? this.discount),
    note: note ?? this.note,
  );

  @override
  bool operator ==(Object other) =>
      other is OrderLine &&
      other.code == code &&
      other.label == label &&
      other.unitPriceRp == unitPriceRp &&
      other.qty == qty &&
      other.category == category &&
      other.discount == discount &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(code, label, unitPriceRp, qty, category, discount, note);
}

/// Tambah satu produk katalog ke pesanan: baris berkode sama yang
/// sudah ada bertambah qty-nya sebesar [qty] (urutan
/// dipertahankan; diskon yang sudah diedit kasir di baris itu
/// dipertahankan), selain itu baris baru ditambahkan di akhir
/// dengan qty sebesar [qty] dan [defaultDiscount] dari katalog
/// (boleh null). [qty] bawaan 1; keypad mode Qty meneruskan
/// pengali aktifnya ke sini. qty < 1 dijepit ke 1.
List<OrderLine> orderAddProduct(
  List<OrderLine> lines, {
  required String code,
  required String label,
  required int unitPriceRp,
  String category = '',
  Discount? defaultDiscount,
  int qty = 1,
}) {
  final addQty = qty < 1 ? 1 : qty;
  final idx = lines.indexWhere((l) => l.code == code);
  if (idx < 0) {
    return [
      ...lines,
      OrderLine(
        code: code,
        label: label,
        unitPriceRp: unitPriceRp,
        qty: addQty,
        category: category,
        discount: defaultDiscount,
      ),
    ];
  }
  final next = [...lines];
  next[idx] = next[idx].copyWith(qty: next[idx].qty + addQty);
  return next;
}

/// Pasang/ganti catatan baris ke-[index] (teks sesudah trim;
/// string kosong = catatan dihapus). Indeks di luar jangkauan
/// diabaikan.
List<OrderLine> orderSetLineNote(List<OrderLine> lines, int index, String note) {
  if (index < 0 || index >= lines.length) return lines;
  final next = [...lines];
  next[index] = next[index].copyWith(note: note.trim());
  return next;
}

/// Pasang/ganti diskon baris ke-[index]; [discount] null (atau
/// panggil [orderClearLineDiscount]) menghapusnya. Indeks di luar
/// jangkauan diabaikan.
List<OrderLine> orderSetLineDiscount(
  List<OrderLine> lines,
  int index,
  Discount? discount,
) {
  if (index < 0 || index >= lines.length) return lines;
  final next = [...lines];
  next[index] = discount == null
      ? next[index].copyWith(clearDiscount: true)
      : next[index].copyWith(discount: discount);
  return next;
}

/// Tambah satu baris nominal bebas dari keypad. Baris bebas dengan
/// label + nominal yang sama menggabung (qty +1); nominal berbeda
/// jadi baris sendiri supaya kasir bisa mengoreksi per baris.
/// Nominal <= 0 tidak menambah apa pun.
List<OrderLine> orderAddFreeAmount(
  List<OrderLine> lines, {
  required String label,
  required int amountRp,
}) {
  if (amountRp <= 0) return lines;
  final idx = lines.indexWhere(
    (l) =>
        l.code == null &&
        l.label == label &&
        l.unitPriceRp == amountRp &&
        l.discount == null,
  );
  if (idx < 0) {
    return [
      ...lines,
      OrderLine(label: label, unitPriceRp: amountRp, qty: 1),
    ];
  }
  final next = [...lines];
  next[idx] = next[idx].copyWith(qty: next[idx].qty + 1);
  return next;
}

/// Label baris untuk satu nominal bebas: judul kustom kasir
/// (sesudah trim) bila ia mengisinya, selain itu [fallbackLabel]
/// ("Item Bebas" dari l10n). Judul kustom adalah jalan untuk
/// barang/jasa yang belum terinput di katalog — barisnya tetap
/// terbaca jelas di pesanan, struk, dan laporan. Penggabungan
/// baris bebas mengikuti aturan yang sudah ada di
/// [orderAddFreeAmount] (label + nominal sama menggabung), jadi
/// judul berbeda memang membentuk baris berbeda.
String resolveFreeItemLabel(String rawTitle, {required String fallbackLabel}) {
  final trimmed = rawTitle.trim();
  return trimmed.isEmpty ? fallbackLabel : trimmed;
}

/// Ubah qty baris ke-[index] sebesar [delta] (+1/−1). Hasil qty
/// <= 0 menghapus barisnya — kasir mengurangi sampai habis memang
/// bermaksud membuang baris itu. Indeks di luar jangkauan diabaikan.
List<OrderLine> orderChangeQty(List<OrderLine> lines, int index, int delta) {
  if (index < 0 || index >= lines.length) return lines;
  final newQty = lines[index].qty + delta;
  if (newQty <= 0) return orderRemoveLine(lines, index);
  final next = [...lines];
  next[index] = next[index].copyWith(qty: newQty);
  return next;
}

/// Hapus baris ke-[index]; indeks di luar jangkauan diabaikan.
List<OrderLine> orderRemoveLine(List<OrderLine> lines, int index) {
  if (index < 0 || index >= lines.length) return lines;
  return [...lines]..removeAt(index);
}

/// Total pesanan SEBELUM diskon apa pun (Σ harga × qty).
int orderGrossRp(List<OrderLine> lines) =>
    lines.fold(0, (sum, l) => sum + l.lineGrossRp);

/// Subtotal: Σ baris SESUDAH diskon baris masing-masing. Inilah
/// nilai yang didiskon oleh diskon order dan diskon poin.
int orderSubtotalRp(List<OrderLine> lines) =>
    lines.fold(0, (sum, l) => sum + l.lineTotalRp);

/// Potongan diskon order atas [lines] (dihitung dari subtotal).
int orderDiscountAmountRp(List<OrderLine> lines, Discount? orderDiscount) =>
    discountAmountFor(orderSubtotalRp(lines), orderDiscount);

/// Total diskon keseluruhan: diskon baris + diskon order. Angka
/// ini yang ditampilkan terpisah di ringkasan & struk — tidak
/// disembunyikan di dalam angka akhir. (Diskon POIN dihitung
/// terpisah oleh [pointsDiscountRpFor] dan ditambahkan pemanggil
/// bila ada penukaran terverifikasi.)
int orderTotalDiscountRp(List<OrderLine> lines, Discount? orderDiscount) =>
    lines.fold(0, (sum, l) => sum + l.lineDiscountRp) +
    orderDiscountAmountRp(lines, orderDiscount);

/// Sisa yang harus dibayar rupiah SEBELUM penukaran poin:
/// subtotal − diskon order, berlantai 0.
int orderDueRp(List<OrderLine> lines, Discount? orderDiscount) {
  final due = orderSubtotalRp(lines) - orderDiscountAmountRp(lines, orderDiscount);
  return due < 0 ? 0 : due;
}

/// Total akhir pesanan (rupiah) — satu-satunya nominal yang
/// dilunasi pembeli dalam rupiah. Urutan hitung tetap:
/// baris (harga × qty − diskon baris) → subtotal → diskon order
/// → diskon poin terverifikasi ([pointsDiscountRp], bawaan 0)
/// → total akhir, berlantai 0 (tidak pernah negatif).
int orderGrandTotalRp(
  List<OrderLine> lines,
  Discount? orderDiscount, {
  int pointsDiscountRp = 0,
}) {
  final total = orderDueRp(lines, orderDiscount) - pointsDiscountRp;
  return total < 0 ? 0 : total;
}

// ---------------------------------------------------------------------
// Poin loyalitas (pedoman: nusan = poin, BUKAN alat pembayaran)
// ---------------------------------------------------------------------

/// Poin nusan yang DIPEROLEH dari satu transaksi lunas — model
/// PER KELIPATAN (keputusan NUX 3 Nov 2026): tiap [stepRp] rupiah
/// yang benar-benar dibayar memberi [pointsPerStep] poin.
/// Perolehan = floor(rupiahDibayar / kelipatan) × poinPerKelipatan.
/// Basis [paidRp] adalah total rupiah yang sungguh dibayar
/// pembeli sesudah SEMUA diskon (termasuk diskon poin) — jadi
/// transaksi promosi Rp0 memberi 0 poin. Parameter tak sah
/// (kelipatan/poin per kelipatan <= 0) → 0 poin.
int pointsEarnedFor({
  required int paidRp,
  required int stepRp,
  required int pointsPerStep,
}) {
  if (paidRp <= 0 || stepRp <= 0 || pointsPerStep <= 0) return 0;
  return (paidRp ~/ stepRp) * pointsPerStep;
}

/// Nilai potongan (rupiah) dari penukaran [points] poin:
/// points × [rateRpPerPoint] ("nilai potongan per poin" milik
/// toko — parameter diskon, BUKAN kurs), dijepit oleh:
/// - [remainingRp]: sisa yang harus dibayar sesudah diskon biasa
///   (diskon poin tidak pernah melebihi sisa tagihan), dan
/// - [maxPercent] (bila diatur): persen maksimum dari [totalRp]
///   (total sesudah diskon baris & order, sebelum diskon poin).
/// Hasil tidak pernah negatif. Poin/nilai tak sah → 0.
int pointsDiscountRpFor({
  required int points,
  required int rateRpPerPoint,
  required int remainingRp,
  required int totalRp,
  int? maxPercent,
}) {
  if (points <= 0 || rateRpPerPoint <= 0 || remainingRp <= 0) return 0;
  var cap = remainingRp;
  if (maxPercent != null) {
    final pctCap = (totalRp * maxPercent) ~/ 100;
    if (pctCap < cap) cap = pctCap;
  }
  final raw = points * rateRpPerPoint;
  return raw < cap ? raw : cap;
}

/// Jumlah poin MAKSIMUM yang berguna ditukar pada satu transaksi:
/// poin di atas ini nilai potongannya akan terjepit plafon
/// [pointsDiscountRpFor] — pelanggan akan menyerahkan poin tanpa
/// potongan tambahan, jadi kasir dicegah menukarkan lebih dari
/// ini. Dihitung floor(plafon rupiah / nilai per poin) supaya
/// tidak pernah melampaui plafon.
int maxRedeemablePoints({
  required int remainingRp,
  required int totalRp,
  required int rateRpPerPoint,
  int? maxPercent,
}) {
  if (rateRpPerPoint <= 0 || remainingRp <= 0) return 0;
  var cap = remainingRp;
  if (maxPercent != null) {
    final pctCap = (totalRp * maxPercent) ~/ 100;
    if (pctCap < cap) cap = pctCap;
  }
  return cap ~/ rateRpPerPoint;
}

// ---------------------------------------------------------------------
// Tunai
// ---------------------------------------------------------------------

/// Kembalian tunai: uang diterima − yang harus dibayar. Negatif
/// berarti uangnya belum cukup (belum bisa lunas).
int cashChangeRp({required int receivedRp, required int dueRp}) =>
    receivedRp - dueRp;

/// Bolehkah transaksi tunai dilunasi sekarang? Hanya bila uang
/// diterima menutupi sisa bayar (kembalian >= 0).
bool cashCanSettle({required int receivedRp, required int dueRp}) =>
    receivedRp >= dueRp;

/// Baris-baris rincian struk pelanggan untuk satu pesanan lunas:
/// per baris pesanan — label item, lalu "qty × harga satuan =
/// total baris" (total SESUDAH diskon baris) menjorok dua spasi,
/// dan catatan baris (bila ada) sebagai baris menjorok
/// "<noteWord>: <catatan>" tepat di bawah itemnya. [formatRp]
/// adalah pemformat rupiah layar; [noteWord] kata
/// "Catatan"/"Note" dari l10n. Teks mentah apa adanya —
/// pemanggil (PrintService) yang membersihkan non-ASCII.
List<String> orderReceiptDetailLines(
  List<OrderLine> lines, {
  required String Function(int rp) formatRp,
  required String noteWord,
}) {
  final out = <String>[];
  for (final line in lines) {
    out.add(line.label);
    out.add(
      '  ${line.qty} x ${formatRp(line.unitPriceRp)}'
      ' = ${formatRp(line.lineTotalRp)}',
    );
    if (line.note.isNotEmpty) out.add('  $noteWord: ${line.note}');
  }
  return out;
}

/// Ringkasan penjualan selama kasir berada di Mode Toko.
///
/// JUJUR soal cakupan: ini akumulator sesi di memori layar ini
/// saja — nol lagi setiap Mode Toko dibuka, bukan laporan harian
/// dan bukan catatan resmi (catatan resmi tetap record penjualan
/// tersimpan). Label di layar menyatakannya sebagai "Sesi Ini".
/// Total dalam RUPIAH (total akhir penjualan lunas sesi ini).
class StoreSessionSummary {
  final int saleCount;
  final int totalRp;

  const StoreSessionSummary({this.saleCount = 0, this.totalRp = 0});

  static const empty = StoreSessionSummary();

  /// Catat satu penjualan yang sungguh lunas sebesar [totalRp]
  /// (dipanggil hanya dari penyelesaian pembayaran rupiah yang
  /// tercatat, tidak dari peristiwa lain).
  StoreSessionSummary recordSale(int totalRp) => StoreSessionSummary(
    saleCount: saleCount + 1,
    totalRp: this.totalRp + totalRp,
  );

  @override
  bool operator ==(Object other) =>
      other is StoreSessionSummary &&
      other.saleCount == saleCount &&
      other.totalRp == totalRp;

  @override
  int get hashCode => Object.hash(saleCount, totalRp);
}
