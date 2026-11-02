import 'package:flutter/foundation.dart';

import '../l10n/app_localizations.dart';

/// Ubah error teknis menjadi pesan ringkas yang layak tampil ke pengguna.
///
/// Prinsip: UI TIDAK PERNAH menampilkan error mentah — error mentah memuat
/// detail infrastruktur (hostname server, alamat IP, nama exception, stack)
/// yang tidak berguna bagi pengguna dan tidak pantas terekspos. Detail asli
/// hanya ditulis ke log developer lewat [debugPrint].
///
/// [fallback] dipakai bila error tidak cocok pola mana pun — isi dengan
/// pesan ringkas sesuai konteks layar pemanggil (sudah diterjemahkan).
/// [l10n] dipakai untuk keempat pesan baku di bawah.
String friendlyError(Object error,
    {required String fallback, required AppLocalizations l10n}) {
  debugPrint('[error-teknis] $error');
  final s = error.toString().toLowerCase();

  // Koneksi: offline, timeout, DNS, server tidak terjangkau.
  if (s.contains('socket') ||
      s.contains('connection') ||
      s.contains('timeout') ||
      s.contains('timed out') ||
      s.contains('failed host lookup') ||
      s.contains('unreachable') ||
      s.contains('handshake')) {
    return l10n.errorConnection;
  }

  // Saldo / dana tidak cukup.
  if (s.contains('insufficient') || s.contains('balance')) {
    return l10n.errorBalance;
  }

  // Kode bayar (offer Bolt12) tidak valid / tidak didukung —
  // dipisah dari pesan invoice: pengguna yang membayar kode
  // bayar tidak boleh membaca "invoice kedaluwarsa" untuk kode
  // yang sebenarnya tidak dikenal atau berdenominasi asing.
  if (s.contains('offer') &&
      (s.contains('invalid') ||
          s.contains('parse') ||
          s.contains('unsupported'))) {
    return l10n.sendOfferInvalid;
  }

  // Invoice tidak valid / kedaluwarsa.
  if (s.contains('invoice') &&
      (s.contains('invalid') || s.contains('expired') || s.contains('parse'))) {
    return l10n.errorInvoice;
  }

  // Data dompet lokal bermasalah (seed/storage) — jangan tampilkan detail.
  if (s.contains('seed') || s.contains('korup') || s.contains('storage')) {
    return l10n.errorWalletData;
  }

  return fallback;
}
