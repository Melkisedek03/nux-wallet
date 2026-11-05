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
  String get unitTitle => 'Unit';

  @override
  String get unitSubtitle =>
      'Display unit for amounts in balance, send, receive, and history';

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
  String get bootOfflineButton => 'Continue without internet';

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
  String get txNote => 'Note';

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
    return 'Receive $amount';
  }

  @override
  String get receiveNoteLabel => 'Note (optional)';

  @override
  String get receiveNoteHint => 'e.g. for November school fees';

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
  String get amountLabel => 'Amount';

  @override
  String get createInvoice => 'Create Invoice';

  @override
  String get paymentReceived => 'Payment Received';

  @override
  String receivedAmount(String amount) {
    return '+$amount';
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
    return 'Amount: $amount';
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
    return 'Available to send: $amount';
  }

  @override
  String get sendInsufficientBalance =>
      'Your balance is not enough to pay this invoice.';

  @override
  String sendReserveNote(String reserve, String sendable) {
    return 'This amount can\'t be sent yet. Of your balance, $reserve is always kept aside as a safety reserve for your payment channel — it stays yours, it is not a fee, and it returns in full if the channel is closed. You can currently send: $sendable.';
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
  String confirmPayAmountLine(String amount) {
    return 'Amount: $amount';
  }

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
      'Store cashier — rupiah sales & nusan points program';

  @override
  String get storeIdleHint =>
      'Build an order, then settle the payment in rupiah. Customers earn nusan points after a settled sale.';

  @override
  String get storeFreeAmountLabel => 'Custom Amount (Rp)';

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
  String get storeAddNote => 'Add Note';

  @override
  String get storeLineNoteTitle => 'Item Note';

  @override
  String get storeNoteWord => 'Note';

  @override
  String get storeClearNote => 'Clear Note';

  @override
  String get storeSaveNote => 'Save';

  @override
  String get storeHoldOrder => 'Hold Order';

  @override
  String get storeHeldSaved =>
      'Order held — resume it any time from the Held list.';

  @override
  String get storeHeldTitle => 'Held Orders';

  @override
  String storeHeldBadge(int count) {
    return 'Held ($count)';
  }

  @override
  String get storeHeldEmpty => 'No orders are on hold.';

  @override
  String storeHeldEntryMeta(String time, int count, String total) {
    return '$time • $count item(s) • $total';
  }

  @override
  String get storeHeldResumeBlocked =>
      'The current order is not empty — hold or finish the order being built first.';

  @override
  String get storeHeldResumed => 'Held order resumed.';

  @override
  String get storeExitHoldTitle => 'Order Not Finished';

  @override
  String get storeExitHoldBody =>
      'The order you are putting together is not finished. If you leave now, it will be held automatically and can be resumed any time from the Held list.';

  @override
  String get storeExitStay => 'Stay Here';

  @override
  String get storeExitHoldLeave => 'Hold & Exit';

  @override
  String get storeExitHoldFailed =>
      'Could not hold the order — staying on this screen so the order is not lost.';

  @override
  String get storeDraftRestored =>
      'Your last order draft was restored — pick up right where you left off.';

  @override
  String get storeDeleteHeldTitle => 'Delete Held Order?';

  @override
  String storeDeleteHeldMessage(String summary) {
    return 'Delete the held order $summary? This can\'t be undone.';
  }

  @override
  String get storeKeypadModeQty => 'Qty';

  @override
  String get storeKeypadModeAmount => 'Amount';

  @override
  String storeQtyBadge(int qty) {
    return 'Qty: $qty';
  }

  @override
  String get storeQtyModeHint =>
      'Qty mode: tap digits as a multiplier, then tap a catalog product or scan its code — the product is added that many times.';

  @override
  String storeProductAddedQty(String name, int qty) {
    return 'Added: $name ×$qty';
  }

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
  String get storeDiscountFixed => 'Fixed (Rp)';

  @override
  String get storeDiscountValue => 'Discount Value';

  @override
  String get storeSessionTitle => 'This Session';

  @override
  String storeSessionSales(int count, String total) {
    return '$count sales • Rp$total';
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
  String get storeProductPrice => 'Price (Rp)';

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
      'Open a shift first to build orders and take rupiah payments in Store Mode.';

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
      'Can\'t close the shift yet: a points issuance is still in progress. Finish issuing the points first.';

  @override
  String get storeCloseShiftConfirmTitle => 'Close This Shift?';

  @override
  String get storeCloseShiftConfirmBody =>
      'Once closed, later sales go into a new shift.';

  @override
  String get storeCloseShiftHeldTitle => 'Held Orders Still Pending';

  @override
  String storeCloseShiftHeldBody(int count, String total) {
    return 'There are $count held orders (total $total) still unpaid. Held orders stay saved and can be resumed in the next shift.';
  }

  @override
  String get storeCloseShiftHeldConfirm => 'Close Shift Anyway';

  @override
  String get storeBack => 'Back';

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
  String get storeSalesHistory => 'Sales History';

  @override
  String get storeSalesHistoryEmpty => 'No sales recorded yet.';

  @override
  String get storeSaleDetailTitle => 'Sale Details';

  @override
  String get storeSalePaymentLabel => 'Payment';

  @override
  String get storeSaleReceiptUnavailable =>
      'Receipt not available for this record.';

  @override
  String get storeReprintReceipt => 'Reprint Receipt';

  @override
  String get storePreviewShareReceipt => 'Preview & Share';

  @override
  String get storeOperatorLoginTitle => 'Operator Login';

  @override
  String get storeOperatorSetupTitle => 'Create Owner Account';

  @override
  String get storeOperatorSetupBody =>
      'Store Mode now uses operator logins. Create the first owner account: this account manages other operators and approves sensitive actions.';

  @override
  String get storeOperatorNameLabel => 'Operator Name';

  @override
  String get storeOperatorPinLabel => 'PIN (6 digits)';

  @override
  String get storeOperatorPinConfirmLabel => 'Repeat PIN';

  @override
  String get storeOperatorPinMismatch => 'PINs do not match.';

  @override
  String get storeOperatorPinInvalid => 'PIN must be 6 digits.';

  @override
  String get storeOperatorNameRequired => 'Operator name is required.';

  @override
  String get storeOperatorLoginButton => 'Log In';

  @override
  String get storeOperatorWrongPin => 'Wrong PIN.';

  @override
  String get storeOperatorSwitch => 'Switch Operator';

  @override
  String get storeOperatorRoleOwner => 'Owner';

  @override
  String get storeOperatorRoleCashier => 'Cashier';

  @override
  String get storeAdminPinTitle => 'Admin PIN';

  @override
  String get storeAdminPinBody =>
      'This action needs owner approval. Ask the owner to enter their PIN.';

  @override
  String get storeAdminApproved => 'Admin approval accepted.';

  @override
  String get storeVoidSaleButton => 'Void Sale';

  @override
  String get storeVoidSaleTitle => 'Void Settled Sale?';

  @override
  String get storeVoidSaleBody =>
      'The sale is marked VOID: it leaves report totals and its points journal entries are reversed. The original record stays, marked VOID. This cannot be undone.';

  @override
  String get storeVoidReasonLabel => 'Void reason (required)';

  @override
  String get storeVoidDone => 'Sale marked VOID.';

  @override
  String get storeOperatorsTitle => 'Manage Operators';

  @override
  String get storeOperatorLastOwner =>
      'Cannot deactivate the last active owner.';

  @override
  String get storeOperatorAdd => 'Add Operator';

  @override
  String get storeOperatorRoleLabel => 'Role';

  @override
  String get storeOperatorDeactivate => 'Deactivate';

  @override
  String get storeOperatorActivate => 'Activate';

  @override
  String get storeOperatorResetPin => 'Change PIN';

  @override
  String get storeOperatorInactiveBadge => 'Inactive';

  @override
  String get storeAuditTitle => 'Activity Log';

  @override
  String get storeAuditEmpty => 'No activity recorded yet.';

  @override
  String get storeSettingsAdminSection => 'Operators & Security';

  @override
  String get storeSettingsDiscountThresholdLabel =>
      'Cashier discount limit (%)';

  @override
  String get storeSettingsDiscountThresholdHint =>
      'Manual discounts above this limit must be approved with an admin PIN.';

  @override
  String get storeCustomerTitle => 'Customers';

  @override
  String get storeCustomerChoose => 'Choose Customer';

  @override
  String get storeCustomerAdd => 'Add Customer';

  @override
  String get storeCustomerNameLabel => 'Customer Name (optional)';

  @override
  String get storeCustomerOfferLabel => 'Static Payment Code (Bolt12)';

  @override
  String get storeCustomerScan => 'Scan';

  @override
  String get storeCustomerInvalidOffer =>
      'Invalid payment code — must be a Bolt12 offer (lno1…).';

  @override
  String get storeCustomerEmpty => 'No saved customers yet.';

  @override
  String get storeCustomerEdit => 'Edit';

  @override
  String get storeCustomerDelete => 'Delete';

  @override
  String get storeCustomerManage => 'Manage Customers';

  @override
  String get storeAuditLogin => 'Login';

  @override
  String get storeAuditLogout => 'Log out';

  @override
  String get storeAuditOperatorCreated => 'Operator created';

  @override
  String get storeAuditOperatorUpdated => 'Operator updated';

  @override
  String get storeAuditPinChanged => 'PIN changed';

  @override
  String get storeAuditShiftOpen => 'Shift opened';

  @override
  String get storeAuditShiftClose => 'Shift closed';

  @override
  String get storeAuditAdminOverride => 'Admin override';

  @override
  String get storeAuditSaleVoid => 'Sale voided';

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
  String get storeReportInvoices => '#Sales';

  @override
  String get storeReportInvUnit => 'sales';

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

  @override
  String get storeCatalogManagerTitle => 'Manage Catalog';

  @override
  String get storeAddProduct => 'Add Product';

  @override
  String get storeEditProduct => 'Edit Product';

  @override
  String get storeNoDiscount => 'No Discount';

  @override
  String get storeCheckout => 'Settle Payment';

  @override
  String get storePayTitle => 'Settle Payment';

  @override
  String get storePayTotalLabel => 'Order Total';

  @override
  String get storeCash => 'Cash';

  @override
  String get storeQris => 'QRIS';

  @override
  String get storeQrisNote =>
      'The customer pays via QRIS as usual at this store. The app only records the payment method — tap the button below once the QRIS payment has been received.';

  @override
  String get storeCashReceived => 'Cash Received';

  @override
  String get storeCashExact => 'Exact';

  @override
  String get storeChange => 'Change';

  @override
  String storeCashShort(String amount) {
    return 'Short Rp$amount';
  }

  @override
  String get storeSettle => 'Settled — Finish';

  @override
  String get storeSettleQris => 'QRIS Received — Finish';

  @override
  String get storeSettlePromo => 'Finish Without Payment';

  @override
  String get storePromoNote =>
      'Order total is Rp0 (promotion) — no payment is taken; the sale is still recorded.';

  @override
  String get storeCancelOrder => 'Cancel Order';

  @override
  String get storeVoidConfirmTitle => 'Cancel This Order?';

  @override
  String get storeVoidConfirmBody =>
      'The order is cancelled and recorded as VOID in the report. This can\'t be undone.';

  @override
  String get storeVoidRecorded => 'Order cancelled — recorded as VOID.';

  @override
  String get storeRedeemTitle => 'Redeem Nusan Points';

  @override
  String get storeRedeemHint =>
      'Redemption is read from this store\'s own points issuance records — the customer pays nothing. Ask the customer to show their Bolt12 offer in their ELNUX app, scan it, then apply a discount up to the points recorded for them.';

  @override
  String get storeRedeemScanOffer => 'Scan Customer Offer';

  @override
  String storeRedeemBalance(int balance) {
    return 'Recorded points for this customer: $balance points.';
  }

  @override
  String get storeRedeemNoBalance =>
      'No points are recorded for this offer at this store yet — redemption isn\'t possible.';

  @override
  String get storeRedeemNeedOffer =>
      'Redemption uses the customer\'s Bolt12 offer. That code isn\'t an offer — ask the customer to open their offer in ELNUX and scan again.';

  @override
  String get storeRedeemPointsLabel => 'Points';

  @override
  String get storeRedeemApply => 'Apply Discount';

  @override
  String storeRedeemApplied(int points, String amount) {
    return 'Redemption recorded: $points points = Rp$amount discount.';
  }

  @override
  String get storeRedeemUndo => 'Undo Redemption';

  @override
  String get storeRedeemScanAgain => 'Scan Again';

  @override
  String storeRedeemMaxNote(int max) {
    return 'At most $max points for this order.';
  }

  @override
  String storeRedeemClamped(int max) {
    return 'That exceeds the limit — using $max points.';
  }

  @override
  String get storeRedeemInvalidPoints =>
      'That points amount isn\'t valid, or exceeds the possible discount for this order.';

  @override
  String get storeSaleCompleted => 'Sale Completed';

  @override
  String storePointsEarnedLine(int points) {
    return 'Nusan points earned: $points points';
  }

  @override
  String get storePointsIssueButton => 'Scan & Issue';

  @override
  String get storePointsSkip => 'Skip';

  @override
  String get storePointsIssuedOk => 'Nusan points issued to the customer.';

  @override
  String get storeIssueInvalidCode =>
      'That code isn\'t a readable ELNUX invoice or payment code — scan the customer\'s code again.';

  @override
  String get storeIssueAmountMismatch =>
      'The code amount doesn\'t equal the points to issue — ask the customer to create a code for exactly the earned points.';

  @override
  String get storeIssueFailed =>
      'Issuing the points failed — they stay pending and can be issued from the Pending Points list.';

  @override
  String get storeIssueStillPending =>
      'The points payment is still in flight — it stays pending; check again from the Pending Points list.';

  @override
  String get storeIssueInvoiceNote =>
      'Points issued to a one-time invoice — they are not recorded in the store journal. To make points redeemable on the next visit, issue them to the customer\'s Bolt12 offer.';

  @override
  String get storeDoneButton => 'Done';

  @override
  String storePendingBadge(int count) {
    return 'Pending Points ($count)';
  }

  @override
  String get storePendingTitle => 'Pending Points';

  @override
  String get storePendingEmpty => 'No points are pending.';

  @override
  String storePendingEntryMeta(String time, String total) {
    return '$time • $total';
  }

  @override
  String get storePendingIssue => 'Issue';

  @override
  String get storePendingWaive => 'Cancel Issuance';

  @override
  String get storePendingWaiveTitle => 'Cancel Points Issuance?';

  @override
  String storePendingWaiveBody(String total, String time) {
    return 'The points from the $time sale (total $total) will NOT be issued to the customer. The sale record stays saved.';
  }

  @override
  String get storePendingWaived => 'Points issuance cancelled.';

  @override
  String get storeReceiptTotalPay => 'TOTAL TO PAY';

  @override
  String storeReceiptPointsDiscount(int points, String amount) {
    return 'Points redemption ($points pts) -Rp$amount';
  }

  @override
  String storeReceiptPointsEarned(int points) {
    return 'Nusan points earned: +$points points';
  }

  @override
  String storeReceiptPointsPending(int points) {
    return 'Nusan points earned: +$points points (not yet issued)';
  }

  @override
  String storeReceiptPointsRule(String rate) {
    return '1 nusan = Disc. Rp$rate';
  }

  @override
  String get storeReceiptPromo => 'No payment (promotion)';

  @override
  String get storeReceiptCustomer => 'Customer';

  @override
  String get storeReceiptDate => 'Date';

  @override
  String get storeReceiptBillNo => 'Bill No';

  @override
  String get storeReceiptTokenNo => 'Order/Outlet';

  @override
  String get storeReceiptItemHeader => 'Item';

  @override
  String get storeReceiptAmountHeader => 'Amount';

  @override
  String get storeReceiptOrderDiscount => 'Order Discount';

  @override
  String get storeReceiptLineDiscount => 'Item Disc.';

  @override
  String get storeReceiptGrandTotal => 'Pay';

  @override
  String get storeReceiptReprintBanner => '*** REPRINT ***';

  @override
  String get storeReceiptReprintLabel => 'Reprint';

  @override
  String get storeReceiptCashier => 'Cashier';

  @override
  String get storePayAmountLabel => 'Amount';

  @override
  String get storeAddPayMethod => 'Add Payment Method';

  @override
  String get storeNonCashOverNote =>
      'Non-cash methods cannot exceed the remaining total.';

  @override
  String get storeMethodSplit => 'Split';

  @override
  String get storeFilterToday => 'Today';

  @override
  String get storeFilterYesterday => 'Yesterday';

  @override
  String get storeReportIncome => 'Income';

  @override
  String get storeReportOpeningFloat => 'Float';

  @override
  String get storeReportCashPosition => 'Cash Position';

  @override
  String get storeReportHeldInfo => 'Held Orders';

  @override
  String get storeReportHeldTotal => 'Held Total ORDER';

  @override
  String get storeOpeningFloatTitle => 'Shift Opening Float';

  @override
  String get storeOpeningFloatHint =>
      'Cash in the drawer when the shift opens (for change). Rp0 is fine — only cash payments add to the drawer position; non-cash methods do not affect it.';

  @override
  String get storeOpeningFloatLabel => 'Drawer Float';

  @override
  String get storePayMethodsTitle => 'Non-Cash Payment Methods';

  @override
  String get storePayMethodsHint =>
      'Methods offered in the payment page dropdown (Cash is always available). Tap × to remove.';

  @override
  String get storePayMethodNameLabel => 'New Method Name';

  @override
  String get storePayMethodAdd => 'Add';

  @override
  String get storeTelegramTitle => 'Send Report via Telegram';

  @override
  String get storeTelegramHint =>
      'The shift report is sent to Telegram automatically when a shift is closed — straight from the app, no middleman server. Create a bot via @BotFather, then fill in its token and the destination chat ID below.';

  @override
  String get storeTelegramTokenLabel => 'Telegram Bot Token';

  @override
  String get storeTelegramTokenHint => 'From BotFather, e.g. 123456789:AA…';

  @override
  String get storeTelegramChatLabel => 'Destination Chat ID';

  @override
  String get storeTelegramChatHint =>
      'Numeric ID of the destination chat or group';

  @override
  String get storeTelegramSent => 'Shift report sent to Telegram.';

  @override
  String get storeTelegramFailed =>
      'Telegram report failed to send — check the connection & settings.';

  @override
  String get staticCodeLabelTitle => 'Payment Code Label';

  @override
  String get staticCodeLabelEdit => 'Edit Label';

  @override
  String get staticCodeLabelHint =>
      'This label is written into the payment code and seen by payers. Changing it creates a NEW payment code — share the new code again. Leave empty to return to the default label.';

  @override
  String storeReceiptPointsDiscountLabel(String points) {
    return 'Disc. ($points nusan)';
  }

  @override
  String get storeReceiptFooterDefault => 'Thank You\nPlease Visit Again';

  @override
  String get storeShareReceipt => 'Share Receipt';

  @override
  String get storeReceiptPreviewTitle => 'Receipt';

  @override
  String get storeShareReceiptFailed => 'Could not create the receipt image.';

  @override
  String get storeSettingsAddress => 'Store Address (receipt header line)';

  @override
  String get storeSettingsCity => 'Store City (receipt header line)';

  @override
  String get storeSettingsShowToken => 'Show Token Number on Receipt';

  @override
  String get storeSettingsShowTokenHint =>
      'Daily queue number on the receipt; restarts from 1 each day.';

  @override
  String get storeSettingsFooterText => 'Receipt Footer Text';

  @override
  String get storeSettingsFooterTextHint =>
      'Leave empty for the default text in the app language.';

  @override
  String get storeSettingsTitle => 'Store Settings';

  @override
  String get storeSettingsStoreName => 'Store Name';

  @override
  String get storeSettingsPointsEnabled => 'Nusan Points Program On';

  @override
  String get storeSettingsPointsHint =>
      'Points are a promotional bonus on rupiah purchases — not a payment method. Points are only redeemed as a discount at this store.';

  @override
  String get storeSettingsEarnStep => 'Earning Step (Rp)';

  @override
  String get storeSettingsEarnPoints => 'Points per Step';

  @override
  String get storeSettingsRedeemRate => 'Discount Value per Point (Rp)';

  @override
  String get storeSettingsMaxRedeem => 'Max Points Discount (% of total)';

  @override
  String get storeSettingsMaxRedeemHint =>
      'May be left empty = no cap beyond the remaining order total.';

  @override
  String storeSettingsEarnPreview(String step, int points) {
    return 'Example: an Rp$step purchase earns $points points.';
  }

  @override
  String get storeSettingsSave => 'Save Settings';

  @override
  String get storeSettingsSaved => 'Store settings saved.';

  @override
  String get storeSettingsInvalid =>
      'Check again: the step and discount value must be above 0; the max cap is 1–100 when filled.';

  @override
  String get storeRulesTitle => 'Points Program Rules';

  @override
  String get storeRulesButton => 'Point Rules';

  @override
  String get storeRulesHeading => 'Nusan Points — Store Promotional Bonus';

  @override
  String get storeRulesP1 =>
      'Nusan points are a promotional bonus from this store — not money and not a payment method. Purchases at this store are always paid in rupiah (cash or QRIS).';

  @override
  String get storeRulesP2 =>
      'Points are earned only from settled rupiah purchases, under the earning terms in effect at this store.';

  @override
  String get storeRulesP3 =>
      'Points can only be redeemed as a discount on purchases at this store, at the per-point discount value set by the store.';

  @override
  String get storeRulesP4 =>
      'Points cannot be cashed out, sold, bought, or exchanged for cash in any form.';

  @override
  String get storeRulesP5 =>
      'The per-point discount value and program terms may change with prior notice at this store.';

  @override
  String get storeRulesP6 =>
      'To receive and redeem points, customers use their own ELNUX app.';

  @override
  String get storeRulesP7 =>
      'When first receiving points, the customer\'s wallet may be charged a one-time receiving-path creation fee of 0.5% of the amount received (a network rule, charged only when the path is created).';

  @override
  String get storeRulesFooter =>
      'These terms follow the store\'s points program guidelines. Keep your purchase receipt as proof of points earned and redeemed.';

  @override
  String get storeMigrationTitle => 'Store Mode Updated';

  @override
  String get storeMigrationShiftClosed =>
      'An old shift (nusan pricing) that was still open has been closed and marked as legacy data. Sales are recorded in rupiah from now on.';

  @override
  String storeMigrationHeldDropped(int count) {
    return '$count held order(s) from the old version (nusan pricing) were dropped and not carried over.';
  }

  @override
  String get storeMigrationCatalog =>
      'The old nusan-priced catalog is no longer used. Refill the catalog with rupiah prices via the Manage button.';

  @override
  String get storeMigrationOk => 'Got It';

  @override
  String get storeReportCash => 'CASH';

  @override
  String get storeReportQris => 'QRIS';

  @override
  String get storeReportPointsDiscount => 'Points Discount';

  @override
  String get storeReportPointsIssued => 'Points Issued';

  @override
  String get storeReportPointsPending => 'Points Pending';

  @override
  String get storeReportPointsRedeemed => 'Points Redeemed';

  @override
  String get offlineSpike => 'Lightning Offline Test';

  @override
  String get offlineSpikeSubtitle =>
      'Connect two phones over Bluetooth (experimental)';

  @override
  String get offlineIntro =>
      'Stage 2 test: two ELNUX nodes connect as peers over a Bluetooth bridge, open a direct channel, then pay over Lightning while both phones are offline. Open the channel while the phones are side by side and the funder (the opening phone) is online; offline payments use a channel that is already ready. Turn on Bluetooth and Location services on both phones before starting.';

  @override
  String get offlineOwnNodeId => 'This Phone\'s Node ID';

  @override
  String get offlineNodeNotRunning => 'Node is not running yet';

  @override
  String get offlineCopy => 'Copy';

  @override
  String get offlineCopied => 'Node ID copied';

  @override
  String get offlineChooseRole => 'This Phone\'s Role';

  @override
  String get offlineRoleHost => 'Host (waits for a guest)';

  @override
  String get offlineRoleGuest => 'Guest (searches for a host)';

  @override
  String get offlineStop => 'Stop';

  @override
  String get offlineDiscoveredHosts => 'Discovered Hosts';

  @override
  String get offlineConnect => 'Connect';

  @override
  String get offlineHostNodeIdLabel => 'Host Node ID';

  @override
  String get offlineHostNodeIdHint => 'Paste the node ID from the host phone';

  @override
  String get offlineConnectNode => 'Connect Lightning Node';

  @override
  String get offlineScan => 'Scan QR';

  @override
  String get offlinePeersTitle => 'Lightning Peers';

  @override
  String get offlinePeerConnected => 'Connected';

  @override
  String get offlinePeerDisconnected => 'Disconnected';

  @override
  String get offlineNoPeers => 'No peers yet.';

  @override
  String get offlineChannelTitle => 'Direct Channel';

  @override
  String get offlineTargetPeer => 'Target peer';

  @override
  String get offlineNoTargetPeer => 'not known yet';

  @override
  String get offlineOnchainAddress =>
      'Node on-chain address (for channel funds)';

  @override
  String get offlineOnchainBalance => 'Spendable on-chain balance';

  @override
  String get offlineChannelAmount => 'Channel amount (nusan)';

  @override
  String get offlineOpenChannel => 'Open Channel';

  @override
  String get offlineOpenBlockedOfflineSession =>
      'This session started without internet, so the node has no chain access and a new channel\'s funding broadcast cannot reach the network. Restart the app with internet to open a channel.';

  @override
  String get offlineChannelPending => 'Awaiting confirmations';

  @override
  String get offlineConfirmations => 'Confirmations';

  @override
  String get offlineChannelReady => 'Ready';

  @override
  String get offlineChannelReadyPeerDown => 'Ready (peer disconnected)';

  @override
  String get offlineNoDirectChannels => 'No direct channels yet.';

  @override
  String get offlineChannelValue => 'Value';

  @override
  String get offlineOutbound => 'Out';

  @override
  String get offlineInbound => 'In';

  @override
  String get offlinePayTestTitle => 'Test Payment';

  @override
  String get offlineInvoiceAmount => 'Invoice amount (nusan)';

  @override
  String get offlineCreateInvoice => 'Create Invoice';

  @override
  String get offlineInvoiceToPay => 'Invoice to pay';

  @override
  String get offlinePayNow => 'Pay';

  @override
  String get offlineLogTitle => 'Test Log';

  @override
  String get offlineStatusIdle => 'Not started';

  @override
  String get offlineStatusAdvertising => 'Advertising as host…';

  @override
  String get offlineStatusDiscovering => 'Searching for hosts…';

  @override
  String get offlineStatusConnecting => 'Connecting the bridge…';

  @override
  String get offlineStatusLinked => 'Bridge linked';

  @override
  String get offlineStatusError => 'Error';
}
