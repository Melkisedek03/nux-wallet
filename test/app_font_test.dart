import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nux_wallet/theme.dart';

bool _containsBytes(Uint8List hay, List<int> needle) {
  if (needle.isEmpty || hay.length < needle.length) return false;
  outer:
  for (var i = 0; i <= hay.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('font aplikasi adalah Momo Trust Display', () {
    expect(AppTheme.fontFamily, 'Momo Trust Display');
  });

  test('kedua tema memakai font aplikasi', () {
    // ThemeData tidak mengekspos fontFamily sebagai getter —
    // konstruktor menerapkannya ke textTheme, jadi itu yang
    // diperiksa.
    expect(
      AppTheme.darkTheme.textTheme.bodyMedium?.fontFamily,
      AppTheme.fontFamily,
    );
    expect(
      AppTheme.lightTheme.textTheme.bodyMedium?.fontFamily,
      AppTheme.fontFamily,
    );
  });

  test('berkas font terdaftar dan ikut ter-bundle', () async {
    final data =
        await rootBundle.load('assets/fonts/MomoTrustDisplay-Regular.ttf');
    final bytes = data.buffer.asUint8List();
    expect(bytes.length, greaterThan(50000));
    // Tanda TTF (sfnt version 1.0) + nama keluarga di name table.
    // Nama tersimpan UTF-16BE (tiap karakter didahului 0x00).
    expect(bytes.sublist(0, 4), [0x00, 0x01, 0x00, 0x00]);
    final nameUtf16be = 'Momo Trust Display'
        .codeUnits
        .expand((c) => [0, c])
        .toList();
    expect(_containsBytes(bytes, nameUtf16be), isTrue);
  });
}
