import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../locale_controller.dart';
import '../services/jelajah_registry.dart';
import '../services/market_info.dart';
import '../theme.dart';
import '../utils/format.dart';

/// Layar Jelajah — pengganti tab Pasar.
///
/// Dua seksi dalam satu halaman bergulir:
///
/// 1. **Info Pasar** (baca-saja): harga NUX terakhir dalam IDR dari
///    data pasar publik qutrade.io (kurs konversi USDT/IDR Indodax),
///    perubahan antar penutupan harian, tinggi blok dari electrs
///    tim, dan cap waktu pembaruan. Seksi disembunyikan dengan
///    anggun bila sumber harga tidak terjangkau — tidak pernah
///    menampilkan angka nol atau angka basi tanpa cap waktu.
/// 2. **Direktori Toko**: daftar toko Mode Toko terkurasi tim dari
///    berkas registri statis. Kartu toko murni informasi (nama,
///    wilayah, jam, catatan, lencana program poin) dengan satu
///    tindakan netral: Salin Offer. Tidak ada tombol beli/jual/
///    tukar/bayar di layar ini — pembayaran belanja tetap rupiah
///    sesuai pedoman Mode Toko dan hukum Indonesia (kripto adalah
///    aset yang diperdagangkan, bukan alat pembayaran).
class JelajahScreen extends StatefulWidget {
  const JelajahScreen({super.key});

  @override
  State<JelajahScreen> createState() => _JelajahScreenState();
}

class _JelajahScreenState extends State<JelajahScreen> {
  final _registryService = JelajahRegistryService();
  final _marketService = MarketInfoService();
  final _searchController = TextEditingController();

  bool _loading = true;
  JelajahRegistryResult _registry =
      const JelajahRegistryResult(stores: []);
  NuxMarketInfo? _market;
  String? _city;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _muat({bool paksaSegar = false}) async {
    final hasil = await Future.wait<Object?>([
      _registryService.muat(),
      _marketService.muat(paksaSegar: paksaSegar),
    ]);
    if (!mounted) return;
    setState(() {
      _registry = hasil[0] as JelajahRegistryResult;
      _market = hasil[1] as NuxMarketInfo?;
      _loading = false;
    });
  }

  String _jam(DateTime waktu) => DateFormat('HH:mm').format(waktu);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final palette = context.palette;
    final tokoTampil = filterJelajahStores(
      _registry.stores,
      city: _city,
      query: _query,
    );
    return RefreshIndicator(
      onRefresh: () => _muat(paksaSegar: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          if (_market != null) ...[
            _kartuPasar(context, _market!),
            const SizedBox(height: 22),
          ],
          _kepalaDirektori(context),
          const SizedBox(height: 10),
          _barisSaring(context),
          const SizedBox(height: 12),
          if (_registry.stores.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                context.l10n.jelajahEmpty,
                style: TextStyle(fontSize: 13, color: palette.muted),
                textAlign: TextAlign.center,
              ),
            )
          else if (tokoTampil.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                context.l10n.jelajahNoResults,
                style: TextStyle(fontSize: 13, color: palette.muted),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...tokoTampil.map((toko) => _kartuToko(context, toko)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Seksi Info Pasar
  // ------------------------------------------------------------------

  Widget _kartuPasar(BuildContext context, NuxMarketInfo info) {
    final palette = context.palette;
    final hargaIdr = info.priceIdr;
    final perubahan = info.changePct;
    final naik = (perubahan ?? 0) >= 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('NUX',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.l10n.jelajahSource,
                    style: TextStyle(fontSize: 12, color: palette.muted)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 19),
                color: palette.muted,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _muat(paksaSegar: true),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hargaIdr != null
                    ? _formatIdr(hargaIdr)
                    : '${_formatUsdt(info.lastUsdt)} USDT',
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800),
              ),
              if (perubahan != null) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${naik ? '▲' : '▼'} ${perubahan.abs().toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: naik
                          ? const Color(0xFF34D399)
                          : const Color(0xFFF87171),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (hargaIdr != null) '${_formatUsdt(info.lastUsdt)} USDT',
              if (perubahan != null) context.l10n.jelajahChange24h,
              context.l10n.jelajahUpdated(_jam(info.fetchedAt)),
            ].join('  ·  '),
            style: TextStyle(fontSize: 12, color: palette.muted),
          ),
          if (info.blockHeight != null) ...[
            const SizedBox(height: 6),
            Text(
              '${context.l10n.jelajahBlockHeight}: '
              '${formatRupiah(info.blockHeight!)}',
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            context.l10n.jelajahDisclaimer,
            style: TextStyle(fontSize: 11, color: palette.faint),
          ),
        ],
      ),
    );
  }

  /// Harga rupiah: bulat bergaya id_ID untuk nilai umum; dua desimal
  /// (koma) bila nilainya sangat kecil agar tidak tampil "Rp 0".
  String _formatIdr(double nilai) {
    if (nilai >= 20) return 'Rp ${formatRupiah(nilai.round())}';
    return 'Rp ${nilai.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  /// Harga USDT dengan presisi pasar (maks 6 desimal, nol ekor
  /// dibuang, minimal 2 desimal).
  String _formatUsdt(double nilai) {
    var teks = nilai.toStringAsFixed(6);
    while (teks.contains('.') &&
        teks.endsWith('0') &&
        teks.split('.').last.length > 2) {
      teks = teks.substring(0, teks.length - 1);
    }
    return teks;
  }

  // ------------------------------------------------------------------
  // Seksi Direktori Toko
  // ------------------------------------------------------------------

  Widget _kepalaDirektori(BuildContext context) {
    final palette = context.palette;
    final waktu = _registry.fetchedAt;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(context.l10n.jelajahDirectory,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        if (waktu != null)
          Text(
            context.l10n.jelajahDirectoryUpdated(_jam(waktu)),
            style: TextStyle(fontSize: 11, color: palette.faint),
          ),
      ],
    );
  }

  Widget _barisSaring(BuildContext context) {
    final palette = context.palette;
    final kota = jelajahCities(_registry.stores);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: context.l10n.jelajahSearchHint,
              prefixIcon: const Icon(Icons.search, size: 19),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (nilai) => setState(() => _query = nilai),
          ),
        ),
        if (kota.length > 1) ...[
          const SizedBox(width: 10),
          DropdownButton<String?>(
            value: _city,
            underline: const SizedBox.shrink(),
            style: TextStyle(fontSize: 13, color: palette.label),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(context.l10n.jelajahAllCities),
              ),
              ...kota.map(
                (nama) => DropdownMenuItem<String?>(
                  value: nama,
                  child: Text(nama),
                ),
              ),
            ],
            onChanged: (nilai) => setState(() => _city = nilai),
          ),
        ],
      ],
    );
  }

  Widget _kartuToko(BuildContext context, JelajahStore toko) {
    final palette = context.palette;
    final wilayah = [
      if (toko.city.isNotEmpty) toko.city,
      if (toko.area.isNotEmpty) toko.area,
    ].join(' • ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(toko.name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (toko.pointsProgram)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF34D399).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    context.l10n.jelajahPointsProgram,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF34D399),
                    ),
                  ),
                ),
            ],
          ),
          if (wilayah.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(wilayah,
                style: TextStyle(fontSize: 12, color: palette.muted)),
          ],
          if (toko.addressNote.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(toko.addressNote,
                style: TextStyle(fontSize: 12, color: palette.muted)),
          ],
          if (toko.hours.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(toko.hours,
                style: TextStyle(fontSize: 12, color: palette.muted)),
          ],
          if (toko.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(toko.note, style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 15),
              label: Text(context.l10n.jelajahCopyOffer),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: toko.offer));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(context.l10n.jelajahOfferCopied)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
