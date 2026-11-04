import 'package:flutter/material.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../services/store_customers.dart';
import '../utils/bolt12_info.dart';
import 'scan_screen.dart';

/// Dialog tambah/ubah pelanggan Mode Toko: nama + offer
/// Bolt12 statis (ketik/tempel, atau pindai dari ELNUX
/// pelanggan). Mengembalikan (nama, offer) yang sudah
/// divalidasi bentuknya sebagai offer; null bila batal.
/// Penyimpanan adalah urusan pemanggil.
Future<({String name, String offer})?> showStoreCustomerEditDialog(
  BuildContext context, {
  StoreCustomer? existing,
  String? initialOffer,
}) {
  final nameController = TextEditingController(text: existing?.name ?? '');
  final offerController = TextEditingController(
    text: existing?.offer ?? initialOffer ?? '',
  );
  String? error;
  return showDialog<({String name, String offer})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        backgroundColor: ctx.palette.card,
        title: Text(
          existing == null
              ? ctx.l10n.storeCustomerAdd
              : ctx.l10n.storeCustomerTitle,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameController,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: ctx.l10n.storeCustomerNameLabel,
                  filled: true,
                  fillColor: ctx.palette.cardAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: offerController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: ctx.l10n.storeCustomerOfferLabel,
                  filled: true,
                  fillColor: ctx.palette.cardAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final raw = await Navigator.push<String>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => const ScanScreen(),
                      ),
                    );
                    if (raw == null || raw.trim().isEmpty) return;
                    offerController.text = raw.trim();
                    setLocal(() => error = null);
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  label: Text(ctx.l10n.storeCustomerScan),
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.redAccent,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final offer = offerController.text.trim();
              if (name.isEmpty) {
                setLocal(
                  () => error = ctx.l10n.storeOperatorNameRequired,
                );
                return;
              }
              if (parseOfferInfo(offer) == null) {
                setLocal(
                  () => error = ctx.l10n.storeCustomerInvalidOffer,
                );
                return;
              }
              Navigator.pop(ctx, (name: name, offer: offer));
            },
            child: Text(ctx.l10n.storeSettingsSave),
          ),
        ],
      ),
    ),
  );
}

/// Pemilih pelanggan (lembar bawah) untuk halaman
/// Penyelesaian Pembayaran: daftar pelanggan tersimpan —
/// ketuk satu untuk memakai offer-nya. Baris tambahan:
/// tambah pelanggan baru (dialog edit → simpan → langsung
/// terpilih) dan kelola pelanggan (layar penuh; kembali dari
/// sana pemilih tertutup tanpa pilihan). [subtitleFor]
/// memberi teks pendamping per pelanggan (mis. saldo jurnal
/// poinnya). Mengembalikan pelanggan terpilih atau null.
Future<StoreCustomer?> showStoreCustomerPicker(
  BuildContext context, {
  required String? Function(StoreCustomer customer) subtitleFor,
}) async {
  final store = StoreCustomerStore();
  final customers = await store.loadAll();
  if (!context.mounted) return null;
  final l10n = context.l10n;
  return showModalBottomSheet<StoreCustomer>(
    context: context,
    backgroundColor: context.palette.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Text(
                l10n.storeCustomerChoose,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (customers.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                child: Text(
                  l10n.storeCustomerEmpty,
                  style: TextStyle(color: ctx.palette.muted, fontSize: 13),
                ),
              ),
            for (final customer in customers)
              ListTile(
                leading: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFF34D399),
                ),
                title: Text(
                  customer.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: subtitleFor(customer) == null
                    ? null
                    : Text(subtitleFor(customer)!),
                onTap: () => Navigator.pop(ctx, customer),
              ),
            const Divider(height: 16),
            ListTile(
              leading: const Icon(Icons.person_add_rounded),
              title: Text(l10n.storeCustomerAdd),
              onTap: () async {
                final draft = await showStoreCustomerEditDialog(ctx);
                if (draft == null || !ctx.mounted) return;
                final created = await store.add(
                  name: draft.name,
                  offer: draft.offer,
                );
                if (ctx.mounted) Navigator.pop(ctx, created);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_rounded),
              title: Text(l10n.storeCustomerManage),
              onTap: () async {
                await Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => const StoreCustomersScreen(),
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Kelola Pelanggan Mode Toko: daftar pelanggan tersimpan
/// (nama + offer statis), tambah/ubah/hapus. Sampai di sini
/// dari Pengaturan Toko atau dari pemilih pelanggan di
/// halaman Penyelesaian Pembayaran.
class StoreCustomersScreen extends StatefulWidget {
  const StoreCustomersScreen({super.key});

  @override
  State<StoreCustomersScreen> createState() => _StoreCustomersScreenState();
}

class _StoreCustomersScreenState extends State<StoreCustomersScreen> {
  final _store = StoreCustomerStore();
  List<StoreCustomer> _customers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final customers = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _customers = customers;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final draft = await showStoreCustomerEditDialog(context);
    if (draft == null || !mounted) return;
    await _store.add(name: draft.name, offer: draft.offer);
    if (mounted) _load();
  }

  Future<void> _edit(StoreCustomer customer) async {
    final draft = await showStoreCustomerEditDialog(
      context,
      existing: customer,
    );
    if (draft == null || !mounted) return;
    await _store.update(
      customer.copyWith(name: draft.name, offer: draft.offer),
    );
    if (mounted) _load();
  }

  Future<void> _delete(StoreCustomer customer) async {
    await _store.delete(customer.id);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.storeCustomerTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _add,
            icon: const Icon(Icons.person_add_rounded),
            tooltip: l10n.storeCustomerAdd,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF34D399)),
            )
          : _customers.isEmpty
              ? Center(
                  child: Text(
                    l10n.storeCustomerEmpty,
                    style: TextStyle(color: context.palette.muted),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  children: [
                    for (final customer in _customers)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: context.palette.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.palette.border),
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF34D399),
                          ),
                          title: Text(
                            customer.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            customer.offer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') _edit(customer);
                              if (value == 'delete') _delete(customer);
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(l10n.storeCustomerEdit),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(l10n.storeCustomerDelete),
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
