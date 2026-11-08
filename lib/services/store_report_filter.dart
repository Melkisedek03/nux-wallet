/// Filter periode BERSAMA untuk laporan-laporan Mode Toko
/// (pondasi yang disetujui NUX 8 Nov 2026: filter yang sama
/// dipakai setiap laporan — Daftar Laporan tinggal menambah
/// layar, filternya tidak dibuat ulang). Murni & bisa dites:
/// widget pemilihnya ada di
/// `widgets/store_report_period_chips.dart`, jendela hasil
/// filter ini yang diberikan ke fungsi agregasi laporan.
library;

/// Pilihan periode laporan.
enum StoreReportPeriod {
  /// Hari kalender ini, dari awal hari sampai awal hari besok.
  today,

  /// Jendela bergulir 7 × 24 jam ke belakang dari sekarang.
  last7Days,

  /// Jendela bergulir 30 × 24 jam ke belakang dari sekarang.
  last30Days,

  /// Semua catatan (tanpa batas bawah yang berarti).
  all,

  /// Rentang tanggal pilihan sendiri dari pemilih tanggal —
  /// hari pertama & terakhir inklusif (hari kalender utuh).
  custom,
}

/// Pilihan filter yang sedang aktif: satu [period] + (hanya
/// untuk [StoreReportPeriod.custom]) rentang tanggalnya.
/// [customStart]/[customEnd] adalah tanggal kalender (jamnya
/// diabaikan oleh [storeReportWindowFor]).
class StoreReportFilter {
  final StoreReportPeriod period;
  final DateTime? customStart;
  final DateTime? customEnd;

  const StoreReportFilter(this.period, {this.customStart, this.customEnd});

  /// Filter preset tanpa rentang tanggal.
  const StoreReportFilter.preset(StoreReportPeriod period)
    : this(period);

  bool get isCustom => period == StoreReportPeriod.custom;

  @override
  bool operator ==(Object other) =>
      other is StoreReportFilter &&
      other.period == period &&
      other.customStart == customStart &&
      other.customEnd == customEnd;

  @override
  int get hashCode => Object.hash(period, customStart, customEnd);
}

/// Batas jendela laporan: [from] inklusif, [to] eksklusif.
typedef StoreReportWindow = ({DateTime from, DateTime to});

/// Hitung jendela untuk [filter] relatif terhadap [now].
///
/// Ujung atas preset adalah awal hari besok (bukan `now`
/// persis) supaya penjualan yang baru saja lunas tidak
/// tersisih hanya karena perbedaan detik/jam perangkat.
/// Preset berjalan memakai jendela bergulir 7/30 × 24 jam dari
/// [now]. Preset custom memakai hari kalender utuh: dari awal
/// hari pertama sampai awal hari sesudah hari terakhir, jadi
/// tanggal akhir pilihan pemilih ikut tercakup seluruhnya.
StoreReportWindow storeReportWindowFor(
  StoreReportFilter filter, {
  required DateTime now,
}) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  final tomorrow = startOfToday.add(const Duration(days: 1));
  switch (filter.period) {
    case StoreReportPeriod.today:
      return (from: startOfToday, to: tomorrow);
    case StoreReportPeriod.last7Days:
      return (from: now.subtract(const Duration(days: 7)), to: tomorrow);
    case StoreReportPeriod.last30Days:
      return (from: now.subtract(const Duration(days: 30)), to: tomorrow);
    case StoreReportPeriod.all:
      return (from: DateTime(2000), to: tomorrow);
    case StoreReportPeriod.custom:
      final s = filter.customStart ?? startOfToday;
      final e = filter.customEnd ?? s;
      return (
        from: DateTime(s.year, s.month, s.day),
        to: DateTime(
          e.year,
          e.month,
          e.day,
        ).add(const Duration(days: 1)),
      );
  }
}
