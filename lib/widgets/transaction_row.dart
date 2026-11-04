import 'package:flutter/material.dart';

import '../theme.dart';

/// Satu baris transaksi di daftar Aktivitas/Riwayat.
///
/// Susunan kolom tengahnya TIGA baris, bukan dua:
///
/// 1. judul (catatan pembayaran bila ada, kalau tidak judul
///    arah Diterima/Terkirim),
/// 2. ID pembayaran pendek + chip jenis (⚡ JIT / ⛓ on-chain),
/// 3. chip status (Menunggu/Gagal) — hanya bila status bukan sukses.
///
/// Chip status sengaja TIDAK lagi dijejalkan di baris ke-2: di HP
/// sempit baris itu kehabisan tempat (ID + chip jenis + chip status
/// + kolom nominal/waktu di kanan) sehingga chip status terpotong
/// dan bertabrakan dengan teks waktu (temuan NUX dari tangkapan
/// layar 29 Okt 2026). Di barisnya sendiri, chip status selalu
/// punya ruang penuh dan tidak berdesak-desakan dengan apa pun.
class TransactionRow extends StatelessWidget {
  final Widget icon;
  final String title;

  /// ID pembayaran pendek (subjudul baris ke-2).
  final String addr;

  /// Label jenis: '⚡ JIT', '⛓ on-chain', atau '⚡'.
  final String tag;
  final bool isIn;
  final String amount;
  final String time;

  /// Teks status untuk baris ke-3 ('Sedang diproses'/'Menunggu'/
  /// 'Gagal'); null untuk pembayaran sukses — baris ke-3 tidak
  /// dibuat sama sekali.
  final String? status;

  /// True bila statusnya kegagalan (chip merah); false = menunggu
  /// (chip kuning).
  final bool statusBad;

  final VoidCallback? onTap;

  const TransactionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.addr,
    required this.tag,
    required this.isIn,
    required this.amount,
    required this.time,
    this.status,
    this.statusBad = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isJit = tag.contains('JIT');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: isIn
                    ? LinearGradient(colors: [
                        const Color(0xFF10B981).withValues(alpha: 0.25),
                        const Color(0xFF10B981).withValues(alpha: 0.08),
                      ])
                    : null,
                color: isIn ? null : context.palette.softBg,
              ),
              child: Center(child: icon),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Baris 1: judul arah.
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  // Baris 2: ID pendek + chip jenis, dibungkus
                  // FittedBox scaleDown (pola yang sama seperti pil
                  // status kartu saldo): selebar apa pun isinya —
                  // layar ekstrem, skala font besar — baris ini
                  // menyusut mengikuti tempatnya dan tidak bisa
                  // meluap. Di lebar normal skalanya 1.0.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(addr,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                                fontSize: 12,
                                color: context.palette.muted)),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isJit
                                ? const Color(0xFF10B981)
                                    .withValues(alpha: 0.15)
                                : context.palette.softBg,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(tag,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isJit
                                      ? const Color(0xFF34D399)
                                      : context.palette.dim)),
                        ),
                      ],
                    ),
                  ),
                  // Baris 3: chip status di barisnya sendiri,
                  // dengan pelindung menyusut yang sama.
                  if (status != null) ...[
                    const SizedBox(height: 5),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (statusBad
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFFF59E0B))
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(status!,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusBad
                                    ? context.palette.dangerSoft
                                    : context.palette.warningIcon)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(amount,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isIn
                            ? const Color(0xFF34D399)
                            : Colors.white)),
                const SizedBox(height: 3),
                Text(time,
                    style: TextStyle(
                        fontSize: 11, color: context.palette.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
