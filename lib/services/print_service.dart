import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';

/// Pesan lokal untuk satu [PrintOutcome] — dipakai layar
/// Pengaturan Printer dan layar Detail Transaksi.
String printOutcomeMessage(AppLocalizations l10n, PrintOutcome outcome) {
  return switch (outcome) {
    PrintOutcome.success => l10n.printSuccess,
    PrintOutcome.noPrinter => l10n.printNoPrinter,
    PrintOutcome.bluetoothOff => l10n.printBluetoothOff,
    PrintOutcome.permissionDenied => l10n.printPermissionDenied,
    PrintOutcome.failed => l10n.printFailed,
  };
}

/// Pengaturan printer struk: perangkat terpilih (alamat MAC + nama)
/// dan teks header/footer struk. Header/footer kosong berarti pakai
/// bawaan saat mencetak (header 'ELNUX', footer dari bahasa aplikasi).
class PrinterSettings {
  final String macAddress;
  final String printerName;
  final String headerText;
  final String footerText;

  const PrinterSettings({
    this.macAddress = '',
    this.printerName = '',
    this.headerText = '',
    this.footerText = '',
  });

  bool get hasPrinter => macAddress.isNotEmpty;

  PrinterSettings copyWith({
    String? macAddress,
    String? printerName,
    String? headerText,
    String? footerText,
  }) {
    return PrinterSettings(
      macAddress: macAddress ?? this.macAddress,
      printerName: printerName ?? this.printerName,
      headerText: headerText ?? this.headerText,
      footerText: footerText ?? this.footerText,
    );
  }
}

/// Hasil satu percobaan cetak; layar memetakannya ke pesan lokal.
enum PrintOutcome { success, noPrinter, bluetoothOff, permissionDenied, failed }

/// Isi struk satu transaksi. Semua teks sudah dilokalkan dan
/// dibersihkan pemanggil (hanya ASCII — printer thermal tidak
/// mengenal glif seperti panah/emoji pada layar detail).
class ReceiptData {
  final String typeText;
  final String statusText;
  final String amountText;
  final String timeText;

  /// Label + nilai hash pembayaran atau txid; keduanya null bila
  /// catatan tidak punya keduanya.
  final String? hashLabel;
  final String? hashValue;

  /// Invoice yang masih bisa dibayar (masuk, pending, tersimpan,
  /// belum kedaluwarsa) — dicetak sebagai QR perintah native
  /// ESC/POS; null berarti tanpa QR.
  final String? invoice;

  /// Baris rincian bebas (teks monospace apa adanya, satu baris
  /// per entri) yang dicetak di badan struk sesudah baris
  /// jenis/status/waktu — dipakai struk Mode Toko untuk rincian
  /// item pesanan. Null (bawaan) = tanpa rincian: keluaran struk
  /// pemanggil lain TIDAK berubah sama sekali.
  final List<String>? detailLines;

  /// Teks kop struk yang menggantikan header pengaturan printer
  /// untuk struk ini saja — dipakai Mode Toko untuk nama toko.
  /// Null/kosong (bawaan) = kop dari pengaturan printer apa
  /// adanya: keluaran struk pemanggil lain TIDAK berubah.
  final String? headerText;

  const ReceiptData({
    required this.typeText,
    required this.statusText,
    required this.amountText,
    required this.timeText,
    this.hashLabel,
    this.hashValue,
    this.invoice,
    this.detailLines,
    this.headerText,
  });
}

/// Layanan cetak struk 58mm lewat Bluetooth Classic (SPP) dalam
/// mode perintah ESC/POS murni (teks, bukan gambar) agar cepat:
/// byte struk disusun esc_pos_utils_plus, dikirim mentah lewat
/// print_bluetooth_thermal ke printer yang sudah ter-pairing.
class PrintService {
  static const _keyMac = 'printer_mac_address';
  static const _keyName = 'printer_name';
  static const _keyHeader = 'printer_header_text';
  static const _keyFooter = 'printer_footer_text';

  static Future<PrinterSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return PrinterSettings(
      macAddress: prefs.getString(_keyMac) ?? '',
      printerName: prefs.getString(_keyName) ?? '',
      headerText: prefs.getString(_keyHeader) ?? '',
      footerText: prefs.getString(_keyFooter) ?? '',
    );
  }

  static Future<void> saveSettings(PrinterSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMac, settings.macAddress);
    await prefs.setString(_keyName, settings.printerName);
    await prefs.setString(_keyHeader, settings.headerText);
    await prefs.setString(_keyFooter, settings.footerText);
  }

  /// Daftar printer yang sudah ter-pairing di Android. Meminta
  /// izin Bluetooth dulu (paket menampilkan dialog sistemnya
  /// sendiri di Android 12+ lewat panggilan pemeriksaan izin).
  static Future<List<BluetoothInfo>> pairedPrinters() async {
    final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (!granted) return const [];
    try {
      return await PrintBluetoothThermal.pairedBluetooths;
    } catch (_) {
      return const [];
    }
  }

  static Future<PrintOutcome> printReceipt({
    required PrinterSettings settings,
    required ReceiptData receipt,
    required String typeLabel,
    required String statusLabel,
    required String timeLabel,
    required String defaultFooter,
  }) async {
    if (!settings.hasPrinter) return PrintOutcome.noPrinter;
    final kop = receipt.headerText?.trim() ?? '';
    final effectiveSettings = kop.isEmpty
        ? settings
        : settings.copyWith(headerText: kop);
    final bytes = await _receiptBytes(
      settings: effectiveSettings,
      defaultFooter: defaultFooter,
      body: (gen) {
        var b = <int>[];
        b += gen.text(
          receipt.amountText,
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
          ),
          linesAfter: 1,
        );
        b += gen.row([
          PosColumn(text: typeLabel, width: 4),
          PosColumn(text: receipt.typeText, width: 8),
        ]);
        b += gen.row([
          PosColumn(text: statusLabel, width: 4),
          PosColumn(text: receipt.statusText, width: 8),
        ]);
        b += gen.row([
          PosColumn(text: timeLabel, width: 4),
          PosColumn(text: receipt.timeText, width: 8),
        ]);
        final details = receipt.detailLines;
        if (details != null && details.isNotEmpty) {
          b += gen.hr();
          for (final line in details) {
            b += gen.text(_asciiSafe(line.isEmpty ? ' ' : line));
          }
        }
        if (receipt.hashValue != null) {
          b += gen.hr();
          if (receipt.hashLabel != null) b += gen.text(receipt.hashLabel!);
          b += gen.text(receipt.hashValue!);
        }
        if (receipt.invoice != null) {
          b += gen.feed(1);
          b += gen.qrcode(receipt.invoice!);
        }
        return b;
      },
    );
    return _send(settings, bytes);
  }

  /// Cetak teks mentah berbaris (satu perintah teks per baris)
  /// untuk dokumen yang sudah terformat monospace ≤32 kolom —
  /// dipakai laporan penjualan Mode Toko. TANPA bingkai
  /// header/footer struk: dokumen laporan membawa kepala dan
  /// kakinya sendiri. Karakter non-ASCII diganti '?' karena
  /// printer thermal hanya mengenal halaman kode dasar.
  static Future<PrintOutcome> printTextLines({
    required PrinterSettings settings,
    required List<String> lines,
  }) async {
    if (!settings.hasPrinter) return PrintOutcome.noPrinter;
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);
    var bytes = <int>[];
    bytes += gen.reset();
    for (final line in lines) {
      bytes += gen.text(_asciiSafe(line.isEmpty ? ' ' : line));
    }
    bytes += gen.feed(3);
    return _send(settings, bytes);
  }

  static String _asciiSafe(String s) =>
      String.fromCharCodes(s.runes.map((r) => r > 126 ? 63 : r));

  static Future<PrintOutcome> printTest({
    required PrinterSettings settings,
    required String testTitle,
    required String timeText,
    required String defaultFooter,
  }) async {
    if (!settings.hasPrinter) return PrintOutcome.noPrinter;
    final bytes = await _receiptBytes(
      settings: settings,
      defaultFooter: defaultFooter,
      body: (gen) {
        var b = <int>[];
        b += gen.text(
          testTitle,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        b += gen.text(
          timeText,
          styles: const PosStyles(align: PosAlign.center),
        );
        b += gen.text(
          'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
          styles: const PosStyles(align: PosAlign.center),
        );
        b += gen.text(
          'abcdefghijklmnopqrstuvwxyz 0123456789',
          styles: const PosStyles(align: PosAlign.center),
        );
        return b;
      },
    );
    return _send(settings, bytes);
  }

  /// Rangka struk utuh: header (bawaan 'ELNUX' bila kosong), garis,
  /// isi dari [body], garis, footer (bawaan bahasa bila kosong),
  /// lalu umpan kertas — printer 58mm portabel umumnya tanpa
  /// pemotong, jadi tidak ada perintah cut.
  static Future<List<int>> _receiptBytes({
    required PrinterSettings settings,
    required String defaultFooter,
    required List<int> Function(Generator gen) body,
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);
    var bytes = <int>[];
    bytes += gen.reset();

    final header = settings.headerText.trim().isEmpty
        ? 'ELNUX'
        : settings.headerText.trim();
    final headerLines = header.split('\n');
    for (var i = 0; i < headerLines.length; i++) {
      final line = headerLines[i].trim();
      if (line.isEmpty) continue;
      bytes += gen.text(
        line,
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: i == 0 ? PosTextSize.size2 : PosTextSize.size1,
        ),
      );
    }
    bytes += gen.hr();
    bytes += body(gen);
    bytes += gen.hr();

    final footer = settings.footerText.trim().isEmpty
        ? defaultFooter
        : settings.footerText.trim();
    for (final line in footer.split('\n')) {
      final text = line.trim();
      if (text.isEmpty) continue;
      bytes += gen.text(text, styles: const PosStyles(align: PosAlign.center));
    }
    bytes += gen.feed(3);
    return bytes;
  }

  /// Periksa izin + Bluetooth menyala, sambungkan ke printer
  /// terpilih, lalu kirim byte struk apa adanya.
  static Future<PrintOutcome> _send(
    PrinterSettings settings,
    List<int> bytes,
  ) async {
    try {
      final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!granted) return PrintOutcome.permissionDenied;
      if (!await PrintBluetoothThermal.bluetoothEnabled) {
        return PrintOutcome.bluetoothOff;
      }
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: settings.macAddress,
      );
      if (!connected) return PrintOutcome.failed;
      final written = await PrintBluetoothThermal.writeBytes(bytes);
      return written ? PrintOutcome.success : PrintOutcome.failed;
    } catch (_) {
      return PrintOutcome.failed;
    }
  }
}
