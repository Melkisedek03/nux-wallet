import 'dart:async';

import 'package:flutter/services.dart';

/// Status adapter Bluetooth sebagaimana dibutuhkan layar
/// Pengaturan Printer: hanya menyala/tidak yang dibedakan —
/// keadaan peralihan dilipat ke [mati] karena layar hanya
/// bereaksi pada menyala.
enum StatusAdapterBluetooth { menyala, mati }

/// Status pemasangan (bonding) satu perangkat.
enum StatusBondBluetooth { belum, proses, terpasang }

/// Satu perangkat Bluetooth Classic hasil penemuan.
class PerangkatBluetoothKlasik {
  const PerangkatBluetoothKlasik({
    required this.address,
    required this.name,
    required this.statusBond,
  });

  /// Alamat MAC — identitas stabil perangkat.
  final String address;

  /// Nama siaran perangkat; bisa null bila sistem tidak
  /// memberikannya.
  final String? name;

  final StatusBondBluetooth statusBond;
}

/// Layanan Bluetooth Classic milik sendiri untuk layar
/// Pengaturan Printer — pengganti paket flutter_blue_classic
/// yang berlisensi GPL-3.0 (satu-satunya dependensi copyleft
/// di aplikasi; lihat BluetoothKlasik.kt di sisi Android).
///
/// Permukaannya sengaja disamai dengan yang dulu dipakai layar
/// itu: status adapter, menyalakan Bluetooth, penemuan
/// perangkat yang belum terpasang, dan bonding dari dalam
/// aplikasi — semuanya di atas API Android bawaan lewat
/// MethodChannel/EventChannel. Daftar perangkat yang sudah
/// terpasang dan transport cetak tetap ditangani
/// print_bluetooth_thermal lewat PrintService, tidak berubah.
class BluetoothKlasik {
  static const MethodChannel _saluran =
      MethodChannel('nux_wallet/bluetooth_klasik');
  static const EventChannel _saluranPeristiwa =
      EventChannel('nux_wallet/bluetooth_klasik/peristiwa');

  Stream<Map<dynamic, dynamic>>? _peristiwa;

  /// Arus peristiwa mentah dari sisi Android, dibagi ke tiga
  /// arus turunan di bawah. Broadcast: banyak pendengar boleh
  /// menempel; langganan pertama membuka saluran, lepasnya
  /// pendengar terakhir menutupnya (penerima siaran di sisi
  /// Android mengikuti hidup saluran ini).
  Stream<Map<dynamic, dynamic>> get _arusPeristiwa {
    return _peristiwa ??= _saluranPeristiwa
        .receiveBroadcastStream()
        .map((e) => e as Map<dynamic, dynamic>)
        .asBroadcastStream();
  }

  /// Perubahan status adapter (dan keadaan awal saat saluran
  /// dibuka).
  Stream<StatusAdapterBluetooth> get adapterState => _arusPeristiwa
      .where((e) => e['jenis'] == 'adapter')
      .map((e) => e['menyala'] == true
          ? StatusAdapterBluetooth.menyala
          : StatusAdapterBluetooth.mati);

  /// True selama penemuan perangkat berjalan.
  Stream<bool> get isScanning => _arusPeristiwa
      .where((e) => e['jenis'] == 'pindai')
      .map((e) => e['aktif'] == true);

  /// Perangkat yang ditemukan selama penemuan berjalan.
  Stream<PerangkatBluetoothKlasik> get scanResults =>
      _arusPeristiwa.where((e) => e['jenis'] == 'perangkat').map(
            (e) => PerangkatBluetoothKlasik(
              address: e['alamat'] as String,
              name: e['nama'] as String?,
              statusBond: switch (e['bond'] as String?) {
                'terpasang' => StatusBondBluetooth.terpasang,
                'proses' => StatusBondBluetooth.proses,
                _ => StatusBondBluetooth.belum,
              },
            ),
          );

  /// Apakah Bluetooth sedang menyala.
  Future<bool> get isEnabled async {
    try {
      return await _saluran.invokeMethod<bool>('menyala') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Minta menyalakan Bluetooth — Android menampilkan dialog
  /// konfirmasi sistem; hasilnya tiba lewat [adapterState].
  Future<void> turnOn() async {
    try {
      await _saluran.invokeMethod<bool>('nyalakan');
    } on PlatformException {
      // Senyap: layar memeriksa ulang status lewat adapterState
      // dan isEnabled; dialog yang ditolak user bukan galat.
    }
  }

  /// Mulai penemuan perangkat Classic di sekitar. Hasilnya
  /// mengalir lewat [scanResults], keaktifannya lewat
  /// [isScanning]; penemuan berhenti sendiri di sisi Android
  /// (±12 detik) atau lewat [stopScan].
  void startScan() {
    _saluran.invokeMethod<bool>('mulaiPindai').catchError((_) => false);
  }

  /// Hentikan penemuan yang sedang berjalan.
  void stopScan() {
    _saluran.invokeMethod<bool>('berhentiPindai').catchError((_) => false);
  }

  /// Pasangkan perangkat pada [address] dari dalam aplikasi
  /// (dialog sistem bisa muncul untuk konfirmasi/PIN).
  /// Mengembalikan true bila perangkat berakhir terpasang.
  Future<bool> bondDevice(String address) async {
    try {
      return await _saluran.invokeMethod<bool>(
            'pasang',
            <String, Object?>{'alamat': address},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }
}
