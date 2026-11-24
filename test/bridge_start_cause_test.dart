import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/services/bridge_start_cause.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('classifyBridgeStartFailure (G2.3)', () {
    test('izin ditolak → permission', () {
      expect(
        classifyBridgeStartFailure(
          permissionsGranted: false,
          locationService: ServiceStatus.enabled,
          bluetoothService: ServiceStatus.enabled,
        ),
        BridgeStartCause.permission,
      );
    });

    test('izin ok + Lokasi mati → locationOff', () {
      expect(
        classifyBridgeStartFailure(
          permissionsGranted: true,
          locationService: ServiceStatus.disabled,
          bluetoothService: ServiceStatus.enabled,
        ),
        BridgeStartCause.locationOff,
      );
    });

    test('izin ok + Lokasi nyala + Bluetooth mati → bluetoothOff', () {
      expect(
        classifyBridgeStartFailure(
          permissionsGranted: true,
          locationService: ServiceStatus.enabled,
          bluetoothService: ServiceStatus.disabled,
        ),
        BridgeStartCause.bluetoothOff,
      );
    });

    test('semua ok → unknown', () {
      expect(
        classifyBridgeStartFailure(
          permissionsGranted: true,
          locationService: ServiceStatus.enabled,
          bluetoothService: ServiceStatus.enabled,
        ),
        BridgeStartCause.unknown,
      );
    });

    test('prioritas: izin mengalahkan layanan yang mati', () {
      expect(
        classifyBridgeStartFailure(
          permissionsGranted: false,
          locationService: ServiceStatus.disabled,
          bluetoothService: ServiceStatus.disabled,
        ),
        BridgeStartCause.permission,
      );
    });

    test('prioritas: Lokasi mengalahkan Bluetooth', () {
      expect(
        classifyBridgeStartFailure(
          permissionsGranted: true,
          locationService: ServiceStatus.disabled,
          bluetoothService: ServiceStatus.disabled,
        ),
        BridgeStartCause.locationOff,
      );
    });

    test('layanan notApplicable bukan mati → unknown', () {
      expect(
        classifyBridgeStartFailure(
          permissionsGranted: true,
          locationService: ServiceStatus.notApplicable,
          bluetoothService: ServiceStatus.notApplicable,
        ),
        BridgeStartCause.unknown,
      );
    });
  });
}
