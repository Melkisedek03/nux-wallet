import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../locale_controller.dart';
import '../services/store_receipt_image.dart';
import '../utils/store_receipt.dart';

/// Pratinjau struk pelanggan Mode Toko + berbagi sebagai
/// gambar. Widget struknya (latar putih, teks hitam monospace)
/// dirender dari urutan elemen yang SAMA dengan cetak kertas
/// (lib/utils/store_receipt.dart), jadi yang dilihat kasir di
/// pratinjau adalah struk yang sama dengan yang tercetak dan
/// yang dibagikan.
///
/// Berbagi: tangkap RepaintBoundary → PNG → konversi JPG
/// (store_receipt_image.dart; fallback PNG) → share sheet
/// sistem lewat SharePlus (pola berbagi yang sudah dipakai
/// aplikasi).
class StoreReceiptPreviewDialog extends StatefulWidget {
  const StoreReceiptPreviewDialog({super.key, required this.elements});

  final List<StoreReceiptElement> elements;

  @override
  State<StoreReceiptPreviewDialog> createState() =>
      _StoreReceiptPreviewDialogState();
}

class _StoreReceiptPreviewDialogState
    extends State<StoreReceiptPreviewDialog> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary =
          _boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('pratinjau belum siap');
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('tangkapan kosong');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final file = await writeReceiptShareImage(
        byteData.buffer.asUint8List(),
        fileStem: 'struk-elnux-$stamp',
      );
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.storeShareReceiptFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.storeReceiptPreviewTitle),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      content: SingleChildScrollView(
        child: RepaintBoundary(
          key: _boundaryKey,
          child: _ReceiptCard(elements: widget.elements),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sharing ? null : () => Navigator.pop(context),
          child: Text(l10n.storeDoneButton),
        ),
        ElevatedButton.icon(
          onPressed: _sharing ? null : _share,
          icon: _sharing
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.share_rounded, size: 18),
          label: Text(l10n.storeShareReceipt),
        ),
      ],
    );
  }
}

/// Kartu struk bergaya kertas: putih, hitam, monospace, lebar
/// tetap wajar. Nama toko tampil besar proporsional (peran
/// double-height pada cetak kertas); Grand Total paling besar.
class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.elements});

  final List<StoreReceiptElement> elements;

  static const _base = TextStyle(
    fontFamily: 'monospace',
    color: Colors.black,
    fontSize: 13,
    height: 1.4,
  );

  Widget _forElement(StoreReceiptElement e) {
    switch (e) {
      case ReceiptCenterText(:final text, :final bold, :final big):
        return Text(
          text,
          textAlign: TextAlign.center,
          style: _base.copyWith(
            fontSize: big ? 23 : 13,
            fontWeight: big || bold ? FontWeight.w800 : FontWeight.w400,
          ),
        );
      case ReceiptDashedRule():
        return Text(
          '-' * 48,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: _base.copyWith(fontSize: 11),
        );
      case ReceiptMetaRow(:final label, :final value, :final spread):
        if (spread) {
          return Row(
            children: [
              Text('$label:', style: _base),
              const Spacer(),
              Text(
                value,
                style: _base.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label panjang ("No. Token/Outlet ID:") mendapat
            // kotak lebih lebar — label pendek tetap sejajar
            // seperti sebelumnya.
            SizedBox(
              width: label.length > 12 ? 164 : 98,
              child: Text('$label:', style: _base, maxLines: 1),
            ),
            Expanded(child: Text(value, style: _base)),
          ],
        );
      case ReceiptItemsHeader(:final itemLabel, :final amountLabel):
        return Row(
          children: [
            Text(
              itemLabel,
              style: _base.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text(
              amountLabel,
              style: _base.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        );
      case ReceiptItemRow(:final name, :final amountText):
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                name,
                style: _base,
                // Nama item selalu satu baris — tidak mendorong
                // kolom jumlah (nama sudah terpangkas dari
                // pembangun; elipsis hanya pengaman tampilan).
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Text(amountText, style: _base),
          ],
        );
      case ReceiptItemSub(:final text):
        return Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Text(text, style: _base.copyWith(fontSize: 12)),
        );
      case ReceiptRow(:final label, :final amountText, :final bold):
        final style = _base.copyWith(
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: style)),
            const SizedBox(width: 10),
            Text(amountText, style: style),
          ],
        );
      case ReceiptGrandTotal(:final label, :final amountText):
        final style = _base.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w900,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: Text(label, style: style)),
            const SizedBox(width: 10),
            Text(amountText, style: style),
          ],
        );
      case ReceiptTextLine(:final text):
        return Text(text, style: _base);
      case ReceiptSpacer():
        return const SizedBox(height: 18);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [for (final e in elements) _forElement(e)],
      ),
    );
  }
}
