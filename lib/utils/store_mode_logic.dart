/// Logika murni Mode Toko (PoS kasir): keypad nominal bebas,
/// daftar baris pesanan, ringkasan sesi, dan keputusan layout.
///
/// Semua di file ini bebas efek samping dan teruji unit — layar
/// Mode Toko (store_mode_screen.dart) hanya menyambungkan hasil
/// keputusan di sini ke widget dan ke node.
///
/// Satu sumber kebenaran nominal penjualan adalah DAFTAR BARIS
/// pesanan: keypad hanya pengisi satu baris "item bebas", tombol
/// jumlah cepat hanya menambah nilai keypad, dan total yang dibuat
/// kode bayar selalu [orderTotalNusan] dari baris-baris itu.
library;

/// Lebar (dp) minimal untuk layout dua panel Mode Toko: di bawah
/// ini satu kolom (kasir di atas, status/QR di bawah, boleh
/// scroll); di atasnya dua panel berdampingan (kiri kasir, kanan
/// QR + status + ringkasan selalu terlihat) — pola tablet
/// landscape dari desain yang disetujui NUX 2 Nov 2026.
const storeModeTwoPanelBreakpoint = 720.0;

/// Haruskah Mode Toko memakai layout dua panel pada [width] dp?
bool storeModeUsesTwoPanels(double width) =>
    width >= storeModeTwoPanelBreakpoint;

/// Plafon nominal keypad (nusan): 9 digit. Cukup untuk harga UMKM
/// mana pun, dan menahan nominal yang jelas-jelas salah ketik
/// sebelum jadi invoice.
const storeKeypadMaxNusan = 999999999;

/// Tekan satu digit (0–9) pada keypad: digit ditambahkan di kanan.
/// Tekanan yang melewati [storeKeypadMaxNusan] diabaikan.
int keypadPressDigit(int current, int digit) {
  final next = current * 10 + digit;
  return next > storeKeypadMaxNusan ? current : next;
}

/// Tekan "00" pada keypad: dua nol sekaligus. Pada nilai 0 tetap 0
/// (tidak ada "00" yatim di tampilan); melewati plafon diabaikan.
int keypadPressDoubleZero(int current) {
  if (current == 0) return 0;
  final next = current * 100;
  return next > storeKeypadMaxNusan ? current : next;
}

/// Hapus satu digit paling kanan; pada 0 tetap 0.
int keypadBackspace(int current) => current ~/ 10;

/// Tombol jumlah cepat: MENAMBAH [quick] ke nilai keypad saat ini,
/// terpotong di [storeKeypadMaxNusan].
int keypadQuickAdd(int current, int quick) {
  final next = current + quick;
  return next > storeKeypadMaxNusan ? storeKeypadMaxNusan : next;
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

  /// Nominal nusan tetap.
  fixed,
}

/// Satu diskon: persen ATAU nominal, tidak pernah keduanya.
/// Dipakai seragam di tiga tempat: bawaan produk katalog, baris
/// pesanan, dan diskon order — aturan hitungnya satu ([discountAmountFor]).
class Discount {
  final DiscountKind kind;

  /// Persen (0–100) bila [kind] persen; nusan bila nominal.
  final int value;

  const Discount.percent(int percent)
    : kind = DiscountKind.percent,
      value = percent;

  const Discount.fixed(int nusan) : kind = DiscountKind.fixed, value = nusan;

  @override
  bool operator ==(Object other) =>
      other is Discount && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// Besaran potongan (nusan bulat) dari [discount] atas [baseNusan].
///
/// Aturan angka Mode Toko (keputusan NUX 3 Nov 2026): semua hitung
/// di domain nusan bulat; persen dibulatkan ke BAWAH
/// (floor(base × persen / 100)); nominal dibatasi maksimal sebesar
/// nilai yang didiskon; hasilnya tidak pernah negatif dan tidak
/// pernah melebihi [baseNusan]. Diskon null/nol → 0.
int discountAmountFor(int baseNusan, Discount? discount) {
  if (discount == null || baseNusan <= 0 || discount.value <= 0) return 0;
  return switch (discount.kind) {
    DiscountKind.percent =>
      discount.value >= 100 ? baseNusan : (baseNusan * discount.value) ~/ 100,
    DiscountKind.fixed =>
      discount.value >= baseNusan ? baseNusan : discount.value,
  };
}

/// Satu baris pesanan Mode Toko.
///
/// Baris produk katalog membawa [code] (isi barcode/QR produk)
/// supaya scan/ketuk berulang menggabung ke baris yang sama; baris
/// bebas (dari keypad) [code]-nya null dan menggabung hanya bila
/// label + harga satuannya sama persis.
class OrderLine {
  final String? code;
  final String label;
  final int unitPriceNusan;
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
    required this.unitPriceNusan,
    required this.qty,
    this.category = '',
    this.discount,
    this.note = '',
  });

  /// Harga × qty sebelum diskon baris.
  int get lineGrossNusan => unitPriceNusan * qty;

  /// Potongan baris ini (nusan).
  int get lineDiscountNusan => discountAmountFor(lineGrossNusan, discount);

  /// Yang dibayar pembeli untuk baris ini: bruto − diskon baris.
  int get lineTotalNusan => lineGrossNusan - lineDiscountNusan;

  OrderLine copyWith({
    int? qty,
    Discount? discount,
    bool clearDiscount = false,
    String? note,
  }) => OrderLine(
    code: code,
    label: label,
    unitPriceNusan: unitPriceNusan,
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
      other.unitPriceNusan == unitPriceNusan &&
      other.qty == qty &&
      other.category == category &&
      other.discount == discount &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(code, label, unitPriceNusan, qty, category, discount, note);
}

/// Tambah satu produk katalog ke pesanan: baris berkode sama yang
/// sudah ada bertambah qty-nya sebesar [qty] (urutan
/// dipertahankan; diskon yang sudah diedit kasir di baris itu
/// dipertahankan), selain itu baris baru ditambahkan di akhir
/// dengan qty sebesar [qty] dan [defaultDiscount] dari katalog
/// (boleh null). [qty] bawaan 1 — perilaku lama; keypad mode Qty
/// meneruskan pengali aktifnya ke sini. qty < 1 dijepit ke 1.
List<OrderLine> orderAddProduct(
  List<OrderLine> lines, {
  required String code,
  required String label,
  required int unitPriceNusan,
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
        unitPriceNusan: unitPriceNusan,
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
  required int amountNusan,
}) {
  if (amountNusan <= 0) return lines;
  final idx = lines.indexWhere(
    (l) =>
        l.code == null &&
        l.label == label &&
        l.unitPriceNusan == amountNusan &&
        l.discount == null,
  );
  if (idx < 0) {
    return [
      ...lines,
      OrderLine(label: label, unitPriceNusan: amountNusan, qty: 1),
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
int orderGrossNusan(List<OrderLine> lines) =>
    lines.fold(0, (sum, l) => sum + l.lineGrossNusan);

/// Subtotal: Σ baris SESUDAH diskon baris masing-masing. Inilah
/// nilai yang didiskon oleh diskon order.
int orderSubtotalNusan(List<OrderLine> lines) =>
    lines.fold(0, (sum, l) => sum + l.lineTotalNusan);

/// Potongan diskon order atas [lines] (dihitung dari subtotal).
int orderDiscountAmountNusan(List<OrderLine> lines, Discount? orderDiscount) =>
    discountAmountFor(orderSubtotalNusan(lines), orderDiscount);

/// Total diskon keseluruhan: diskon baris + diskon order. Angka
/// ini yang ditampilkan terpisah di ringkasan & struk — tidak
/// disembunyikan di dalam angka akhir.
int orderTotalDiscountNusan(List<OrderLine> lines, Discount? orderDiscount) =>
    lines.fold(0, (sum, l) => sum + l.lineDiscountNusan) +
    orderDiscountAmountNusan(lines, orderDiscount);

/// Total akhir pesanan (nusan) — satu-satunya nominal yang boleh
/// dibuat kode bayar oleh Mode Toko. Urutan hitung tetap:
/// baris (harga × qty − diskon baris) → subtotal → diskon order →
/// total akhir, berlantai 0 (tidak pernah negatif).
int orderGrandTotalNusan(List<OrderLine> lines, Discount? orderDiscount) {
  final total =
      orderSubtotalNusan(lines) -
      orderDiscountAmountNusan(lines, orderDiscount);
  return total < 0 ? 0 : total;
}

/// Baris-baris rincian struk pelanggan untuk satu pesanan lunas:
/// per baris pesanan — label item, lalu "qty × harga satuan =
/// total baris" (total SESUDAH diskon baris) menjorok dua spasi,
/// dan catatan baris (bila ada) sebagai baris menjorok
/// "<noteWord>: <catatan>" tepat di bawah itemnya. [formatNusan]
/// adalah pemformat angka layar (pemisah ribuan aplikasi);
/// [noteWord] kata "Catatan"/"Note" dari l10n. Teks mentah apa
/// adanya — pemanggil (PrintService) yang membersihkan non-ASCII.
List<String> orderReceiptDetailLines(
  List<OrderLine> lines, {
  required String Function(int nusan) formatNusan,
  required String noteWord,
}) {
  final out = <String>[];
  for (final line in lines) {
    out.add(line.label);
    out.add(
      '  ${line.qty} x ${formatNusan(line.unitPriceNusan)}'
      ' = ${formatNusan(line.lineTotalNusan)}',
    );
    if (line.note.isNotEmpty) out.add('  $noteWord: ${line.note}');
  }
  return out;
}

/// Ringkasan penjualan selama kasir berada di Mode Toko.
///
/// JUJUR soal cakupan: ini akumulator sesi di memori layar ini
/// saja — nol lagi setiap Mode Toko dibuka, bukan laporan harian
/// dan bukan catatan resmi (catatan resmi tetap Riwayat node).
/// Label di layar menyatakannya sebagai "Sesi Ini".
class StoreSessionSummary {
  final int saleCount;
  final BigInt totalMsat;

  const StoreSessionSummary({this.saleCount = 0, required this.totalMsat});

  static final empty = StoreSessionSummary(totalMsat: BigInt.zero);

  /// Catat satu penjualan yang sungguh diterima sebesar
  /// [amountMsat] (dipanggil hanya dari event penerimaan nyata).
  StoreSessionSummary recordSale(BigInt amountMsat) => StoreSessionSummary(
    saleCount: saleCount + 1,
    totalMsat: totalMsat + amountMsat,
  );

  @override
  bool operator ==(Object other) =>
      other is StoreSessionSummary &&
      other.saleCount == saleCount &&
      other.totalMsat == totalMsat;

  @override
  int get hashCode => Object.hash(saleCount, totalMsat);
}
