import 'package:flutter/material.dart';

import '../locale_controller.dart';
import '../theme.dart';

/// Penanda sesi boot-offline di Beranda (G1.4): chip menetap selama
/// aplikasi berjalan dalam sesi yang di-boot tanpa internet, supaya
/// pengguna tahu angka di kartu saldo tidak semuanya bisa dipakai
/// — hanya jalur yang sudah siap yang bergerak offline. Bentuknya
/// mengikuti strip peringatan dompet legacy di Beranda yang sama
/// (ikon + teks melipat, sudut membulat), dengan rona emerald
/// sebagai penanda keadaan, bukan peringatan.
///
/// Diketuk, chip membuka layar Mode Offline ([onTap] dipasang
/// pemiliknya) — pengguna yang melihat penanda ini langsung
/// sampai ke tempat jalur offline dikelola, tanpa mencari
/// jalannya lewat menu lain.
class OfflineSessionChip extends StatelessWidget {
  const OfflineSessionChip({super.key, this.onTap});

  /// Dipanggil saat chip diketuk; null = chip tidak bisa diketuk.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: Color(0xFF34D399),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.offlineSessionChip,
                style: TextStyle(
                  fontSize: 12.5,
                  color: context.palette.label,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
