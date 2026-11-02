/// Keputusan murni pengawas event pembayaran masuk di layar Terima.
///
/// Pengawas event (poll Event_PaymentReceived dari antrean node)
/// hanya berguna selama ada sesuatu yang sedang ditunggu layar:
///
/// - invoice Bolt11 yang belum lunas ([invoicePending]),
/// - panel Kode Bayar Statis yang sedang terbuka
///   ([staticPanelOpen]) — offer Bolt12 tidak punya kedaluwarsa
///   dan bisa dibayar kapan pun selama panel tampil, dan
/// - panel sukses yang sedang merayakan penerimaan
///   ([celebrating]) — pengawas tetap hidup selama jendela ini
///   supaya pembayaran berikutnya yang tiba di tengah perayaan
///   tetap tertangkap dan menggantikan panel, bukan hilang
///   diam-diam di antrean.
///
/// Di luar ketiga keadaan itu pengawas berhenti: antrean event
/// adalah milik bersama satu node, tidak ada gunanya dikuras
/// layar ini saat tidak ada yang ditunggu.
library;

/// Berapa lama panel sukses ("Pembayaran diterima") tampil
/// sebelum layar Terima mereset dirinya dan siap menerima
/// pembayaran berikutnya. Cukup untuk notif + getar + animasi
/// centang terbaca user, cukup singkat untuk kasir Mode Toko.
const receiveCelebrationDuration = Duration(seconds: 5);

/// Haruskah pengawas event layar Terima berjalan pada keadaan ini?
bool receiveWatcherShouldRun({
  required bool invoicePending,
  required bool staticPanelOpen,
  required bool celebrating,
}) =>
    invoicePending || staticPanelOpen || celebrating;
