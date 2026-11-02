/// Pembaca info dasar offer BOLT12 (kode bayar `lno1…`) untuk
/// layar Kirim.
///
/// ELNUX perlu tiga hal dari offer yang ditempel/dipindai
/// pengguna SEBELUM pembayaran dicoba, karena binding node hanya
/// menerima offer sebagai string utuh tanpa pembaca field:
///
/// 1. **nominal** — offer bernominal tetap dibayar apa adanya
///    lewat `send` node; offer tanpa nominal (variable-amount,
///    seperti Kode Bayar Statis ELNUX) wajib diisi pembayar lalu
///    dibayar lewat `sendUsingAmount`. Nominal juga bahan
///    pemeriksaan pra-bayar terhadap saldo & kapasitas kirim.
/// 2. **kedaluwarsa** — offer bisa membawa batas waktu absolut;
///    yang sudah lewat harus ditolak dengan pesan yang benar,
///    bukan pesan generik.
/// 3. **mata uang** — offer berdenominasi mata uang asing tidak
///    bisa dibayar node (UnsupportedCurrency); kenali di sini
///    supaya pesannya jelas.
///
/// Batas kejujuran parser ini: pengkodean offer BOLT12 adalah
/// bech32 TANPA checksum (terverifikasi dari source rust-lightning
/// fork: trait Bech32Encode memakai varian NoChecksum), jadi tidak
/// ada checksum yang bisa diverifikasi seperti invoice Bolt11.
/// Yang diperiksa di sini hanyalah struktur: karakter bech32 sah,
/// bit terkonversi utuh, dan rekaman TLV berjalan rapi sampai
/// akhir persis. Tanda tangan offer TIDAK diperiksa — node tetap
/// penentu akhir sah/tidaknya offer saat pembayaran dijalankan,
/// dan parser ini fail-open terhadap rekaman TLV yang tidak
/// dikenal (dilewati, bukan ditolak).
library;

import 'dart:convert';

/// Info hasil baca offer: nominal (null = pembayar menentukan),
/// deskripsi, batas kedaluwarsa absolut, dan penanda denominasi
/// mata uang asing.
class Bolt12OfferInfo {
  /// Nominal tetap offer dalam msat; null bila offer tidak
  /// menetapkan nominal (variable-amount).
  final BigInt? amountMsat;

  /// Deskripsi offer dari penerbitnya, bila ada.
  final String? description;

  /// Batas kedaluwarsa absolut (detik sejak epoch unix); null
  /// bila offer tidak kedaluwarsa.
  final BigInt? absoluteExpirySecs;

  /// True bila offer berdenominasi mata uang asing (rekaman
  /// `offer_currency` ada) — nominalnya BUKAN msat dan node
  /// menolak membayarnya.
  final bool hasForeignCurrency;

  const Bolt12OfferInfo({
    required this.amountMsat,
    required this.description,
    required this.absoluteExpirySecs,
    required this.hasForeignCurrency,
  });

  /// Apakah offer menetapkan nominal tetap.
  bool get isFixedAmount => amountMsat != null;

  bool isExpiredAt(DateTime now) {
    if (absoluteExpirySecs == null) return false;
    return BigInt.from(now.millisecondsSinceEpoch ~/ 1000) >=
        absoluteExpirySecs!;
  }
}

const _bech32Charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

// Jenis rekaman TLV offer (terverifikasi dari tlv_stream Offer
// di rust-lightning fork, lightning/src/offers/offer.rs).
const _tlvAmount = 8;
const _tlvCurrency = 6;
const _tlvDescription = 10;
const _tlvAbsoluteExpiry = 14;

/// Apakah [text] berbentuk offer BOLT12: awalan `lno1`
/// (tidak peka huruf besar/kecil, spasi pinggir ditoleransi).
bool isBolt12Offer(String text) =>
    text.trim().toLowerCase().startsWith('lno1');

/// Baca info offer dari string `lno1…`.
///
/// Mengembalikan null bila string bukan offer yang strukturnya
/// utuh: awalan salah, karakter di luar set bech32, sisa bit
/// konversi tidak nol, atau rekaman TLV terpotong/tidak berakhir
/// persis di ujung payload. Field yang tidak terbaca di sini
/// bukan vonis offer tidak sah — lihat catatan fail-open di
/// kepala berkas; keputusan akhir tetap di node.
Bolt12OfferInfo? parseOfferInfo(String offer) {
  final s = offer.trim().toLowerCase();
  if (!s.startsWith('lno1')) return null;

  // Data sesudah pemisah '1': seluruhnya kata 5-bit, TANPA
  // checksum 6 kata seperti bech32 biasa (lihat kepala berkas).
  final words = <int>[];
  for (var i = 4; i < s.length; i++) {
    final v = _bech32Charset.indexOf(s[i]);
    if (v < 0) return null;
    words.add(v);
  }
  if (words.isEmpty) return null;
  final bytes = _convertBits(words, 5, 8, pad: false);
  if (bytes == null || bytes.isEmpty) return null;

  BigInt? amountMsat;
  String? description;
  BigInt? absoluteExpirySecs;
  var hasForeignCurrency = false;

  var i = 0;
  while (i < bytes.length) {
    final typeRead = _readBigSize(bytes, i);
    if (typeRead == null) return null;
    final lenRead = _readBigSize(bytes, typeRead.$2);
    if (lenRead == null) return null;
    final len = lenRead.$1;
    final start = lenRead.$2;
    if (len > BigInt.from(bytes.length - start)) return null;
    final value = bytes.sublist(start, start + len.toInt());
    i = start + len.toInt();

    final type = typeRead.$1;
    if (type == BigInt.from(_tlvAmount) && amountMsat == null) {
      // offer_amount: tu64 big-endian (nol di depan dibuang).
      if (value.length > 8) return null;
      amountMsat = _bigEndianValue(value);
    } else if (type == BigInt.from(_tlvCurrency)) {
      hasForeignCurrency = true;
    } else if (type == BigInt.from(_tlvDescription) && description == null) {
      final text = utf8.decode(value, allowMalformed: true).trim();
      description = text.isEmpty ? null : text;
    } else if (type == BigInt.from(_tlvAbsoluteExpiry) &&
        absoluteExpirySecs == null) {
      if (value.length > 8) return null;
      absoluteExpirySecs = _bigEndianValue(value);
    }
    // Rekaman lain (chains, paths, issuer_id, fitur, ...) dilewati.
  }
  return Bolt12OfferInfo(
    amountMsat: amountMsat,
    description: description,
    absoluteExpirySecs: absoluteExpirySecs,
    hasForeignCurrency: hasForeignCurrency,
  );
}

/// Baca nominal isian pengguna (nusan) menjadi msat.
///
/// Pola yang sama persis dengan kolom nominal layar Terima:
/// pemisah ribuan '.' dibuang, ',' dibaca sebagai desimal,
/// pecahan nusan ditoleransi dan dibulatkan ke msat terdekat.
/// Mengembalikan null bila isian kosong, bukan angka, atau
/// tidak positif — pemanggil menampilkan pesan nominal tidak
/// valid yang sudah ada.
BigInt? parseNusanInputToMsat(String text) {
  final cleaned = text.trim().replaceAll('.', '').replaceAll(',', '.');
  final nusan = double.tryParse(cleaned);
  if (nusan == null || nusan <= 0) return null;
  return BigInt.from((nusan * 1000).round());
}

/// Nilai bilangan bulat big-endian dari byte tu64.
BigInt _bigEndianValue(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

/// Baca satu bilangan BigSize (pengkodean panjang/jenis TLV
/// Lightning): < 0xfd satu byte; 0xfd/0xfe/0xff diikuti 2/4/8
/// byte big-endian. Mengembalikan (nilai, offset berikutnya)
/// atau null bila terpotong.
(BigInt, int)? _readBigSize(List<int> bytes, int offset) {
  if (offset >= bytes.length) return null;
  final first = bytes[offset];
  if (first < 0xfd) return (BigInt.from(first), offset + 1);
  final extra = first == 0xfd ? 2 : (first == 0xfe ? 4 : 8);
  if (offset + 1 + extra > bytes.length) return null;
  var v = BigInt.zero;
  for (var j = 0; j < extra; j++) {
    v = (v << 8) | BigInt.from(bytes[offset + 1 + j]);
  }
  return (v, offset + 1 + extra);
}

/// Konversi kelompok bit (pola convertbits BIP-173).
///
/// Dengan pad=false, sisa bit di ujung harus nol dan tidak boleh
/// membentuk byte utuh tambahan; bila tidak, hasil dianggap rusak
/// dan null dikembalikan.
List<int>? _convertBits(List<int> data, int fromBits, int toBits,
    {required bool pad}) {
  var acc = 0;
  var bits = 0;
  final out = <int>[];
  final maxv = (1 << toBits) - 1;
  for (final v in data) {
    if (v < 0 || (v >> fromBits) != 0) return null;
    acc = (acc << fromBits) | v;
    bits += fromBits;
    while (bits >= toBits) {
      bits -= toBits;
      out.add((acc >> bits) & maxv);
    }
  }
  if (pad) {
    if (bits > 0) out.add((acc << (toBits - bits)) & maxv);
  } else {
    if (bits >= fromBits) return null;
    if ((acc << (toBits - bits)) & maxv != 0) return null;
  }
  return out;
}
