/// Pembaca info dasar invoice BOLT11 (payment hash + masa berlaku
/// + deskripsi).
///
/// ELNUX perlu tiga hal dari sebuah invoice:
///
/// 1. **payment hash** — untuk mencocokkan invoice tersimpan dengan
///    catatan pembayaran di node (PaymentKind_Bolt11/Jit menyimpan
///    hash yang sama), supaya layar detail riwayat bisa menampilkan
///    kembali invoice yang masih pending.
/// 2. **waktu kedaluwarsa** — dihitung dari timestamp invoice +
///    tag 'x' (default 3600 detik bila tag tidak ada), supaya
///    aplikasi tahu invoice masih layak ditampilkan atau sudah mati.
/// 3. **deskripsi** (tag 'd') — catatan teks yang ditulis pembuat
///    invoice ("untuk SPP November"); ditampilkan ke pembayar
///    sebelum membayar dan disimpan sebagai catatan riwayat.
///    Field 'h' (hash deskripsi) TIDAK bisa dikembalikan menjadi
///    teks, jadi invoice yang hanya membawa 'h' terbaca tanpa
///    deskripsi.
///
/// Ini BUKAN decoder lengkap dan TIDAK memverifikasi tanda tangan
/// invoice: fungsinya hanya membaca tiga field di atas. Checksum
/// bech32 tetap diverifikasi — invoice yang checksum-nya rusak
/// dianggap tidak valid dan fungsi mengembalikan null (fail-open:
/// pemanggil cukup tidak menautkan invoice tersimpan, tanpa error
/// ke user).
///
/// Fungsi ketiga, [parseBolt11AmountMsat], membaca nominal dari
/// awalan (HRP) invoice mana pun untuk pemeriksaan pra-bayar di
/// layar Kirim — juga fail-open dengan checksum terverifikasi.
library;

import 'dart:convert';

/// Info hasil baca invoice: payment hash (hex 64 karakter),
/// waktu kedaluwarsa menurut jam invoice itu sendiri, dan
/// deskripsi/catatan invoice (null bila invoice tidak membawa
/// tag 'd' atau isinya kosong).
class Bolt11Info {
  final String paymentHashHex;
  final DateTime expiresAt;
  final String? description;

  const Bolt11Info({
    required this.paymentHashHex,
    required this.expiresAt,
    this.description,
  });

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
}

const _bech32Charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

/// Baca payment hash + kedaluwarsa dari [invoice].
///
/// Mengembalikan null bila invoice bukan bech32 yang valid, checksum
/// salah, atau field payment hash ('p') tidak ditemukan/utuh.
Bolt11Info? parseBolt11Info(String invoice) {
  final s = invoice.trim().toLowerCase();
  if (!s.startsWith('ln')) return null;
  final sep = s.lastIndexOf('1');
  if (sep < 1) return null;
  final dataPart = s.substring(sep + 1);
  if (dataPart.length < 6) return null;

  // Decode bech32: setiap karakter → nilai 5-bit.
  final words = <int>[];
  for (var i = 0; i < dataPart.length; i++) {
    final v = _bech32Charset.indexOf(dataPart[i]);
    if (v < 0) return null;
    words.add(v);
  }
  if (!_bech32ChecksumValid(s.substring(0, sep), words)) return null;

  // Buang 6 kata checksum di ujung.
  final payload = words.sublist(0, words.length - 6);
  // 7 kata pertama = timestamp (35 bit).
  if (payload.length < 7) return null;
  var timestamp = 0;
  for (var i = 0; i < 7; i++) {
    timestamp = (timestamp << 5) | payload[i];
  }

  String? paymentHashHex;
  int? expirySecs;
  String? description;
  var i = 7;
  while (i + 3 <= payload.length) {
    final type = payload[i];
    final len = (payload[i + 1] << 5) | payload[i + 2];
    i += 3;
    if (i + len > payload.length) break; // tag terpotong — berhenti
    final data = payload.sublist(i, i + len);
    i += len;
    if (type == 1 && paymentHashHex == null) {
      // 'p' = payment_hash: 52 kata 5-bit → 32 byte.
      final bytes = _convertBits(data, 5, 8, pad: false);
      if (bytes != null && bytes.length == 32) {
        paymentHashHex =
            bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }
    } else if (type == 6 && expirySecs == null) {
      // 'x' = expiry: bilangan bulat basis-32 big-endian.
      var v = 0;
      for (final w in data) {
        v = (v << 5) | w;
      }
      expirySecs = v;
    } else if (type == 13 && description == null) {
      // 'd' = description: byte UTF-8 yang dikemas 5-bit.
      // Dekode toleran (bit sisa di ujung diabaikan, byte nol
      // ekor dibuang): deskripsi hanya untuk tampilan, jadi
      // kekakuan padding pembuat invoice lain tidak boleh
      // menggagalkan pembacaan hash/kedaluwarsa di atas.
      final bytes = _wordsToBytesTolerant(data);
      final text = utf8.decode(bytes, allowMalformed: true).trim();
      if (text.isNotEmpty) description = text;
    }
  }
  if (paymentHashHex == null) return null;
  final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      (timestamp + (expirySecs ?? 3600)) * 1000,
      isUtc: true);
  return Bolt11Info(
    paymentHashHex: paymentHashHex,
    expiresAt: expiresAt,
    description: description,
  );
}

/// Kemas ulang kata 5-bit menjadi byte, toleran: bit sisa yang
/// tidak membentuk byte utuh diabaikan dan byte 0x00 di ujung
/// dibuang (sisa bantalan enkode). Dipakai khusus deskripsi —
/// untuk payment hash tetap dipakai [_convertBits] yang ketat.
List<int> _wordsToBytesTolerant(List<int> words) {
  var acc = 0;
  var bits = 0;
  final out = <int>[];
  for (final w in words) {
    acc = (acc << 5) | w;
    bits += 5;
    while (bits >= 8) {
      bits -= 8;
      out.add((acc >> bits) & 0xff);
    }
  }
  while (out.isNotEmpty && out.last == 0) {
    out.removeLast();
  }
  return out;
}

/// Baca nominal invoice (msat) dari awalannya (HRP bech32).
///
/// Nominal BOLT11 tinggal di HRP: `ln` + kode mata uang + angka +
/// pengali opsional (m = 10^-3, u = 10^-6, n = 10^-9, p = 10^-12
/// dari satu koin utuh; tanpa pengali = koin utuh). Dipakai layar
/// Kirim untuk memeriksa nominal terhadap saldo & kapasitas kirim
/// SEBELUM pembayaran dicoba — binding node sendiri tidak
/// menyediakan pembaca nominal invoice.
///
/// Mengembalikan null bila invoice tidak valid (termasuk checksum
/// rusak), tidak bernominal (amountless), atau nominal 'p'-nya
/// tidak bulat ke msat. Null berarti "tidak diketahui" — pemanggil
/// melanjutkan alur lama tanpa pemeriksaan (fail-open); node tetap
/// penentu akhir sah/tidaknya invoice saat pembayaran dijalankan.
BigInt? parseBolt11AmountMsat(String invoice) {
  final s = invoice.trim().toLowerCase();
  if (!s.startsWith('ln')) return null;
  final sep = s.lastIndexOf('1');
  if (sep < 1) return null;
  final dataPart = s.substring(sep + 1);
  if (dataPart.length < 6) return null;

  // Checksum wajib sah — nominal dari invoice rusak tidak boleh
  // menjadi dasar pesan apa pun ke pengguna.
  final words = <int>[];
  for (var i = 0; i < dataPart.length; i++) {
    final v = _bech32Charset.indexOf(dataPart[i]);
    if (v < 0) return null;
    words.add(v);
  }
  final hrp = s.substring(0, sep);
  if (!_bech32ChecksumValid(hrp, words)) return null;

  // HRP sesudah 'ln': kode mata uang (huruf) lalu angka nominal.
  var rest = hrp.substring(2);
  if (rest.isEmpty) return null;
  var multiplierMsat = BigInt.from(100000000000); // koin utuh → msat
  final last = rest[rest.length - 1];
  if ((last == 'm' || last == 'u' || last == 'n' || last == 'p') &&
      rest.length >= 2 &&
      _isDigit(rest.codeUnitAt(rest.length - 2))) {
    multiplierMsat = switch (last) {
      'm' => BigInt.from(100000000),
      'u' => BigInt.from(100000),
      'n' => BigInt.from(100),
      _ => BigInt.zero, // 'p' ditangani khusus di bawah
    };
    rest = rest.substring(0, rest.length - 1);
    if (last == 'p') {
      // 1 p = 0,1 msat: hanya bulat bila angkanya kelipatan 10.
      final digits = _trailingDigits(rest);
      if (digits == null) return null;
      final value = BigInt.parse(digits);
      if (value % BigInt.from(10) != BigInt.zero) return null;
      return value ~/ BigInt.from(10);
    }
  }
  final digits = _trailingDigits(rest);
  if (digits == null) return null;
  return BigInt.parse(digits) * multiplierMsat;
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// Deretan angka di ujung [s] — nominal invoice. Null bila tidak
/// ada angka sama sekali (amountless) atau ada nol di depan
/// (bentuk yang tidak pernah diterbitkan penerbit invoice sah).
String? _trailingDigits(String s) {
  var i = s.length;
  while (i > 0 && _isDigit(s.codeUnitAt(i - 1))) {
    i--;
  }
  if (i == s.length) return null;
  final digits = s.substring(i);
  if (digits.length > 1 && digits.startsWith('0')) return null;
  return digits;
}

/// Verifikasi checksum bech32 (polymod harus 1).
bool _bech32ChecksumValid(String hrp, List<int> dataWithChecksum) {
  var chk = 1;
  void polymodStep(int v) {
    final top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    for (var i = 0; i < 5; i++) {
      if ((top >> i) & 1 == 1) chk ^= gen[i];
    }
  }

  // Expand HRP: nilai tinggi, 0, nilai rendah.
  for (var i = 0; i < hrp.length; i++) {
    polymodStep(hrp.codeUnitAt(i) >> 5);
  }
  polymodStep(0);
  for (var i = 0; i < hrp.length; i++) {
    polymodStep(hrp.codeUnitAt(i) & 31);
  }
  for (final v in dataWithChecksum) {
    polymodStep(v);
  }
  return chk == 1;
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
