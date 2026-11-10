import 'package:ldk_node/src/generated/api/types.dart';

import 'payment_notes.dart';

/// Penyusun CSV riwayat transaksi untuk ekspor dari tab Riwayat.
///
/// Kolom dan nilainya sengaja kanonis dan bebas format tampilan
/// (bahasa Inggris, jumlah desimal bertanda titik, tanpa pemisah
/// ribuan) supaya berkasnya nyaman diolah di spreadsheet. Tanda
/// jumlah mengikuti arah — masuk +, keluar − — sama seperti
/// baris di layar, dan amount_msat menyimpan nilai mentah persis
/// dari node. Urutan baris mengikuti urutan masukan (terbaru di
/// depan, sama seperti daftar Riwayat yang diekspor).
String buildTransactionsCsv(
  List<PaymentDetails> payments, {
  Map<String, String> routeTags = const {},
}) {
  final buf = StringBuffer()
    ..writeln(
      'date_iso,type,direction,status,amount_nusan,'
      'amount_msat,payment_id,payment_hash,txid',
    );
  for (final payment in payments) {
    final hashHex = _paymentHashHex(payment.kind);
    final typeLabel = _typeLabel(
      payment.kind,
      routeTag: hashHex == null ? null : routeTags[hashHex],
    );
    buf.writeln(
      [
        _cell(_isoTime(payment)),
        _cell(typeLabel),
        _cell(
          payment.direction == PaymentDirection.inbound
              ? 'Incoming'
              : 'Outgoing',
        ),
        _cell(_statusLabel(payment.status)),
        _cell(_amountNusan(payment)),
        _cell(_amountMsat(payment)),
        _cell(_hex(payment.id.data)),
        _cell(_paymentHashHex(payment.kind) ?? ''),
        _cell(_txid(payment.kind) ?? ''),
      ].join(','),
    );
  }
  return buf.toString();
}

/// Waktu lokal ISO 8601 dari cap waktu unix node (detik).
String _isoTime(PaymentDetails payment) => DateTime.fromMillisecondsSinceEpoch(
  payment.latestUpdateTimestamp.toInt() * 1000,
).toIso8601String();

String _typeLabel(PaymentKind kind, {String? routeTag}) {
  if (kind is PaymentKind_Onchain) return 'On-chain';
  if (kind is PaymentKind_Bolt11Jit) return 'Lightning JIT';
  // Tag rute lokal (PaymentTagStore): pembayaran Lightning yang
  // tercatat berjalan lewat channel langsung — samakan dengan
  // label baris Riwayat.
  if (routeTag == paymentTagDirect) return 'Lightning Direct';
  if (kind is PaymentKind_Bolt11) return 'Lightning';
  if (kind is PaymentKind_Spontaneous) return 'Spontaneous';
  return 'Lightning';
}

String _statusLabel(PaymentStatus status) => switch (status) {
  PaymentStatus.succeeded => 'Succeeded',
  PaymentStatus.pending => 'Pending',
  PaymentStatus.failed => 'Failed',
};

/// Jumlah bertanda arah dalam msat mentah; kosong bila node
/// tidak mencatat jumlah (mis. pembayaran yang belum selesai).
String _amountMsat(PaymentDetails payment) {
  final amount = payment.amountMsat;
  if (amount == null) return '';
  final signed = payment.direction == PaymentDirection.inbound
      ? amount
      : -amount;
  return signed.toString();
}

/// Jumlah bertanda arah dalam nusan desimal polos (titik,
/// maksimal 3 angka di belakang koma, nol ekor dibuang).
String _amountNusan(PaymentDetails payment) {
  final amount = payment.amountMsat;
  if (amount == null) return '';
  final signed = payment.direction == PaymentDirection.inbound
      ? amount
      : -amount;
  final negative = signed < BigInt.zero;
  final abs = signed.abs();
  final whole = abs ~/ BigInt.from(1000);
  final rem = (abs % BigInt.from(1000)).toInt();
  if (rem == 0) return '${negative ? '-' : ''}$whole';
  final frac = rem.toString().padLeft(3, '0').replaceAll(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}$whole.$frac';
}

String _hex(Iterable<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Hash pembayaran dari jenis Lightning; null untuk on-chain.
String? _paymentHashHex(PaymentKind kind) {
  if (kind is PaymentKind_Bolt11) return _hex(kind.hash.data);
  if (kind is PaymentKind_Bolt11Jit) return _hex(kind.hash.data);
  if (kind is PaymentKind_Spontaneous) return _hex(kind.hash.data);
  if (kind is PaymentKind_Bolt12Offer) {
    return kind.hash == null ? null : _hex(kind.hash!.data);
  }
  if (kind is PaymentKind_Bolt12Refund) {
    return kind.hash == null ? null : _hex(kind.hash!.data);
  }
  return null;
}

String? _txid(PaymentKind kind) =>
    kind is PaymentKind_Onchain ? kind.txid.hash : null;

/// Kutip sel bila memuat koma/kutip/baris baru (nilai saat ini
/// tidak ada yang memuatnya — pengaman untuk masa depan).
String _cell(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
