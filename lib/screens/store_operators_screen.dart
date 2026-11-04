import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/store_operators.dart';
import '../utils/store_receipt.dart' show receiptTimestampText;

/// Kelola Operator Mode Toko (Fase A): daftar akun operator,
/// tambah operator (nama + peran + PIN 6 digit), ganti PIN,
/// aktif/nonaktifkan. Layar ini hanya bisa dicapai dari
/// Pengaturan Toko yang sudah berada di balik gerbang PIN
/// admin layar Mode Toko.
///
/// Pengaman dasar: owner aktif terakhir tidak bisa
/// dinonaktifkan (toko tidak boleh kehilangan adminnya).
class StoreOperatorsScreen extends StatefulWidget {
  const StoreOperatorsScreen({super.key});

  @override
  State<StoreOperatorsScreen> createState() => _StoreOperatorsScreenState();
}

class _StoreOperatorsScreenState extends State<StoreOperatorsScreen> {
  final _store = StoreOperatorStore();
  final _audit = StoreAuditStore();
  List<StoreOperator> _operators = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ops = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _operators = ops;
      _loading = false;
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addOperator() async {
    final l10n = context.l10n;
    final nameController = TextEditingController();
    final pinController = TextEditingController();
    final pinConfirmController = TextEditingController();
    var role = storeRoleCashier;
    String? error;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: ctx.palette.card,
          title: Text(l10n.storeOperatorAdd),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: l10n.storeOperatorNameLabel,
                    filled: true,
                    fillColor: ctx.palette.cardAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: storeRoleCashier,
                      label: Text(l10n.storeOperatorRoleCashier),
                    ),
                    ButtonSegment(
                      value: storeRoleOwner,
                      label: Text(l10n.storeOperatorRoleOwner),
                    ),
                  ],
                  selected: {role},
                  onSelectionChanged: (s) => setLocal(() => role = s.first),
                ),
                const SizedBox(height: 12),
                _pinField(pinController, l10n.storeOperatorPinLabel),
                const SizedBox(height: 12),
                _pinField(
                  pinConfirmController,
                  l10n.storeOperatorPinConfirmLabel,
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                final pin = pinController.text;
                if (name.isEmpty) {
                  setLocal(() => error = l10n.storeOperatorNameRequired);
                  return;
                }
                if (!isValidStorePin(pin)) {
                  setLocal(() => error = l10n.storeOperatorPinInvalid);
                  return;
                }
                if (pin != pinConfirmController.text) {
                  setLocal(() => error = l10n.storeOperatorPinMismatch);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(l10n.storeOperatorAdd),
            ),
          ],
        ),
      ),
    );
    if (created != true || !mounted) return;
    final op = await _store.create(
      name: nameController.text.trim(),
      role: role,
      pin: pinController.text,
    );
    await _audit.append(
      operator: null,
      action: StoreAuditAction.operatorCreated,
      detail: '${op.name} (${op.role})',
    );
    nameController.dispose();
    pinController.dispose();
    pinConfirmController.dispose();
    if (mounted) _load();
  }

  Widget _pinField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(storePinLength),
      ],
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: context.palette.cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Future<void> _resetPin(StoreOperator op) async {
    final l10n = context.l10n;
    final pinController = TextEditingController();
    final pinConfirmController = TextEditingController();
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: ctx.palette.card,
          title: Text('${l10n.storeOperatorResetPin} — ${op.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pinField(pinController, l10n.storeOperatorPinLabel),
              const SizedBox(height: 12),
              _pinField(pinConfirmController, l10n.storeOperatorPinConfirmLabel),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(
                  error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                final pin = pinController.text;
                if (!isValidStorePin(pin)) {
                  setLocal(() => error = l10n.storeOperatorPinInvalid);
                  return;
                }
                if (pin != pinConfirmController.text) {
                  setLocal(() => error = l10n.storeOperatorPinMismatch);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(l10n.storeSettingsSave),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    await _store.setPin(op.id, pinController.text);
    await _audit.append(
      operator: null,
      action: StoreAuditAction.pinChanged,
      detail: op.name,
    );
    pinController.dispose();
    pinConfirmController.dispose();
  }

  Future<void> _toggleActive(StoreOperator op) async {
    final l10n = context.l10n;
    if (op.active && op.isOwner) {
      final otherActiveOwners = _operators
          .where((o) => o.isOwner && o.active && o.id != op.id)
          .length;
      if (otherActiveOwners == 0) {
        _snack(l10n.storeOperatorLastOwner);
        return;
      }
    }
    await _store.update(op.copyWith(active: !op.active));
    await _audit.append(
      operator: null,
      action: StoreAuditAction.operatorUpdated,
      detail: '${op.name} → ${op.active ? 'inactive' : 'active'}',
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storeOperatorsTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _addOperator,
            icon: const Icon(Icons.person_add_rounded),
            tooltip: l10n.storeOperatorAdd,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF34D399)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              children: [
                for (final op in _operators)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: context.palette.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.palette.border),
                    ),
                    child: ListTile(
                      leading: Icon(
                        op.isOwner
                            ? Icons.admin_panel_settings_rounded
                            : Icons.point_of_sale_rounded,
                        color: op.active
                            ? const Color(0xFF34D399)
                            : context.palette.muted,
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!op.active)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: context.palette.cardAlt,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                l10n.storeOperatorInactiveBadge,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: context.palette.muted,
                                ),
                              ),
                            ),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'pin') _resetPin(op);
                              if (value == 'toggle') _toggleActive(op);
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'pin',
                                child: Text(l10n.storeOperatorResetPin),
                              ),
                              PopupMenuItem(
                                value: 'toggle',
                                child: Text(
                                  op.active
                                      ? l10n.storeOperatorDeactivate
                                      : l10n.storeOperatorActivate,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Log Aktivitas Mode Toko (Fase A): penampil baca-saja log
/// audit append-only — login, ganti operator, buka/tutup
/// shift, override admin, VOID penjualan, dan perubahan akun.
/// Baris terbaru di depan.
class StoreAuditScreen extends StatefulWidget {
  const StoreAuditScreen({super.key});

  @override
  State<StoreAuditScreen> createState() => _StoreAuditScreenState();
}

class _StoreAuditScreenState extends State<StoreAuditScreen> {
  final _audit = StoreAuditStore();
  List<StoreAuditEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _audit.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  String _actionLabel(BuildContext context, String action) {
    final l10n = context.l10n;
    return switch (action) {
      StoreAuditAction.login => l10n.storeAuditLogin,
      StoreAuditAction.logout => l10n.storeAuditLogout,
      StoreAuditAction.operatorCreated => l10n.storeAuditOperatorCreated,
      StoreAuditAction.operatorUpdated => l10n.storeAuditOperatorUpdated,
      StoreAuditAction.pinChanged => l10n.storeAuditPinChanged,
      StoreAuditAction.shiftOpen => l10n.storeAuditShiftOpen,
      StoreAuditAction.shiftClose => l10n.storeAuditShiftClose,
      StoreAuditAction.adminOverride => l10n.storeAuditAdminOverride,
      StoreAuditAction.saleVoid => l10n.storeAuditSaleVoid,
      _ => action,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storeAuditTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF34D399)),
            )
          : _entries.isEmpty
              ? Center(
                  child: Text(
                    l10n.storeAuditEmpty,
                    style: TextStyle(color: context.palette.muted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  itemCount: _entries.length,
                  itemBuilder: (context, i) {
                    final entry = _entries[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: context.palette.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.palette.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _actionLabel(context, entry.action),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                receiptTimestampText(entry.time),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.palette.muted,
                                ),
                              ),
                            ],
                          ),
                          if (entry.operatorName.isNotEmpty)
                            Text(
                              entry.operatorName,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.palette.muted,
                              ),
                            ),
                          if (entry.detail.isNotEmpty)
                            Text(
                              entry.detail,
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
