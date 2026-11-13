import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_id.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('id'),
  ];

  /// No description provided for @appLanguage.
  ///
  /// In id, this message translates to:
  /// **'Bahasa'**
  String get appLanguage;

  /// No description provided for @chooseLanguage.
  ///
  /// In id, this message translates to:
  /// **'Pilih Bahasa'**
  String get chooseLanguage;

  /// No description provided for @languageIndonesian.
  ///
  /// In id, this message translates to:
  /// **'Bahasa Indonesia'**
  String get languageIndonesian;

  /// No description provided for @languageEnglish.
  ///
  /// In id, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @themeTitle.
  ///
  /// In id, this message translates to:
  /// **'Tema'**
  String get themeTitle;

  /// No description provided for @unitTitle.
  ///
  /// In id, this message translates to:
  /// **'Satuan'**
  String get unitTitle;

  /// No description provided for @unitSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Satuan tampilan jumlah di saldo, kirim, terima, dan riwayat'**
  String get unitSubtitle;

  /// No description provided for @themeSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Gelap atau terang, sesuai selera'**
  String get themeSubtitle;

  /// No description provided for @changeThemeTooltip.
  ///
  /// In id, this message translates to:
  /// **'Ganti tema'**
  String get changeThemeTooltip;

  /// No description provided for @greetingMorning.
  ///
  /// In id, this message translates to:
  /// **'Selamat pagi'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In id, this message translates to:
  /// **'Selamat siang'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In id, this message translates to:
  /// **'Selamat sore'**
  String get greetingEvening;

  /// No description provided for @greetingNight.
  ///
  /// In id, this message translates to:
  /// **'Selamat malam'**
  String get greetingNight;

  /// No description provided for @bootConnecting.
  ///
  /// In id, this message translates to:
  /// **'Menghubungkan ke LSP…'**
  String get bootConnecting;

  /// No description provided for @splashTagline.
  ///
  /// In id, this message translates to:
  /// **'Uangmu, Kendalimu.'**
  String get splashTagline;

  /// No description provided for @bootFailedTitle.
  ///
  /// In id, this message translates to:
  /// **'Gagal menghubungkan node'**
  String get bootFailedTitle;

  /// No description provided for @bootFailedRetry.
  ///
  /// In id, this message translates to:
  /// **'Coba lagi'**
  String get bootFailedRetry;

  /// No description provided for @bootOfflineButton.
  ///
  /// In id, this message translates to:
  /// **'Lanjutkan tanpa internet'**
  String get bootOfflineButton;

  /// No description provided for @bootGenericError.
  ///
  /// In id, this message translates to:
  /// **'Terjadi kendala saat memulai dompet.'**
  String get bootGenericError;

  /// No description provided for @lspNodeIdMissing.
  ///
  /// In id, this message translates to:
  /// **'lspNodeId belum diisi di lib/config.dart — minta node id LSP ke operator.'**
  String get lspNodeIdMissing;

  /// No description provided for @seedCorrupt.
  ///
  /// In id, this message translates to:
  /// **'File seed korup (panjang {length}, harus 64). Hapus {path} untuk generate ulang (DANA LAMA HILANG).'**
  String seedCorrupt(int length, String path);

  /// No description provided for @exitTitle.
  ///
  /// In id, this message translates to:
  /// **'Keluar dari ELNUX?'**
  String get exitTitle;

  /// No description provided for @exitBody.
  ///
  /// In id, this message translates to:
  /// **'Aplikasi akan ditutup. Selama aplikasi tertutup, dompet tidak dapat menerima pembayaran.'**
  String get exitBody;

  /// No description provided for @cancel.
  ///
  /// In id, this message translates to:
  /// **'Batal'**
  String get cancel;

  /// No description provided for @exitConfirm.
  ///
  /// In id, this message translates to:
  /// **'Keluar'**
  String get exitConfirm;

  /// No description provided for @totalBalance.
  ///
  /// In id, this message translates to:
  /// **'Total Saldo'**
  String get totalBalance;

  /// No description provided for @balanceViaLsp.
  ///
  /// In id, this message translates to:
  /// **'Via LSP'**
  String get balanceViaLsp;

  /// No description provided for @balanceDirectChannel.
  ///
  /// In id, this message translates to:
  /// **'Channel langsung'**
  String get balanceDirectChannel;

  /// No description provided for @balanceOnchain.
  ///
  /// In id, this message translates to:
  /// **'On-chain'**
  String get balanceOnchain;

  /// No description provided for @balanceSpendable.
  ///
  /// In id, this message translates to:
  /// **'Siap pakai'**
  String get balanceSpendable;

  /// No description provided for @balanceTimelock.
  ///
  /// In id, this message translates to:
  /// **'Menunggu timelock'**
  String get balanceTimelock;

  /// No description provided for @balanceTimelockUnlocks.
  ///
  /// In id, this message translates to:
  /// **'terbuka ~blok {height}'**
  String balanceTimelockUnlocks(int height);

  /// No description provided for @balanceLspShort.
  ///
  /// In id, this message translates to:
  /// **'LSP'**
  String get balanceLspShort;

  /// No description provided for @balanceSelf.
  ///
  /// In id, this message translates to:
  /// **'Self'**
  String get balanceSelf;

  /// No description provided for @balanceDirectShort.
  ///
  /// In id, this message translates to:
  /// **'Langsung'**
  String get balanceDirectShort;

  /// No description provided for @onchainTitle.
  ///
  /// In id, this message translates to:
  /// **'Dompet On-chain'**
  String get onchainTitle;

  /// No description provided for @onchainSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Saldo dan alamat deposit on-chain'**
  String get onchainSubtitle;

  /// No description provided for @onchainTotal.
  ///
  /// In id, this message translates to:
  /// **'Total'**
  String get onchainTotal;

  /// No description provided for @onchainAddress.
  ///
  /// In id, this message translates to:
  /// **'Alamat deposit'**
  String get onchainAddress;

  /// No description provided for @onchainAddressHint.
  ///
  /// In id, this message translates to:
  /// **'Kirim NUX ke alamat ini untuk mengisi dompet on-chain.'**
  String get onchainAddressHint;

  /// No description provided for @onchainCopied.
  ///
  /// In id, this message translates to:
  /// **'Alamat disalin'**
  String get onchainCopied;

  /// No description provided for @onchainLoadFailed.
  ///
  /// In id, this message translates to:
  /// **'Gagal memuat dompet on-chain'**
  String get onchainLoadFailed;

  /// No description provided for @networkTestnet.
  ///
  /// In id, this message translates to:
  /// **'Lightning Network • Testnet'**
  String get networkTestnet;

  /// No description provided for @networkMainnet.
  ///
  /// In id, this message translates to:
  /// **'Lightning Network • Mainnet'**
  String get networkMainnet;

  /// No description provided for @lightningActive.
  ///
  /// In id, this message translates to:
  /// **'Lightning aktif — siap terima instan'**
  String get lightningActive;

  /// No description provided for @lightningConnecting.
  ///
  /// In id, this message translates to:
  /// **'Menghubungkan Lightning…'**
  String get lightningConnecting;

  /// No description provided for @legacyStrip.
  ///
  /// In id, this message translates to:
  /// **'Dompet ini belum punya frasa backup. Buka tab Profil untuk membuat dompet baru dengan frasa sebelum menerima dana.'**
  String get legacyStrip;

  /// No description provided for @send.
  ///
  /// In id, this message translates to:
  /// **'Kirim'**
  String get send;

  /// No description provided for @receive.
  ///
  /// In id, this message translates to:
  /// **'Terima'**
  String get receive;

  /// No description provided for @activity.
  ///
  /// In id, this message translates to:
  /// **'Aktivitas'**
  String get activity;

  /// No description provided for @seeAll.
  ///
  /// In id, this message translates to:
  /// **'Lihat semua'**
  String get seeAll;

  /// No description provided for @noActivity.
  ///
  /// In id, this message translates to:
  /// **'Belum ada aktivitas'**
  String get noActivity;

  /// No description provided for @market.
  ///
  /// In id, this message translates to:
  /// **'Jelajah'**
  String get market;

  /// No description provided for @jelajahSource.
  ///
  /// In id, this message translates to:
  /// **'Harga pasar — qutrade.io'**
  String get jelajahSource;

  /// No description provided for @jelajahUpdated.
  ///
  /// In id, this message translates to:
  /// **'Diperbarui {time}'**
  String jelajahUpdated(String time);

  /// No description provided for @jelajahChange24h.
  ///
  /// In id, this message translates to:
  /// **'Perubahan 24 jam'**
  String get jelajahChange24h;

  /// No description provided for @jelajahBlockHeight.
  ///
  /// In id, this message translates to:
  /// **'Tinggi blok'**
  String get jelajahBlockHeight;

  /// No description provided for @jelajahDirectory.
  ///
  /// In id, this message translates to:
  /// **'Direktori Toko'**
  String get jelajahDirectory;

  /// No description provided for @jelajahSearchHint.
  ///
  /// In id, this message translates to:
  /// **'Cari toko atau barang…'**
  String get jelajahSearchHint;

  /// No description provided for @jelajahAllCities.
  ///
  /// In id, this message translates to:
  /// **'Semua kota'**
  String get jelajahAllCities;

  /// No description provided for @jelajahPointsProgram.
  ///
  /// In id, this message translates to:
  /// **'Program Poin Mode Toko'**
  String get jelajahPointsProgram;

  /// No description provided for @jelajahCopyOffer.
  ///
  /// In id, this message translates to:
  /// **'Salin Offer'**
  String get jelajahCopyOffer;

  /// No description provided for @jelajahOfferCopied.
  ///
  /// In id, this message translates to:
  /// **'Offer tersalin'**
  String get jelajahOfferCopied;

  /// No description provided for @jelajahEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada toko terdaftar. Pemilik toko dapat mendaftarkan tokonya lewat kanal komunitas Nusacoin.'**
  String get jelajahEmpty;

  /// No description provided for @jelajahNoResults.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada toko yang cocok dengan pencarian.'**
  String get jelajahNoResults;

  /// No description provided for @jelajahDisclaimer.
  ///
  /// In id, this message translates to:
  /// **'Informasi pasar dari sumber publik. Bukan nasihat keuangan.'**
  String get jelajahDisclaimer;

  /// No description provided for @jelajahDirectoryUpdated.
  ///
  /// In id, this message translates to:
  /// **'Direktori diperbarui {time}'**
  String jelajahDirectoryUpdated(String time);

  /// No description provided for @home.
  ///
  /// In id, this message translates to:
  /// **'Beranda'**
  String get home;

  /// No description provided for @history.
  ///
  /// In id, this message translates to:
  /// **'Riwayat'**
  String get history;

  /// No description provided for @profile.
  ///
  /// In id, this message translates to:
  /// **'Profil'**
  String get profile;

  /// No description provided for @received.
  ///
  /// In id, this message translates to:
  /// **'Diterima'**
  String get received;

  /// No description provided for @sent.
  ///
  /// In id, this message translates to:
  /// **'Terkirim'**
  String get sent;

  /// No description provided for @pending.
  ///
  /// In id, this message translates to:
  /// **'Menunggu'**
  String get pending;

  /// No description provided for @processing.
  ///
  /// In id, this message translates to:
  /// **'Sedang diproses'**
  String get processing;

  /// No description provided for @failed.
  ///
  /// In id, this message translates to:
  /// **'Gagal'**
  String get failed;

  /// No description provided for @noTransactions.
  ///
  /// In id, this message translates to:
  /// **'Belum ada transaksi. Pembayaran masuk dan keluar akan tampil di sini.'**
  String get noTransactions;

  /// No description provided for @txDetailTitle.
  ///
  /// In id, this message translates to:
  /// **'Detail Transaksi'**
  String get txDetailTitle;

  /// No description provided for @txType.
  ///
  /// In id, this message translates to:
  /// **'Jenis'**
  String get txType;

  /// No description provided for @txStatus.
  ///
  /// In id, this message translates to:
  /// **'Status'**
  String get txStatus;

  /// No description provided for @txTime.
  ///
  /// In id, this message translates to:
  /// **'Waktu'**
  String get txTime;

  /// No description provided for @txPaymentId.
  ///
  /// In id, this message translates to:
  /// **'ID Pembayaran'**
  String get txPaymentId;

  /// No description provided for @txPaymentHash.
  ///
  /// In id, this message translates to:
  /// **'Hash Pembayaran'**
  String get txPaymentHash;

  /// No description provided for @txNote.
  ///
  /// In id, this message translates to:
  /// **'Catatan'**
  String get txNote;

  /// No description provided for @txSucceeded.
  ///
  /// In id, this message translates to:
  /// **'Berhasil'**
  String get txSucceeded;

  /// No description provided for @txExpiredBadge.
  ///
  /// In id, this message translates to:
  /// **'Kedaluwarsa'**
  String get txExpiredBadge;

  /// No description provided for @txInvoiceExpiredNote.
  ///
  /// In id, this message translates to:
  /// **'Invoice ini sudah kedaluwarsa dan tidak bisa dibayar lagi. Buat invoice baru untuk menerima pembayaran.'**
  String get txInvoiceExpiredNote;

  /// No description provided for @txInvoiceNotSavedNote.
  ///
  /// In id, this message translates to:
  /// **'Invoice ini dibuat sebelum fitur simpan invoice tersedia, jadi string invoice-nya tidak tersimpan di aplikasi dan tidak bisa ditampilkan kembali.'**
  String get txInvoiceNotSavedNote;

  /// No description provided for @txProcessingNote.
  ///
  /// In id, this message translates to:
  /// **'Uangmu aman dan sedang menunggu giliran tercatat di jaringan. Akan selesai sendiri.'**
  String get txProcessingNote;

  /// No description provided for @txJitNote.
  ///
  /// In id, this message translates to:
  /// **'Pembayaran ini sekaligus membuatkan jalur penerimaan baru untukmu, jadi ada potongan biaya pembuatan 0,5%. Pembayaran berikutnya lewat jalur ini tidak dipotong lagi.'**
  String get txJitNote;

  /// No description provided for @txCopied.
  ///
  /// In id, this message translates to:
  /// **'Disalin'**
  String get txCopied;

  /// No description provided for @receiveRestoredHint.
  ///
  /// In id, this message translates to:
  /// **'Invoice terakhir yang belum dibayar dipulihkan dari simpanan.'**
  String get receiveRestoredHint;

  /// No description provided for @backupWallet.
  ///
  /// In id, this message translates to:
  /// **'Pencadangan Dompet'**
  String get backupWallet;

  /// No description provided for @legacyWalletSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Dompet ini dibuat sebelum fitur frasa backup ada'**
  String get legacyWalletSubtitle;

  /// No description provided for @backupSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Lihat frasa backup dompet Anda'**
  String get backupSubtitle;

  /// No description provided for @noPhraseTitle.
  ///
  /// In id, this message translates to:
  /// **'Dompet ini tidak punya frasa backup'**
  String get noPhraseTitle;

  /// No description provided for @noPhraseBody.
  ///
  /// In id, this message translates to:
  /// **'Dompet ini dibuat oleh versi aplikasi sebelumnya yang menyimpan kunci tanpa frasa. Bila HP hilang atau rusak, dana di dompet ini tidak bisa dipulihkan.\n\nBila dompet ini masih KOSONG (belum pernah menerima dana), buat dompet baru yang dilengkapi frasa backup sekarang:'**
  String get noPhraseBody;

  /// No description provided for @createNewWalletTitle.
  ///
  /// In id, this message translates to:
  /// **'Buat dompet baru?'**
  String get createNewWalletTitle;

  /// No description provided for @deleteOldWalletBody.
  ///
  /// In id, this message translates to:
  /// **'Dompet lama akan DIHAPUS PERMANEN beserta seluruh datanya. Lanjutkan HANYA bila dompet lama masih kosong — dana apa pun di dalamnya hilang selamanya.'**
  String get deleteOldWalletBody;

  /// No description provided for @deleteAndCreate.
  ///
  /// In id, this message translates to:
  /// **'Hapus & buat baru'**
  String get deleteAndCreate;

  /// No description provided for @createNewWalletButton.
  ///
  /// In id, this message translates to:
  /// **'Buat dompet baru dengan frasa'**
  String get createNewWalletButton;

  /// No description provided for @networkTestnetLabel.
  ///
  /// In id, this message translates to:
  /// **'Jaringan: Nusacoin Testnet'**
  String get networkTestnetLabel;

  /// No description provided for @networkMainnetLabel.
  ///
  /// In id, this message translates to:
  /// **'Jaringan: Nusacoin Mainnet'**
  String get networkMainnetLabel;

  /// No description provided for @appVersionLabel.
  ///
  /// In id, this message translates to:
  /// **'Versi {version} • Build {build}'**
  String appVersionLabel(String version, String build);

  /// No description provided for @backupWarning.
  ///
  /// In id, this message translates to:
  /// **'Tulis kata-kata ini di kertas dan simpan di tempat aman. Siapa pun yang punya kata-kata ini bisa mengambil danamu.'**
  String get backupWarning;

  /// No description provided for @showBackupWords.
  ///
  /// In id, this message translates to:
  /// **'Tampilkan Kata Backup'**
  String get showBackupWords;

  /// No description provided for @backupCopied.
  ///
  /// In id, this message translates to:
  /// **'Kata backup disalin'**
  String get backupCopied;

  /// No description provided for @copy.
  ///
  /// In id, this message translates to:
  /// **'Salin'**
  String get copy;

  /// No description provided for @backupConfirmed.
  ///
  /// In id, this message translates to:
  /// **'Saya sudah menulis kata-kata ini di tempat aman'**
  String get backupConfirmed;

  /// No description provided for @done.
  ///
  /// In id, this message translates to:
  /// **'Selesai'**
  String get done;

  /// No description provided for @invalidAmount.
  ///
  /// In id, this message translates to:
  /// **'Masukkan nominal yang valid'**
  String get invalidAmount;

  /// No description provided for @receiveInvoiceDesc.
  ///
  /// In id, this message translates to:
  /// **'Terima {amount}'**
  String receiveInvoiceDesc(String amount);

  /// No description provided for @receiveNoteLabel.
  ///
  /// In id, this message translates to:
  /// **'Catatan (opsional)'**
  String get receiveNoteLabel;

  /// No description provided for @receiveNoteHint.
  ///
  /// In id, this message translates to:
  /// **'cth. untuk SPP bulan November'**
  String get receiveNoteHint;

  /// No description provided for @createInvoiceFailed.
  ///
  /// In id, this message translates to:
  /// **'Gagal membuat invoice. Coba lagi.'**
  String get createInvoiceFailed;

  /// No description provided for @receiveJitMinimumNote.
  ///
  /// In id, this message translates to:
  /// **'Untuk penerimaan pertama (sekaligus membuatkan jalur penerimaanmu), jumlah terkecilnya 1.000 nusan. Setelah jalurmu jadi, kamu bisa menerima berapa pun, termasuk di bawah 1.000 nusan.'**
  String get receiveJitMinimumNote;

  /// No description provided for @receiveTitle.
  ///
  /// In id, this message translates to:
  /// **'Terima NUX'**
  String get receiveTitle;

  /// No description provided for @jitInfo.
  ///
  /// In id, this message translates to:
  /// **'Invoice Lightning dengan channel instan (JIT). Tidak perlu tunggu konfirmasi block.'**
  String get jitInfo;

  /// No description provided for @amountLabel.
  ///
  /// In id, this message translates to:
  /// **'Nominal'**
  String get amountLabel;

  /// No description provided for @createInvoice.
  ///
  /// In id, this message translates to:
  /// **'Buat Invoice'**
  String get createInvoice;

  /// No description provided for @paymentReceived.
  ///
  /// In id, this message translates to:
  /// **'Pembayaran Diterima'**
  String get paymentReceived;

  /// No description provided for @receivedAmount.
  ///
  /// In id, this message translates to:
  /// **'+{amount}'**
  String receivedAmount(String amount);

  /// No description provided for @fundsArrived.
  ///
  /// In id, this message translates to:
  /// **'Dana sudah masuk ke channel Lightning kamu.'**
  String get fundsArrived;

  /// No description provided for @invoiceTitle.
  ///
  /// In id, this message translates to:
  /// **'Invoice Lightning'**
  String get invoiceTitle;

  /// No description provided for @invoiceCopied.
  ///
  /// In id, this message translates to:
  /// **'Invoice disalin'**
  String get invoiceCopied;

  /// No description provided for @shareInvoiceHint.
  ///
  /// In id, this message translates to:
  /// **'Bagikan invoice ini ke pengirim. Channel akan dibuka otomatis saat pembayaran diterima.'**
  String get shareInvoiceHint;

  /// No description provided for @staticCodeTitle.
  ///
  /// In id, this message translates to:
  /// **'Kode Bayar Statis'**
  String get staticCodeTitle;

  /// No description provided for @staticCodeHint.
  ///
  /// In id, this message translates to:
  /// **'Kode ini bisa dipakai berulang kali tanpa kedaluwarsa — bagikan sekali, pembayar menentukan jumlahnya setiap kali membayar.'**
  String get staticCodeHint;

  /// No description provided for @staticCodeInactive.
  ///
  /// In id, this message translates to:
  /// **'Kode statis belum aktif. Terima satu pembayaran lewat invoice terlebih dahulu — sesudah jalur pertama terbentuk, kode ini aktif dengan sendirinya.'**
  String get staticCodeInactive;

  /// No description provided for @staticCodeCopied.
  ///
  /// In id, this message translates to:
  /// **'Kode bayar disalin'**
  String get staticCodeCopied;

  /// No description provided for @staticCodeNeedsConnection.
  ///
  /// In id, this message translates to:
  /// **'Kode bayar dibuat begitu dompet tersambung. Periksa koneksimu, lalu coba lagi.'**
  String get staticCodeNeedsConnection;

  /// No description provided for @staticCodeFailed.
  ///
  /// In id, this message translates to:
  /// **'Gagal membuat kode bayar. Coba lagi.'**
  String get staticCodeFailed;

  /// No description provided for @staticOfferDescription.
  ///
  /// In id, this message translates to:
  /// **'Kode bayar ELNUX'**
  String get staticOfferDescription;

  /// No description provided for @confirmPayOfferTitle.
  ///
  /// In id, this message translates to:
  /// **'Bayar kode bayar ini?'**
  String get confirmPayOfferTitle;

  /// No description provided for @sendOfferAmountLine.
  ///
  /// In id, this message translates to:
  /// **'Nominal: {amount}'**
  String sendOfferAmountLine(String amount);

  /// No description provided for @sendOfferVariableHint.
  ///
  /// In id, this message translates to:
  /// **'Kode bayar ini tidak menetapkan nominal — tentukan sendiri jumlah yang mau dibayar.'**
  String get sendOfferVariableHint;

  /// No description provided for @sendOfferInvalid.
  ///
  /// In id, this message translates to:
  /// **'Kode bayar tidak valid.'**
  String get sendOfferInvalid;

  /// No description provided for @sendOfferExpired.
  ///
  /// In id, this message translates to:
  /// **'Kode bayar sudah kedaluwarsa.'**
  String get sendOfferExpired;

  /// No description provided for @pasteInvoiceFirst.
  ///
  /// In id, this message translates to:
  /// **'Tempel invoice dulu'**
  String get pasteInvoiceFirst;

  /// No description provided for @invalidInvoice.
  ///
  /// In id, this message translates to:
  /// **'Ini bukan invoice Lightning yang valid'**
  String get invalidInvoice;

  /// No description provided for @payFailed.
  ///
  /// In id, this message translates to:
  /// **'Pembayaran gagal. Coba lagi.'**
  String get payFailed;

  /// No description provided for @payWaitingOutcome.
  ///
  /// In id, this message translates to:
  /// **'Menunggu hasil akhir pembayaran…'**
  String get payWaitingOutcome;

  /// No description provided for @payFailedFinal.
  ///
  /// In id, this message translates to:
  /// **'Pembayaran gagal. Dana tidak terkirim dan saldo Anda tetap utuh.'**
  String get payFailedFinal;

  /// No description provided for @payStillPending.
  ///
  /// In id, this message translates to:
  /// **'Pembayaran masih diproses melewati batas tunggu. Hasil akhirnya akan tampil di Riwayat — jangan bayar ulang invoice yang sama sebelum statusnya jelas.'**
  String get payStillPending;

  /// No description provided for @sendTitle.
  ///
  /// In id, this message translates to:
  /// **'Kirim NUX'**
  String get sendTitle;

  /// No description provided for @sendInfo.
  ///
  /// In id, this message translates to:
  /// **'Tempel atau scan invoice Lightning dari penerima. Pembayaran instan via channel.'**
  String get sendInfo;

  /// No description provided for @sendableLine.
  ///
  /// In id, this message translates to:
  /// **'Bisa dikirim: {amount}'**
  String sendableLine(String amount);

  /// No description provided for @sendInsufficientBalance.
  ///
  /// In id, this message translates to:
  /// **'Saldo tidak cukup untuk membayar invoice ini.'**
  String get sendInsufficientBalance;

  /// No description provided for @sendReserveNote.
  ///
  /// In id, this message translates to:
  /// **'Jumlah ini belum bisa dikirim. Dari saldomu, {reserve} selalu disisakan sebagai cadangan pengaman jalur — tetap milikmu, bukan potongan, dan kembali utuh bila jalur ditutup. Yang bisa dikirim saat ini: {sendable}.'**
  String sendReserveNote(String reserve, String sendable);

  /// No description provided for @sendZeroSendableHint.
  ///
  /// In id, this message translates to:
  /// **'Terima kiriman terlebih dahulu supaya saldomu melewati cadangan — sesudah itu kamu bisa mengirim lagi.'**
  String get sendZeroSendableHint;

  /// No description provided for @backToHome.
  ///
  /// In id, this message translates to:
  /// **'Kembali ke Beranda'**
  String get backToHome;

  /// No description provided for @paste.
  ///
  /// In id, this message translates to:
  /// **'Tempel'**
  String get paste;

  /// No description provided for @scanQr.
  ///
  /// In id, this message translates to:
  /// **'Pindai QR'**
  String get scanQr;

  /// No description provided for @pay.
  ///
  /// In id, this message translates to:
  /// **'Bayar'**
  String get pay;

  /// No description provided for @confirmPayTitle.
  ///
  /// In id, this message translates to:
  /// **'Bayar invoice ini?'**
  String get confirmPayTitle;

  /// No description provided for @confirmPayBody.
  ///
  /// In id, this message translates to:
  /// **'Pembayaran Lightning bersifat instan dan tidak bisa dibatalkan. Periksa lagi invoice di bawah sebelum lanjut.'**
  String get confirmPayBody;

  /// No description provided for @confirmPayAmountLine.
  ///
  /// In id, this message translates to:
  /// **'Nominal: {amount}'**
  String confirmPayAmountLine(String amount);

  /// No description provided for @paymentSuccess.
  ///
  /// In id, this message translates to:
  /// **'Pembayaran Berhasil!'**
  String get paymentSuccess;

  /// No description provided for @scanTitle.
  ///
  /// In id, this message translates to:
  /// **'Pindai Invoice QR'**
  String get scanTitle;

  /// No description provided for @cameraDenied.
  ///
  /// In id, this message translates to:
  /// **'Izin kamera ditolak. Aktifkan izin kamera untuk ELNUX di Pengaturan HP, lalu coba lagi.'**
  String get cameraDenied;

  /// No description provided for @cameraUnavailable.
  ///
  /// In id, this message translates to:
  /// **'Kamera tidak dapat dibuka di perangkat ini.'**
  String get cameraUnavailable;

  /// No description provided for @pointCamera.
  ///
  /// In id, this message translates to:
  /// **'Arahkan kamera ke QR invoice'**
  String get pointCamera;

  /// No description provided for @scanFromGallery.
  ///
  /// In id, this message translates to:
  /// **'Pilih dari galeri'**
  String get scanFromGallery;

  /// No description provided for @scanNoQrFound.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada kode QR pada gambar itu'**
  String get scanNoQrFound;

  /// No description provided for @errorConnection.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat terhubung. Periksa koneksi internet Anda, lalu coba lagi.'**
  String get errorConnection;

  /// No description provided for @errorBalance.
  ///
  /// In id, this message translates to:
  /// **'Saldo tidak mencukupi.'**
  String get errorBalance;

  /// No description provided for @errorInvoice.
  ///
  /// In id, this message translates to:
  /// **'Invoice tidak valid atau sudah kedaluwarsa.'**
  String get errorInvoice;

  /// No description provided for @errorWalletData.
  ///
  /// In id, this message translates to:
  /// **'Data dompet bermasalah. Hubungi operator untuk bantuan.'**
  String get errorWalletData;

  /// No description provided for @restoreWallet.
  ///
  /// In id, this message translates to:
  /// **'Pemulihan Dompet'**
  String get restoreWallet;

  /// No description provided for @restoreSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Pulihkan dompet dari frasa backup'**
  String get restoreSubtitle;

  /// No description provided for @restoreIntro.
  ///
  /// In id, this message translates to:
  /// **'Masukkan frasa backup dompet yang ingin dipulihkan. Frasa ELNUX berbahasa Inggris, sesuai urutan saat pertama dibuat.'**
  String get restoreIntro;

  /// No description provided for @restoreHint.
  ///
  /// In id, this message translates to:
  /// **'Ketik atau tempel frasa, pisahkan tiap kata dengan spasi'**
  String get restoreHint;

  /// No description provided for @restoreWordCount.
  ///
  /// In id, this message translates to:
  /// **'{count} kata'**
  String restoreWordCount(int count);

  /// No description provided for @restoreInvalidCount.
  ///
  /// In id, this message translates to:
  /// **'Jumlah kata harus 12, 15, 18, 21, atau 24 (frasa ELNUX 12 kata).'**
  String get restoreInvalidCount;

  /// No description provided for @restoreInvalidWords.
  ///
  /// In id, this message translates to:
  /// **'Frasa tidak valid — periksa ejaan dan urutan kata.'**
  String get restoreInvalidWords;

  /// No description provided for @restoreButton.
  ///
  /// In id, this message translates to:
  /// **'Pulihkan Dompet'**
  String get restoreButton;

  /// No description provided for @restoreConfirmTitle.
  ///
  /// In id, this message translates to:
  /// **'Pulihkan dompet ini?'**
  String get restoreConfirmTitle;

  /// No description provided for @restoreConfirmBody.
  ///
  /// In id, this message translates to:
  /// **'Dompet yang sedang aktif akan DIHAPUS PERMANEN beserta seluruh datanya. Lanjutkan HANYA bila dompet aktif masih kosong, atau frasanya sudah dicadangkan. Frasa hanya memulihkan dompet — status channel Lightning tidak ikut pulih.'**
  String get restoreConfirmBody;

  /// No description provided for @restoreConfirmAction.
  ///
  /// In id, this message translates to:
  /// **'Hapus & Pulihkan'**
  String get restoreConfirmAction;

  /// No description provided for @restoreWorking.
  ///
  /// In id, this message translates to:
  /// **'Memulihkan dompet…'**
  String get restoreWorking;

  /// No description provided for @restoreSuccess.
  ///
  /// In id, this message translates to:
  /// **'Dompet berhasil dipulihkan'**
  String get restoreSuccess;

  /// No description provided for @restoreFailed.
  ///
  /// In id, this message translates to:
  /// **'Gagal memulihkan dompet. Coba lagi.'**
  String get restoreFailed;

  /// No description provided for @shareLog.
  ///
  /// In id, this message translates to:
  /// **'Bagikan Log'**
  String get shareLog;

  /// No description provided for @shareLogSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Kirim catatan teknis node saat ada kendala'**
  String get shareLogSubtitle;

  /// No description provided for @shareLogUnavailable.
  ///
  /// In id, this message translates to:
  /// **'Log belum tersedia.'**
  String get shareLogUnavailable;

  /// No description provided for @shareLogFailed.
  ///
  /// In id, this message translates to:
  /// **'Gagal membagikan log. Coba lagi.'**
  String get shareLogFailed;

  /// No description provided for @printer.
  ///
  /// In id, this message translates to:
  /// **'Printer'**
  String get printer;

  /// No description provided for @printerSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Printer struk, uji cetak, header & footer'**
  String get printerSubtitle;

  /// No description provided for @printerSettings.
  ///
  /// In id, this message translates to:
  /// **'Pengaturan Printer'**
  String get printerSettings;

  /// No description provided for @printerSelect.
  ///
  /// In id, this message translates to:
  /// **'Pilih printer'**
  String get printerSelect;

  /// No description provided for @printerNoneSelected.
  ///
  /// In id, this message translates to:
  /// **'Belum ada printer dipilih'**
  String get printerNoneSelected;

  /// No description provided for @printerNoPaired.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada printer ter-pairing. Pairing printer dulu di Pengaturan Bluetooth Android.'**
  String get printerNoPaired;

  /// No description provided for @printerTest.
  ///
  /// In id, this message translates to:
  /// **'Uji Cetak'**
  String get printerTest;

  /// No description provided for @printerHeader.
  ///
  /// In id, this message translates to:
  /// **'Teks header'**
  String get printerHeader;

  /// No description provided for @printerHeaderHint.
  ///
  /// In id, this message translates to:
  /// **'Dicetak di bagian atas setiap struk (mis. nama dan alamat toko)'**
  String get printerHeaderHint;

  /// No description provided for @printerFooter.
  ///
  /// In id, this message translates to:
  /// **'Teks footer'**
  String get printerFooter;

  /// No description provided for @printerFooterHint.
  ///
  /// In id, this message translates to:
  /// **'Dicetak di bagian bawah setiap struk'**
  String get printerFooterHint;

  /// No description provided for @print.
  ///
  /// In id, this message translates to:
  /// **'Cetak'**
  String get print;

  /// No description provided for @printSuccess.
  ///
  /// In id, this message translates to:
  /// **'Struk tercetak'**
  String get printSuccess;

  /// No description provided for @printFailed.
  ///
  /// In id, this message translates to:
  /// **'Gagal mencetak. Periksa printer lalu coba lagi.'**
  String get printFailed;

  /// No description provided for @printNoPrinter.
  ///
  /// In id, this message translates to:
  /// **'Belum ada printer dipilih. Pilih dulu di Profil, Printer.'**
  String get printNoPrinter;

  /// No description provided for @printBluetoothOff.
  ///
  /// In id, this message translates to:
  /// **'Bluetooth mati. Nyalakan dulu lalu coba lagi.'**
  String get printBluetoothOff;

  /// No description provided for @printPermissionDenied.
  ///
  /// In id, this message translates to:
  /// **'Izin Bluetooth diperlukan untuk memakai printer.'**
  String get printPermissionDenied;

  /// No description provided for @receiptDefaultFooter.
  ///
  /// In id, this message translates to:
  /// **'Terima kasih'**
  String get receiptDefaultFooter;

  /// No description provided for @printerSearchHint.
  ///
  /// In id, this message translates to:
  /// **'Cari nama atau alamat'**
  String get printerSearchHint;

  /// No description provided for @printerTurnOn.
  ///
  /// In id, this message translates to:
  /// **'Nyalakan Bluetooth'**
  String get printerTurnOn;

  /// No description provided for @printerScan.
  ///
  /// In id, this message translates to:
  /// **'Pindai printer'**
  String get printerScan;

  /// No description provided for @printerScanning.
  ///
  /// In id, this message translates to:
  /// **'Memindai…'**
  String get printerScanning;

  /// No description provided for @printerDiscovered.
  ///
  /// In id, this message translates to:
  /// **'Perangkat ditemukan'**
  String get printerDiscovered;

  /// No description provided for @printerTapToPair.
  ///
  /// In id, this message translates to:
  /// **'Ketuk untuk memasangkan dan memilih'**
  String get printerTapToPair;

  /// No description provided for @printerBondFailed.
  ///
  /// In id, this message translates to:
  /// **'Gagal memasangkan perangkat itu.'**
  String get printerBondFailed;

  /// No description provided for @printerPairedSelected.
  ///
  /// In id, this message translates to:
  /// **'Printer terpasang dan dipilih'**
  String get printerPairedSelected;

  /// No description provided for @historyExport.
  ///
  /// In id, this message translates to:
  /// **'Ekspor CSV'**
  String get historyExport;

  /// No description provided for @historyExportFailed.
  ///
  /// In id, this message translates to:
  /// **'Gagal membuat berkas CSV.'**
  String get historyExportFailed;

  /// No description provided for @historyFilter.
  ///
  /// In id, this message translates to:
  /// **'Filter tanggal'**
  String get historyFilter;

  /// No description provided for @historyLast7Days.
  ///
  /// In id, this message translates to:
  /// **'7 hari terakhir'**
  String get historyLast7Days;

  /// No description provided for @historyLast30Days.
  ///
  /// In id, this message translates to:
  /// **'30 hari terakhir'**
  String get historyLast30Days;

  /// No description provided for @historyCustomRange.
  ///
  /// In id, this message translates to:
  /// **'Periode tanggal…'**
  String get historyCustomRange;

  /// No description provided for @historyNoTransactionsInPeriod.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada transaksi pada periode ini.'**
  String get historyNoTransactionsInPeriod;

  /// No description provided for @updateTitle.
  ///
  /// In id, this message translates to:
  /// **'Pembaruan Tersedia'**
  String get updateTitle;

  /// No description provided for @updateVersionAvailable.
  ///
  /// In id, this message translates to:
  /// **'Versi baru tersedia: {versi}'**
  String updateVersionAvailable(String versi);

  /// No description provided for @updateNotes.
  ///
  /// In id, this message translates to:
  /// **'Catatan rilis'**
  String get updateNotes;

  /// No description provided for @updateDownloadInstall.
  ///
  /// In id, this message translates to:
  /// **'Unduh & Pasang'**
  String get updateDownloadInstall;

  /// No description provided for @updateLater.
  ///
  /// In id, this message translates to:
  /// **'Nanti'**
  String get updateLater;

  /// No description provided for @updateDownloading.
  ///
  /// In id, this message translates to:
  /// **'Mengunduh… {percent}%'**
  String updateDownloading(int percent);

  /// No description provided for @updateFailed.
  ///
  /// In id, this message translates to:
  /// **'Unduhan gagal. Periksa koneksi lalu coba lagi.'**
  String get updateFailed;

  /// No description provided for @updateRetry.
  ///
  /// In id, this message translates to:
  /// **'Coba Lagi'**
  String get updateRetry;

  /// No description provided for @updateCheckTitle.
  ///
  /// In id, this message translates to:
  /// **'Periksa Pembaruan'**
  String get updateCheckTitle;

  /// No description provided for @updateCheckSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Lihat apakah ada versi ELNUX yang lebih baru'**
  String get updateCheckSubtitle;

  /// No description provided for @updateUpToDate.
  ///
  /// In id, this message translates to:
  /// **'ELNUX sudah versi terbaru.'**
  String get updateUpToDate;

  /// No description provided for @updateCheckFailed.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat memeriksa pembaruan saat ini.'**
  String get updateCheckFailed;

  /// No description provided for @updateChecking.
  ///
  /// In id, this message translates to:
  /// **'Memeriksa pembaruan…'**
  String get updateChecking;

  /// No description provided for @communityTitle.
  ///
  /// In id, this message translates to:
  /// **'Komunitas'**
  String get communityTitle;

  /// No description provided for @communityWebsiteLabel.
  ///
  /// In id, this message translates to:
  /// **'Website'**
  String get communityWebsiteLabel;

  /// No description provided for @communityTelegramGroup.
  ///
  /// In id, this message translates to:
  /// **'Grup Telegram'**
  String get communityTelegramGroup;

  /// No description provided for @communityOpenFailed.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat membuka tautan.'**
  String get communityOpenFailed;

  /// No description provided for @storeMode.
  ///
  /// In id, this message translates to:
  /// **'Mode Toko'**
  String get storeMode;

  /// No description provided for @storeModeSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Kasir toko — penjualan rupiah & program poin nusan'**
  String get storeModeSubtitle;

  /// No description provided for @storeIdleHint.
  ///
  /// In id, this message translates to:
  /// **'Susun pesanan, lalu selesaikan pembayaran dalam rupiah. Poin nusan diperoleh pelanggan sesudah penjualan lunas.'**
  String get storeIdleHint;

  /// No description provided for @storeFreeAmountLabel.
  ///
  /// In id, this message translates to:
  /// **'Nominal Bebas (Rp)'**
  String get storeFreeAmountLabel;

  /// No description provided for @storeAddFreeItem.
  ///
  /// In id, this message translates to:
  /// **'Tambah Item Bebas'**
  String get storeAddFreeItem;

  /// No description provided for @storeFreeItem.
  ///
  /// In id, this message translates to:
  /// **'Item Bebas'**
  String get storeFreeItem;

  /// No description provided for @storeFreeTitleLabel.
  ///
  /// In id, this message translates to:
  /// **'Nama Item (opsional)'**
  String get storeFreeTitleLabel;

  /// No description provided for @storeSearchHint.
  ///
  /// In id, this message translates to:
  /// **'Cari nama atau kode produk…'**
  String get storeSearchHint;

  /// No description provided for @storeSearchNoResults.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada produk yang cocok dengan pencarian.'**
  String get storeSearchNoResults;

  /// No description provided for @storeRemoveLineTitle.
  ///
  /// In id, this message translates to:
  /// **'Hapus dari Pesanan?'**
  String get storeRemoveLineTitle;

  /// No description provided for @storeRemoveLineMessage.
  ///
  /// In id, this message translates to:
  /// **'Hapus {name} dari pesanan?'**
  String storeRemoveLineMessage(String name);

  /// No description provided for @storeRemoveLineConfirm.
  ///
  /// In id, this message translates to:
  /// **'Hapus'**
  String get storeRemoveLineConfirm;

  /// No description provided for @storeAddNote.
  ///
  /// In id, this message translates to:
  /// **'Tambah Catatan'**
  String get storeAddNote;

  /// No description provided for @storeLineNoteTitle.
  ///
  /// In id, this message translates to:
  /// **'Catatan Item'**
  String get storeLineNoteTitle;

  /// No description provided for @storeNoteWord.
  ///
  /// In id, this message translates to:
  /// **'Cat.'**
  String get storeNoteWord;

  /// No description provided for @storeClearNote.
  ///
  /// In id, this message translates to:
  /// **'Hapus Catatan'**
  String get storeClearNote;

  /// No description provided for @storeSaveNote.
  ///
  /// In id, this message translates to:
  /// **'Simpan'**
  String get storeSaveNote;

  /// No description provided for @storeHoldOrder.
  ///
  /// In id, this message translates to:
  /// **'Tahan'**
  String get storeHoldOrder;

  /// No description provided for @storeHeldSaved.
  ///
  /// In id, this message translates to:
  /// **'Pesanan ditahan — bisa dilanjutkan kapan saja dari daftar Ditahan.'**
  String get storeHeldSaved;

  /// No description provided for @storeHeldTitle.
  ///
  /// In id, this message translates to:
  /// **'Pesanan Ditahan'**
  String get storeHeldTitle;

  /// No description provided for @storeHeldBadge.
  ///
  /// In id, this message translates to:
  /// **'Ditahan ({count})'**
  String storeHeldBadge(int count);

  /// No description provided for @storeHeldEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada pesanan yang ditahan.'**
  String get storeHeldEmpty;

  /// No description provided for @storeHeldEntryMeta.
  ///
  /// In id, this message translates to:
  /// **'{time} • {count} item • {total}'**
  String storeHeldEntryMeta(String time, int count, String total);

  /// No description provided for @storeHeldResumeBlocked.
  ///
  /// In id, this message translates to:
  /// **'Pesanan berjalan belum kosong — tahan atau selesaikan dulu pesanan yang sedang disusun.'**
  String get storeHeldResumeBlocked;

  /// No description provided for @storeHeldResumed.
  ///
  /// In id, this message translates to:
  /// **'Pesanan ditahan dilanjutkan.'**
  String get storeHeldResumed;

  /// No description provided for @storeExitHoldTitle.
  ///
  /// In id, this message translates to:
  /// **'Pesanan Belum Selesai'**
  String get storeExitHoldTitle;

  /// No description provided for @storeExitHoldBody.
  ///
  /// In id, this message translates to:
  /// **'Pesanan yang sedang disusun belum selesai. Bila keluar sekarang, pesanan ini ditahan otomatis dan bisa dilanjutkan kapan saja dari daftar Ditahan.'**
  String get storeExitHoldBody;

  /// No description provided for @storeExitStay.
  ///
  /// In id, this message translates to:
  /// **'Tetap di Sini'**
  String get storeExitStay;

  /// No description provided for @storeExitHoldLeave.
  ///
  /// In id, this message translates to:
  /// **'Tahan & Keluar'**
  String get storeExitHoldLeave;

  /// No description provided for @storeExitHoldFailed.
  ///
  /// In id, this message translates to:
  /// **'Pesanan gagal ditahan — tetap di layar ini supaya pesanan tidak hilang.'**
  String get storeExitHoldFailed;

  /// No description provided for @storeDraftRestored.
  ///
  /// In id, this message translates to:
  /// **'Draf pesanan terakhir dipulihkan — lanjutkan dari tempat terakhir.'**
  String get storeDraftRestored;

  /// No description provided for @storeDeleteHeldTitle.
  ///
  /// In id, this message translates to:
  /// **'Hapus Pesanan Ditahan?'**
  String get storeDeleteHeldTitle;

  /// No description provided for @storeDeleteHeldMessage.
  ///
  /// In id, this message translates to:
  /// **'Hapus pesanan ditahan {summary}? Tindakan ini tidak bisa dibatalkan.'**
  String storeDeleteHeldMessage(String summary);

  /// No description provided for @storeKeypadModeQty.
  ///
  /// In id, this message translates to:
  /// **'Qty'**
  String get storeKeypadModeQty;

  /// No description provided for @storeKeypadModeAmount.
  ///
  /// In id, this message translates to:
  /// **'Nominal'**
  String get storeKeypadModeAmount;

  /// No description provided for @storeQtyBadge.
  ///
  /// In id, this message translates to:
  /// **'Qty: {qty}'**
  String storeQtyBadge(int qty);

  /// No description provided for @storeQtyModeHint.
  ///
  /// In id, this message translates to:
  /// **'Mode Qty: ketuk angka sebagai pengali, lalu ketuk produk di katalog atau pindai kodenya — produk masuk sebanyak pengali itu.'**
  String get storeQtyModeHint;

  /// No description provided for @storeProductAddedQty.
  ///
  /// In id, this message translates to:
  /// **'Ditambahkan: {name} ×{qty}'**
  String storeProductAddedQty(String name, int qty);

  /// No description provided for @storeOrderTitle.
  ///
  /// In id, this message translates to:
  /// **'Pesanan'**
  String get storeOrderTitle;

  /// No description provided for @storeOrderEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada item — ketuk produk di katalog, pindai kode, atau tambah nominal bebas.'**
  String get storeOrderEmpty;

  /// No description provided for @storeSubtotal.
  ///
  /// In id, this message translates to:
  /// **'Subtotal'**
  String get storeSubtotal;

  /// No description provided for @storeTotalDiscount.
  ///
  /// In id, this message translates to:
  /// **'Total Diskon'**
  String get storeTotalDiscount;

  /// No description provided for @storeGrandTotal.
  ///
  /// In id, this message translates to:
  /// **'Total'**
  String get storeGrandTotal;

  /// No description provided for @storeOrderDiscount.
  ///
  /// In id, this message translates to:
  /// **'Diskon Order'**
  String get storeOrderDiscount;

  /// No description provided for @storeDiscount.
  ///
  /// In id, this message translates to:
  /// **'Diskon'**
  String get storeDiscount;

  /// No description provided for @storeSetDiscount.
  ///
  /// In id, this message translates to:
  /// **'Atur Diskon'**
  String get storeSetDiscount;

  /// No description provided for @storeApplyDiscount.
  ///
  /// In id, this message translates to:
  /// **'Terapkan'**
  String get storeApplyDiscount;

  /// No description provided for @storeRemoveDiscount.
  ///
  /// In id, this message translates to:
  /// **'Hapus Diskon'**
  String get storeRemoveDiscount;

  /// No description provided for @storeDiscountPercent.
  ///
  /// In id, this message translates to:
  /// **'Persen (%)'**
  String get storeDiscountPercent;

  /// No description provided for @storeDiscountFixed.
  ///
  /// In id, this message translates to:
  /// **'Nominal (Rp)'**
  String get storeDiscountFixed;

  /// No description provided for @storeDiscountValue.
  ///
  /// In id, this message translates to:
  /// **'Nilai Diskon'**
  String get storeDiscountValue;

  /// No description provided for @storeSessionTitle.
  ///
  /// In id, this message translates to:
  /// **'Sesi Ini'**
  String get storeSessionTitle;

  /// No description provided for @storeSessionSales.
  ///
  /// In id, this message translates to:
  /// **'{count} transaksi • Rp{total}'**
  String storeSessionSales(int count, String total);

  /// No description provided for @storePrintReceipt.
  ///
  /// In id, this message translates to:
  /// **'Cetak Struk'**
  String get storePrintReceipt;

  /// No description provided for @storeScanCode.
  ///
  /// In id, this message translates to:
  /// **'Pindai Kode'**
  String get storeScanCode;

  /// No description provided for @storeCatalogTitle.
  ///
  /// In id, this message translates to:
  /// **'Katalog Produk'**
  String get storeCatalogTitle;

  /// No description provided for @storeManageCatalog.
  ///
  /// In id, this message translates to:
  /// **'Kelola'**
  String get storeManageCatalog;

  /// No description provided for @storeCatalogEmpty.
  ///
  /// In id, this message translates to:
  /// **'Katalog masih kosong — tambahkan produk pertama lewat tombol Kelola.'**
  String get storeCatalogEmpty;

  /// No description provided for @storeCategoryAll.
  ///
  /// In id, this message translates to:
  /// **'Semua'**
  String get storeCategoryAll;

  /// No description provided for @storeCodeNotRegistered.
  ///
  /// In id, this message translates to:
  /// **'Kode ini belum terdaftar di katalog.'**
  String get storeCodeNotRegistered;

  /// No description provided for @storeRegisterNow.
  ///
  /// In id, this message translates to:
  /// **'Daftarkan Sekarang'**
  String get storeRegisterNow;

  /// No description provided for @storeProductCode.
  ///
  /// In id, this message translates to:
  /// **'Kode Produk'**
  String get storeProductCode;

  /// No description provided for @storeProductCodeHint.
  ///
  /// In id, this message translates to:
  /// **'Terisi otomatis — boleh diganti dengan barcode produk.'**
  String get storeProductCodeHint;

  /// No description provided for @storeProductCodeLocked.
  ///
  /// In id, this message translates to:
  /// **'Kode tidak bisa diubah setelah produk dibuat.'**
  String get storeProductCodeLocked;

  /// No description provided for @storeProductCodeDuplicate.
  ///
  /// In id, this message translates to:
  /// **'Kode produk ini sudah dipakai produk lain.'**
  String get storeProductCodeDuplicate;

  /// No description provided for @storeProductName.
  ///
  /// In id, this message translates to:
  /// **'Nama Produk'**
  String get storeProductName;

  /// No description provided for @storeProductPrice.
  ///
  /// In id, this message translates to:
  /// **'Harga (Rp)'**
  String get storeProductPrice;

  /// No description provided for @storeProductDiscount.
  ///
  /// In id, this message translates to:
  /// **'Diskon Bawaan (opsional)'**
  String get storeProductDiscount;

  /// No description provided for @storeSaveProduct.
  ///
  /// In id, this message translates to:
  /// **'Simpan Produk'**
  String get storeSaveProduct;

  /// No description provided for @storeProductSaved.
  ///
  /// In id, this message translates to:
  /// **'Produk tersimpan: {name}'**
  String storeProductSaved(String name);

  /// No description provided for @storeProductAdded.
  ///
  /// In id, this message translates to:
  /// **'Ditambahkan: {name}'**
  String storeProductAdded(String name);

  /// No description provided for @storeClearKeypad.
  ///
  /// In id, this message translates to:
  /// **'Bersih'**
  String get storeClearKeypad;

  /// No description provided for @storeProductFormError.
  ///
  /// In id, this message translates to:
  /// **'Periksa lagi: kode, nama, dan harga (di atas 0) wajib diisi.'**
  String get storeProductFormError;

  /// No description provided for @storeProductCategory.
  ///
  /// In id, this message translates to:
  /// **'Kategori (opsional)'**
  String get storeProductCategory;

  /// No description provided for @storeShiftTitle.
  ///
  /// In id, this message translates to:
  /// **'Shift Kasir'**
  String get storeShiftTitle;

  /// No description provided for @storeShiftNotOpen.
  ///
  /// In id, this message translates to:
  /// **'Shift Belum Dibuka'**
  String get storeShiftNotOpen;

  /// No description provided for @storeShiftOpenHint.
  ///
  /// In id, this message translates to:
  /// **'Buka shift dulu untuk menyusun pesanan dan menerima pembayaran rupiah di Mode Toko.'**
  String get storeShiftOpenHint;

  /// No description provided for @storeShiftOpen.
  ///
  /// In id, this message translates to:
  /// **'Buka Shift'**
  String get storeShiftOpen;

  /// No description provided for @storeShiftClose.
  ///
  /// In id, this message translates to:
  /// **'Tutup Shift'**
  String get storeShiftClose;

  /// No description provided for @storeShiftOpenedAt.
  ///
  /// In id, this message translates to:
  /// **'Dibuka {time}'**
  String storeShiftOpenedAt(String time);

  /// No description provided for @storeShiftStillOpen.
  ///
  /// In id, this message translates to:
  /// **'Masih Berjalan'**
  String get storeShiftStillOpen;

  /// No description provided for @storeCloseShiftBlocked.
  ///
  /// In id, this message translates to:
  /// **'Tidak bisa menutup shift: masih ada penerbitan poin yang sedang berjalan. Selesaikan dulu penerbitan poinnya.'**
  String get storeCloseShiftBlocked;

  /// No description provided for @storeCloseShiftConfirmTitle.
  ///
  /// In id, this message translates to:
  /// **'Tutup Shift Ini?'**
  String get storeCloseShiftConfirmTitle;

  /// No description provided for @storeCloseShiftConfirmBody.
  ///
  /// In id, this message translates to:
  /// **'Sesudah ditutup, penjualan berikutnya masuk ke shift baru.'**
  String get storeCloseShiftConfirmBody;

  /// No description provided for @storeCloseShiftHeldTitle.
  ///
  /// In id, this message translates to:
  /// **'Masih Ada Pesanan Ditahan'**
  String get storeCloseShiftHeldTitle;

  /// No description provided for @storeCloseShiftHeldBody.
  ///
  /// In id, this message translates to:
  /// **'Ada {count} pesanan ditahan (total {total}) yang belum dibayar. Pesanan ditahan tetap tersimpan dan bisa dilanjutkan pada shift berikutnya.'**
  String storeCloseShiftHeldBody(int count, String total);

  /// No description provided for @storeCloseShiftHeldConfirm.
  ///
  /// In id, this message translates to:
  /// **'Tetap Tutup Shift'**
  String get storeCloseShiftHeldConfirm;

  /// No description provided for @storeBack.
  ///
  /// In id, this message translates to:
  /// **'Kembali'**
  String get storeBack;

  /// No description provided for @storeShiftClosedTitle.
  ///
  /// In id, this message translates to:
  /// **'Shift Ditutup'**
  String get storeShiftClosedTitle;

  /// No description provided for @storeShiftClosedBody.
  ///
  /// In id, this message translates to:
  /// **'Laporan shift ini sudah bisa dilihat, dicetak, atau dibagikan sebagai PDF.'**
  String get storeShiftClosedBody;

  /// No description provided for @storeLater.
  ///
  /// In id, this message translates to:
  /// **'Nanti'**
  String get storeLater;

  /// No description provided for @storeViewReport.
  ///
  /// In id, this message translates to:
  /// **'Lihat Laporan'**
  String get storeViewReport;

  /// No description provided for @storeSalesReport.
  ///
  /// In id, this message translates to:
  /// **'Laporan Penjualan'**
  String get storeSalesReport;

  /// No description provided for @storeReportsTitle.
  ///
  /// In id, this message translates to:
  /// **'Daftar Laporan'**
  String get storeReportsTitle;

  /// No description provided for @storeExportPdf.
  ///
  /// In id, this message translates to:
  /// **'Ekspor PDF'**
  String get storeExportPdf;

  /// No description provided for @storeReportPaymentsTitle.
  ///
  /// In id, this message translates to:
  /// **'Laporan Pembayaran'**
  String get storeReportPaymentsTitle;

  /// No description provided for @storeReportPaymentsSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Penerimaan per tanggal, dirinci per shift.'**
  String get storeReportPaymentsSubtitle;

  /// No description provided for @storePaymentReportBreakdown.
  ///
  /// In id, this message translates to:
  /// **'Rincian per Shift'**
  String get storePaymentReportBreakdown;

  /// No description provided for @storeReportPointsUsed.
  ///
  /// In id, this message translates to:
  /// **'Poin terpakai: {points} poin (−{amount})'**
  String storeReportPointsUsed(int points, String amount);

  /// No description provided for @storePaymentReportInvoices.
  ///
  /// In id, this message translates to:
  /// **'{count} nota'**
  String storePaymentReportInvoices(int count);

  /// No description provided for @storePaymentReportTotalLine.
  ///
  /// In id, this message translates to:
  /// **'Total {count} nota • Rp{amount}'**
  String storePaymentReportTotalLine(int count, String amount);

  /// No description provided for @storeReportProductSalesTitle.
  ///
  /// In id, this message translates to:
  /// **'Laporan Penjualan Produk'**
  String get storeReportProductSalesTitle;

  /// No description provided for @storeReportProductSalesSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Semua penjualan per produk pada periode terpilih.'**
  String get storeReportProductSalesSubtitle;

  /// No description provided for @storeProductSalesGross.
  ///
  /// In id, this message translates to:
  /// **'Bruto'**
  String get storeProductSalesGross;

  /// No description provided for @storeReportBestsellersTitle.
  ///
  /// In id, this message translates to:
  /// **'Produk Terlaris'**
  String get storeReportBestsellersTitle;

  /// No description provided for @storeReportBestsellersSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Urutan produk dari yang paling banyak terjual.'**
  String get storeReportBestsellersSubtitle;

  /// No description provided for @storeBestsellersEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada penjualan pada periode ini.'**
  String get storeBestsellersEmpty;

  /// No description provided for @storePeriod7Days.
  ///
  /// In id, this message translates to:
  /// **'7 Hari Terakhir'**
  String get storePeriod7Days;

  /// No description provided for @storePeriod30Days.
  ///
  /// In id, this message translates to:
  /// **'30 Hari Terakhir'**
  String get storePeriod30Days;

  /// No description provided for @storePeriodAll.
  ///
  /// In id, this message translates to:
  /// **'Semua'**
  String get storePeriodAll;

  /// No description provided for @storePeriodCustom.
  ///
  /// In id, this message translates to:
  /// **'Pilih Tanggal'**
  String get storePeriodCustom;

  /// No description provided for @storeBestsellersSoldQty.
  ///
  /// In id, this message translates to:
  /// **'Terjual {qty}'**
  String storeBestsellersSoldQty(int qty);

  /// No description provided for @storeBestsellersTotalLine.
  ///
  /// In id, this message translates to:
  /// **'Total terjual {qty} • Rp{amount}'**
  String storeBestsellersTotalLine(int qty, String amount);

  /// No description provided for @storeSalesHistory.
  ///
  /// In id, this message translates to:
  /// **'Riwayat Penjualan'**
  String get storeSalesHistory;

  /// No description provided for @storeSalesHistoryEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada penjualan yang tercatat.'**
  String get storeSalesHistoryEmpty;

  /// No description provided for @storeSaleDetailTitle.
  ///
  /// In id, this message translates to:
  /// **'Detail Penjualan'**
  String get storeSaleDetailTitle;

  /// No description provided for @storeSalePaymentLabel.
  ///
  /// In id, this message translates to:
  /// **'Pembayaran'**
  String get storeSalePaymentLabel;

  /// No description provided for @storeSaleReceiptUnavailable.
  ///
  /// In id, this message translates to:
  /// **'Struk tidak tersedia untuk record ini.'**
  String get storeSaleReceiptUnavailable;

  /// No description provided for @storeReprintReceipt.
  ///
  /// In id, this message translates to:
  /// **'Cetak Ulang'**
  String get storeReprintReceipt;

  /// No description provided for @storePreviewShareReceipt.
  ///
  /// In id, this message translates to:
  /// **'Pratinjau & Bagikan'**
  String get storePreviewShareReceipt;

  /// No description provided for @storeOperatorLoginTitle.
  ///
  /// In id, this message translates to:
  /// **'Login Operator'**
  String get storeOperatorLoginTitle;

  /// No description provided for @storeOperatorSetupTitle.
  ///
  /// In id, this message translates to:
  /// **'Buat Akun Owner'**
  String get storeOperatorSetupTitle;

  /// No description provided for @storeOperatorSetupBody.
  ///
  /// In id, this message translates to:
  /// **'Mode Toko sekarang memakai login operator. Buat akun owner pertama: akun ini mengelola operator lain dan menyetujui aksi sensitif.'**
  String get storeOperatorSetupBody;

  /// No description provided for @storeOperatorNameLabel.
  ///
  /// In id, this message translates to:
  /// **'Nama Operator'**
  String get storeOperatorNameLabel;

  /// No description provided for @storeOperatorPinLabel.
  ///
  /// In id, this message translates to:
  /// **'PIN (6 digit)'**
  String get storeOperatorPinLabel;

  /// No description provided for @storeOperatorPinConfirmLabel.
  ///
  /// In id, this message translates to:
  /// **'Ulangi PIN'**
  String get storeOperatorPinConfirmLabel;

  /// No description provided for @storeOperatorPinMismatch.
  ///
  /// In id, this message translates to:
  /// **'PIN tidak sama.'**
  String get storeOperatorPinMismatch;

  /// No description provided for @storeOperatorPinInvalid.
  ///
  /// In id, this message translates to:
  /// **'PIN harus 6 digit angka.'**
  String get storeOperatorPinInvalid;

  /// No description provided for @storeOperatorNameRequired.
  ///
  /// In id, this message translates to:
  /// **'Nama operator wajib diisi.'**
  String get storeOperatorNameRequired;

  /// No description provided for @storeOperatorLoginButton.
  ///
  /// In id, this message translates to:
  /// **'Masuk'**
  String get storeOperatorLoginButton;

  /// No description provided for @storeOperatorWrongPin.
  ///
  /// In id, this message translates to:
  /// **'PIN salah.'**
  String get storeOperatorWrongPin;

  /// No description provided for @storeOperatorSwitch.
  ///
  /// In id, this message translates to:
  /// **'Ganti Operator'**
  String get storeOperatorSwitch;

  /// No description provided for @storeOperatorRoleOwner.
  ///
  /// In id, this message translates to:
  /// **'Owner'**
  String get storeOperatorRoleOwner;

  /// No description provided for @storeOperatorRoleCashier.
  ///
  /// In id, this message translates to:
  /// **'Kasir'**
  String get storeOperatorRoleCashier;

  /// No description provided for @storeAdminPinTitle.
  ///
  /// In id, this message translates to:
  /// **'PIN Admin'**
  String get storeAdminPinTitle;

  /// No description provided for @storeAdminPinBody.
  ///
  /// In id, this message translates to:
  /// **'Aksi ini butuh persetujuan owner. Minta owner memasukkan PIN-nya.'**
  String get storeAdminPinBody;

  /// No description provided for @storeAdminApproved.
  ///
  /// In id, this message translates to:
  /// **'Persetujuan admin diterima.'**
  String get storeAdminApproved;

  /// No description provided for @storeVoidSaleButton.
  ///
  /// In id, this message translates to:
  /// **'VOID Penjualan'**
  String get storeVoidSaleButton;

  /// No description provided for @storeVoidSaleTitle.
  ///
  /// In id, this message translates to:
  /// **'VOID Penjualan Lunas?'**
  String get storeVoidSaleTitle;

  /// No description provided for @storeVoidSaleBody.
  ///
  /// In id, this message translates to:
  /// **'Penjualan ditandai VOID: hilang dari total laporan dan jurnal poin dibalikkan. Record asal tetap tersimpan bertanda VOID. Tindakan ini tidak bisa dibatalkan.'**
  String get storeVoidSaleBody;

  /// No description provided for @storeVoidReasonLabel.
  ///
  /// In id, this message translates to:
  /// **'Alasan VOID (wajib)'**
  String get storeVoidReasonLabel;

  /// No description provided for @storeVoidDone.
  ///
  /// In id, this message translates to:
  /// **'Penjualan ditandai VOID.'**
  String get storeVoidDone;

  /// No description provided for @storeOperatorsTitle.
  ///
  /// In id, this message translates to:
  /// **'Kelola Operator'**
  String get storeOperatorsTitle;

  /// No description provided for @storeOperatorLastOwner.
  ///
  /// In id, this message translates to:
  /// **'Tidak bisa menonaktifkan owner aktif terakhir.'**
  String get storeOperatorLastOwner;

  /// No description provided for @storeOperatorAdd.
  ///
  /// In id, this message translates to:
  /// **'Tambah Operator'**
  String get storeOperatorAdd;

  /// No description provided for @storeOperatorRoleLabel.
  ///
  /// In id, this message translates to:
  /// **'Peran'**
  String get storeOperatorRoleLabel;

  /// No description provided for @storeOperatorDeactivate.
  ///
  /// In id, this message translates to:
  /// **'Nonaktifkan'**
  String get storeOperatorDeactivate;

  /// No description provided for @storeOperatorActivate.
  ///
  /// In id, this message translates to:
  /// **'Aktifkan'**
  String get storeOperatorActivate;

  /// No description provided for @storeOperatorResetPin.
  ///
  /// In id, this message translates to:
  /// **'Ganti PIN'**
  String get storeOperatorResetPin;

  /// No description provided for @storeOperatorInactiveBadge.
  ///
  /// In id, this message translates to:
  /// **'Nonaktif'**
  String get storeOperatorInactiveBadge;

  /// No description provided for @storeAuditTitle.
  ///
  /// In id, this message translates to:
  /// **'Log Aktivitas'**
  String get storeAuditTitle;

  /// No description provided for @storeAuditEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada aktivitas tercatat.'**
  String get storeAuditEmpty;

  /// No description provided for @storeSettingsAdminSection.
  ///
  /// In id, this message translates to:
  /// **'Operator & Keamanan'**
  String get storeSettingsAdminSection;

  /// No description provided for @storeSettingsDiscountThresholdLabel.
  ///
  /// In id, this message translates to:
  /// **'Ambang diskon kasir (%)'**
  String get storeSettingsDiscountThresholdLabel;

  /// No description provided for @storeSettingsDiscountThresholdHint.
  ///
  /// In id, this message translates to:
  /// **'Diskon manual di atas ambang ini wajib disetujui PIN admin.'**
  String get storeSettingsDiscountThresholdHint;

  /// No description provided for @storeCustomerTitle.
  ///
  /// In id, this message translates to:
  /// **'Pelanggan'**
  String get storeCustomerTitle;

  /// No description provided for @storeCustomerChoose.
  ///
  /// In id, this message translates to:
  /// **'Pilih Pelanggan'**
  String get storeCustomerChoose;

  /// No description provided for @storeCustomerAdd.
  ///
  /// In id, this message translates to:
  /// **'Tambah Pelanggan'**
  String get storeCustomerAdd;

  /// No description provided for @storeCustomerNameLabel.
  ///
  /// In id, this message translates to:
  /// **'Nama Pelanggan (opsional)'**
  String get storeCustomerNameLabel;

  /// No description provided for @storeCustomerOfferLabel.
  ///
  /// In id, this message translates to:
  /// **'Kode Bayar Statis (Bolt12)'**
  String get storeCustomerOfferLabel;

  /// No description provided for @storeCustomerScan.
  ///
  /// In id, this message translates to:
  /// **'Pindai'**
  String get storeCustomerScan;

  /// No description provided for @storeCustomerInvalidOffer.
  ///
  /// In id, this message translates to:
  /// **'Kode bayar tidak sah — harus offer Bolt12 (lno1…).'**
  String get storeCustomerInvalidOffer;

  /// No description provided for @storeCustomerEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada pelanggan tersimpan.'**
  String get storeCustomerEmpty;

  /// No description provided for @storeCustomerEdit.
  ///
  /// In id, this message translates to:
  /// **'Ubah'**
  String get storeCustomerEdit;

  /// No description provided for @storeCustomerDelete.
  ///
  /// In id, this message translates to:
  /// **'Hapus'**
  String get storeCustomerDelete;

  /// No description provided for @storeCustomerManage.
  ///
  /// In id, this message translates to:
  /// **'Kelola Pelanggan'**
  String get storeCustomerManage;

  /// No description provided for @storeAuditLogin.
  ///
  /// In id, this message translates to:
  /// **'Login'**
  String get storeAuditLogin;

  /// No description provided for @storeAuditLogout.
  ///
  /// In id, this message translates to:
  /// **'Keluar'**
  String get storeAuditLogout;

  /// No description provided for @storeAuditOperatorCreated.
  ///
  /// In id, this message translates to:
  /// **'Operator dibuat'**
  String get storeAuditOperatorCreated;

  /// No description provided for @storeAuditOperatorUpdated.
  ///
  /// In id, this message translates to:
  /// **'Operator diubah'**
  String get storeAuditOperatorUpdated;

  /// No description provided for @storeAuditPinChanged.
  ///
  /// In id, this message translates to:
  /// **'PIN diganti'**
  String get storeAuditPinChanged;

  /// No description provided for @storeAuditShiftOpen.
  ///
  /// In id, this message translates to:
  /// **'Buka shift'**
  String get storeAuditShiftOpen;

  /// No description provided for @storeAuditShiftClose.
  ///
  /// In id, this message translates to:
  /// **'Tutup shift'**
  String get storeAuditShiftClose;

  /// No description provided for @storeAuditAdminOverride.
  ///
  /// In id, this message translates to:
  /// **'Override admin'**
  String get storeAuditAdminOverride;

  /// No description provided for @storeAuditSaleVoid.
  ///
  /// In id, this message translates to:
  /// **'VOID penjualan'**
  String get storeAuditSaleVoid;

  /// No description provided for @storeReportCurrentShift.
  ///
  /// In id, this message translates to:
  /// **'Shift Berjalan'**
  String get storeReportCurrentShift;

  /// No description provided for @storeReportByDate.
  ///
  /// In id, this message translates to:
  /// **'Per Tanggal'**
  String get storeReportByDate;

  /// No description provided for @storeReportPastShifts.
  ///
  /// In id, this message translates to:
  /// **'Shift Lampau'**
  String get storeReportPastShifts;

  /// No description provided for @storeReportPrint.
  ///
  /// In id, this message translates to:
  /// **'Cetak Laporan'**
  String get storeReportPrint;

  /// No description provided for @storeReportSharePdf.
  ///
  /// In id, this message translates to:
  /// **'Bagikan PDF'**
  String get storeReportSharePdf;

  /// No description provided for @storeReportEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada penjualan tercatat pada periode ini.'**
  String get storeReportEmpty;

  /// No description provided for @storeReportSummaryTitle.
  ///
  /// In id, this message translates to:
  /// **'LAPORAN SHIFT'**
  String get storeReportSummaryTitle;

  /// No description provided for @storeReportDetailsTitle.
  ///
  /// In id, this message translates to:
  /// **'RINCIAN PENJUALAN'**
  String get storeReportDetailsTitle;

  /// No description provided for @storeReportItemQty.
  ///
  /// In id, this message translates to:
  /// **'Qty Item'**
  String get storeReportItemQty;

  /// No description provided for @storeReportTotalOrder.
  ///
  /// In id, this message translates to:
  /// **'Total ORDER'**
  String get storeReportTotalOrder;

  /// No description provided for @storeReportTotalOrderInfo.
  ///
  /// In id, this message translates to:
  /// **'Info Total ORDER'**
  String get storeReportTotalOrderInfo;

  /// No description provided for @storeReportInvoices.
  ///
  /// In id, this message translates to:
  /// **'#Transaksi'**
  String get storeReportInvoices;

  /// No description provided for @storeReportInvUnit.
  ///
  /// In id, this message translates to:
  /// **'trx'**
  String get storeReportInvUnit;

  /// No description provided for @storeReportVoidInfo.
  ///
  /// In id, this message translates to:
  /// **'Info VOID'**
  String get storeReportVoidInfo;

  /// No description provided for @storeReportVoidItemQty.
  ///
  /// In id, this message translates to:
  /// **'Qty Item VOID'**
  String get storeReportVoidItemQty;

  /// No description provided for @storeReportVoidSubTotal.
  ///
  /// In id, this message translates to:
  /// **'Sub Total VOID'**
  String get storeReportVoidSubTotal;

  /// No description provided for @storeReportVoidDiscount.
  ///
  /// In id, this message translates to:
  /// **'Diskon VOID'**
  String get storeReportVoidDiscount;

  /// No description provided for @storeReportVoidTotalOrder.
  ///
  /// In id, this message translates to:
  /// **'Total ORDER VOID'**
  String get storeReportVoidTotalOrder;

  /// No description provided for @storeReportOther.
  ///
  /// In id, this message translates to:
  /// **'LAINNYA'**
  String get storeReportOther;

  /// No description provided for @storeReportQty.
  ///
  /// In id, this message translates to:
  /// **'Qty'**
  String get storeReportQty;

  /// No description provided for @storeReportMenus.
  ///
  /// In id, this message translates to:
  /// **'{count} menu(s)'**
  String storeReportMenus(int count);

  /// No description provided for @storeReportGeneratedOn.
  ///
  /// In id, this message translates to:
  /// **'Laporan dibuat'**
  String get storeReportGeneratedOn;

  /// No description provided for @storeReportShiftsNote.
  ///
  /// In id, this message translates to:
  /// **'Meliputi {count} shift'**
  String storeReportShiftsNote(int count);

  /// No description provided for @storeCatalogManagerTitle.
  ///
  /// In id, this message translates to:
  /// **'Kelola Katalog'**
  String get storeCatalogManagerTitle;

  /// No description provided for @storeAddProduct.
  ///
  /// In id, this message translates to:
  /// **'Tambah Produk'**
  String get storeAddProduct;

  /// No description provided for @storeEditProduct.
  ///
  /// In id, this message translates to:
  /// **'Ubah Produk'**
  String get storeEditProduct;

  /// No description provided for @storeNoDiscount.
  ///
  /// In id, this message translates to:
  /// **'Tanpa Diskon'**
  String get storeNoDiscount;

  /// No description provided for @storeCheckout.
  ///
  /// In id, this message translates to:
  /// **'Selesai'**
  String get storeCheckout;

  /// No description provided for @storePayTitle.
  ///
  /// In id, this message translates to:
  /// **'Penyelesaian Pembayaran'**
  String get storePayTitle;

  /// No description provided for @storePayTotalLabel.
  ///
  /// In id, this message translates to:
  /// **'Total Belanja'**
  String get storePayTotalLabel;

  /// No description provided for @storeCash.
  ///
  /// In id, this message translates to:
  /// **'Tunai'**
  String get storeCash;

  /// No description provided for @storeQris.
  ///
  /// In id, this message translates to:
  /// **'QRIS'**
  String get storeQris;

  /// No description provided for @storeQrisNote.
  ///
  /// In id, this message translates to:
  /// **'Pelanggan membayar lewat QRIS seperti biasa di toko ini. Aplikasi hanya mencatat metode pembayarannya — tekan tombol di bawah sesudah pembayaran QRIS diterima.'**
  String get storeQrisNote;

  /// No description provided for @storeCashReceived.
  ///
  /// In id, this message translates to:
  /// **'Uang Diterima'**
  String get storeCashReceived;

  /// No description provided for @storeCashExact.
  ///
  /// In id, this message translates to:
  /// **'Uang Pas'**
  String get storeCashExact;

  /// No description provided for @storeChange.
  ///
  /// In id, this message translates to:
  /// **'Kembalian'**
  String get storeChange;

  /// No description provided for @storeCashShort.
  ///
  /// In id, this message translates to:
  /// **'Kurang Rp{amount}'**
  String storeCashShort(String amount);

  /// No description provided for @storeSettle.
  ///
  /// In id, this message translates to:
  /// **'Lunas — Selesaikan'**
  String get storeSettle;

  /// No description provided for @storeSettleQris.
  ///
  /// In id, this message translates to:
  /// **'QRIS Diterima — Selesaikan'**
  String get storeSettleQris;

  /// No description provided for @storeSettlePromo.
  ///
  /// In id, this message translates to:
  /// **'Selesaikan Tanpa Pembayaran'**
  String get storeSettlePromo;

  /// No description provided for @storePromoNote.
  ///
  /// In id, this message translates to:
  /// **'Total belanja Rp0 (promosi) — tidak ada pembayaran yang diterima; penjualan tetap dicatat.'**
  String get storePromoNote;

  /// No description provided for @storeCancelOrder.
  ///
  /// In id, this message translates to:
  /// **'Batalkan Pesanan'**
  String get storeCancelOrder;

  /// No description provided for @storeVoidConfirmTitle.
  ///
  /// In id, this message translates to:
  /// **'Batalkan Pesanan Ini?'**
  String get storeVoidConfirmTitle;

  /// No description provided for @storeVoidConfirmBody.
  ///
  /// In id, this message translates to:
  /// **'Pesanan dibatalkan dan dicatat sebagai VOID di laporan. Tindakan ini tidak bisa dibatalkan.'**
  String get storeVoidConfirmBody;

  /// No description provided for @storeVoidRecorded.
  ///
  /// In id, this message translates to:
  /// **'Pesanan dibatalkan — tercatat sebagai VOID.'**
  String get storeVoidRecorded;

  /// No description provided for @storeRedeemTitle.
  ///
  /// In id, this message translates to:
  /// **'Tukar Poin Nusan'**
  String get storeRedeemTitle;

  /// No description provided for @storeRedeemHint.
  ///
  /// In id, this message translates to:
  /// **'Penukaran dibaca dari catatan penerbitan poin toko ini — pelanggan tidak membayar apa pun. Minta pelanggan menunjukkan offer Bolt12 dari aplikasi ELNUX miliknya, pindai, lalu terapkan potongan sampai sebesar poin yang tercatat untuknya.'**
  String get storeRedeemHint;

  /// No description provided for @storeRedeemScanOffer.
  ///
  /// In id, this message translates to:
  /// **'Pindai Offer Pelanggan'**
  String get storeRedeemScanOffer;

  /// No description provided for @storeRedeemBalance.
  ///
  /// In id, this message translates to:
  /// **'Poin tercatat untuk pelanggan ini: {balance} poin.'**
  String storeRedeemBalance(int balance);

  /// No description provided for @storeRedeemNoBalance.
  ///
  /// In id, this message translates to:
  /// **'Belum ada poin tercatat untuk offer ini di toko ini — penukaran belum bisa dilakukan.'**
  String get storeRedeemNoBalance;

  /// No description provided for @storeRedeemNeedOffer.
  ///
  /// In id, this message translates to:
  /// **'Penukaran memakai offer Bolt12 pelanggan. Kode ini bukan offer — minta pelanggan membuka offer-nya di ELNUX lalu pindai ulang.'**
  String get storeRedeemNeedOffer;

  /// No description provided for @storeRedeemPointsLabel.
  ///
  /// In id, this message translates to:
  /// **'Jumlah Poin'**
  String get storeRedeemPointsLabel;

  /// No description provided for @storeRedeemApply.
  ///
  /// In id, this message translates to:
  /// **'Terapkan Potongan'**
  String get storeRedeemApply;

  /// No description provided for @storeRedeemApplied.
  ///
  /// In id, this message translates to:
  /// **'Penukaran tercatat: {points} poin = potongan Rp{amount}.'**
  String storeRedeemApplied(int points, String amount);

  /// No description provided for @storeRedeemUndo.
  ///
  /// In id, this message translates to:
  /// **'Urungkan Penukaran'**
  String get storeRedeemUndo;

  /// No description provided for @storeRedeemScanAgain.
  ///
  /// In id, this message translates to:
  /// **'Pindai Ulang'**
  String get storeRedeemScanAgain;

  /// No description provided for @storeRedeemMaxNote.
  ///
  /// In id, this message translates to:
  /// **'Maksimal {max} poin untuk belanja ini.'**
  String storeRedeemMaxNote(int max);

  /// No description provided for @storeRedeemClamped.
  ///
  /// In id, this message translates to:
  /// **'Jumlah poin melebihi batas — dipakai {max} poin.'**
  String storeRedeemClamped(int max);

  /// No description provided for @storeRedeemInvalidPoints.
  ///
  /// In id, this message translates to:
  /// **'Jumlah poin tidak sah atau melebihi potongan yang mungkin untuk belanja ini.'**
  String get storeRedeemInvalidPoints;

  /// No description provided for @storeSaleCompleted.
  ///
  /// In id, this message translates to:
  /// **'Penjualan Selesai'**
  String get storeSaleCompleted;

  /// No description provided for @storePointsEarnedLine.
  ///
  /// In id, this message translates to:
  /// **'Poin nusan diperoleh: {points} poin'**
  String storePointsEarnedLine(int points);

  /// No description provided for @storePointsIssueButton.
  ///
  /// In id, this message translates to:
  /// **'Pindai & Terbitkan'**
  String get storePointsIssueButton;

  /// No description provided for @storePointsSkip.
  ///
  /// In id, this message translates to:
  /// **'Lewati'**
  String get storePointsSkip;

  /// No description provided for @storePointsIssuedOk.
  ///
  /// In id, this message translates to:
  /// **'Poin nusan sudah diterbitkan ke pelanggan.'**
  String get storePointsIssuedOk;

  /// No description provided for @storeIssueInvalidCode.
  ///
  /// In id, this message translates to:
  /// **'Kode tidak terbaca sebagai invoice atau kode bayar ELNUX — pindai ulang kode pelanggan.'**
  String get storeIssueInvalidCode;

  /// No description provided for @storeIssueAmountMismatch.
  ///
  /// In id, this message translates to:
  /// **'Nominal kode tidak sama dengan poin yang harus diterbitkan — minta pelanggan membuat kode sejumlah poin yang diperoleh.'**
  String get storeIssueAmountMismatch;

  /// No description provided for @storeIssueFailed.
  ///
  /// In id, this message translates to:
  /// **'Penerbitan poin gagal — poin tetap tertunda dan bisa diterbitkan dari daftar Poin Tertunda.'**
  String get storeIssueFailed;

  /// No description provided for @storeIssueStillPending.
  ///
  /// In id, this message translates to:
  /// **'Pembayaran poin masih berjalan — statusnya tetap tertunda; cek lagi dari daftar Poin Tertunda.'**
  String get storeIssueStillPending;

  /// No description provided for @storeIssueInvoiceNote.
  ///
  /// In id, this message translates to:
  /// **'Poin terbit ke invoice sekali pakai — poin seperti ini tidak tercatat di jurnal toko. Agar bisa ditukar pada kunjungan berikutnya, terbitkan ke offer Bolt12 pelanggan.'**
  String get storeIssueInvoiceNote;

  /// No description provided for @storeDoneButton.
  ///
  /// In id, this message translates to:
  /// **'Selesai'**
  String get storeDoneButton;

  /// No description provided for @storePendingBadge.
  ///
  /// In id, this message translates to:
  /// **'Poin Tertunda ({count})'**
  String storePendingBadge(int count);

  /// No description provided for @storePendingTitle.
  ///
  /// In id, this message translates to:
  /// **'Poin Tertunda'**
  String get storePendingTitle;

  /// No description provided for @storePendingEmpty.
  ///
  /// In id, this message translates to:
  /// **'Tidak ada poin yang tertunda.'**
  String get storePendingEmpty;

  /// No description provided for @storePendingEntryMeta.
  ///
  /// In id, this message translates to:
  /// **'{time} • {total}'**
  String storePendingEntryMeta(String time, String total);

  /// No description provided for @storePendingIssue.
  ///
  /// In id, this message translates to:
  /// **'Terbitkan'**
  String get storePendingIssue;

  /// No description provided for @storePendingWaive.
  ///
  /// In id, this message translates to:
  /// **'Batal Terbit'**
  String get storePendingWaive;

  /// No description provided for @storePendingWaiveTitle.
  ///
  /// In id, this message translates to:
  /// **'Batalkan Penerbitan Poin?'**
  String get storePendingWaiveTitle;

  /// No description provided for @storePendingWaiveBody.
  ///
  /// In id, this message translates to:
  /// **'Poin dari penjualan {time} (total {total}) TIDAK jadi diterbitkan ke pelanggan. Catatan penjualannya tetap tersimpan.'**
  String storePendingWaiveBody(String total, String time);

  /// No description provided for @storePendingWaived.
  ///
  /// In id, this message translates to:
  /// **'Penerbitan poin dibatalkan.'**
  String get storePendingWaived;

  /// No description provided for @storeReceiptTotalPay.
  ///
  /// In id, this message translates to:
  /// **'TOTAL BAYAR'**
  String get storeReceiptTotalPay;

  /// No description provided for @storeReceiptPointsDiscount.
  ///
  /// In id, this message translates to:
  /// **'Penukaran poin ({points} poin) -Rp{amount}'**
  String storeReceiptPointsDiscount(int points, String amount);

  /// No description provided for @storeReceiptPointsEarned.
  ///
  /// In id, this message translates to:
  /// **'Poin nusan diperoleh: +{points} poin'**
  String storeReceiptPointsEarned(int points);

  /// No description provided for @storeReceiptPointsPending.
  ///
  /// In id, this message translates to:
  /// **'Poin nusan diperoleh: +{points} poin (belum diterbitkan)'**
  String storeReceiptPointsPending(int points);

  /// No description provided for @storeReceiptPointsRule.
  ///
  /// In id, this message translates to:
  /// **'1 nusan = pot. Rp{rate}'**
  String storeReceiptPointsRule(String rate);

  /// No description provided for @storeReceiptPromo.
  ///
  /// In id, this message translates to:
  /// **'Tanpa pembayaran (promosi)'**
  String get storeReceiptPromo;

  /// No description provided for @storeReceiptCustomer.
  ///
  /// In id, this message translates to:
  /// **'Pelanggan'**
  String get storeReceiptCustomer;

  /// No description provided for @storeReceiptDate.
  ///
  /// In id, this message translates to:
  /// **'Tanggal'**
  String get storeReceiptDate;

  /// No description provided for @storeReceiptBillNo.
  ///
  /// In id, this message translates to:
  /// **'No. Bill'**
  String get storeReceiptBillNo;

  /// No description provided for @storeReceiptTokenNo.
  ///
  /// In id, this message translates to:
  /// **'Order/Outlet'**
  String get storeReceiptTokenNo;

  /// No description provided for @storeReceiptItemHeader.
  ///
  /// In id, this message translates to:
  /// **'Item'**
  String get storeReceiptItemHeader;

  /// No description provided for @storeReceiptAmountHeader.
  ///
  /// In id, this message translates to:
  /// **'Jumlah'**
  String get storeReceiptAmountHeader;

  /// No description provided for @storeReceiptOrderDiscount.
  ///
  /// In id, this message translates to:
  /// **'Diskon Order'**
  String get storeReceiptOrderDiscount;

  /// No description provided for @storeReceiptLineDiscount.
  ///
  /// In id, this message translates to:
  /// **'Diskon Item'**
  String get storeReceiptLineDiscount;

  /// No description provided for @storeReceiptGrandTotal.
  ///
  /// In id, this message translates to:
  /// **'Bayar'**
  String get storeReceiptGrandTotal;

  /// No description provided for @storeReceiptReprintBanner.
  ///
  /// In id, this message translates to:
  /// **'*** REPRINT ***'**
  String get storeReceiptReprintBanner;

  /// No description provided for @storeReceiptReprintLabel.
  ///
  /// In id, this message translates to:
  /// **'Reprint'**
  String get storeReceiptReprintLabel;

  /// No description provided for @storeReceiptCashier.
  ///
  /// In id, this message translates to:
  /// **'Kasir'**
  String get storeReceiptCashier;

  /// No description provided for @storePayAmountLabel.
  ///
  /// In id, this message translates to:
  /// **'Jumlah'**
  String get storePayAmountLabel;

  /// No description provided for @storeAddPayMethod.
  ///
  /// In id, this message translates to:
  /// **'Tambah Metode Bayar'**
  String get storeAddPayMethod;

  /// No description provided for @storeNonCashOverNote.
  ///
  /// In id, this message translates to:
  /// **'Metode non-tunai tidak boleh melebihi sisa tagihan.'**
  String get storeNonCashOverNote;

  /// No description provided for @storeMethodSplit.
  ///
  /// In id, this message translates to:
  /// **'Gabungan'**
  String get storeMethodSplit;

  /// No description provided for @storeFilterToday.
  ///
  /// In id, this message translates to:
  /// **'Hari Ini'**
  String get storeFilterToday;

  /// No description provided for @storeFilterYesterday.
  ///
  /// In id, this message translates to:
  /// **'Kemarin'**
  String get storeFilterYesterday;

  /// No description provided for @storeReportIncome.
  ///
  /// In id, this message translates to:
  /// **'Income'**
  String get storeReportIncome;

  /// No description provided for @storeReportOpeningFloat.
  ///
  /// In id, this message translates to:
  /// **'Modal'**
  String get storeReportOpeningFloat;

  /// No description provided for @storeReportCashPosition.
  ///
  /// In id, this message translates to:
  /// **'Posisi Tunai'**
  String get storeReportCashPosition;

  /// No description provided for @storeReportHeldInfo.
  ///
  /// In id, this message translates to:
  /// **'Order Ditahan'**
  String get storeReportHeldInfo;

  /// No description provided for @storeReportHeldTotal.
  ///
  /// In id, this message translates to:
  /// **'Total Order Ditahan'**
  String get storeReportHeldTotal;

  /// No description provided for @storeOpeningFloatTitle.
  ///
  /// In id, this message translates to:
  /// **'Modal Awal Shift'**
  String get storeOpeningFloatTitle;

  /// No description provided for @storeOpeningFloatHint.
  ///
  /// In id, this message translates to:
  /// **'Uang tunai di laci saat shift dibuka (untuk kembalian). Boleh Rp0 — hanya pembayaran tunai yang menambah posisi laci; metode non-tunai tidak memengaruhinya.'**
  String get storeOpeningFloatHint;

  /// No description provided for @storeOpeningFloatLabel.
  ///
  /// In id, this message translates to:
  /// **'Modal di Laci'**
  String get storeOpeningFloatLabel;

  /// No description provided for @storePayMethodsTitle.
  ///
  /// In id, this message translates to:
  /// **'Metode Bayar Non-Tunai'**
  String get storePayMethodsTitle;

  /// No description provided for @storePayMethodsHint.
  ///
  /// In id, this message translates to:
  /// **'Metode yang ditawarkan pada dropdown halaman pembayaran (Tunai selalu tersedia). Ketuk × untuk menghapus.'**
  String get storePayMethodsHint;

  /// No description provided for @storePayMethodNameLabel.
  ///
  /// In id, this message translates to:
  /// **'Nama Metode Baru'**
  String get storePayMethodNameLabel;

  /// No description provided for @storePayMethodAdd.
  ///
  /// In id, this message translates to:
  /// **'Tambah'**
  String get storePayMethodAdd;

  /// No description provided for @storeTelegramTitle.
  ///
  /// In id, this message translates to:
  /// **'Kirim Laporan via Telegram'**
  String get storeTelegramTitle;

  /// No description provided for @storeTelegramHint.
  ///
  /// In id, this message translates to:
  /// **'Laporan shift terkirim otomatis ke Telegram saat shift ditutup — langsung dari aplikasi, tanpa server perantara. Buat bot lewat @BotFather, isi token botnya dan ID chat tujuan di bawah.'**
  String get storeTelegramHint;

  /// No description provided for @storeTelegramTokenLabel.
  ///
  /// In id, this message translates to:
  /// **'Token Bot Telegram'**
  String get storeTelegramTokenLabel;

  /// No description provided for @storeTelegramTokenHint.
  ///
  /// In id, this message translates to:
  /// **'Dari BotFather, contoh: 123456789:AA…'**
  String get storeTelegramTokenHint;

  /// No description provided for @storeTelegramChatLabel.
  ///
  /// In id, this message translates to:
  /// **'ID Chat Tujuan'**
  String get storeTelegramChatLabel;

  /// No description provided for @storeTelegramChatHint.
  ///
  /// In id, this message translates to:
  /// **'ID numerik chat atau grup tujuan laporan'**
  String get storeTelegramChatHint;

  /// No description provided for @storeTelegramSent.
  ///
  /// In id, this message translates to:
  /// **'Laporan shift terkirim ke Telegram.'**
  String get storeTelegramSent;

  /// No description provided for @storeTelegramFailed.
  ///
  /// In id, this message translates to:
  /// **'Laporan Telegram gagal terkirim — periksa koneksi & pengaturannya.'**
  String get storeTelegramFailed;

  /// No description provided for @staticCodeLabelTitle.
  ///
  /// In id, this message translates to:
  /// **'Label Kode Bayar'**
  String get staticCodeLabelTitle;

  /// No description provided for @staticCodeLabelEdit.
  ///
  /// In id, this message translates to:
  /// **'Ubah Label'**
  String get staticCodeLabelEdit;

  /// No description provided for @staticCodeLabelHint.
  ///
  /// In id, this message translates to:
  /// **'Label ini tertulis di dalam kode bayar dan dilihat pembayar. Mengganti label membuat kode bayar BARU — bagikan ulang kode yang baru. Kosongkan untuk kembali ke label bawaan.'**
  String get staticCodeLabelHint;

  /// No description provided for @storeReceiptPointsDiscountLabel.
  ///
  /// In id, this message translates to:
  /// **'Pot. ({points} nusan)'**
  String storeReceiptPointsDiscountLabel(String points);

  /// No description provided for @storeReceiptFooterDefault.
  ///
  /// In id, this message translates to:
  /// **'Terima Kasih\nSilakan berkunjung kembali'**
  String get storeReceiptFooterDefault;

  /// No description provided for @storeShareReceipt.
  ///
  /// In id, this message translates to:
  /// **'Bagikan Struk'**
  String get storeShareReceipt;

  /// No description provided for @storeReceiptPreviewTitle.
  ///
  /// In id, this message translates to:
  /// **'Struk'**
  String get storeReceiptPreviewTitle;

  /// No description provided for @storeShareReceiptFailed.
  ///
  /// In id, this message translates to:
  /// **'Tidak dapat membuat gambar struk.'**
  String get storeShareReceiptFailed;

  /// No description provided for @storeSettingsAddress.
  ///
  /// In id, this message translates to:
  /// **'Alamat Toko (baris kop struk)'**
  String get storeSettingsAddress;

  /// No description provided for @storeSettingsCity.
  ///
  /// In id, this message translates to:
  /// **'Kota Toko (baris kop struk)'**
  String get storeSettingsCity;

  /// No description provided for @storeSettingsShowToken.
  ///
  /// In id, this message translates to:
  /// **'Tampilkan Nomor Token di Struk'**
  String get storeSettingsShowToken;

  /// No description provided for @storeSettingsShowTokenHint.
  ///
  /// In id, this message translates to:
  /// **'Nomor antrean harian pada struk; mulai dari 1 setiap hari.'**
  String get storeSettingsShowTokenHint;

  /// No description provided for @storeSettingsFooterText.
  ///
  /// In id, this message translates to:
  /// **'Teks Penutup Struk'**
  String get storeSettingsFooterText;

  /// No description provided for @storeSettingsFooterTextHint.
  ///
  /// In id, this message translates to:
  /// **'Kosongkan untuk teks bawaan bahasa aplikasi.'**
  String get storeSettingsFooterTextHint;

  /// No description provided for @storeSettingsTitle.
  ///
  /// In id, this message translates to:
  /// **'Pengaturan'**
  String get storeSettingsTitle;

  /// No description provided for @storeSettingsStoreName.
  ///
  /// In id, this message translates to:
  /// **'Nama Toko'**
  String get storeSettingsStoreName;

  /// No description provided for @storeSettingsPointsEnabled.
  ///
  /// In id, this message translates to:
  /// **'Program Poin Nusan Aktif'**
  String get storeSettingsPointsEnabled;

  /// No description provided for @storeSettingsPointsHint.
  ///
  /// In id, this message translates to:
  /// **'Poin adalah bonus promosi dari belanja rupiah — bukan alat pembayaran. Poin hanya ditukar sebagai potongan belanja di toko ini.'**
  String get storeSettingsPointsHint;

  /// No description provided for @storeSettingsEarnStep.
  ///
  /// In id, this message translates to:
  /// **'Kelipatan Rupiah Perolehan'**
  String get storeSettingsEarnStep;

  /// No description provided for @storeSettingsEarnPoints.
  ///
  /// In id, this message translates to:
  /// **'Poin per Kelipatan'**
  String get storeSettingsEarnPoints;

  /// No description provided for @storeSettingsRedeemRate.
  ///
  /// In id, this message translates to:
  /// **'Nilai Potongan per Poin (Rp)'**
  String get storeSettingsRedeemRate;

  /// No description provided for @storeSettingsMaxRedeem.
  ///
  /// In id, this message translates to:
  /// **'Batas Maks. Potongan Poin (% dari total)'**
  String get storeSettingsMaxRedeem;

  /// No description provided for @storeSettingsMaxRedeemHint.
  ///
  /// In id, this message translates to:
  /// **'Boleh kosong = tanpa batas selain sisa total belanja.'**
  String get storeSettingsMaxRedeemHint;

  /// No description provided for @storeSettingsEarnPreview.
  ///
  /// In id, this message translates to:
  /// **'Contoh: belanja Rp{step} memperoleh {points} poin.'**
  String storeSettingsEarnPreview(String step, int points);

  /// No description provided for @storeSettingsSave.
  ///
  /// In id, this message translates to:
  /// **'Simpan Pengaturan'**
  String get storeSettingsSave;

  /// No description provided for @storeSettingsSaved.
  ///
  /// In id, this message translates to:
  /// **'Pengaturan toko tersimpan.'**
  String get storeSettingsSaved;

  /// No description provided for @storeSettingsInvalid.
  ///
  /// In id, this message translates to:
  /// **'Periksa lagi: kelipatan dan nilai potongan harus di atas 0; batas maks 1–100 bila diisi.'**
  String get storeSettingsInvalid;

  /// No description provided for @storeRulesTitle.
  ///
  /// In id, this message translates to:
  /// **'Aturan Program Poin'**
  String get storeRulesTitle;

  /// No description provided for @storeRulesButton.
  ///
  /// In id, this message translates to:
  /// **'Aturan Poin'**
  String get storeRulesButton;

  /// No description provided for @storeRulesHeading.
  ///
  /// In id, this message translates to:
  /// **'Poin Nusan — Bonus Promosi Toko'**
  String get storeRulesHeading;

  /// No description provided for @storeRulesP1.
  ///
  /// In id, this message translates to:
  /// **'Poin nusan adalah bonus promosi dari toko, bukan uang dan bukan alat pembayaran. Pembayaran belanja di toko ini selalu dalam rupiah (tunai atau QRIS).'**
  String get storeRulesP1;

  /// No description provided for @storeRulesP2.
  ///
  /// In id, this message translates to:
  /// **'Poin hanya diperoleh dari belanja rupiah yang sudah lunas, sesuai ketentuan perolehan yang berlaku di toko ini.'**
  String get storeRulesP2;

  /// No description provided for @storeRulesP3.
  ///
  /// In id, this message translates to:
  /// **'Poin hanya dapat ditukar sebagai potongan harga belanja di toko ini, sesuai nilai potongan per poin yang ditetapkan toko.'**
  String get storeRulesP3;

  /// No description provided for @storeRulesP4.
  ///
  /// In id, this message translates to:
  /// **'Poin tidak dapat diuangkan, dijual, dibeli, atau ditukar menjadi uang tunai dalam bentuk apa pun.'**
  String get storeRulesP4;

  /// No description provided for @storeRulesP5.
  ///
  /// In id, this message translates to:
  /// **'Nilai potongan per poin dan ketentuan program dapat berubah dengan pemberitahuan sebelumnya di toko ini.'**
  String get storeRulesP5;

  /// No description provided for @storeRulesP6.
  ///
  /// In id, this message translates to:
  /// **'Untuk menerima dan menukar poin, pelanggan memakai aplikasi ELNUX miliknya sendiri.'**
  String get storeRulesP6;

  /// No description provided for @storeRulesP7.
  ///
  /// In id, this message translates to:
  /// **'Saat pertama kali menerima poin, dompet pelanggan mungkin dikenai biaya pembuatan jalur penerimaan sebesar 0,5% dari jumlah yang diterima (ketentuan jaringan, sekali saja saat jalur dibuat).'**
  String get storeRulesP7;

  /// No description provided for @storeRulesFooter.
  ///
  /// In id, this message translates to:
  /// **'Ketentuan ini mengikuti pedoman program poin toko. Simpan struk belanja sebagai bukti perolehan dan penukaran poin.'**
  String get storeRulesFooter;

  /// No description provided for @storeMigrationTitle.
  ///
  /// In id, this message translates to:
  /// **'Mode Toko Diperbarui'**
  String get storeMigrationTitle;

  /// No description provided for @storeMigrationShiftClosed.
  ///
  /// In id, this message translates to:
  /// **'Shift lama (harga nusan) yang masih terbuka sudah ditutup dan ditandai sebagai data lama. Penjualan mulai sekarang dicatat dalam rupiah.'**
  String get storeMigrationShiftClosed;

  /// No description provided for @storeMigrationHeldDropped.
  ///
  /// In id, this message translates to:
  /// **'{count} pesanan ditahan versi lama (harga nusan) gugur dan tidak diteruskan.'**
  String storeMigrationHeldDropped(int count);

  /// No description provided for @storeMigrationCatalog.
  ///
  /// In id, this message translates to:
  /// **'Katalog lama berharga nusan tidak dipakai lagi. Isi ulang katalog dengan harga rupiah lewat tombol Kelola.'**
  String get storeMigrationCatalog;

  /// No description provided for @storeMigrationOk.
  ///
  /// In id, this message translates to:
  /// **'Mengerti'**
  String get storeMigrationOk;

  /// No description provided for @storeReportCash.
  ///
  /// In id, this message translates to:
  /// **'TUNAI'**
  String get storeReportCash;

  /// No description provided for @storeReportQris.
  ///
  /// In id, this message translates to:
  /// **'QRIS'**
  String get storeReportQris;

  /// No description provided for @storeReportPointsDiscount.
  ///
  /// In id, this message translates to:
  /// **'Diskon Poin'**
  String get storeReportPointsDiscount;

  /// No description provided for @storeReportPointsIssued.
  ///
  /// In id, this message translates to:
  /// **'Poin Diterbitkan'**
  String get storeReportPointsIssued;

  /// No description provided for @storeReportPointsPending.
  ///
  /// In id, this message translates to:
  /// **'Poin Tertunda'**
  String get storeReportPointsPending;

  /// No description provided for @storeReportPointsRedeemed.
  ///
  /// In id, this message translates to:
  /// **'Poin Ditukar'**
  String get storeReportPointsRedeemed;

  /// No description provided for @offlineSpike.
  ///
  /// In id, this message translates to:
  /// **'Uji Offline Lightning'**
  String get offlineSpike;

  /// No description provided for @offlineSpikeSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Sambung dua HP lewat Bluetooth (eksperimental)'**
  String get offlineSpikeSubtitle;

  /// No description provided for @offlineModeTitle.
  ///
  /// In id, this message translates to:
  /// **'Mode Offline'**
  String get offlineModeTitle;

  /// No description provided for @offlineModeOff.
  ///
  /// In id, this message translates to:
  /// **'Bayar tanpa internet dengan perangkat di dekatmu'**
  String get offlineModeOff;

  /// No description provided for @offlineModeSearching.
  ///
  /// In id, this message translates to:
  /// **'Mencari perangkat di dekat…'**
  String get offlineModeSearching;

  /// No description provided for @offlineModeConnect.
  ///
  /// In id, this message translates to:
  /// **'Sambungkan'**
  String get offlineModeConnect;

  /// No description provided for @offlineModeConnected.
  ///
  /// In id, this message translates to:
  /// **'Terhubung'**
  String get offlineModeConnected;

  /// No description provided for @offlineModeConnectedTo.
  ///
  /// In id, this message translates to:
  /// **'Terhubung ke {name}'**
  String offlineModeConnectedTo(String name);

  /// No description provided for @offlineModeMyCode.
  ///
  /// In id, this message translates to:
  /// **'Kode perangkat saya'**
  String get offlineModeMyCode;

  /// No description provided for @offlineModeNoPath.
  ///
  /// In id, this message translates to:
  /// **'Jalur pembayaran belum ada'**
  String get offlineModeNoPath;

  /// No description provided for @offlineModeReady.
  ///
  /// In id, this message translates to:
  /// **'Jalur siap — bisa bayar tanpa internet'**
  String get offlineModeReady;

  /// No description provided for @offlineModeEndSession.
  ///
  /// In id, this message translates to:
  /// **'Akhiri Sesi'**
  String get offlineModeEndSession;

  /// No description provided for @offlineModeStartFailed.
  ///
  /// In id, this message translates to:
  /// **'Mode Offline gagal dimulai. Coba lagi.'**
  String get offlineModeStartFailed;

  /// No description provided for @offlineIntro.
  ///
  /// In id, this message translates to:
  /// **'Uji tahap 2: dua node ELNUX tersambung sebagai peer lewat jembatan Bluetooth, membuka channel langsung, lalu membayar Lightning saat kedua HP offline. Buka channel-nya saat kedua HP berdampingan dan pendana (HP yang membuka) sedang online; pembayaran offline memakai channel yang sudah siap. Nyalakan Bluetooth dan layanan Lokasi di kedua HP sebelum mulai.'**
  String get offlineIntro;

  /// No description provided for @offlineOwnNodeId.
  ///
  /// In id, this message translates to:
  /// **'ID Node HP Ini'**
  String get offlineOwnNodeId;

  /// No description provided for @offlineNodeNotRunning.
  ///
  /// In id, this message translates to:
  /// **'Node belum berjalan'**
  String get offlineNodeNotRunning;

  /// No description provided for @offlineCopy.
  ///
  /// In id, this message translates to:
  /// **'Salin'**
  String get offlineCopy;

  /// No description provided for @offlineCopied.
  ///
  /// In id, this message translates to:
  /// **'ID node tersalin'**
  String get offlineCopied;

  /// No description provided for @offlineChooseRole.
  ///
  /// In id, this message translates to:
  /// **'Peran HP Ini'**
  String get offlineChooseRole;

  /// No description provided for @offlineRoleHost.
  ///
  /// In id, this message translates to:
  /// **'Host (menunggu tamu)'**
  String get offlineRoleHost;

  /// No description provided for @offlineRoleGuest.
  ///
  /// In id, this message translates to:
  /// **'Tamu (mencari host)'**
  String get offlineRoleGuest;

  /// No description provided for @offlineRoleCombined.
  ///
  /// In id, this message translates to:
  /// **'Mode Gabung (uji, tanpa peran)'**
  String get offlineRoleCombined;

  /// No description provided for @offlineStop.
  ///
  /// In id, this message translates to:
  /// **'Berhenti'**
  String get offlineStop;

  /// No description provided for @offlineDiscoveredHosts.
  ///
  /// In id, this message translates to:
  /// **'Host Ditemukan'**
  String get offlineDiscoveredHosts;

  /// No description provided for @offlineDiscoveredDevices.
  ///
  /// In id, this message translates to:
  /// **'Perangkat Ditemukan'**
  String get offlineDiscoveredDevices;

  /// No description provided for @offlineHelloPeer.
  ///
  /// In id, this message translates to:
  /// **'ID node peer (dari HELLO)'**
  String get offlineHelloPeer;

  /// No description provided for @offlineConnect.
  ///
  /// In id, this message translates to:
  /// **'Sambung'**
  String get offlineConnect;

  /// No description provided for @offlineHostNodeIdLabel.
  ///
  /// In id, this message translates to:
  /// **'ID Node Host'**
  String get offlineHostNodeIdLabel;

  /// No description provided for @offlineHostNodeIdHint.
  ///
  /// In id, this message translates to:
  /// **'Tempel ID node dari HP host'**
  String get offlineHostNodeIdHint;

  /// No description provided for @offlineConnectNode.
  ///
  /// In id, this message translates to:
  /// **'Sambungkan Node Lightning'**
  String get offlineConnectNode;

  /// No description provided for @offlineScan.
  ///
  /// In id, this message translates to:
  /// **'Pindai QR'**
  String get offlineScan;

  /// No description provided for @offlinePeersTitle.
  ///
  /// In id, this message translates to:
  /// **'Peer Lightning'**
  String get offlinePeersTitle;

  /// No description provided for @offlinePeerConnected.
  ///
  /// In id, this message translates to:
  /// **'Terhubung'**
  String get offlinePeerConnected;

  /// No description provided for @offlinePeerDisconnected.
  ///
  /// In id, this message translates to:
  /// **'Putus'**
  String get offlinePeerDisconnected;

  /// No description provided for @offlineNoPeers.
  ///
  /// In id, this message translates to:
  /// **'Belum ada peer.'**
  String get offlineNoPeers;

  /// No description provided for @offlineChannelTitle.
  ///
  /// In id, this message translates to:
  /// **'Channel Langsung'**
  String get offlineChannelTitle;

  /// No description provided for @offlineTargetPeer.
  ///
  /// In id, this message translates to:
  /// **'Peer tujuan'**
  String get offlineTargetPeer;

  /// No description provided for @offlineNoTargetPeer.
  ///
  /// In id, this message translates to:
  /// **'belum dikenal'**
  String get offlineNoTargetPeer;

  /// No description provided for @offlineOnchainAddress.
  ///
  /// In id, this message translates to:
  /// **'Alamat on-chain node (untuk dana channel)'**
  String get offlineOnchainAddress;

  /// No description provided for @offlineOnchainBalance.
  ///
  /// In id, this message translates to:
  /// **'Saldo on-chain siap pakai'**
  String get offlineOnchainBalance;

  /// No description provided for @offlineChannelAmount.
  ///
  /// In id, this message translates to:
  /// **'Jumlah channel (nusan)'**
  String get offlineChannelAmount;

  /// No description provided for @offlineOpenChannel.
  ///
  /// In id, this message translates to:
  /// **'Buka Channel'**
  String get offlineOpenChannel;

  /// No description provided for @offlineOpenChannelToLsp.
  ///
  /// In id, this message translates to:
  /// **'Buka Channel ke LSP'**
  String get offlineOpenChannelToLsp;

  /// No description provided for @offlineOpenBlockedOfflineSession.
  ///
  /// In id, this message translates to:
  /// **'Sesi ini dimulai tanpa internet, jadi node tidak punya akses ke rantai dan siaran pendanaan channel baru tidak akan sampai ke jaringan. Mulai ulang aplikasi dengan internet untuk membuka channel.'**
  String get offlineOpenBlockedOfflineSession;

  /// No description provided for @offlineChannelPending.
  ///
  /// In id, this message translates to:
  /// **'Menunggu konfirmasi'**
  String get offlineChannelPending;

  /// No description provided for @offlineConfirmations.
  ///
  /// In id, this message translates to:
  /// **'Konfirmasi'**
  String get offlineConfirmations;

  /// No description provided for @offlineChannelReady.
  ///
  /// In id, this message translates to:
  /// **'Siap'**
  String get offlineChannelReady;

  /// No description provided for @offlineChannelReadyPeerDown.
  ///
  /// In id, this message translates to:
  /// **'Siap (peer tidak tersambung)'**
  String get offlineChannelReadyPeerDown;

  /// No description provided for @offlineNoDirectChannels.
  ///
  /// In id, this message translates to:
  /// **'Belum ada channel langsung.'**
  String get offlineNoDirectChannels;

  /// No description provided for @offlineChannelValue.
  ///
  /// In id, this message translates to:
  /// **'Nilai'**
  String get offlineChannelValue;

  /// No description provided for @offlineOutbound.
  ///
  /// In id, this message translates to:
  /// **'Keluar'**
  String get offlineOutbound;

  /// No description provided for @offlineInbound.
  ///
  /// In id, this message translates to:
  /// **'Masuk'**
  String get offlineInbound;

  /// No description provided for @offlinePayTestTitle.
  ///
  /// In id, this message translates to:
  /// **'Pembayaran Uji'**
  String get offlinePayTestTitle;

  /// No description provided for @offlineInvoiceAmount.
  ///
  /// In id, this message translates to:
  /// **'Jumlah invoice (nusan)'**
  String get offlineInvoiceAmount;

  /// No description provided for @offlineCreateInvoice.
  ///
  /// In id, this message translates to:
  /// **'Buat Invoice'**
  String get offlineCreateInvoice;

  /// No description provided for @offlineInvoiceToPay.
  ///
  /// In id, this message translates to:
  /// **'Invoice yang akan dibayar'**
  String get offlineInvoiceToPay;

  /// No description provided for @offlinePayNow.
  ///
  /// In id, this message translates to:
  /// **'Bayar'**
  String get offlinePayNow;

  /// No description provided for @offlineLogTitle.
  ///
  /// In id, this message translates to:
  /// **'Catatan Uji'**
  String get offlineLogTitle;

  /// No description provided for @offlineStatusIdle.
  ///
  /// In id, this message translates to:
  /// **'Belum mulai'**
  String get offlineStatusIdle;

  /// No description provided for @offlineStatusAdvertising.
  ///
  /// In id, this message translates to:
  /// **'Mengiklankan sebagai host…'**
  String get offlineStatusAdvertising;

  /// No description provided for @offlineStatusDiscovering.
  ///
  /// In id, this message translates to:
  /// **'Mencari host…'**
  String get offlineStatusDiscovering;

  /// No description provided for @offlineStatusConnecting.
  ///
  /// In id, this message translates to:
  /// **'Menyambungkan jembatan…'**
  String get offlineStatusConnecting;

  /// No description provided for @offlineStatusLinked.
  ///
  /// In id, this message translates to:
  /// **'Jembatan terhubung'**
  String get offlineStatusLinked;

  /// No description provided for @offlineStatusError.
  ///
  /// In id, this message translates to:
  /// **'Kesalahan'**
  String get offlineStatusError;

  /// No description provided for @channelsTitle.
  ///
  /// In id, this message translates to:
  /// **'Kelola Channel'**
  String get channelsTitle;

  /// No description provided for @channelsSubtitle.
  ///
  /// In id, this message translates to:
  /// **'Lihat dan tutup channel Lightning kamu'**
  String get channelsSubtitle;

  /// No description provided for @channelsEmpty.
  ///
  /// In id, this message translates to:
  /// **'Belum ada channel'**
  String get channelsEmpty;

  /// No description provided for @channelsEmptyHint.
  ///
  /// In id, this message translates to:
  /// **'Channel pertama lahir otomatis saat kamu menerima pembayaran lewat LSP.'**
  String get channelsEmptyHint;

  /// No description provided for @channelsLoadFailed.
  ///
  /// In id, this message translates to:
  /// **'Gagal memuat channel'**
  String get channelsLoadFailed;

  /// No description provided for @channelCapacity.
  ///
  /// In id, this message translates to:
  /// **'Kapasitas'**
  String get channelCapacity;

  /// No description provided for @channelYourBalance.
  ///
  /// In id, this message translates to:
  /// **'Saldo kamu'**
  String get channelYourBalance;

  /// No description provided for @channelStatusReady.
  ///
  /// In id, this message translates to:
  /// **'Siap'**
  String get channelStatusReady;

  /// No description provided for @channelStatusPeerDown.
  ///
  /// In id, this message translates to:
  /// **'Siap (peer tidak tersambung)'**
  String get channelStatusPeerDown;

  /// No description provided for @channelStatusPending.
  ///
  /// In id, this message translates to:
  /// **'Menunggu konfirmasi'**
  String get channelStatusPending;

  /// No description provided for @closeChannelButton.
  ///
  /// In id, this message translates to:
  /// **'Tutup Channel'**
  String get closeChannelButton;

  /// No description provided for @closeChannelTitle.
  ///
  /// In id, this message translates to:
  /// **'Tutup channel ini?'**
  String get closeChannelTitle;

  /// No description provided for @closeChannelBody.
  ///
  /// In id, this message translates to:
  /// **'Saldo Lightning kamu di channel ini ({amount}) akan kembali ke dompet on-chain kamu sesudah transaksi penutup terkonfirmasi di jaringan, dikurangi biaya jaringan penutupan.'**
  String closeChannelBody(String amount);

  /// No description provided for @closeChannelLspWarning.
  ///
  /// In id, this message translates to:
  /// **'Channel ini adalah jalurmu ke LSP. Menutupnya menghentikan penerimaan lewat LSP — Kode Bayar Statis dan invoice yang melahirkan channel baru tidak akan bisa dibayar — sampai channel baru lahir lagi secara otomatis pada penerimaan berikutnya saat kamu online.'**
  String get closeChannelLspWarning;

  /// No description provided for @closeChannelDirectWarning.
  ///
  /// In id, this message translates to:
  /// **'Channel ini adalah jalur pembayaran offline-mu dengan perangkat di seberang. Menutupnya mengakhiri jalur itu; membukanya lagi harus melalui proses pembukaan dari awal.'**
  String get closeChannelDirectWarning;

  /// No description provided for @closeChannelStarted.
  ///
  /// In id, this message translates to:
  /// **'Penutupan dimulai. Saldo akan masuk ke dompet on-chain setelah transaksi penutup terkonfirmasi.'**
  String get closeChannelStarted;

  /// No description provided for @closeForceTitle.
  ///
  /// In id, this message translates to:
  /// **'Tutup kerja sama tidak berhasil'**
  String get closeForceTitle;

  /// No description provided for @closeForceFallback.
  ///
  /// In id, this message translates to:
  /// **'Lawan channel tidak bisa diajak menutup bersama saat ini.'**
  String get closeForceFallback;

  /// No description provided for @closeForceBody.
  ///
  /// In id, this message translates to:
  /// **'Tutup paksa menyiarkan keadaan terakhir channel secara sepihak: dana kamu terkunci jeda pengaman (diukur dalam blok) sebelum tersapu ke dompet on-chain, dan biaya on-chain-nya lebih mahal. Pakai hanya bila memang terpaksa.'**
  String get closeForceBody;

  /// No description provided for @closeForceButton.
  ///
  /// In id, this message translates to:
  /// **'Tutup Paksa'**
  String get closeForceButton;

  /// No description provided for @closeForceStarted.
  ///
  /// In id, this message translates to:
  /// **'Tutup paksa dimulai. Dana akan tersapu ke dompet on-chain sesudah jeda pengaman berakhir.'**
  String get closeForceStarted;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'id'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'id':
      return AppLocalizationsId();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
