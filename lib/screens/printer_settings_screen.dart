import 'dart:async';

import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../locale_controller.dart';
import '../services/bluetooth_klasik.dart';
import '../services/print_service.dart';
import '../theme.dart';

/// Tebakan nama printer dari pola umum printer thermal — hanya
/// untuk urutan/ikon di daftar, tidak pernah menyembunyikan
/// perangkat: daftar ter-pairing dari OS memang berisi semua
/// perangkat Bluetooth, dan printer generik sering bernama di
/// luar pola ini.
bool looksLikePrinter(String name) {
  final n = name.toLowerCase();
  const hints = [
    'printer',
    'print',
    'pos',
    'thermal',
    'mtp',
    'rpp',
    'zj',
    'munbyn',
    'receipt',
    'label',
  ];
  return hints.any(n.contains);
}

/// Halaman Pengaturan Printer — pilih printer struk 58mm,
/// nyalakan Bluetooth dan pasangkan printer baru dari dalam
/// aplikasi bila belum ada, uji cetak, dan atur teks
/// header/footer struk (dipakai juga nanti oleh mini POS).
class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  PrinterSettings _settings = const PrinterSettings();
  List<BluetoothInfo> _paired = const [];
  bool _loaded = false;
  bool _printing = false;
  bool _btOn = true;
  bool _scanning = false;
  String? _bondingAddress;
  List<PerangkatBluetoothKlasik> _discovered = const [];
  final _bluetoothKlasik = BluetoothKlasik();
  StreamSubscription<StatusAdapterBluetooth>? _adapterSub;
  StreamSubscription<PerangkatBluetoothKlasik>? _scanSub;
  StreamSubscription<bool>? _scanningSub;
  final _headerController = TextEditingController();
  final _footerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    _scanSub?.cancel();
    _scanningSub?.cancel();
    _bluetoothKlasik.stopScan();
    _headerController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await PrintService.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _headerController.text = settings.headerText;
      _footerController.text = settings.footerText;
      _loaded = true;
    });
    _adapterSub = _bluetoothKlasik.adapterState.listen((state) {
      if (!mounted) return;
      final on = state == StatusAdapterBluetooth.menyala;
      if (on == _btOn) return;
      setState(() => _btOn = on);
      if (on) _refreshPaired(autoScan: true);
    });
    _scanningSub = _bluetoothKlasik.isScanning.listen((scanning) {
      if (mounted) setState(() => _scanning = scanning);
    });
    final enabled = await _bluetoothKlasik.isEnabled;
    if (!mounted) return;
    setState(() => _btOn = enabled);
    if (!enabled) {
      // Membuka halaman Printer meminta Bluetooth menyala —
      // Android menampilkan satu dialog konfirmasi sistem,
      // pengguna tidak perlu keluar aplikasi. Daftar dimuat
      // oleh pendengar adapterState saat Bluetooth menyala.
      await _bluetoothKlasik.turnOn();
      return;
    }
    await _refreshPaired(autoScan: true);
  }

  Future<void> _refreshPaired({bool autoScan = false}) async {
    final paired = await PrintService.pairedPrinters();
    if (!mounted) return;
    setState(() => _paired = paired);
    if (autoScan && !_settings.hasPrinter) _startScan();
  }

  Future<void> _startScan() async {
    if (_scanning || !_btOn) return;
    // Izin SCAN Android 12+ satu paket dengan izin koneksi
    // yang diminta paket transport saat memuat daftar pairing.
    final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!granted || !mounted) return;
    setState(() => _discovered = const []);
    _scanSub?.cancel();
    _scanSub = _bluetoothKlasik.scanResults.listen((device) {
      if (!mounted) return;
      setState(() {
        final next = [..._discovered];
        final i = next.indexWhere((d) => d.address == device.address);
        if (i >= 0) {
          next[i] = device;
        } else {
          next.add(device);
        }
        _discovered = next;
      });
    });
    _bluetoothKlasik.startScan();
  }

  void _stopScan() {
    _bluetoothKlasik.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
  }

  Future<void> _bondAndSelect(PerangkatBluetoothKlasik device) async {
    final l10n = context.l10n;
    if (device.statusBond != StatusBondBluetooth.terpasang) {
      setState(() => _bondingAddress = device.address);
      final ok = await _bluetoothKlasik.bondDevice(device.address);
      if (!mounted) return;
      setState(() => _bondingAddress = null);
      if (!ok) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.printerBondFailed)));
        return;
      }
    }
    final next = _settings.copyWith(
      macAddress: device.address,
      printerName: (device.name == null || device.name!.isEmpty)
          ? device.address
          : device.name!,
    );
    setState(() => _settings = next);
    await PrintService.saveSettings(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.printerPairedSelected)));
    await _refreshPaired();
  }

  Future<void> _pickPrinter() async {
    final l10n = context.l10n;
    if (_paired.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.printerNoPaired)));
      return;
    }
    final picked = await showDialog<BluetoothInfo>(
      context: context,
      builder: (ctx) => _PrinterPickerDialog(
        devices: _paired,
        selectedMac: _settings.macAddress,
      ),
    );
    if (picked == null) return;
    final next = _settings.copyWith(
      macAddress: picked.macAdress,
      printerName: picked.name,
    );
    setState(() => _settings = next);
    await PrintService.saveSettings(next);
  }

  Future<void> _testPrint() async {
    setState(() => _printing = true);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final timeText =
        '${two(now.day)}-${two(now.month)}-${now.year} ${two(now.hour)}:${two(now.minute)}';
    final outcome = await PrintService.printTest(
      settings: _settings,
      testTitle: context.l10n.printerTest,
      timeText: timeText,
      defaultFooter: context.l10n.receiptDefaultFooter,
    );
    if (!mounted) return;
    setState(() => _printing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(printOutcomeMessage(context.l10n, outcome))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Perangkat hasil pindai yang sudah ter-pairing tidak
    // ditampilkan dua kali.
    final pairedMacs = _paired.map((d) => d.macAdress).toSet();
    final visibleDiscovered =
        _discovered.where((d) => !pairedMacs.contains(d.address)).toList()
          ..sort((a, b) {
            final pa = looksLikePrinter(a.name ?? '') ? 0 : 1;
            final pb = looksLikePrinter(b.name ?? '') ? 0 : 1;
            return pa.compareTo(pb);
          });
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.printerSettings),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.palette.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: context.palette.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.print_rounded,
                            color: Color(0xFF34D399),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _settings.hasPrinter
                                      ? _settings.printerName
                                      : l10n.printerNoneSelected,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_settings.hasPrinter) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    _settings.macAddress,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: context.palette.muted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _pickPrinter,
                              child: Text(l10n.printerSelect),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _printing ? null : _testPrint,
                              child: Text(l10n.printerTest),
                            ),
                          ),
                        ],
                      ),
                      if (_paired.isEmpty && _btOn) ...[
                        const SizedBox(height: 10),
                        Text(
                          l10n.printerNoPaired,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                if (!_btOn) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.palette.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: context.palette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.printBluetoothOff,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: () => _bluetoothKlasik.turnOn(),
                          child: Text(l10n.printerTurnOn),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                ],
                if (_btOn) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.printerDiscovered,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _scanning ? _stopScan : _startScan,
                        icon: Icon(
                          _scanning ? Icons.stop_rounded : Icons.search_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _scanning ? l10n.printerScanning : l10n.printerScan,
                        ),
                      ),
                    ],
                  ),
                  if (_scanning && visibleDiscovered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l10n.printerScanning,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final device in visibleDiscovered)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: context.palette.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.palette.border),
                      ),
                      child: ListTile(
                        leading: Icon(
                          looksLikePrinter(device.name ?? '')
                              ? Icons.print_rounded
                              : Icons.bluetooth_rounded,
                          color: const Color(0xFF34D399),
                        ),
                        title: Text(
                          (device.name == null || device.name!.isEmpty)
                              ? device.address
                              : device.name!,
                        ),
                        subtitle: Text(
                          '${device.address} · ${l10n.printerTapToPair}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: _bondingAddress == device.address
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: _bondingAddress == null
                            ? () => _bondAndSelect(device)
                            : null,
                      ),
                    ),
                  const SizedBox(height: 22),
                ],
                Text(
                  l10n.printerHeader,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.printerHeaderHint,
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _headerController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'ELNUX',
                  ),
                  onChanged: (value) {
                    _settings = _settings.copyWith(headerText: value);
                    PrintService.saveSettings(_settings);
                  },
                ),
                const SizedBox(height: 22),
                Text(
                  l10n.printerFooter,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.printerFooterHint,
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _footerController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: l10n.receiptDefaultFooter,
                  ),
                  onChanged: (value) {
                    _settings = _settings.copyWith(footerText: value);
                    PrintService.saveSettings(_settings);
                  },
                ),
              ],
            ),
    );
  }
}

/// Dialog pemilih printer ter-pairing: daftar dibatasi
/// tingginya dan bisa digulir (daftar pairing OS bisa panjang),
/// ada kolom pencarian, dan perangkat bernama khas printer
/// tampil lebih dulu dengan ikon printer. Tidak ada perangkat
/// yang disembunyikan.
class _PrinterPickerDialog extends StatefulWidget {
  const _PrinterPickerDialog({
    required this.devices,
    required this.selectedMac,
  });

  final List<BluetoothInfo> devices;
  final String selectedMac;

  @override
  State<_PrinterPickerDialog> createState() => _PrinterPickerDialogState();
}

class _PrinterPickerDialogState extends State<_PrinterPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final q = _query.trim().toLowerCase();
    final visible =
        widget.devices.where((d) {
          if (q.isEmpty) return true;
          return d.name.toLowerCase().contains(q) ||
              d.macAdress.toLowerCase().contains(q);
        }).toList()..sort((a, b) {
          final pa = looksLikePrinter(a.name) ? 0 : 1;
          final pb = looksLikePrinter(b.name) ? 0 : 1;
          return pa.compareTo(pb);
        });
    return AlertDialog(
      backgroundColor: context.palette.card,
      title: Text(l10n.printerSelect),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: false,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: l10n.printerSearchHint,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: visible.length,
                itemBuilder: (ctx, i) {
                  final device = visible[i];
                  final isPrinter = looksLikePrinter(device.name);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isPrinter ? Icons.print_rounded : Icons.bluetooth_rounded,
                      color: isPrinter
                          ? const Color(0xFF34D399)
                          : context.palette.muted,
                    ),
                    title: Text(device.name),
                    subtitle: Text(device.macAdress),
                    trailing: device.macAdress == widget.selectedMac
                        ? const Icon(
                            Icons.check_rounded,
                            color: Color(0xFF34D399),
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, device),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
