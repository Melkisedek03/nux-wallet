// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get appLanguage => 'Bahasa';

  @override
  String get chooseLanguage => 'Pilih Bahasa';

  @override
  String get languageIndonesian => 'Bahasa Indonesia';

  @override
  String get languageEnglish => 'English';

  @override
  String get themeTitle => 'Tema';

  @override
  String get unitTitle => 'Satuan';

  @override
  String get unitSubtitle =>
      'Satuan tampilan jumlah di saldo, kirim, terima, dan riwayat';

  @override
  String get themeSubtitle => 'Gelap atau terang, sesuai selera';

  @override
  String get changeThemeTooltip => 'Ganti tema';

  @override
  String get greetingMorning => 'Selamat pagi';

  @override
  String get greetingAfternoon => 'Selamat siang';

  @override
  String get greetingEvening => 'Selamat sore';

  @override
  String get greetingNight => 'Selamat malam';

  @override
  String get bootConnecting => 'Menghubungkan ke LSP…';

  @override
  String get splashTagline => 'Uangmu, Kendalimu.';

  @override
  String get bootFailedTitle => 'Gagal menghubungkan node';

  @override
  String get bootFailedRetry => 'Coba lagi';

  @override
  String get bootOfflineButton => 'Lanjutkan tanpa internet';

  @override
  String get bootGenericError => 'Terjadi kendala saat memulai dompet.';

  @override
  String get lspNodeIdMissing =>
      'lspNodeId belum diisi di lib/config.dart — minta node id LSP ke operator.';

  @override
  String seedCorrupt(int length, String path) {
    return 'File seed korup (panjang $length, harus 64). Hapus $path untuk generate ulang (DANA LAMA HILANG).';
  }

  @override
  String get exitTitle => 'Keluar dari ELNUX?';

  @override
  String get exitBody =>
      'Aplikasi akan ditutup. Selama aplikasi tertutup, dompet tidak dapat menerima pembayaran.';

  @override
  String get cancel => 'Batal';

  @override
  String get exitConfirm => 'Keluar';

  @override
  String get totalBalance => 'Total Saldo';

  @override
  String get balanceViaLsp => 'Via LSP';

  @override
  String get balanceDirectChannel => 'Channel langsung';

  @override
  String get networkTestnet => 'Lightning Network • Testnet';

  @override
  String get networkMainnet => 'Lightning Network • Mainnet';

  @override
  String get lightningActive => 'Lightning aktif — siap terima instan';

  @override
  String get lightningConnecting => 'Menghubungkan Lightning…';

  @override
  String get legacyStrip =>
      'Dompet ini belum punya frasa backup. Buka tab Profil untuk membuat dompet baru dengan frasa sebelum menerima dana.';

  @override
  String get send => 'Kirim';

  @override
  String get receive => 'Terima';

  @override
  String get activity => 'Aktivitas';

  @override
  String get seeAll => 'Lihat semua';

  @override
  String get noActivity => 'Belum ada aktivitas';

  @override
  String get market => 'Jelajah';

  @override
  String get jelajahSource => 'Harga pasar — qutrade.io';

  @override
  String jelajahUpdated(String time) {
    return 'Diperbarui $time';
  }

  @override
  String get jelajahChange24h => 'Perubahan 24 jam';

  @override
  String get jelajahBlockHeight => 'Tinggi blok';

  @override
  String get jelajahDirectory => 'Direktori Toko';

  @override
  String get jelajahSearchHint => 'Cari toko atau barang…';

  @override
  String get jelajahAllCities => 'Semua kota';

  @override
  String get jelajahPointsProgram => 'Program Poin Mode Toko';

  @override
  String get jelajahCopyOffer => 'Salin Offer';

  @override
  String get jelajahOfferCopied => 'Offer tersalin';

  @override
  String get jelajahEmpty =>
      'Belum ada toko terdaftar. Pemilik toko dapat mendaftarkan tokonya lewat kanal komunitas Nusacoin.';

  @override
  String get jelajahNoResults => 'Tidak ada toko yang cocok dengan pencarian.';

  @override
  String get jelajahDisclaimer =>
      'Informasi pasar dari sumber publik. Bukan nasihat keuangan.';

  @override
  String jelajahDirectoryUpdated(String time) {
    return 'Direktori diperbarui $time';
  }

  @override
  String get home => 'Beranda';

  @override
  String get history => 'Riwayat';

  @override
  String get profile => 'Profil';

  @override
  String get received => 'Diterima';

  @override
  String get sent => 'Terkirim';

  @override
  String get pending => 'Menunggu';

  @override
  String get processing => 'Sedang diproses';

  @override
  String get failed => 'Gagal';

  @override
  String get noTransactions =>
      'Belum ada transaksi. Pembayaran masuk dan keluar akan tampil di sini.';

  @override
  String get txDetailTitle => 'Detail Transaksi';

  @override
  String get txType => 'Jenis';

  @override
  String get txStatus => 'Status';

  @override
  String get txTime => 'Waktu';

  @override
  String get txPaymentId => 'ID Pembayaran';

  @override
  String get txPaymentHash => 'Hash Pembayaran';

  @override
  String get txNote => 'Catatan';

  @override
  String get txSucceeded => 'Berhasil';

  @override
  String get txExpiredBadge => 'Kedaluwarsa';

  @override
  String get txInvoiceExpiredNote =>
      'Invoice ini sudah kedaluwarsa dan tidak bisa dibayar lagi. Buat invoice baru untuk menerima pembayaran.';

  @override
  String get txInvoiceNotSavedNote =>
      'Invoice ini dibuat sebelum fitur simpan invoice tersedia, jadi string invoice-nya tidak tersimpan di aplikasi dan tidak bisa ditampilkan kembali.';

  @override
  String get txProcessingNote =>
      'Uangmu aman dan sedang menunggu giliran tercatat di jaringan. Akan selesai sendiri.';

  @override
  String get txJitNote =>
      'Pembayaran ini sekaligus membuatkan jalur penerimaan baru untukmu, jadi ada potongan biaya pembuatan 0,5%. Pembayaran berikutnya lewat jalur ini tidak dipotong lagi.';

  @override
  String get txCopied => 'Disalin';

  @override
  String get receiveRestoredHint =>
      'Invoice terakhir yang belum dibayar dipulihkan dari simpanan.';

  @override
  String get backupWallet => 'Pencadangan Dompet';

  @override
  String get legacyWalletSubtitle =>
      'Dompet ini dibuat sebelum fitur frasa backup ada';

  @override
  String get backupSubtitle => 'Lihat frasa backup dompet Anda';

  @override
  String get noPhraseTitle => 'Dompet ini tidak punya frasa backup';

  @override
  String get noPhraseBody =>
      'Dompet ini dibuat oleh versi aplikasi sebelumnya yang menyimpan kunci tanpa frasa. Bila HP hilang atau rusak, dana di dompet ini tidak bisa dipulihkan.\n\nBila dompet ini masih KOSONG (belum pernah menerima dana), buat dompet baru yang dilengkapi frasa backup sekarang:';

  @override
  String get createNewWalletTitle => 'Buat dompet baru?';

  @override
  String get deleteOldWalletBody =>
      'Dompet lama akan DIHAPUS PERMANEN beserta seluruh datanya. Lanjutkan HANYA bila dompet lama masih kosong — dana apa pun di dalamnya hilang selamanya.';

  @override
  String get deleteAndCreate => 'Hapus & buat baru';

  @override
  String get createNewWalletButton => 'Buat dompet baru dengan frasa';

  @override
  String get networkTestnetLabel => 'Jaringan: Nusacoin Testnet';

  @override
  String get networkMainnetLabel => 'Jaringan: Nusacoin Mainnet';

  @override
  String appVersionLabel(String version, String build) {
    return 'Versi $version • Build $build';
  }

  @override
  String get backupWarning =>
      'Tulis kata-kata ini di kertas dan simpan di tempat aman. Siapa pun yang punya kata-kata ini bisa mengambil danamu.';

  @override
  String get showBackupWords => 'Tampilkan Kata Backup';

  @override
  String get backupCopied => 'Kata backup disalin';

  @override
  String get copy => 'Salin';

  @override
  String get backupConfirmed =>
      'Saya sudah menulis kata-kata ini di tempat aman';

  @override
  String get done => 'Selesai';

  @override
  String get invalidAmount => 'Masukkan nominal yang valid';

  @override
  String receiveInvoiceDesc(String amount) {
    return 'Terima $amount';
  }

  @override
  String get receiveNoteLabel => 'Catatan (opsional)';

  @override
  String get receiveNoteHint => 'cth. untuk SPP bulan November';

  @override
  String get createInvoiceFailed => 'Gagal membuat invoice. Coba lagi.';

  @override
  String get receiveJitMinimumNote =>
      'Untuk penerimaan pertama (sekaligus membuatkan jalur penerimaanmu), jumlah terkecilnya 1.000 nusan. Setelah jalurmu jadi, kamu bisa menerima berapa pun, termasuk di bawah 1.000 nusan.';

  @override
  String get receiveTitle => 'Terima NUX';

  @override
  String get jitInfo =>
      'Invoice Lightning dengan channel instan (JIT). Tidak perlu tunggu konfirmasi block.';

  @override
  String get amountLabel => 'Nominal';

  @override
  String get createInvoice => 'Buat Invoice';

  @override
  String get paymentReceived => 'Pembayaran Diterima';

  @override
  String receivedAmount(String amount) {
    return '+$amount';
  }

  @override
  String get fundsArrived => 'Dana sudah masuk ke channel Lightning kamu.';

  @override
  String get invoiceTitle => 'Invoice Lightning';

  @override
  String get invoiceCopied => 'Invoice disalin';

  @override
  String get shareInvoiceHint =>
      'Bagikan invoice ini ke pengirim. Channel akan dibuka otomatis saat pembayaran diterima.';

  @override
  String get staticCodeTitle => 'Kode Bayar Statis';

  @override
  String get staticCodeHint =>
      'Kode ini bisa dipakai berulang kali tanpa kedaluwarsa — bagikan sekali, pembayar menentukan jumlahnya setiap kali membayar.';

  @override
  String get staticCodeCopied => 'Kode bayar disalin';

  @override
  String get staticCodeNeedsConnection =>
      'Kode bayar dibuat begitu dompet tersambung. Periksa koneksimu, lalu coba lagi.';

  @override
  String get staticCodeFailed => 'Gagal membuat kode bayar. Coba lagi.';

  @override
  String get staticOfferDescription => 'Kode bayar ELNUX';

  @override
  String get confirmPayOfferTitle => 'Bayar kode bayar ini?';

  @override
  String sendOfferAmountLine(String amount) {
    return 'Nominal: $amount';
  }

  @override
  String get sendOfferVariableHint =>
      'Kode bayar ini tidak menetapkan nominal — tentukan sendiri jumlah yang mau dibayar.';

  @override
  String get sendOfferInvalid => 'Kode bayar tidak valid.';

  @override
  String get sendOfferExpired => 'Kode bayar sudah kedaluwarsa.';

  @override
  String get pasteInvoiceFirst => 'Tempel invoice dulu';

  @override
  String get invalidInvoice => 'Ini bukan invoice Lightning yang valid';

  @override
  String get payFailed => 'Pembayaran gagal. Coba lagi.';

  @override
  String get payWaitingOutcome => 'Menunggu hasil akhir pembayaran…';

  @override
  String get payFailedFinal =>
      'Pembayaran gagal. Dana tidak terkirim dan saldo Anda tetap utuh.';

  @override
  String get payStillPending =>
      'Pembayaran masih diproses melewati batas tunggu. Hasil akhirnya akan tampil di Riwayat — jangan bayar ulang invoice yang sama sebelum statusnya jelas.';

  @override
  String get sendTitle => 'Kirim NUX';

  @override
  String get sendInfo =>
      'Tempel atau scan invoice Lightning dari penerima. Pembayaran instan via channel.';

  @override
  String sendableLine(String amount) {
    return 'Bisa dikirim: $amount';
  }

  @override
  String get sendInsufficientBalance =>
      'Saldo tidak cukup untuk membayar invoice ini.';

  @override
  String sendReserveNote(String reserve, String sendable) {
    return 'Jumlah ini belum bisa dikirim. Dari saldomu, $reserve selalu disisakan sebagai cadangan pengaman jalur — tetap milikmu, bukan potongan, dan kembali utuh bila jalur ditutup. Yang bisa dikirim saat ini: $sendable.';
  }

  @override
  String get sendZeroSendableHint =>
      'Terima kiriman terlebih dahulu supaya saldomu melewati cadangan — sesudah itu kamu bisa mengirim lagi.';

  @override
  String get backToHome => 'Kembali ke Beranda';

  @override
  String get paste => 'Tempel';

  @override
  String get scanQr => 'Pindai QR';

  @override
  String get pay => 'Bayar';

  @override
  String get confirmPayTitle => 'Bayar invoice ini?';

  @override
  String get confirmPayBody =>
      'Pembayaran Lightning bersifat instan dan tidak bisa dibatalkan. Periksa lagi invoice di bawah sebelum lanjut.';

  @override
  String confirmPayAmountLine(String amount) {
    return 'Nominal: $amount';
  }

  @override
  String get paymentSuccess => 'Pembayaran Berhasil!';

  @override
  String get scanTitle => 'Pindai Invoice QR';

  @override
  String get cameraDenied =>
      'Izin kamera ditolak. Aktifkan izin kamera untuk ELNUX di Pengaturan HP, lalu coba lagi.';

  @override
  String get cameraUnavailable => 'Kamera tidak dapat dibuka di perangkat ini.';

  @override
  String get pointCamera => 'Arahkan kamera ke QR invoice';

  @override
  String get scanFromGallery => 'Pilih dari galeri';

  @override
  String get scanNoQrFound => 'Tidak ada kode QR pada gambar itu';

  @override
  String get errorConnection =>
      'Tidak dapat terhubung. Periksa koneksi internet Anda, lalu coba lagi.';

  @override
  String get errorBalance => 'Saldo tidak mencukupi.';

  @override
  String get errorInvoice => 'Invoice tidak valid atau sudah kedaluwarsa.';

  @override
  String get errorWalletData =>
      'Data dompet bermasalah. Hubungi operator untuk bantuan.';

  @override
  String get restoreWallet => 'Pemulihan Dompet';

  @override
  String get restoreSubtitle => 'Pulihkan dompet dari frasa backup';

  @override
  String get restoreIntro =>
      'Masukkan frasa backup dompet yang ingin dipulihkan. Frasa ELNUX berbahasa Inggris, sesuai urutan saat pertama dibuat.';

  @override
  String get restoreHint =>
      'Ketik atau tempel frasa, pisahkan tiap kata dengan spasi';

  @override
  String restoreWordCount(int count) {
    return '$count kata';
  }

  @override
  String get restoreInvalidCount =>
      'Jumlah kata harus 12, 15, 18, 21, atau 24 (frasa ELNUX 12 kata).';

  @override
  String get restoreInvalidWords =>
      'Frasa tidak valid — periksa ejaan dan urutan kata.';

  @override
  String get restoreButton => 'Pulihkan Dompet';

  @override
  String get restoreConfirmTitle => 'Pulihkan dompet ini?';

  @override
  String get restoreConfirmBody =>
      'Dompet yang sedang aktif akan DIHAPUS PERMANEN beserta seluruh datanya. Lanjutkan HANYA bila dompet aktif masih kosong, atau frasanya sudah dicadangkan. Frasa hanya memulihkan dompet — status channel Lightning tidak ikut pulih.';

  @override
  String get restoreConfirmAction => 'Hapus & Pulihkan';

  @override
  String get restoreWorking => 'Memulihkan dompet…';

  @override
  String get restoreSuccess => 'Dompet berhasil dipulihkan';

  @override
  String get restoreFailed => 'Gagal memulihkan dompet. Coba lagi.';

  @override
  String get shareLog => 'Bagikan Log';

  @override
  String get shareLogSubtitle => 'Kirim catatan teknis node saat ada kendala';

  @override
  String get shareLogUnavailable => 'Log belum tersedia.';

  @override
  String get shareLogFailed => 'Gagal membagikan log. Coba lagi.';

  @override
  String get printer => 'Printer';

  @override
  String get printerSubtitle => 'Printer struk, uji cetak, header & footer';

  @override
  String get printerSettings => 'Pengaturan Printer';

  @override
  String get printerSelect => 'Pilih printer';

  @override
  String get printerNoneSelected => 'Belum ada printer dipilih';

  @override
  String get printerNoPaired =>
      'Tidak ada printer ter-pairing. Pairing printer dulu di Pengaturan Bluetooth Android.';

  @override
  String get printerTest => 'Uji Cetak';

  @override
  String get printerHeader => 'Teks header';

  @override
  String get printerHeaderHint =>
      'Dicetak di bagian atas setiap struk (mis. nama dan alamat toko)';

  @override
  String get printerFooter => 'Teks footer';

  @override
  String get printerFooterHint => 'Dicetak di bagian bawah setiap struk';

  @override
  String get print => 'Cetak';

  @override
  String get printSuccess => 'Struk tercetak';

  @override
  String get printFailed => 'Gagal mencetak. Periksa printer lalu coba lagi.';

  @override
  String get printNoPrinter =>
      'Belum ada printer dipilih. Pilih dulu di Profil, Printer.';

  @override
  String get printBluetoothOff =>
      'Bluetooth mati. Nyalakan dulu lalu coba lagi.';

  @override
  String get printPermissionDenied =>
      'Izin Bluetooth diperlukan untuk memakai printer.';

  @override
  String get receiptDefaultFooter => 'Terima kasih';

  @override
  String get printerSearchHint => 'Cari nama atau alamat';

  @override
  String get printerTurnOn => 'Nyalakan Bluetooth';

  @override
  String get printerScan => 'Pindai printer';

  @override
  String get printerScanning => 'Memindai…';

  @override
  String get printerDiscovered => 'Perangkat ditemukan';

  @override
  String get printerTapToPair => 'Ketuk untuk memasangkan dan memilih';

  @override
  String get printerBondFailed => 'Gagal memasangkan perangkat itu.';

  @override
  String get printerPairedSelected => 'Printer terpasang dan dipilih';

  @override
  String get historyExport => 'Ekspor CSV';

  @override
  String get historyExportFailed => 'Gagal membuat berkas CSV.';

  @override
  String get historyFilter => 'Filter tanggal';

  @override
  String get historyLast7Days => '7 hari terakhir';

  @override
  String get historyLast30Days => '30 hari terakhir';

  @override
  String get historyCustomRange => 'Periode tanggal…';

  @override
  String get historyNoTransactionsInPeriod =>
      'Tidak ada transaksi pada periode ini.';

  @override
  String get updateTitle => 'Pembaruan Tersedia';

  @override
  String updateVersionAvailable(String versi) {
    return 'Versi baru tersedia: $versi';
  }

  @override
  String get updateNotes => 'Catatan rilis';

  @override
  String get updateDownloadInstall => 'Unduh & Pasang';

  @override
  String get updateLater => 'Nanti';

  @override
  String updateDownloading(int percent) {
    return 'Mengunduh… $percent%';
  }

  @override
  String get updateFailed => 'Unduhan gagal. Periksa koneksi lalu coba lagi.';

  @override
  String get updateRetry => 'Coba Lagi';

  @override
  String get updateCheckTitle => 'Periksa Pembaruan';

  @override
  String get updateCheckSubtitle =>
      'Lihat apakah ada versi ELNUX yang lebih baru';

  @override
  String get updateUpToDate => 'ELNUX sudah versi terbaru.';

  @override
  String get updateCheckFailed => 'Tidak dapat memeriksa pembaruan saat ini.';

  @override
  String get updateChecking => 'Memeriksa pembaruan…';

  @override
  String get communityTitle => 'Komunitas';

  @override
  String get communityWebsiteLabel => 'Website';

  @override
  String get communityTelegramGroup => 'Grup Telegram';

  @override
  String get communityOpenFailed => 'Tidak dapat membuka tautan.';

  @override
  String get storeMode => 'Mode Toko';

  @override
  String get storeModeSubtitle =>
      'Kasir toko — penjualan rupiah & program poin nusan';

  @override
  String get storeIdleHint =>
      'Susun pesanan, lalu selesaikan pembayaran dalam rupiah. Poin nusan diperoleh pelanggan sesudah penjualan lunas.';

  @override
  String get storeFreeAmountLabel => 'Nominal Bebas (Rp)';

  @override
  String get storeAddFreeItem => 'Tambah Item Bebas';

  @override
  String get storeFreeItem => 'Item Bebas';

  @override
  String get storeFreeTitleLabel => 'Nama Item (opsional)';

  @override
  String get storeSearchHint => 'Cari nama atau kode produk…';

  @override
  String get storeSearchNoResults =>
      'Tidak ada produk yang cocok dengan pencarian.';

  @override
  String get storeRemoveLineTitle => 'Hapus dari Pesanan?';

  @override
  String storeRemoveLineMessage(String name) {
    return 'Hapus $name dari pesanan?';
  }

  @override
  String get storeRemoveLineConfirm => 'Hapus';

  @override
  String get storeAddNote => 'Tambah Catatan';

  @override
  String get storeLineNoteTitle => 'Catatan Item';

  @override
  String get storeNoteWord => 'Cat.';

  @override
  String get storeClearNote => 'Hapus Catatan';

  @override
  String get storeSaveNote => 'Simpan';

  @override
  String get storeHoldOrder => 'Tahan Pesanan';

  @override
  String get storeHeldSaved =>
      'Pesanan ditahan — bisa dilanjutkan kapan saja dari daftar Ditahan.';

  @override
  String get storeHeldTitle => 'Pesanan Ditahan';

  @override
  String storeHeldBadge(int count) {
    return 'Ditahan ($count)';
  }

  @override
  String get storeHeldEmpty => 'Belum ada pesanan yang ditahan.';

  @override
  String storeHeldEntryMeta(String time, int count, String total) {
    return '$time • $count item • $total';
  }

  @override
  String get storeHeldResumeBlocked =>
      'Pesanan berjalan belum kosong — tahan atau selesaikan dulu pesanan yang sedang disusun.';

  @override
  String get storeHeldResumed => 'Pesanan ditahan dilanjutkan.';

  @override
  String get storeExitHoldTitle => 'Pesanan Belum Selesai';

  @override
  String get storeExitHoldBody =>
      'Pesanan yang sedang disusun belum selesai. Bila keluar sekarang, pesanan ini ditahan otomatis dan bisa dilanjutkan kapan saja dari daftar Ditahan.';

  @override
  String get storeExitStay => 'Tetap di Sini';

  @override
  String get storeExitHoldLeave => 'Tahan & Keluar';

  @override
  String get storeExitHoldFailed =>
      'Pesanan gagal ditahan — tetap di layar ini supaya pesanan tidak hilang.';

  @override
  String get storeDraftRestored =>
      'Draf pesanan terakhir dipulihkan — lanjutkan dari tempat terakhir.';

  @override
  String get storeDeleteHeldTitle => 'Hapus Pesanan Ditahan?';

  @override
  String storeDeleteHeldMessage(String summary) {
    return 'Hapus pesanan ditahan $summary? Tindakan ini tidak bisa dibatalkan.';
  }

  @override
  String get storeKeypadModeQty => 'Qty';

  @override
  String get storeKeypadModeAmount => 'Nominal';

  @override
  String storeQtyBadge(int qty) {
    return 'Qty: $qty';
  }

  @override
  String get storeQtyModeHint =>
      'Mode Qty: ketuk angka sebagai pengali, lalu ketuk produk di katalog atau pindai kodenya — produk masuk sebanyak pengali itu.';

  @override
  String storeProductAddedQty(String name, int qty) {
    return 'Ditambahkan: $name ×$qty';
  }

  @override
  String get storeOrderTitle => 'Pesanan';

  @override
  String get storeOrderEmpty =>
      'Belum ada item — ketuk produk di katalog, pindai kode, atau tambah nominal bebas.';

  @override
  String get storeSubtotal => 'Subtotal';

  @override
  String get storeTotalDiscount => 'Total Diskon';

  @override
  String get storeGrandTotal => 'Total';

  @override
  String get storeOrderDiscount => 'Diskon Order';

  @override
  String get storeDiscount => 'Diskon';

  @override
  String get storeSetDiscount => 'Atur Diskon';

  @override
  String get storeApplyDiscount => 'Terapkan';

  @override
  String get storeRemoveDiscount => 'Hapus Diskon';

  @override
  String get storeDiscountPercent => 'Persen (%)';

  @override
  String get storeDiscountFixed => 'Nominal (Rp)';

  @override
  String get storeDiscountValue => 'Nilai Diskon';

  @override
  String get storeSessionTitle => 'Sesi Ini';

  @override
  String storeSessionSales(int count, String total) {
    return '$count transaksi • Rp$total';
  }

  @override
  String get storePrintReceipt => 'Cetak Struk';

  @override
  String get storeScanCode => 'Pindai Kode';

  @override
  String get storeCatalogTitle => 'Katalog Produk';

  @override
  String get storeManageCatalog => 'Kelola';

  @override
  String get storeCatalogEmpty =>
      'Katalog masih kosong — tambahkan produk pertama lewat tombol Kelola.';

  @override
  String get storeCategoryAll => 'Semua';

  @override
  String get storeCodeNotRegistered => 'Kode ini belum terdaftar di katalog.';

  @override
  String get storeRegisterNow => 'Daftarkan Sekarang';

  @override
  String get storeProductCode => 'Kode Produk';

  @override
  String get storeProductCodeHint =>
      'Terisi otomatis — boleh diganti dengan barcode produk.';

  @override
  String get storeProductCodeLocked =>
      'Kode tidak bisa diubah setelah produk dibuat.';

  @override
  String get storeProductCodeDuplicate =>
      'Kode produk ini sudah dipakai produk lain.';

  @override
  String get storeProductName => 'Nama Produk';

  @override
  String get storeProductPrice => 'Harga (Rp)';

  @override
  String get storeProductDiscount => 'Diskon Bawaan (opsional)';

  @override
  String get storeSaveProduct => 'Simpan Produk';

  @override
  String storeProductSaved(String name) {
    return 'Produk tersimpan: $name';
  }

  @override
  String storeProductAdded(String name) {
    return 'Ditambahkan: $name';
  }

  @override
  String get storeClearKeypad => 'Bersih';

  @override
  String get storeProductFormError =>
      'Periksa lagi: kode, nama, dan harga (di atas 0) wajib diisi.';

  @override
  String get storeProductCategory => 'Kategori (opsional)';

  @override
  String get storeShiftTitle => 'Shift Kasir';

  @override
  String get storeShiftNotOpen => 'Shift Belum Dibuka';

  @override
  String get storeShiftOpenHint =>
      'Buka shift dulu untuk menyusun pesanan dan menerima pembayaran rupiah di Mode Toko.';

  @override
  String get storeShiftOpen => 'Buka Shift';

  @override
  String get storeShiftClose => 'Tutup Shift';

  @override
  String storeShiftOpenedAt(String time) {
    return 'Dibuka $time';
  }

  @override
  String get storeShiftStillOpen => 'Masih Berjalan';

  @override
  String get storeCloseShiftBlocked =>
      'Tidak bisa menutup shift: masih ada penerbitan poin yang sedang berjalan. Selesaikan dulu penerbitan poinnya.';

  @override
  String get storeCloseShiftConfirmTitle => 'Tutup Shift Ini?';

  @override
  String get storeCloseShiftConfirmBody =>
      'Sesudah ditutup, penjualan berikutnya masuk ke shift baru.';

  @override
  String get storeCloseShiftHeldTitle => 'Masih Ada Pesanan Ditahan';

  @override
  String storeCloseShiftHeldBody(int count, String total) {
    return 'Ada $count pesanan ditahan (total $total) yang belum dibayar. Pesanan ditahan tetap tersimpan dan bisa dilanjutkan pada shift berikutnya.';
  }

  @override
  String get storeCloseShiftHeldConfirm => 'Tetap Tutup Shift';

  @override
  String get storeBack => 'Kembali';

  @override
  String get storeShiftClosedTitle => 'Shift Ditutup';

  @override
  String get storeShiftClosedBody =>
      'Laporan shift ini sudah bisa dilihat, dicetak, atau dibagikan sebagai PDF.';

  @override
  String get storeLater => 'Nanti';

  @override
  String get storeViewReport => 'Lihat Laporan';

  @override
  String get storeSalesReport => 'Laporan Penjualan';

  @override
  String get storeReportsTitle => 'Daftar Laporan';

  @override
  String get storeExportPdf => 'Ekspor PDF';

  @override
  String get storeReportPaymentsTitle => 'Laporan Pembayaran';

  @override
  String get storeReportPaymentsSubtitle =>
      'Penerimaan per tanggal, dirinci per shift.';

  @override
  String get storePaymentReportBreakdown => 'Rincian per Shift';

  @override
  String storeReportPointsUsed(int points, String amount) {
    return 'Poin terpakai: $points poin (−$amount)';
  }

  @override
  String storePaymentReportInvoices(int count) {
    return '$count nota';
  }

  @override
  String storePaymentReportTotalLine(int count, String amount) {
    return 'Total $count nota • Rp$amount';
  }

  @override
  String get storeReportProductSalesTitle => 'Laporan Penjualan Produk';

  @override
  String get storeReportProductSalesSubtitle =>
      'Semua penjualan per produk pada periode terpilih.';

  @override
  String get storeProductSalesGross => 'Bruto';

  @override
  String get storeReportBestsellersTitle => 'Produk Terlaris';

  @override
  String get storeReportBestsellersSubtitle =>
      'Urutan produk dari yang paling banyak terjual.';

  @override
  String get storeBestsellersEmpty => 'Belum ada penjualan pada periode ini.';

  @override
  String get storePeriod7Days => '7 Hari Terakhir';

  @override
  String get storePeriod30Days => '30 Hari Terakhir';

  @override
  String get storePeriodAll => 'Semua';

  @override
  String get storePeriodCustom => 'Pilih Tanggal';

  @override
  String storeBestsellersSoldQty(int qty) {
    return 'Terjual $qty';
  }

  @override
  String storeBestsellersTotalLine(int qty, String amount) {
    return 'Total terjual $qty • Rp$amount';
  }

  @override
  String get storeSalesHistory => 'Riwayat Penjualan';

  @override
  String get storeSalesHistoryEmpty => 'Belum ada penjualan yang tercatat.';

  @override
  String get storeSaleDetailTitle => 'Detail Penjualan';

  @override
  String get storeSalePaymentLabel => 'Pembayaran';

  @override
  String get storeSaleReceiptUnavailable =>
      'Struk tidak tersedia untuk record ini.';

  @override
  String get storeReprintReceipt => 'Cetak Ulang';

  @override
  String get storePreviewShareReceipt => 'Pratinjau & Bagikan';

  @override
  String get storeOperatorLoginTitle => 'Login Operator';

  @override
  String get storeOperatorSetupTitle => 'Buat Akun Owner';

  @override
  String get storeOperatorSetupBody =>
      'Mode Toko sekarang memakai login operator. Buat akun owner pertama: akun ini mengelola operator lain dan menyetujui aksi sensitif.';

  @override
  String get storeOperatorNameLabel => 'Nama Operator';

  @override
  String get storeOperatorPinLabel => 'PIN (6 digit)';

  @override
  String get storeOperatorPinConfirmLabel => 'Ulangi PIN';

  @override
  String get storeOperatorPinMismatch => 'PIN tidak sama.';

  @override
  String get storeOperatorPinInvalid => 'PIN harus 6 digit angka.';

  @override
  String get storeOperatorNameRequired => 'Nama operator wajib diisi.';

  @override
  String get storeOperatorLoginButton => 'Masuk';

  @override
  String get storeOperatorWrongPin => 'PIN salah.';

  @override
  String get storeOperatorSwitch => 'Ganti Operator';

  @override
  String get storeOperatorRoleOwner => 'Owner';

  @override
  String get storeOperatorRoleCashier => 'Kasir';

  @override
  String get storeAdminPinTitle => 'PIN Admin';

  @override
  String get storeAdminPinBody =>
      'Aksi ini butuh persetujuan owner. Minta owner memasukkan PIN-nya.';

  @override
  String get storeAdminApproved => 'Persetujuan admin diterima.';

  @override
  String get storeVoidSaleButton => 'VOID Penjualan';

  @override
  String get storeVoidSaleTitle => 'VOID Penjualan Lunas?';

  @override
  String get storeVoidSaleBody =>
      'Penjualan ditandai VOID: hilang dari total laporan dan jurnal poin dibalikkan. Record asal tetap tersimpan bertanda VOID. Tindakan ini tidak bisa dibatalkan.';

  @override
  String get storeVoidReasonLabel => 'Alasan VOID (wajib)';

  @override
  String get storeVoidDone => 'Penjualan ditandai VOID.';

  @override
  String get storeOperatorsTitle => 'Kelola Operator';

  @override
  String get storeOperatorLastOwner =>
      'Tidak bisa menonaktifkan owner aktif terakhir.';

  @override
  String get storeOperatorAdd => 'Tambah Operator';

  @override
  String get storeOperatorRoleLabel => 'Peran';

  @override
  String get storeOperatorDeactivate => 'Nonaktifkan';

  @override
  String get storeOperatorActivate => 'Aktifkan';

  @override
  String get storeOperatorResetPin => 'Ganti PIN';

  @override
  String get storeOperatorInactiveBadge => 'Nonaktif';

  @override
  String get storeAuditTitle => 'Log Aktivitas';

  @override
  String get storeAuditEmpty => 'Belum ada aktivitas tercatat.';

  @override
  String get storeSettingsAdminSection => 'Operator & Keamanan';

  @override
  String get storeSettingsDiscountThresholdLabel => 'Ambang diskon kasir (%)';

  @override
  String get storeSettingsDiscountThresholdHint =>
      'Diskon manual di atas ambang ini wajib disetujui PIN admin.';

  @override
  String get storeCustomerTitle => 'Pelanggan';

  @override
  String get storeCustomerChoose => 'Pilih Pelanggan';

  @override
  String get storeCustomerAdd => 'Tambah Pelanggan';

  @override
  String get storeCustomerNameLabel => 'Nama Pelanggan (opsional)';

  @override
  String get storeCustomerOfferLabel => 'Kode Bayar Statis (Bolt12)';

  @override
  String get storeCustomerScan => 'Pindai';

  @override
  String get storeCustomerInvalidOffer =>
      'Kode bayar tidak sah — harus offer Bolt12 (lno1…).';

  @override
  String get storeCustomerEmpty => 'Belum ada pelanggan tersimpan.';

  @override
  String get storeCustomerEdit => 'Ubah';

  @override
  String get storeCustomerDelete => 'Hapus';

  @override
  String get storeCustomerManage => 'Kelola Pelanggan';

  @override
  String get storeAuditLogin => 'Login';

  @override
  String get storeAuditLogout => 'Keluar';

  @override
  String get storeAuditOperatorCreated => 'Operator dibuat';

  @override
  String get storeAuditOperatorUpdated => 'Operator diubah';

  @override
  String get storeAuditPinChanged => 'PIN diganti';

  @override
  String get storeAuditShiftOpen => 'Buka shift';

  @override
  String get storeAuditShiftClose => 'Tutup shift';

  @override
  String get storeAuditAdminOverride => 'Override admin';

  @override
  String get storeAuditSaleVoid => 'VOID penjualan';

  @override
  String get storeReportCurrentShift => 'Shift Berjalan';

  @override
  String get storeReportByDate => 'Per Tanggal';

  @override
  String get storeReportPastShifts => 'Shift Lampau';

  @override
  String get storeReportPrint => 'Cetak Laporan';

  @override
  String get storeReportSharePdf => 'Bagikan PDF';

  @override
  String get storeReportEmpty =>
      'Belum ada penjualan tercatat pada periode ini.';

  @override
  String get storeReportSummaryTitle => 'LAPORAN SHIFT';

  @override
  String get storeReportDetailsTitle => 'RINCIAN PENJUALAN';

  @override
  String get storeReportItemQty => 'Qty Item';

  @override
  String get storeReportTotalOrder => 'Total ORDER';

  @override
  String get storeReportTotalOrderInfo => 'Info Total ORDER';

  @override
  String get storeReportInvoices => '#Transaksi';

  @override
  String get storeReportInvUnit => 'trx';

  @override
  String get storeReportVoidInfo => 'Info VOID';

  @override
  String get storeReportVoidItemQty => 'Qty Item VOID';

  @override
  String get storeReportVoidSubTotal => 'Sub Total VOID';

  @override
  String get storeReportVoidDiscount => 'Diskon VOID';

  @override
  String get storeReportVoidTotalOrder => 'Total ORDER VOID';

  @override
  String get storeReportOther => 'LAINNYA';

  @override
  String get storeReportQty => 'Qty';

  @override
  String storeReportMenus(int count) {
    return '$count menu(s)';
  }

  @override
  String get storeReportGeneratedOn => 'Laporan dibuat';

  @override
  String storeReportShiftsNote(int count) {
    return 'Meliputi $count shift';
  }

  @override
  String get storeCatalogManagerTitle => 'Kelola Katalog';

  @override
  String get storeAddProduct => 'Tambah Produk';

  @override
  String get storeEditProduct => 'Ubah Produk';

  @override
  String get storeNoDiscount => 'Tanpa Diskon';

  @override
  String get storeCheckout => 'Selesaikan Pembayaran';

  @override
  String get storePayTitle => 'Penyelesaian Pembayaran';

  @override
  String get storePayTotalLabel => 'Total Belanja';

  @override
  String get storeCash => 'Tunai';

  @override
  String get storeQris => 'QRIS';

  @override
  String get storeQrisNote =>
      'Pelanggan membayar lewat QRIS seperti biasa di toko ini. Aplikasi hanya mencatat metode pembayarannya — tekan tombol di bawah sesudah pembayaran QRIS diterima.';

  @override
  String get storeCashReceived => 'Uang Diterima';

  @override
  String get storeCashExact => 'Uang Pas';

  @override
  String get storeChange => 'Kembalian';

  @override
  String storeCashShort(String amount) {
    return 'Kurang Rp$amount';
  }

  @override
  String get storeSettle => 'Lunas — Selesaikan';

  @override
  String get storeSettleQris => 'QRIS Diterima — Selesaikan';

  @override
  String get storeSettlePromo => 'Selesaikan Tanpa Pembayaran';

  @override
  String get storePromoNote =>
      'Total belanja Rp0 (promosi) — tidak ada pembayaran yang diterima; penjualan tetap dicatat.';

  @override
  String get storeCancelOrder => 'Batalkan Pesanan';

  @override
  String get storeVoidConfirmTitle => 'Batalkan Pesanan Ini?';

  @override
  String get storeVoidConfirmBody =>
      'Pesanan dibatalkan dan dicatat sebagai VOID di laporan. Tindakan ini tidak bisa dibatalkan.';

  @override
  String get storeVoidRecorded => 'Pesanan dibatalkan — tercatat sebagai VOID.';

  @override
  String get storeRedeemTitle => 'Tukar Poin Nusan';

  @override
  String get storeRedeemHint =>
      'Penukaran dibaca dari catatan penerbitan poin toko ini — pelanggan tidak membayar apa pun. Minta pelanggan menunjukkan offer Bolt12 dari aplikasi ELNUX miliknya, pindai, lalu terapkan potongan sampai sebesar poin yang tercatat untuknya.';

  @override
  String get storeRedeemScanOffer => 'Pindai Offer Pelanggan';

  @override
  String storeRedeemBalance(int balance) {
    return 'Poin tercatat untuk pelanggan ini: $balance poin.';
  }

  @override
  String get storeRedeemNoBalance =>
      'Belum ada poin tercatat untuk offer ini di toko ini — penukaran belum bisa dilakukan.';

  @override
  String get storeRedeemNeedOffer =>
      'Penukaran memakai offer Bolt12 pelanggan. Kode ini bukan offer — minta pelanggan membuka offer-nya di ELNUX lalu pindai ulang.';

  @override
  String get storeRedeemPointsLabel => 'Jumlah Poin';

  @override
  String get storeRedeemApply => 'Terapkan Potongan';

  @override
  String storeRedeemApplied(int points, String amount) {
    return 'Penukaran tercatat: $points poin = potongan Rp$amount.';
  }

  @override
  String get storeRedeemUndo => 'Urungkan Penukaran';

  @override
  String get storeRedeemScanAgain => 'Pindai Ulang';

  @override
  String storeRedeemMaxNote(int max) {
    return 'Maksimal $max poin untuk belanja ini.';
  }

  @override
  String storeRedeemClamped(int max) {
    return 'Jumlah poin melebihi batas — dipakai $max poin.';
  }

  @override
  String get storeRedeemInvalidPoints =>
      'Jumlah poin tidak sah atau melebihi potongan yang mungkin untuk belanja ini.';

  @override
  String get storeSaleCompleted => 'Penjualan Selesai';

  @override
  String storePointsEarnedLine(int points) {
    return 'Poin nusan diperoleh: $points poin';
  }

  @override
  String get storePointsIssueButton => 'Pindai & Terbitkan';

  @override
  String get storePointsSkip => 'Lewati';

  @override
  String get storePointsIssuedOk =>
      'Poin nusan sudah diterbitkan ke pelanggan.';

  @override
  String get storeIssueInvalidCode =>
      'Kode tidak terbaca sebagai invoice atau kode bayar ELNUX — pindai ulang kode pelanggan.';

  @override
  String get storeIssueAmountMismatch =>
      'Nominal kode tidak sama dengan poin yang harus diterbitkan — minta pelanggan membuat kode sejumlah poin yang diperoleh.';

  @override
  String get storeIssueFailed =>
      'Penerbitan poin gagal — poin tetap tertunda dan bisa diterbitkan dari daftar Poin Tertunda.';

  @override
  String get storeIssueStillPending =>
      'Pembayaran poin masih berjalan — statusnya tetap tertunda; cek lagi dari daftar Poin Tertunda.';

  @override
  String get storeIssueInvoiceNote =>
      'Poin terbit ke invoice sekali pakai — poin seperti ini tidak tercatat di jurnal toko. Agar bisa ditukar pada kunjungan berikutnya, terbitkan ke offer Bolt12 pelanggan.';

  @override
  String get storeDoneButton => 'Selesai';

  @override
  String storePendingBadge(int count) {
    return 'Poin Tertunda ($count)';
  }

  @override
  String get storePendingTitle => 'Poin Tertunda';

  @override
  String get storePendingEmpty => 'Tidak ada poin yang tertunda.';

  @override
  String storePendingEntryMeta(String time, String total) {
    return '$time • $total';
  }

  @override
  String get storePendingIssue => 'Terbitkan';

  @override
  String get storePendingWaive => 'Batal Terbit';

  @override
  String get storePendingWaiveTitle => 'Batalkan Penerbitan Poin?';

  @override
  String storePendingWaiveBody(String total, String time) {
    return 'Poin dari penjualan $time (total $total) TIDAK jadi diterbitkan ke pelanggan. Catatan penjualannya tetap tersimpan.';
  }

  @override
  String get storePendingWaived => 'Penerbitan poin dibatalkan.';

  @override
  String get storeReceiptTotalPay => 'TOTAL BAYAR';

  @override
  String storeReceiptPointsDiscount(int points, String amount) {
    return 'Penukaran poin ($points poin) -Rp$amount';
  }

  @override
  String storeReceiptPointsEarned(int points) {
    return 'Poin nusan diperoleh: +$points poin';
  }

  @override
  String storeReceiptPointsPending(int points) {
    return 'Poin nusan diperoleh: +$points poin (belum diterbitkan)';
  }

  @override
  String storeReceiptPointsRule(String rate) {
    return '1 nusan = pot. Rp$rate';
  }

  @override
  String get storeReceiptPromo => 'Tanpa pembayaran (promosi)';

  @override
  String get storeReceiptCustomer => 'Pelanggan';

  @override
  String get storeReceiptDate => 'Tanggal';

  @override
  String get storeReceiptBillNo => 'No. Bill';

  @override
  String get storeReceiptTokenNo => 'Order/Outlet';

  @override
  String get storeReceiptItemHeader => 'Item';

  @override
  String get storeReceiptAmountHeader => 'Jumlah';

  @override
  String get storeReceiptOrderDiscount => 'Diskon Order';

  @override
  String get storeReceiptLineDiscount => 'Diskon Item';

  @override
  String get storeReceiptGrandTotal => 'Bayar';

  @override
  String get storeReceiptReprintBanner => '*** REPRINT ***';

  @override
  String get storeReceiptReprintLabel => 'Reprint';

  @override
  String get storeReceiptCashier => 'Kasir';

  @override
  String get storePayAmountLabel => 'Jumlah';

  @override
  String get storeAddPayMethod => 'Tambah Metode Bayar';

  @override
  String get storeNonCashOverNote =>
      'Metode non-tunai tidak boleh melebihi sisa tagihan.';

  @override
  String get storeMethodSplit => 'Gabungan';

  @override
  String get storeFilterToday => 'Hari Ini';

  @override
  String get storeFilterYesterday => 'Kemarin';

  @override
  String get storeReportIncome => 'Income';

  @override
  String get storeReportOpeningFloat => 'Modal';

  @override
  String get storeReportCashPosition => 'Posisi Tunai';

  @override
  String get storeReportHeldInfo => 'Order Ditahan';

  @override
  String get storeReportHeldTotal => 'Total Order Ditahan';

  @override
  String get storeOpeningFloatTitle => 'Modal Awal Shift';

  @override
  String get storeOpeningFloatHint =>
      'Uang tunai di laci saat shift dibuka (untuk kembalian). Boleh Rp0 — hanya pembayaran tunai yang menambah posisi laci; metode non-tunai tidak memengaruhinya.';

  @override
  String get storeOpeningFloatLabel => 'Modal di Laci';

  @override
  String get storePayMethodsTitle => 'Metode Bayar Non-Tunai';

  @override
  String get storePayMethodsHint =>
      'Metode yang ditawarkan pada dropdown halaman pembayaran (Tunai selalu tersedia). Ketuk × untuk menghapus.';

  @override
  String get storePayMethodNameLabel => 'Nama Metode Baru';

  @override
  String get storePayMethodAdd => 'Tambah';

  @override
  String get storeTelegramTitle => 'Kirim Laporan via Telegram';

  @override
  String get storeTelegramHint =>
      'Laporan shift terkirim otomatis ke Telegram saat shift ditutup — langsung dari aplikasi, tanpa server perantara. Buat bot lewat @BotFather, isi token botnya dan ID chat tujuan di bawah.';

  @override
  String get storeTelegramTokenLabel => 'Token Bot Telegram';

  @override
  String get storeTelegramTokenHint => 'Dari BotFather, contoh: 123456789:AA…';

  @override
  String get storeTelegramChatLabel => 'ID Chat Tujuan';

  @override
  String get storeTelegramChatHint =>
      'ID numerik chat atau grup tujuan laporan';

  @override
  String get storeTelegramSent => 'Laporan shift terkirim ke Telegram.';

  @override
  String get storeTelegramFailed =>
      'Laporan Telegram gagal terkirim — periksa koneksi & pengaturannya.';

  @override
  String get staticCodeLabelTitle => 'Label Kode Bayar';

  @override
  String get staticCodeLabelEdit => 'Ubah Label';

  @override
  String get staticCodeLabelHint =>
      'Label ini tertulis di dalam kode bayar dan dilihat pembayar. Mengganti label membuat kode bayar BARU — bagikan ulang kode yang baru. Kosongkan untuk kembali ke label bawaan.';

  @override
  String storeReceiptPointsDiscountLabel(String points) {
    return 'Pot. ($points nusan)';
  }

  @override
  String get storeReceiptFooterDefault =>
      'Terima Kasih\nSilakan berkunjung kembali';

  @override
  String get storeShareReceipt => 'Bagikan Struk';

  @override
  String get storeReceiptPreviewTitle => 'Struk';

  @override
  String get storeShareReceiptFailed => 'Tidak dapat membuat gambar struk.';

  @override
  String get storeSettingsAddress => 'Alamat Toko (baris kop struk)';

  @override
  String get storeSettingsCity => 'Kota Toko (baris kop struk)';

  @override
  String get storeSettingsShowToken => 'Tampilkan Nomor Token di Struk';

  @override
  String get storeSettingsShowTokenHint =>
      'Nomor antrean harian pada struk; mulai dari 1 setiap hari.';

  @override
  String get storeSettingsFooterText => 'Teks Penutup Struk';

  @override
  String get storeSettingsFooterTextHint =>
      'Kosongkan untuk teks bawaan bahasa aplikasi.';

  @override
  String get storeSettingsTitle => 'Pengaturan Toko';

  @override
  String get storeSettingsStoreName => 'Nama Toko';

  @override
  String get storeSettingsPointsEnabled => 'Program Poin Nusan Aktif';

  @override
  String get storeSettingsPointsHint =>
      'Poin adalah bonus promosi dari belanja rupiah — bukan alat pembayaran. Poin hanya ditukar sebagai potongan belanja di toko ini.';

  @override
  String get storeSettingsEarnStep => 'Kelipatan Rupiah Perolehan';

  @override
  String get storeSettingsEarnPoints => 'Poin per Kelipatan';

  @override
  String get storeSettingsRedeemRate => 'Nilai Potongan per Poin (Rp)';

  @override
  String get storeSettingsMaxRedeem =>
      'Batas Maks. Potongan Poin (% dari total)';

  @override
  String get storeSettingsMaxRedeemHint =>
      'Boleh kosong = tanpa batas selain sisa total belanja.';

  @override
  String storeSettingsEarnPreview(String step, int points) {
    return 'Contoh: belanja Rp$step memperoleh $points poin.';
  }

  @override
  String get storeSettingsSave => 'Simpan Pengaturan';

  @override
  String get storeSettingsSaved => 'Pengaturan toko tersimpan.';

  @override
  String get storeSettingsInvalid =>
      'Periksa lagi: kelipatan dan nilai potongan harus di atas 0; batas maks 1–100 bila diisi.';

  @override
  String get storeRulesTitle => 'Aturan Program Poin';

  @override
  String get storeRulesButton => 'Aturan Poin';

  @override
  String get storeRulesHeading => 'Poin Nusan — Bonus Promosi Toko';

  @override
  String get storeRulesP1 =>
      'Poin nusan adalah bonus promosi dari toko, bukan uang dan bukan alat pembayaran. Pembayaran belanja di toko ini selalu dalam rupiah (tunai atau QRIS).';

  @override
  String get storeRulesP2 =>
      'Poin hanya diperoleh dari belanja rupiah yang sudah lunas, sesuai ketentuan perolehan yang berlaku di toko ini.';

  @override
  String get storeRulesP3 =>
      'Poin hanya dapat ditukar sebagai potongan harga belanja di toko ini, sesuai nilai potongan per poin yang ditetapkan toko.';

  @override
  String get storeRulesP4 =>
      'Poin tidak dapat diuangkan, dijual, dibeli, atau ditukar menjadi uang tunai dalam bentuk apa pun.';

  @override
  String get storeRulesP5 =>
      'Nilai potongan per poin dan ketentuan program dapat berubah dengan pemberitahuan sebelumnya di toko ini.';

  @override
  String get storeRulesP6 =>
      'Untuk menerima dan menukar poin, pelanggan memakai aplikasi ELNUX miliknya sendiri.';

  @override
  String get storeRulesP7 =>
      'Saat pertama kali menerima poin, dompet pelanggan mungkin dikenai biaya pembuatan jalur penerimaan sebesar 0,5% dari jumlah yang diterima (ketentuan jaringan, sekali saja saat jalur dibuat).';

  @override
  String get storeRulesFooter =>
      'Ketentuan ini mengikuti pedoman program poin toko. Simpan struk belanja sebagai bukti perolehan dan penukaran poin.';

  @override
  String get storeMigrationTitle => 'Mode Toko Diperbarui';

  @override
  String get storeMigrationShiftClosed =>
      'Shift lama (harga nusan) yang masih terbuka sudah ditutup dan ditandai sebagai data lama. Penjualan mulai sekarang dicatat dalam rupiah.';

  @override
  String storeMigrationHeldDropped(int count) {
    return '$count pesanan ditahan versi lama (harga nusan) gugur dan tidak diteruskan.';
  }

  @override
  String get storeMigrationCatalog =>
      'Katalog lama berharga nusan tidak dipakai lagi. Isi ulang katalog dengan harga rupiah lewat tombol Kelola.';

  @override
  String get storeMigrationOk => 'Mengerti';

  @override
  String get storeReportCash => 'TUNAI';

  @override
  String get storeReportQris => 'QRIS';

  @override
  String get storeReportPointsDiscount => 'Diskon Poin';

  @override
  String get storeReportPointsIssued => 'Poin Diterbitkan';

  @override
  String get storeReportPointsPending => 'Poin Tertunda';

  @override
  String get storeReportPointsRedeemed => 'Poin Ditukar';

  @override
  String get offlineSpike => 'Uji Offline Lightning';

  @override
  String get offlineSpikeSubtitle =>
      'Sambung dua HP lewat Bluetooth (eksperimental)';

  @override
  String get offlineIntro =>
      'Uji tahap 2: dua node ELNUX tersambung sebagai peer lewat jembatan Bluetooth, membuka channel langsung, lalu membayar Lightning saat kedua HP offline. Buka channel-nya saat kedua HP berdampingan dan pendana (HP yang membuka) sedang online; pembayaran offline memakai channel yang sudah siap. Nyalakan Bluetooth dan layanan Lokasi di kedua HP sebelum mulai.';

  @override
  String get offlineOwnNodeId => 'ID Node HP Ini';

  @override
  String get offlineNodeNotRunning => 'Node belum berjalan';

  @override
  String get offlineCopy => 'Salin';

  @override
  String get offlineCopied => 'ID node tersalin';

  @override
  String get offlineChooseRole => 'Peran HP Ini';

  @override
  String get offlineRoleHost => 'Host (menunggu tamu)';

  @override
  String get offlineRoleGuest => 'Tamu (mencari host)';

  @override
  String get offlineStop => 'Berhenti';

  @override
  String get offlineDiscoveredHosts => 'Host Ditemukan';

  @override
  String get offlineConnect => 'Sambung';

  @override
  String get offlineHostNodeIdLabel => 'ID Node Host';

  @override
  String get offlineHostNodeIdHint => 'Tempel ID node dari HP host';

  @override
  String get offlineConnectNode => 'Sambungkan Node Lightning';

  @override
  String get offlineScan => 'Pindai QR';

  @override
  String get offlinePeersTitle => 'Peer Lightning';

  @override
  String get offlinePeerConnected => 'Terhubung';

  @override
  String get offlinePeerDisconnected => 'Putus';

  @override
  String get offlineNoPeers => 'Belum ada peer.';

  @override
  String get offlineChannelTitle => 'Channel Langsung';

  @override
  String get offlineTargetPeer => 'Peer tujuan';

  @override
  String get offlineNoTargetPeer => 'belum dikenal';

  @override
  String get offlineOnchainAddress =>
      'Alamat on-chain node (untuk dana channel)';

  @override
  String get offlineOnchainBalance => 'Saldo on-chain siap pakai';

  @override
  String get offlineChannelAmount => 'Jumlah channel (nusan)';

  @override
  String get offlineOpenChannel => 'Buka Channel';

  @override
  String get offlineOpenBlockedOfflineSession =>
      'Sesi ini dimulai tanpa internet, jadi node tidak punya akses ke rantai dan siaran pendanaan channel baru tidak akan sampai ke jaringan. Mulai ulang aplikasi dengan internet untuk membuka channel.';

  @override
  String get offlineChannelPending => 'Menunggu konfirmasi';

  @override
  String get offlineConfirmations => 'Konfirmasi';

  @override
  String get offlineChannelReady => 'Siap';

  @override
  String get offlineChannelReadyPeerDown => 'Siap (peer tidak tersambung)';

  @override
  String get offlineNoDirectChannels => 'Belum ada channel langsung.';

  @override
  String get offlineChannelValue => 'Nilai';

  @override
  String get offlineOutbound => 'Keluar';

  @override
  String get offlineInbound => 'Masuk';

  @override
  String get offlinePayTestTitle => 'Pembayaran Uji';

  @override
  String get offlineInvoiceAmount => 'Jumlah invoice (nusan)';

  @override
  String get offlineCreateInvoice => 'Buat Invoice';

  @override
  String get offlineInvoiceToPay => 'Invoice yang akan dibayar';

  @override
  String get offlinePayNow => 'Bayar';

  @override
  String get offlineLogTitle => 'Catatan Uji';

  @override
  String get offlineStatusIdle => 'Belum mulai';

  @override
  String get offlineStatusAdvertising => 'Mengiklankan sebagai host…';

  @override
  String get offlineStatusDiscovering => 'Mencari host…';

  @override
  String get offlineStatusConnecting => 'Menyambungkan jembatan…';

  @override
  String get offlineStatusLinked => 'Jembatan terhubung';

  @override
  String get offlineStatusError => 'Kesalahan';
}
