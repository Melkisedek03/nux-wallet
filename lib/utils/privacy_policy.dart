/// Kebijakan privasi ELNUX — URL publik + aturan "gulir sampai bawah".
///
/// Kebijakan di-host sebagai halaman statis di GitHub Pages repo ini
/// (sumber: `docs/kebijakan-privasi-elnux.html` + `docs/privacy-policy-elnux.html`,
/// diaktifkan lewat Settings → Pages, sumber main + /docs). URL ini dipakai
/// di dua tempat: layar persetujuan sekali sesudah instalasi dan tautan
/// baca di kaki tab Profil — keduanya menampilkan halaman yang sama
/// lewat WebView (lihat lib/screens/privacy_policy_screen.dart).
library;

/// URL kebijakan privasi Bahasa Indonesia.
const privacyPolicyUrlId =
    'https://nusanian.github.io/nux-wallet/kebijakan-privasi-elnux.html';

/// URL kebijakan privasi Bahasa Inggris.
const privacyPolicyUrlEn =
    'https://nusanian.github.io/nux-wallet/privacy-policy-elnux.html';

/// Pilih URL kebijakan sesuai bahasa tampilan aplikasi: 'id' → halaman
/// Indonesia, bahasa lain → halaman Inggris.
String privacyPolicyUrlFor(String languageCode) =>
    languageCode == 'id' ? privacyPolicyUrlId : privacyPolicyUrlEn;

/// Apakah posisi gulir sudah mencapai bawah halaman.
///
/// Dipakai untuk mengaktifkan centangan persetujuan: centangan hanya
/// aktif sesudah user menggulir sampai bawah (keputusan NUX 25 Nov 2026).
/// [scrollTop] = jarak gulir dari atas, [clientHeight] = tinggi viewport,
/// [scrollHeight] = tinggi total konten. [threshold] memberi toleransi
/// (pembulatan piksel / bilah alamat) supaya "bawah" tidak menuntut
/// piksel yang persis.
///
/// Kasus tanpa guliran (konten muat dalam viewport: [scrollHeight]
/// <= [clientHeight]) juga mengembalikan true — tidak ada yang bisa
/// digulir, jadi tidak ada yang perlu ditunggu.
bool isScrolledToBottom({
  required double scrollTop,
  required double clientHeight,
  required double scrollHeight,
  double threshold = 24,
}) {
  return scrollTop + clientHeight >= scrollHeight - threshold;
}
