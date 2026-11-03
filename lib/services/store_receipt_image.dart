import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Tulis gambar struk Mode Toko untuk dibagikan: tangkapan
/// pratinjau (PNG dari RepaintBoundary) dikonversi menjadi
/// **JPG** (paket `image`, murni Dart; kualitas 90; diratakan
/// ke latar putih karena JPG tak punya alfa) di direktori
/// sementara aplikasi.
///
/// Bila konversi gagal karena alasan apa pun, berkas PNG
/// aslinya yang ditulis — berbagi struk tidak boleh gagal
/// total hanya karena konversi format.
Future<File> writeReceiptShareImage(
  Uint8List pngBytes, {
  required String fileStem,
}) async {
  final dir = await getTemporaryDirectory();
  try {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) throw StateError('tangkapan struk tak terbaca');
    final flat = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 3,
    );
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, decoded);
    final jpgBytes = img.encodeJpg(flat, quality: 90);
    final file = File('${dir.path}/$fileStem.jpg');
    await file.writeAsBytes(jpgBytes);
    return file;
  } catch (_) {
    final file = File('${dir.path}/$fileStem.png');
    await file.writeAsBytes(pngBytes);
    return file;
  }
}
