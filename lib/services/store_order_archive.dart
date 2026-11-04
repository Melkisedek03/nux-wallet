import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'store_order_history.dart';

/// Arsip riwayat penjualan Mode Toko di storage HP (keputusan
/// NUX 4 Nov 2026): basis data aktif menahan paling banyak
/// [StoreOrderHistoryStore.maxRecords] record terakhir; record
/// yang berlebih TIDAK dibuang — ia ditambahkan (append) sebagai
/// baris JSON (JSONL) ke berkas arsip ini di direktori dokumen
/// aplikasi, satu record per baris, memakai serialisasi record
/// yang sama dengan era simpanan lama.
///
/// Kontrak kegagalan: penulisan arsip yang gagal MELEMPAR ke
/// pemanggil, dan pemanggil (pemeliharaan overflow riwayat)
/// hanya menghapus record dari basis data SESUDAH arsip
/// tertulis — jadi kegagalan tulis berarti record tetap aktif
/// dan pengarsipan dicoba lagi pada pelunasan berikutnya.
class StoreOrderArchive {
  StoreOrderArchive({Future<Directory> Function()? dirProvider})
    : _dirProvider = dirProvider;

  /// Instans produksi (direktori dokumen aplikasi).
  static final StoreOrderArchive instance = StoreOrderArchive();

  /// Nama berkas arsip di direktori dokumen aplikasi.
  static const String archiveFileName = 'store_order_archive.jsonl';

  final Future<Directory> Function()? _dirProvider;

  Future<File> _archiveFile() async {
    final dir = await (_dirProvider?.call() ??
        getApplicationDocumentsDirectory());
    return File(p.join(dir.path, archiveFileName));
  }

  /// Tambahkan [orders] ke ujung berkas arsip (dibuat bila
  /// belum ada). Daftar kosong = tidak menyentuh berkas.
  Future<void> appendOrders(List<CompletedOrder> orders) async {
    if (orders.isEmpty) return;
    final file = await _archiveFile();
    final buffer = StringBuffer();
    for (final order in orders) {
      buffer.writeln(jsonEncode(order.toJson()));
    }
    await file.writeAsString(
      buffer.toString(),
      mode: FileMode.append,
      flush: true,
    );
  }

  /// Baca kembali seluruh record terarsip (bahan uji &
  /// pemeriksaan; layar kasir tidak membaca arsip — arsip
  /// adalah simpanan jangka panjang di perangkat, bukan bahan
  /// laporan berjalan).
  Future<List<CompletedOrder>> loadArchived() async {
    try {
      final file = await _archiveFile();
      if (!await file.exists()) return const [];
      final lines = await file.readAsLines();
      final orders = <CompletedOrder>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        Object? parsed;
        try {
          parsed = jsonDecode(line);
        } catch (_) {
          continue;
        }
        final order = CompletedOrder.fromJson(parsed);
        if (order != null) orders.add(order);
      }
      return orders;
    } catch (_) {
      return const [];
    }
  }
}
