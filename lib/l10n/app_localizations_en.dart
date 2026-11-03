// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appLanguage => 'Language';

  @override
  String get chooseLanguage => 'Choose Language';

  @override
  String get languageIndonesian => 'Bahasa Indonesia';

  @override
  String get languageEnglish => 'English';

  @override
  String get themeTitle => 'Theme';

  @override
  String get themeSubtitle => 'Dark or light, as you like';

  @override
  String get changeThemeTooltip => 'Change theme';

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String get greetingNight => 'Good night';

  @override
  String get bootConnecting => 'Connecting to LSP…';

  @override
  String get splashTagline => 'Your money, your control.';

  @override
  String get bootFailedTitle => 'Failed to connect node';

  @override
  String get bootFailedRetry => 'Try again';

  @override
  String get bootGenericError =>
      'Something went wrong while starting the wallet.';

  @override
  String get lspNodeIdMissing =>
      'lspNodeId is not set in lib/config.dart — ask the operator for the LSP node id.';

  @override
  String seedCorrupt(int length, String path) {
    return 'Seed file corrupted (length $length, must be 64). Delete $path to regenerate (OLD FUNDS WILL BE LOST).';
  }

  @override
  String get exitTitle => 'Exit ELNUX?';

  @override
  String get exitBody =>
      'The app will close. While the app is closed, the wallet cannot receive payments.';

  @override
  String get cancel => 'Cancel';

  @override
  String get exitConfirm => 'Exit';

  @override
  String get totalBalance => 'Total Balance';

  @override
  String get networkTestnet => 'Lightning Network • Testnet';

  @override
  String get networkMainnet => 'Lightning Network • Mainnet';

  @override
  String get lightningActive => 'Lightning active — ready for instant receive';

  @override
  String get lightningConnecting => 'Connecting Lightning…';

  @override
  String get legacyStrip =>
      'This wallet has no backup phrase yet. Open the Profile tab to create a new wallet with a phrase before receiving funds.';

  @override
  String get send => 'Send';

  @override
  String get receive => 'Receive';

  @override
  String get buy => 'Buy';

  @override
  String get swap => 'Swap';

  @override
  String get activity => 'Activity';

  @override
  String get seeAll => 'See all';

  @override
  String get noActivity => 'No activity yet';

  @override
  String get market => 'Market';

  @override
  String get marketSoon => 'NUX market info — coming soon.';

  @override
  String get home => 'Home';

  @override
  String get history => 'History';

  @override
  String get profile => 'Profile';

  @override
  String get received => 'Received';

  @override
  String get sent => 'Sent';

  @override
  String get pending => 'Pending';

  @override
  String get processing => 'Processing';

  @override
  String get failed => 'Failed';

  @override
  String get noTransactions =>
      'No transactions yet. Incoming and outgoing payments will appear here.';

  @override
  String get txDetailTitle => 'Transaction Details';

  @override
  String get txType => 'Type';

  @override
  String get txStatus => 'Status';

  @override
  String get txTime => 'Time';

  @override
  String get txPaymentId => 'Payment ID';

  @override
  String get txPaymentHash => 'Payment Hash';

  @override
  String get txSucceeded => 'Succeeded';

  @override
  String get txExpiredBadge => 'Expired';

  @override
  String get txInvoiceExpiredNote =>
      'This invoice has expired and can no longer be paid. Create a new invoice to receive a payment.';

  @override
  String get txInvoiceNotSavedNote =>
      'This invoice was created before the saved-invoice feature existed, so its invoice string was not stored in the app and cannot be shown again.';

  @override
  String get txProcessingNote =>
      'Your money is safe and is waiting for its turn to be recorded on the network. It will complete on its own.';

  @override
  String get txJitNote =>
      'This payment also created a new receiving channel for you, so a 0.5% creation fee was deducted. Payments that follow through this channel won\'t be charged this fee.';

  @override
  String get txCopied => 'Copied';

  @override
  String get receiveRestoredHint =>
      'Your last unpaid invoice was restored from storage.';

  @override
  String get backupWallet => 'Backup Wallet';

  @override
  String get legacyWalletSubtitle =>
      'This wallet was created before the backup phrase feature existed';

  @override
  String get backupSubtitle => 'View your wallet backup phrase';

  @override
  String get noPhraseTitle => 'This wallet has no backup phrase';

  @override
  String get noPhraseBody =>
      'This wallet was created by a previous app version that stored keys without a phrase. If the phone is lost or damaged, funds in this wallet cannot be recovered.\n\nIf this wallet is still EMPTY (never received funds), create a new phrase-backed wallet now:';

  @override
  String get createNewWalletTitle => 'Create a new wallet?';

  @override
  String get deleteOldWalletBody =>
      'The old wallet will be PERMANENTLY DELETED along with all its data. Continue ONLY if the old wallet is still empty — any funds in it will be lost forever.';

  @override
  String get deleteAndCreate => 'Delete & create new';

  @override
  String get createNewWalletButton => 'Create a new wallet with a phrase';

  @override
  String get networkTestnetLabel => 'Network: Nusacoin Testnet';

  @override
  String get networkMainnetLabel => 'Network: Nusacoin Mainnet';

  @override
  String appVersionLabel(String version, String build) {
    return 'Version $version • Build $build';
  }

  @override
  String get backupWarning =>
      'Write these words on paper and store them somewhere safe. Anyone who has these words can take your funds.';

  @override
  String get showBackupWords => 'Show Backup Words';

  @override
  String get backupCopied => 'Backup words copied';

  @override
  String get copy => 'Copy';

  @override
  String get backupConfirmed => 'I have written these words somewhere safe';

  @override
  String get done => 'Done';

  @override
  String get invalidAmount => 'Enter a valid amount';

  @override
  String receiveInvoiceDesc(String amount) {
    return 'Receive $amount nusan';
  }

  @override
  String get createInvoiceFailed => 'Failed to create invoice. Try again.';

  @override
  String get receiveJitMinimumNote =>
      'For your first receive (which also creates your receiving channel), the smallest amount is 1,000 nusan. Once your channel is ready, you can receive any amount, including less than 1,000 nusan.';

  @override
  String get receiveTitle => 'Receive NUX';

  @override
  String get jitInfo =>
      'Lightning invoice with an instant channel (JIT). No need to wait for block confirmation.';

  @override
  String get amountLabel => 'Amount (nusan)';

  @override
  String get createInvoice => 'Create Invoice';

  @override
  String get paymentReceived => 'Payment Received';

  @override
  String receivedAmount(String amount) {
    return '+$amount nusan';
  }

  @override
  String get fundsArrived => 'Funds have arrived in your Lightning channel.';

  @override
  String get invoiceTitle => 'Lightning Invoice';

  @override
  String get invoiceCopied => 'Invoice copied';

  @override
  String get shareInvoiceHint =>
      'Share this invoice with the sender. The channel will open automatically when the payment is received.';

  @override
  String get staticCodeTitle => 'Static Payment Code';

  @override
  String get staticCodeHint =>
      'This code can be used again and again with no expiry — share it once, and the payer chooses the amount each time they pay.';

  @override
  String get staticCodeCopied => 'Payment code copied';

  @override
  String get staticCodeNeedsConnection =>
      'Your payment code is created once the wallet is connected. Check your connection, then try again.';

  @override
  String get staticCodeFailed =>
      'Couldn\'t create your payment code. Try again.';

  @override
  String get staticOfferDescription => 'ELNUX payment code';

  @override
  String get confirmPayOfferTitle => 'Pay this payment code?';

  @override
  String sendOfferAmountLine(String amount) {
    return 'Amount: $amount nusan';
  }

  @override
  String get sendOfferVariableHint =>
      'This payment code doesn\'t set an amount — choose how much to pay.';

  @override
  String get sendOfferInvalid => 'This payment code is invalid.';

  @override
  String get sendOfferExpired => 'This payment code has expired.';

  @override
  String get pasteInvoiceFirst => 'Paste an invoice first';

  @override
  String get invalidInvoice => 'This is not a valid Lightning invoice';

  @override
  String get payFailed => 'Payment failed. Try again.';

  @override
  String get payWaitingOutcome => 'Waiting for the final payment result…';

  @override
  String get payFailedFinal =>
      'Payment failed. No funds were sent and your balance is unchanged.';

  @override
  String get payStillPending =>
      'The payment is still being processed past the wait limit. Its final result will appear in History — do not pay the same invoice again until its status is clear.';

  @override
  String get sendTitle => 'Send NUX';

  @override
  String get sendInfo =>
      'Paste or scan a Lightning invoice from the recipient. Instant payment via channel.';

  @override
  String sendableLine(String amount) {
    return 'Available to send: $amount nusan';
  }

  @override
  String get sendInsufficientBalance =>
      'Your balance is not enough to pay this invoice.';

  @override
  String sendReserveNote(String reserve, String sendable) {
    return 'This amount can\'t be sent yet. Of your balance, $reserve nusan is always kept aside as a safety reserve for your payment channel — it stays yours, it is not a fee, and it returns in full if the channel is closed. You can currently send: $sendable nusan.';
  }

  @override
  String get sendZeroSendableHint =>
      'Receive a payment first so your balance rises above the reserve — after that you can send again.';

  @override
  String get backToHome => 'Back to Home';

  @override
  String get paste => 'Paste';

  @override
  String get scanQr => 'Scan QR';

  @override
  String get pay => 'Pay';

  @override
  String get confirmPayTitle => 'Pay this invoice?';

  @override
  String get confirmPayBody =>
      'Lightning payments are instant and cannot be cancelled. Double-check the invoice below before continuing.';

  @override
  String get paymentSuccess => 'Payment Successful!';

  @override
  String get scanTitle => 'Scan QR Invoice';

  @override
  String get cameraDenied =>
      'Camera permission denied. Enable camera permission for ELNUX in phone Settings, then try again.';

  @override
  String get cameraUnavailable => 'Camera cannot be opened on this device.';

  @override
  String get pointCamera => 'Point the camera at the QR invoice';

  @override
  String get scanFromGallery => 'Choose from gallery';

  @override
  String get scanNoQrFound => 'No QR code found in that image';

  @override
  String get errorConnection =>
      'Cannot connect. Check your internet connection, then try again.';

  @override
  String get errorBalance => 'Insufficient balance.';

  @override
  String get errorInvoice => 'Invoice is invalid or has expired.';

  @override
  String get errorWalletData =>
      'Wallet data is corrupted. Contact the operator for help.';

  @override
  String get restoreWallet => 'Restore Wallet';

  @override
  String get restoreSubtitle => 'Restore your wallet from a backup phrase';

  @override
  String get restoreIntro =>
      'Enter the backup phrase of the wallet you want to restore. ELNUX phrases are in English, in the original order.';

  @override
  String get restoreHint =>
      'Type or paste the phrase, separating each word with a space';

  @override
  String restoreWordCount(int count) {
    return '$count words';
  }

  @override
  String get restoreInvalidCount =>
      'The phrase must have 12, 15, 18, 21, or 24 words (ELNUX phrases have 12 words).';

  @override
  String get restoreInvalidWords =>
      'Invalid phrase — check the spelling and word order.';

  @override
  String get restoreButton => 'Restore Wallet';

  @override
  String get restoreConfirmTitle => 'Restore this wallet?';

  @override
  String get restoreConfirmBody =>
      'The active wallet will be PERMANENTLY DELETED with all its data. Continue ONLY if the active wallet is still empty, or its phrase is already backed up. A phrase restores the wallet — Lightning channel states are not restored.';

  @override
  String get restoreConfirmAction => 'Delete & Restore';

  @override
  String get restoreWorking => 'Restoring wallet…';

  @override
  String get restoreSuccess => 'Wallet restored successfully';

  @override
  String get restoreFailed => 'Failed to restore the wallet. Try again.';

  @override
  String get shareLog => 'Share Log';

  @override
  String get shareLogSubtitle =>
      'Send the node\'s technical log when something goes wrong';

  @override
  String get shareLogUnavailable => 'The log isn\'t available yet.';

  @override
  String get shareLogFailed => 'Couldn\'t share the log. Try again.';

  @override
  String get printer => 'Printer';

  @override
  String get printerSubtitle => 'Receipt printer, test print, header & footer';

  @override
  String get printerSettings => 'Printer Settings';

  @override
  String get printerSelect => 'Select printer';

  @override
  String get printerNoneSelected => 'No printer selected';

  @override
  String get printerNoPaired =>
      'No paired printers found. Pair the printer in Android Bluetooth settings first.';

  @override
  String get printerTest => 'Test Print';

  @override
  String get printerHeader => 'Header text';

  @override
  String get printerHeaderHint =>
      'Printed at the top of every receipt (e.g. shop name and address)';

  @override
  String get printerFooter => 'Footer text';

  @override
  String get printerFooterHint => 'Printed at the bottom of every receipt';

  @override
  String get print => 'Print';

  @override
  String get printSuccess => 'Receipt printed';

  @override
  String get printFailed => 'Couldn\'t print. Check the printer and try again.';

  @override
  String get printNoPrinter =>
      'No printer selected yet. Choose one in Profile, Printer.';

  @override
  String get printBluetoothOff => 'Bluetooth is off. Turn it on and try again.';

  @override
  String get printPermissionDenied =>
      'Bluetooth permission is needed to use the printer.';

  @override
  String get receiptDefaultFooter => 'Thank you';

  @override
  String get printerSearchHint => 'Search by name or address';

  @override
  String get printerTurnOn => 'Turn on Bluetooth';

  @override
  String get printerScan => 'Scan for printers';

  @override
  String get printerScanning => 'Scanning…';

  @override
  String get printerDiscovered => 'Found devices';

  @override
  String get printerTapToPair => 'Tap to pair and select';

  @override
  String get printerBondFailed => 'Couldn\'t pair with that device.';

  @override
  String get printerPairedSelected => 'Printer paired and selected';

  @override
  String get historyExport => 'Export CSV';

  @override
  String get historyExportFailed => 'Couldn\'t create the CSV file.';

  @override
  String get historyFilter => 'Date filter';

  @override
  String get historyLast7Days => 'Last 7 days';

  @override
  String get historyLast30Days => 'Last 30 days';

  @override
  String get historyCustomRange => 'Custom date range…';

  @override
  String get historyNoTransactionsInPeriod => 'No transactions in this period.';

  @override
  String get updateTitle => 'Update Available';

  @override
  String updateVersionAvailable(String versi) {
    return 'A new version is available: $versi';
  }

  @override
  String get updateNotes => 'Release notes';

  @override
  String get updateDownloadInstall => 'Download & Install';

  @override
  String get updateLater => 'Later';

  @override
  String updateDownloading(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateFailed =>
      'Download failed. Check your connection and try again.';

  @override
  String get updateRetry => 'Try Again';

  @override
  String get updateCheckTitle => 'Check for Updates';

  @override
  String get updateCheckSubtitle => 'See if a newer ELNUX version is available';

  @override
  String get updateUpToDate => 'ELNUX is up to date.';

  @override
  String get updateCheckFailed => 'Couldn\'t check for updates right now.';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String get communityTitle => 'Community';

  @override
  String get communityWebsiteLabel => 'Website';

  @override
  String get communityTelegramGroup => 'Telegram Group';

  @override
  String get communityOpenFailed => 'Couldn\'t open the link.';

  @override
  String get storeMode => 'Store Mode';

  @override
  String get storeModeSubtitle =>
      'Cashier mode for accepting payments in your store';

  @override
  String get storeCreateCode => 'Create Payment Code';

  @override
  String get storeWaitingPayment => 'Waiting for payment…';

  @override
  String get storeCancelCode => 'Cancel Code';

  @override
  String get storeIdleHint =>
      'Build an order, then create a payment code for its total — or show the static payment code.';

  @override
  String get storeFreeAmountLabel => 'Custom Amount (nusan)';

  @override
  String get storeAddFreeItem => 'Add Custom Item';

  @override
  String get storeFreeItem => 'Custom Item';

  @override
  String get storeFreeTitleLabel => 'Item Name (optional)';

  @override
  String get storeSearchHint => 'Search by product name or code…';

  @override
  String get storeSearchNoResults => 'No products match your search.';

  @override
  String get storeRemoveLineTitle => 'Remove from Order?';

  @override
  String storeRemoveLineMessage(String name) {
    return 'Remove $name from the order?';
  }

  @override
  String get storeRemoveLineConfirm => 'Remove';

  @override
  String get storeOrderTitle => 'Order';

  @override
  String get storeOrderEmpty =>
      'No items yet — tap a catalog product, scan a code, or add a custom amount.';

  @override
  String get storeSubtotal => 'Subtotal';

  @override
  String get storeTotalDiscount => 'Total Discount';

  @override
  String get storeGrandTotal => 'Total';

  @override
  String get storeOrderDiscount => 'Order Discount';

  @override
  String get storeDiscount => 'Discount';

  @override
  String get storeSetDiscount => 'Set Discount';

  @override
  String get storeApplyDiscount => 'Apply';

  @override
  String get storeRemoveDiscount => 'Remove Discount';

  @override
  String get storeDiscountPercent => 'Percent (%)';

  @override
  String get storeDiscountFixed => 'Fixed (nusan)';

  @override
  String get storeDiscountValue => 'Discount Value';

  @override
  String get storeZeroTotalHint =>
      'A total of 0 can\'t be made into a payment code — reduce the discount or add items.';

  @override
  String get storeSessionTitle => 'This Session';

  @override
  String storeSessionSales(int count, String total) {
    return '$count sales • $total nusan';
  }

  @override
  String get storePrintReceipt => 'Print Receipt';

  @override
  String get storeScanCode => 'Scan Code';

  @override
  String get storeCatalogTitle => 'Product Catalog';

  @override
  String get storeManageCatalog => 'Manage';

  @override
  String get storeCatalogEmpty =>
      'The catalog is still empty — add the first product via Manage.';

  @override
  String get storeCodeNotRegistered =>
      'This code isn\'t registered in the catalog yet.';

  @override
  String get storeRegisterNow => 'Register It Now';

  @override
  String get storeProductCode => 'Product Code';

  @override
  String get storeProductName => 'Product Name';

  @override
  String get storeProductPrice => 'Price (nusan)';

  @override
  String get storeProductDiscount => 'Default Discount (optional)';

  @override
  String get storeSaveProduct => 'Save Product';

  @override
  String storeProductSaved(String name) {
    return 'Product saved: $name';
  }

  @override
  String storeProductAdded(String name) {
    return 'Added: $name';
  }

  @override
  String storeReceiptDiscountNote(String amount) {
    return 'Total discount on this sale: $amount nusan';
  }

  @override
  String get storeClearKeypad => 'Clear';

  @override
  String get storeProductFormError =>
      'Check again: code, name, and a price above 0 are all required.';

  @override
  String get storeProductCategory => 'Category (optional)';

  @override
  String get storeShiftTitle => 'Cashier Shift';

  @override
  String get storeShiftNotOpen => 'Shift Not Open';

  @override
  String get storeShiftOpenHint =>
      'Open a shift first to build orders, create payment codes, and take payments in Store Mode.';

  @override
  String get storeShiftOpen => 'Open Shift';

  @override
  String get storeShiftClose => 'Close Shift';

  @override
  String storeShiftOpenedAt(String time) {
    return 'Opened $time';
  }

  @override
  String get storeShiftStillOpen => 'Still Open';

  @override
  String get storeCloseShiftBlocked =>
      'Can\'t close the shift yet: a payment code is still waiting or a payment is being celebrated. Finish or cancel it first.';

  @override
  String get storeCloseShiftConfirmTitle => 'Close This Shift?';

  @override
  String get storeCloseShiftConfirmBody =>
      'Once closed, later sales go into a new shift.';

  @override
  String get storeShiftClosedTitle => 'Shift Closed';

  @override
  String get storeShiftClosedBody =>
      'This shift\'s report is ready to view, print, or share as PDF.';

  @override
  String get storeLater => 'Later';

  @override
  String get storeViewReport => 'View Report';

  @override
  String get storeSalesReport => 'Sales Report';

  @override
  String get storeReportCurrentShift => 'Current Shift';

  @override
  String get storeReportByDate => 'By Date';

  @override
  String get storeReportPastShifts => 'Past Shifts';

  @override
  String get storeReportPrint => 'Print Report';

  @override
  String get storeReportSharePdf => 'Share PDF';

  @override
  String get storeReportEmpty => 'No sales recorded in this period yet.';

  @override
  String get storeInvoiceExpiredVoid =>
      'The payment code expired — the order was recorded as VOID.';

  @override
  String get storeReportSummaryTitle => 'SELECTED REPORT';

  @override
  String get storeReportDetailsTitle => 'MENU SALES DETAILS';

  @override
  String get storeReportItemQty => 'Item Qty';

  @override
  String get storeReportTotalOrder => 'Total ORDER';

  @override
  String get storeReportTotalOrderInfo => 'Total ORDER Info';

  @override
  String get storeReportInvoices => '#Invoices';

  @override
  String get storeReportInvUnit => 'inv.';

  @override
  String get storeReportVoidInfo => 'VOID Info';

  @override
  String get storeReportVoidItemQty => 'VOID Item Qty';

  @override
  String get storeReportVoidSubTotal => 'VOID Sub Total';

  @override
  String get storeReportVoidDiscount => 'VOID Discount';

  @override
  String get storeReportVoidTotalOrder => 'VOID Total ORDER';

  @override
  String get storeReportOther => 'OTHER';

  @override
  String get storeReportQty => 'Qty';

  @override
  String storeReportMenus(int count) {
    return '$count menu(s)';
  }

  @override
  String get storeReportGeneratedOn => 'Rpt.generated on';

  @override
  String storeReportShiftsNote(int count) {
    return 'Covers $count shift(s)';
  }
}
