import 'package:flutter/material.dart';

import '../locale_controller.dart';
import '../theme.dart';

/// Halaman Aturan Program Poin Nusan — teks yang dapat dibaca
/// pelanggan di Mode Toko (pedoman miniPOS §7 & checklist §9:
/// halaman aturan program poin tersedia di aplikasi).
///
/// Isinya setia pada kedudukan program: poin nusan adalah BONUS
/// promosi dari belanja rupiah — bukan uang, tidak dapat
/// diuangkan, tidak dijual, dan hanya dapat ditukar sebagai
/// potongan harga di toko ini sesuai nilai potongan yang
/// ditetapkan toko. Tidak ada janji nilai dan tidak ada masa
/// berlaku (keputusan NUX 3 Nov 2026: masa berlaku poin tidak
/// ada, jadi tidak ditulis di sini).
class StorePointRulesScreen extends StatelessWidget {
  const StorePointRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final paragraphs = [
      l10n.storeRulesP1,
      l10n.storeRulesP2,
      l10n.storeRulesP3,
      l10n.storeRulesP4,
      l10n.storeRulesP5,
      l10n.storeRulesP6,
      l10n.storeRulesP7,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storeRulesTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          const Icon(
            Icons.loyalty_rounded,
            size: 40,
            color: Color(0xFF34D399),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.storeRulesHeading,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          for (final p in paragraphs) ...[
            Text(p, style: const TextStyle(fontSize: 14, height: 1.5)),
            const SizedBox(height: 12),
          ],
          Text(
            l10n.storeRulesFooter,
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
        ],
      ),
    );
  }
}
