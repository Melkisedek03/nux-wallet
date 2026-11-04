import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/store_operators.dart';

/// Dialog entri PIN 6 digit bersama (login operator, override
/// admin, dan layar kelola operator). Mengembalikan PIN yang
/// dimasukkan (bentuknya sudah divalidasi 6 digit angka) atau
/// null bila dibatalkan. Verifikasi PIN terhadap simpanan
/// adalah urusan pemanggil — dialog ini hanya mengumpulkan.
Future<String?> showStorePinDialog(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final controller = TextEditingController();
      String? error;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: ctx.palette.card,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                body,
                style: TextStyle(fontSize: 13, color: ctx.palette.muted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(storePinLength),
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  letterSpacing: 6,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  errorText: error,
                  filled: true,
                  fillColor: ctx.palette.cardAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) {
                  if (isValidStorePin(controller.text)) {
                    Navigator.pop(ctx, controller.text);
                  } else {
                    setLocal(
                      () => error = ctx.l10n.storeOperatorPinInvalid,
                    );
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                if (isValidStorePin(controller.text)) {
                  Navigator.pop(ctx, controller.text);
                } else {
                  setLocal(
                    () => error = ctx.l10n.storeOperatorPinInvalid,
                  );
                }
              },
              child: Text(ctx.l10n.storeOperatorLoginButton),
            ),
          ],
        ),
      );
    },
  );
}

/// Gerbang operator Mode Toko (Fase A): selama belum ada sesi
/// operator, badan layar Mode Toko adalah panel ini.
///
/// Dua keadaan:
/// - Belum ada operator AKTIF sama sekali → formulir pembuatan
///   akun OWNER pertama (nama + PIN 6 digit + ulangi PIN).
///   Keadaan ini juga jalur pemulihan kunci total (semua akun
///   nonaktif): perangkat fisik di tangan = wewenang memulih —
///   konsisten dengan model akuntabilitas Fase A.
/// - Sudah ada operator → daftar operator aktif; ketuk nama →
///   dialog PIN → sesi dimulai (pemanggil menerima operator
///   lewat [onLoggedIn]) dan login tercatat di log audit.
class StoreOperatorGate extends StatefulWidget {
  const StoreOperatorGate({
    super.key,
    required this.operatorStore,
    required this.auditStore,
    required this.onLoggedIn,
    required this.onExit,
  });

  final StoreOperatorStore operatorStore;
  final StoreAuditStore auditStore;

  /// Sesi operator dimulai; pemanggil mengganti badan layar.
  final ValueChanged<StoreOperator> onLoggedIn;

  /// Keluar dari Mode Toko tanpa login.
  final VoidCallback onExit;

  @override
  State<StoreOperatorGate> createState() => _StoreOperatorGateState();
}

class _StoreOperatorGateState extends State<StoreOperatorGate> {
  List<StoreOperator>? _operators;
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinConfirmController = TextEditingController();
  String? _setupError;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    _pinConfirmController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await widget.operatorStore.loadAll();
    if (!mounted) return;
    setState(() => _operators = [for (final o in all) if (o.active) o]);
  }

  Future<void> _createOwner() async {
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    final pin = _pinController.text;
    if (name.isEmpty) {
      setState(() => _setupError = l10n.storeOperatorNameRequired);
      return;
    }
    if (!isValidStorePin(pin)) {
      setState(() => _setupError = l10n.storeOperatorPinInvalid);
      return;
    }
    if (pin != _pinConfirmController.text) {
      setState(() => _setupError = l10n.storeOperatorPinMismatch);
      return;
    }
    setState(() {
      _creating = true;
      _setupError = null;
    });
    final op = await widget.operatorStore.create(
      name: name,
      role: storeRoleOwner,
      pin: pin,
    );
    await widget.auditStore.append(
      operator: op,
      action: StoreAuditAction.operatorCreated,
      detail: op.name,
    );
    await widget.auditStore.append(
      operator: op,
      action: StoreAuditAction.login,
    );
    if (!mounted) return;
    widget.onLoggedIn(op);
  }

  Future<void> _loginAs(StoreOperator op) async {
    final pin = await showStorePinDialog(
      context,
      title: op.name,
      body: context.l10n.storeOperatorPinLabel,
    );
    if (pin == null || !mounted) return;
    final verified = await widget.operatorStore.verifyPin(op.id, pin);
    if (!mounted) return;
    if (verified == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.storeOperatorWrongPin)),
      );
      return;
    }
    await widget.auditStore.append(
      operator: verified,
      action: StoreAuditAction.login,
    );
    if (!mounted) return;
    widget.onLoggedIn(verified);
  }

  @override
  Widget build(BuildContext context) {
    final operators = _operators;
    if (operators == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: context.palette.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.palette.border),
          ),
          child: operators.isEmpty
              ? _buildSetup(context)
              : _buildLoginList(context, operators),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: widget.onExit,
          child: Text(context.l10n.storeBack),
        ),
      ],
    );
  }

  Widget _buildSetup(BuildContext context) {
    final l10n = context.l10n;
    InputDecoration field(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: context.palette.cardAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.admin_panel_settings_rounded,
          size: 44,
          color: Color(0xFF34D399),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.storeOperatorSetupTitle,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.storeOperatorSetupBody,
          style: TextStyle(fontSize: 13, color: context.palette.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _nameController,
          decoration: field(l10n.storeOperatorNameLabel),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(storePinLength),
          ],
          decoration: field(l10n.storeOperatorPinLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pinConfirmController,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(storePinLength),
          ],
          decoration: field(l10n.storeOperatorPinConfirmLabel),
        ),
        if (_setupError != null) ...[
          const SizedBox(height: 10),
          Text(
            _setupError!,
            style: const TextStyle(fontSize: 13, color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 18),
        ElevatedButton(
          onPressed: _creating ? null : _createOwner,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            l10n.storeOperatorLoginButton,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginList(
    BuildContext context,
    List<StoreOperator> operators,
  ) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.lock_person_rounded,
          size: 44,
          color: Color(0xFF34D399),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.storeOperatorLoginTitle,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        for (final op in operators)
          ListTile(
            leading: Icon(
              op.isOwner
                  ? Icons.admin_panel_settings_rounded
                  : Icons.point_of_sale_rounded,
              color: const Color(0xFF34D399),
            ),
            title: Text(
              op.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              op.isOwner
                  ? l10n.storeOperatorRoleOwner
                  : l10n.storeOperatorRoleCashier,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _loginAs(op),
          ),
      ],
    );
  }
}
