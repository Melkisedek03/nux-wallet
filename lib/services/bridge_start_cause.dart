import 'package:permission_handler/permission_handler.dart';

/// Penyebab kegagalan mulai jembatan Mode Offline (G2.3): Nearby
/// hanya mengembalikan bool, jadi penyebabnya tidak terbaca dari
/// kegagalannya sendiri — harus diuji langsung dari sistem.
enum BridgeStartCause {
  /// Izin Bluetooth atau Lokasi belum diberikan.
  permission,

  /// Layanan Lokasi perangkat mati.
  locationOff,

  /// Adapter Bluetooth perangkat mati.
  bluetoothOff,

  /// Penyebab tidak bisa dibedakan — pemanggil menampilkan pesan
  /// fallback yang tetap menyebut tindakannya.
  unknown,
}

/// Klasifikasi murni (tanpa panggilan platform) untuk
/// [probeBridgeStartCause] — urutan prioritas: izin dulu, lalu
/// layanan Lokasi, lalu Bluetooth.
///
/// Izin dicek PERTAMA karena dua alasan platform: di Android 12+,
/// `BluetoothAdapter.isEnabled()` membutuhkan izin
/// BLUETOOTH_CONNECT (tanpa izin melempar SecurityException), dan
/// di iOS pengecekan layanan Bluetooth memicu prompt bila izin
/// belum pernah diminta.
BridgeStartCause classifyBridgeStartFailure({
  required bool permissionsGranted,
  required ServiceStatus locationService,
  required ServiceStatus bluetoothService,
}) {
  if (!permissionsGranted) return BridgeStartCause.permission;
  if (locationService == ServiceStatus.disabled) {
    return BridgeStartCause.locationOff;
  }
  if (bluetoothService == ServiceStatus.disabled) {
    return BridgeStartCause.bluetoothOff;
  }
  return BridgeStartCause.unknown;
}

/// Izin yang harus diberikan agar Nearby bisa mengiklankan dan
/// menemukan perangkat. Set yang sama dengan yang diminta layar
/// Uji Offline — tanpa `nearbyWifiDevices`: izin itu hanya ada di
/// Android 13+ dan di perangkat lama terbaca sebagai ditolak,
/// sehingga mengarang penyebab izin yang sebenarnya tidak ada.
/// (permission_handler memetakan tiga izin Bluetooth baru ke izin
/// BLUETOOTH lama di perangkat sebelum Android 12, jadi set ini
/// bermakna di semua versi Android.)
const _requiredPermissions = <Permission>[
  Permission.bluetoothScan,
  Permission.bluetoothAdvertise,
  Permission.bluetoothConnect,
  Permission.locationWhenInUse,
];

/// Uji penyebab kegagalan mulai jembatan dari sistem.
/// Gagal-terbuka: bila ada pemeriksaan yang melempar (perilaku
/// platform yang tidak terduga), hasilnya
/// [BridgeStartCause.unknown] — pesan fallback tetap menyebut
/// tindakan yang perlu dicoba pengguna.
Future<BridgeStartCause> probeBridgeStartCause() async {
  try {
    var granted = true;
    for (final permission in _requiredPermissions) {
      if (!await permission.isGranted) {
        granted = false;
        break;
      }
    }
    final locationService = await Permission.location.serviceStatus;
    final bluetoothService = await Permission.bluetooth.serviceStatus;
    return classifyBridgeStartFailure(
      permissionsGranted: granted,
      locationService: locationService,
      bluetoothService: bluetoothService,
    );
  } catch (_) {
    return BridgeStartCause.unknown;
  }
}
