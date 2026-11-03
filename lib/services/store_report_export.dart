import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Susun PDF laporan penjualan Mode Toko dari dua dokumen teks
/// yang sama dengan versi cetak 58mm (fon Courier supaya
/// perataan kolom monospace persis sama), simpan ke cache, dan
/// kembalikan berkasnya untuk dibagikan lewat share sheet
/// (pola SharePlus yang sama dengan Bagikan Log).
Future<File> writeShiftReportPdf({
  required String summaryText,
  required String detailsText,
  required String fileStem,
}) async {
  pw.Widget lineWidget(String line) => pw.Text(
    line.isEmpty ? ' ' : line,
    style: pw.TextStyle(font: pw.Font.courier(), fontSize: 9.5),
  );

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => [
        for (final line in summaryText.split('\n')) lineWidget(line),
        pw.SizedBox(height: 24),
        for (final line in detailsText.split('\n')) lineWidget(line),
      ],
    ),
  );

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileStem.pdf');
  await file.writeAsBytes(await doc.save());
  return file;
}
