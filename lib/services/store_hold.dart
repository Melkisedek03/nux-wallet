import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/store_mode_logic.dart';
import 'store_order_history.dart';

/// Satu pesanan Mode Toko yang DITAHAN kasir — tamu bayar
/// belakangan (keputusan NUX 3 Nov 2026). Pesanan ditahan adalah
/// pesanan berjalan yang diparkir apa adanya: baris lengkap
/// (diskon baris + catatan ikut), diskon order, dan waktu tahan.
/// Ia BUKAN penjualan: belum dibayar, tidak masuk riwayat
/// pesanan, tidak masuk laporan shift — ia baru menjadi penjualan
/// bila dilanjutkan lalu kode bayarnya lunas.
///
/// Pesanan ditahan tidak terikat shift: menutup shift TIDAK
/// menghapusnya (layar hanya memperingatkan kasir saat Tutup
/// Shift), dan ia bisa dilanjutkan di shift berikutnya. Yang
/// boleh menghapusnya hanya kasir: Lanjutkan (pindah jadi
/// pesanan berjalan) atau Hapus manual dari daftar tahan.
class HeldOrder {
  /// Id unik entri (dibuat pemanggil dari jam mikrodetik —
  /// cukup unik untuk satu perangkat kasir).
  final String id;
  final DateTime heldAt;
  final List<OrderLine> lines;
  final Discount? orderDiscount;

  const HeldOrder({
    required this.id,
    required this.heldAt,
    required this.lines,
    required this.orderDiscount,
  });

  /// Total akhir pesanan ini bila dibuat kode bayar sekarang —
  /// dihitung dengan fungsi yang sama dengan layar kasir.
  int get grandTotalNusan => orderGrandTotalNusan(lines, orderDiscount);

  /// Jumlah item keseluruhan (Σ qty semua baris) — bahan
  /// ringkasan entri di daftar tahan.
  int get totalQty => lines.fold(0, (sum, l) => sum + l.qty);

  Map<String, Object?> toJson() => {
    'id': id,
    'heldAtMs': heldAt.millisecondsSinceEpoch,
    'lines': lines.map(orderLineToJson).toList(),
    'orderDiscount': discountToJson(orderDiscount),
  };

  /// Baca satu entri; null bila bentuknya tidak sah (id/waktu
  /// wajib ada, baris wajib non-kosong dan semuanya sah —
  /// entri tahan yang rusak sebagian tidak boleh dilanjutkan
  /// menjadi pesanan yang salah).
  static HeldOrder? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final heldAtMs = raw['heldAtMs'];
    final rawLines = raw['lines'];
    if (id is! String || id.isEmpty) return null;
    if (heldAtMs is! num || rawLines is! List || rawLines.isEmpty) {
      return null;
    }
    final lines = <OrderLine>[];
    for (final entry in rawLines) {
      final line = orderLineFromJson(entry);
      if (line == null) return null;
      lines.add(line);
    }
    return HeldOrder(
      id: id,
      heldAt: DateTime.fromMillisecondsSinceEpoch(heldAtMs.toInt()),
      lines: lines,
      orderDiscount: discountFromJson(raw['orderDiscount']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HeldOrder &&
      other.id == id &&
      other.heldAt.millisecondsSinceEpoch ==
          heldAt.millisecondsSinceEpoch &&
      other.orderDiscount == orderDiscount &&
      _heldLinesEqual(other.lines, lines);

  @override
  int get hashCode => Object.hash(
    id,
    heldAt.millisecondsSinceEpoch,
    orderDiscount,
    Object.hashAll(lines),
  );
}

bool _heldLinesEqual(List<OrderLine> a, List<OrderLine> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String encodeHeldOrders(List<HeldOrder> orders) =>
    jsonEncode(orders.map((o) => o.toJson()).toList());

/// Baca daftar tahan dari string simpanan; fail-open seperti
/// store lokal lain: rusak → kosong, entri tak sah dilewati
/// satu-satu.
List<HeldOrder> decodeHeldOrders(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  Object? parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (parsed is! List) return const [];
  final orders = <HeldOrder>[];
  for (final entry in parsed) {
    final order = HeldOrder.fromJson(entry);
    if (order != null) orders.add(order);
  }
  return orders;
}

/// Penyimpanan daftar tahan Mode Toko di SharedPreferences.
///
/// Batas simpan [maxRecords] entri TERBARU (pola yang sama
/// dengan riwayat pesanan & shift): menahan adalah parkir
/// sementara untuk tamu yang bayar belakangan — 50 entri jauh di
/// atas kebutuhan satu toko, dan entri tertua yang terbuang oleh
/// batas ini adalah yang paling lama tidak dilanjutkan.
class HeldOrderStore {
  static const String storageKey = 'store_held_orders_v1';
  static const int maxRecords = 50;

  Future<List<HeldOrder>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return decodeHeldOrders(prefs.getString(storageKey));
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<HeldOrder> orders) async {
    try {
      final trimmed = orders.length > maxRecords
          ? orders.sublist(orders.length - maxRecords)
          : orders;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, encodeHeldOrders(trimmed));
    } catch (_) {
      // Abaikan — daftar tahan di layar tetap yang berlaku sesi ini.
    }
  }
}
