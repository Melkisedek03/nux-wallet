import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/store_settings.dart';
import '../utils/format.dart';
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
    final invalid =
        step == null ||
        step <= 0 ||
        perStep == null ||
        perStep < 0 ||
        rate == null ||
        rate <= 0 ||
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
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
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
              ],
            ),
    );
  }
}
