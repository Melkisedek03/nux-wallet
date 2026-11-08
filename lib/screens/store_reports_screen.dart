import 'package:flutter/material.dart';

import '../locale_controller.dart';
import '../theme.dart';
import 'store_bestsellers_screen.dart';
import 'store_product_sales_screen.dart';

/// Daftar Laporan Mode Toko — halaman indeks laporan-laporan
/// untuk owner (permintaan NUX 8 Nov 2026). Halaman ini khusus
/// owner: gerbangnya dipasang pemanggil di layar Mode Toko
/// (persetujuan PIN admin, pola yang sama dengan Pengaturan
/// Toko), jadi layar ini sendiri tidak memeriksa peran lagi.
///
/// Laporan baru cukup ditambahkan sebagai satu entri di daftar
/// isi build() + satu layar laporan — bentuk halaman ini tidak
/// berubah mengikuti bertambahnya jenis laporan.
class StoreReportsScreen extends StatelessWidget {
  const StoreReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = <_ReportEntry>[
      _ReportEntry(
        icon: Icons.emoji_events_rounded,
        title: l10n.storeReportBestsellersTitle,
        subtitle: l10n.storeReportBestsellersSubtitle,
        builder: (_) => const StoreBestsellersScreen(),
      ),
      _ReportEntry(
        icon: Icons.inventory_2_rounded,
        title: l10n.storeReportProductSalesTitle,
        subtitle: l10n.storeReportProductSalesSubtitle,
        builder: (_) => const StoreProductSalesScreen(),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.storeReportsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final entry in entries) _ReportTile(entry: entry),
        ],
      ),
    );
  }
}

/// Satu judul laporan di daftar: ikon + judul + keterangan
/// singkat + layar yang dibuka saat judul dipilih.
class _ReportEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;

  const _ReportEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.entry});

  final _ReportEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: entry.builder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: context.palette.softBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  entry.icon,
                  size: 22,
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.palette.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
