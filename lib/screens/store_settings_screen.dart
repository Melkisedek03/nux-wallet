import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/store_settings.dart';
import '../utils/format.dart';
import 'store_customers_screen.dart';
import 'store_operators_screen.dart';
import 'store_point_rules_screen.dart';

/// Layar Pengaturan Toko Mode Toko v2: nama toko (kop struk)
/// dan parameter program poin nusan milik toko ini.
///
/// Semua angka adalah kebijakan toko sendiri (pedoman miniPOS):
/// kelipatan perolehan & poin per kelipatan menentukan poin yang
/// lahir dari belanja rupiah; nilai potongan per poin adalah
/// aturan diskon saat poin ditukar (BUKAN kurs); batas maksimum
/// membatasi diskon poin per transaksi. Menyimpan menulis ke
/// [StoreSettingsStore]; layar Mode Toko membaca ulang
/// pengaturan ini saat kembali dari layar ini.
class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  final _store = StoreSettingsStore();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stepController = TextEditingController();
  final _perStepController = TextEditingController();
  final _rateController = TextEditingController();
  final _maxPercentController = TextEditingController();
  final _footerController = TextEditingController();
  final _thresholdController = TextEditingController();
  final _methodController = TextEditingController();
  final _tgTokenController = TextEditingController();
  final _tgChatController = TextEditingController();

  /// Master metode bayar non-tunai yang sedang disunting.
  List<String> _methods = const [];
  bool _pointsEnabled = true;
  bool _showToken = true;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pratinjau perolehan mengikuti ketikan kasir.
    _stepController.addListener(_refreshPreview);
    _perStepController.addListener(_refreshPreview);
    _load();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stepController.dispose();
    _perStepController.dispose();
    _rateController.dispose();
    _maxPercentController.dispose();
    _footerController.dispose();
    _thresholdController.dispose();
    _methodController.dispose();
    _tgTokenController.dispose();
    _tgChatController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await _store.load();
    if (!mounted) return;
    setState(() {
      _nameController.text = settings.storeName;
      _addressController.text = settings.storeAddress;
      _cityController.text = settings.storeCity;
      _pointsEnabled = settings.pointsEnabled;
      _stepController.text = settings.earnStepRp.toString();
      _perStepController.text = settings.earnPointsPerStep.toString();
      _rateController.text = settings.redeemRateRp.toString();
      _maxPercentController.text =
          settings.maxRedeemPercent?.toString() ?? '';
      _footerController.text = settings.receiptFooterText;
      _showToken = settings.showTokenNumber;
      _thresholdController.text =
          settings.adminDiscountThresholdPercent.toString();
      _methods = List.of(settings.paymentMethods);
      _tgTokenController.text = settings.telegramBotToken;
      _tgChatController.text = settings.telegramChatId;
      _loading = false;
    });
  }

  int? _parseField(TextEditingController c) =>
      int.tryParse(c.text.replaceAll('.', '').replaceAll(',', '').trim());

  Future<void> _save() async {
    final l10n = context.l10n;
    final step = _parseField(_stepController);
    final perStep = _parseField(_perStepController);
    final rate = _parseField(_rateController);
    final maxRaw = _maxPercentController.text.trim();
    final maxPercent = maxRaw.isEmpty ? null : int.tryParse(maxRaw);
    final threshold = _parseField(_thresholdController);
    final invalid =
        step == null ||
        step <= 0 ||
        perStep == null ||
        perStep < 0 ||
        rate == null ||
        rate <= 0 ||
        threshold == null ||
        threshold < 0 ||
        threshold > 100 ||
        (maxRaw.isNotEmpty &&
            (maxPercent == null || maxPercent < 1 || maxPercent > 100));
    if (invalid) {
      setState(() => _error = l10n.storeSettingsInvalid);
      return;
    }
    final settings = StoreSettings(
      storeName: _nameController.text.trim(),
      pointsEnabled: _pointsEnabled,
      earnStepRp: step,
      earnPointsPerStep: perStep,
      redeemRateRp: rate,
      maxRedeemPercent: maxPercent,
      storeAddress: _addressController.text.trim(),
      storeCity: _cityController.text.trim(),
      showTokenNumber: _showToken,
      receiptFooterText: _footerController.text.trim(),
      adminDiscountThresholdPercent: threshold,
      paymentMethods: normalizePaymentMethods(_methods),
      telegramBotToken: _tgTokenController.text.trim(),
      telegramChatId: _tgChatController.text.trim(),
    );
    await _store.save(settings);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.storeSettingsSaved)));
    Navigator.pop(context);
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        filled: true,
        fillColor: context.palette.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storeSettingsTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF34D399)),
            )
          : ListView(
              // Atas 18 (bukan 4): field pertama tidak tertutup
              // AppBar transparan — pelajaran yang sama seperti
              // halaman Penyelesaian Pembayaran (temuan NUX
              // 4 Nov 2026).
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              children: [
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: l10n.storeSettingsStoreName,
                    filled: true,
                    fillColor: context.palette.cardAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: l10n.storeSettingsAddress,
                    filled: true,
                    fillColor: context.palette.cardAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cityController,
                  decoration: InputDecoration(
                    labelText: l10n.storeSettingsCity,
                    filled: true,
                    fillColor: context.palette.cardAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.storeSettingsPointsEnabled,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Switch(
                      value: _pointsEnabled,
                      onChanged: (v) => setState(() => _pointsEnabled = v),
                    ),
                  ],
                ),
                Text(
                  l10n.storeSettingsPointsHint,
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
                const SizedBox(height: 16),
                _numberField(
                  controller: _stepController,
                  label: l10n.storeSettingsEarnStep,
                  suffix: 'Rp',
                ),
                const SizedBox(height: 12),
                _numberField(
                  controller: _perStepController,
                  label: l10n.storeSettingsEarnPoints,
                ),
                const SizedBox(height: 12),
                _numberField(
                  controller: _rateController,
                  label: l10n.storeSettingsRedeemRate,
                  suffix: 'Rp',
                ),
                const SizedBox(height: 12),
                _numberField(
                  controller: _maxPercentController,
                  label: l10n.storeSettingsMaxRedeem,
                  hint: l10n.storeSettingsMaxRedeemHint,
                  suffix: '%',
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.storeSettingsEarnPreview(
                    formatRupiah(_parseField(_stepController) ?? 0),
                    _parseField(_perStepController) ?? 0,
                  ),
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _footerController,
                  decoration: InputDecoration(
                    labelText: l10n.storeSettingsFooterText,
                    hintText: l10n.storeSettingsFooterTextHint,
                    filled: true,
                    fillColor: context.palette.cardAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.storeSettingsShowToken,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Switch(
                      value: _showToken,
                      onChanged: (v) => setState(() => _showToken = v),
                    ),
                  ],
                ),
                Text(
                  l10n.storeSettingsShowTokenHint,
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
                const SizedBox(height: 22),
                Text(
                  l10n.storeSettingsAdminSection,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _numberField(
                  controller: _thresholdController,
                  label: l10n.storeSettingsDiscountThresholdLabel,
                  suffix: '%',
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.storeSettingsDiscountThresholdHint,
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
                const SizedBox(height: 22),
                // Master metode bayar non-tunai (permintaan
                // NUX 5 Nov 2026): tampil sebagai pilihan
                // dropdown di halaman pembayaran.
                Text(
                  l10n.storePayMethodsTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.storePayMethodsHint,
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final method in _methods)
                      Chip(
                        label: Text(method),
                        onDeleted: () =>
                            setState(() => _methods.remove(method)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _methodController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: l10n.storePayMethodNameLabel,
                          filled: true,
                          fillColor: context.palette.cardAlt,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () {
                        final name = _methodController.text.trim();
                        if (name.isEmpty) return;
                        final next = normalizePaymentMethods([
                          ..._methods,
                          name,
                        ]);
                        _methodController.clear();
                        setState(() => _methods = next);
                      },
                      child: Text(l10n.storePayMethodAdd),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                // Kirim Laporan via Telegram (hanya admin —
                // layar ini bergerbang PIN): token bot dari
                // BotFather + id chat owner; laporan terkirim
                // saat shift ditutup.
                Text(
                  l10n.storeTelegramTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.storeTelegramHint,
                  style: TextStyle(fontSize: 12, color: context.palette.muted),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _tgTokenController,
                  decoration: InputDecoration(
                    labelText: l10n.storeTelegramTokenLabel,
                    hintText: l10n.storeTelegramTokenHint,
                    filled: true,
                    fillColor: context.palette.cardAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tgChatController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.storeTelegramChatLabel,
                    hintText: l10n.storeTelegramChatHint,
                    filled: true,
                    fillColor: context.palette.cardAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    l10n.storeSettingsSave,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StorePointRulesScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.info_outline_rounded, size: 19),
                  label: Text(l10n.storeRulesButton),
                ),
                // Kelola operator & log aktivitas (Fase A) —
                // layar ini sendiri sudah di balik gerbang PIN
                // admin dari layar Mode Toko.
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StoreOperatorsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.people_rounded, size: 19),
                  label: Text(l10n.storeOperatorsTitle),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StoreAuditScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.fact_check_rounded, size: 19),
                  label: Text(l10n.storeAuditTitle),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StoreCustomersScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.person_rounded, size: 19),
                  label: Text(l10n.storeCustomerTitle),
                ),
              ],
            ),
    );
  }
}
