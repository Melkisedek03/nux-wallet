/// Keputusan murni pengawas event pembayaran masuk di layar Terima.
///
/// Pengawas event (poll Event_PaymentReceived dari antrean node)
/// bersenjata SELAMA layar Terima aktif ([screenActive]) — bukan
/// hanya saat ada invoice pending atau panel Kode Bayar Statis
/// sedang terbuka. Offer Bolt12 tidak punya kedaluwarsa dan bisa
/// dibayar kapan pun; pembayaran yang tiba saat QR kode statis
/// TIDAK sedang ditampilkan tetap pembayaran sungguhan ke dompet
/// ini, dan panel sukses layar Terima harus merayakannya juga
/// (temuan lapangan NUX 3 Nov 2026: sebelumnya pengawas mati pada
/// keadaan itu, jadi hanya suara + getar dari detektor dashboard
/// yang muncul, tanpa animasi centang).
///
/// Perlindungan dari perayaan palsu bukan di gerbang ini: antrean
/// event dikuras lebih dulu saat pengawas mulai (event lama milik
/// pembayaran yang tiba saat user di layar lain dibuang), dan
/// pengawas berhenti total saat layar ditutup (dispose) — antrean
/// adalah milik bersama satu node, tidak boleh dikuras layar yang
/// sudah tidak aktif.
library;

/// Berapa lama panel sukses ("Pembayaran diterima") tampil
/// sebelum layar Terima mereset dirinya dan siap menerima
/// pembayaran berikutnya. Cukup untuk notif + getar + animasi
/// centang terbaca user, cukup singkat untuk kasir Mode Toko.
const receiveCelebrationDuration = Duration(seconds: 5);

/// Haruskah pengawas event layar Terima berjalan pada keadaan ini?
/// Ya, selama layarnya aktif; tidak, sesudah layarnya ditutup.
bool receiveWatcherShouldRun({required bool screenActive}) => screenActive;
