/// Layar kebijakan privasi ELNUX — WebView di dalam aplikasi.
///
/// Dua mode (keputusan NUX 25 Nov 2026):
///
/// * [PrivacyPolicyScreen.consent] — gerbang sekali sesudah instalasi
///   (ditampilkan sesudah boot, sebelum layar frasa backup dompet baru).
///   Centangan persetujuan AKTIF hanya sesudah user menggulir kebijakan
///   sampai bawah; tombol Lanjut aktif hanya sesudah centangan dicentang.
///   Layar tidak bisa di-back (PopScope) — persetujuan dicatat pemanggil
///   lewat nilai pop `true`. Bila halaman gagal dimuat (mis. tanpa
///   internet), tersedia Muat Ulang + Lewati untuk sekarang — lewati
///   TIDAK mencatat persetujuan, gerbang tampil lagi saat buka
///   berikutnya, supaya user luring tidak pernah terkunci dari dompetnya.
/// * [PrivacyPolicyScreen.read] — mode baca dari tautan di kaki tab
///   Profil: hanya WebView, tanpa centangan/tombol.
///
/// Deteksi "sampai bawah" dilakukan di dalam halaman lewat JavaScript
/// (channel `ScrollBottom` + pengait scroll yang dipasang tiap halaman
/// selesai dimuat); aturan ambangnya — termasuk kasus konten muat
/// tanpa guliran — hidup di [isScrolledToBottom] (diuji unit).
///
/// Untuk keterujian, tampilan kebijakan disuntik lewat
/// [policyViewBuilder] (bawaan: WebView sungguhan); tes memakai
/// tampilan palsu yang memanggil balik [onReachedBottom]/[onLoadFailed].
library;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../locale_controller.dart';
import '../theme.dart';
import '../utils/privacy_policy.dart';

/// Pembangun tampilan kebijakan: menerima URL + tiga balik-panggil
/// dari layar (halaman sampai bawah / gagal muat / mulai muat ulang).
typedef PrivacyPolicyViewBuilder =
    Widget Function(
      BuildContext context, {
      required String url,
      required VoidCallback onReachedBottom,
      required VoidCallback onLoadFailed,
      required VoidCallback onLoadStarted,
    });

class PrivacyPolicyScreen extends StatefulWidget {
  final bool consentMode;
  final PrivacyPolicyViewBuilder? policyViewBuilder;

  /// Gerbang persetujuan sesudah instalasi.
  const PrivacyPolicyScreen.consent({super.key, this.policyViewBuilder})
    : consentMode = true;

  /// Mode baca (tautan di kaki Profil).
  const PrivacyPolicyScreen.read({super.key, this.policyViewBuilder})
    : consentMode = false;

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  bool _reachedBottom = false;
  bool _checked = false;
  bool _loadFailed = false;
  bool _loading = true;

  void _onReachedBottom() {
    if (!_reachedBottom && mounted) setState(() => _reachedBottom = true);
  }

  void _onLoadFailed() {
    if (mounted) {
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  void _onLoadStarted() {
    if (mounted) {
      setState(() {
        // Halaman baru (mis. pindah bahasa lewat tautan di halaman):
        // persetujuan mengacu pada halaman yang sedang dibaca, jadi
        // kemajuan gulir + centangan diulang dari awal.
        _loadFailed = false;
        _loading = true;
        _reachedBottom = false;
        _checked = false;
      });
    }
  }

  void _onPageFinished() {
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final url = privacyPolicyUrlFor(
      Localizations.localeOf(context).languageCode,
    );
    final viewBuilder = widget.policyViewBuilder ?? _defaultViewBuilder;
    final body = Column(
      children: [
        if (_loading && !_loadFailed)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _loadFailed
              ? _LoadFailedView(
                  onRetry: () {
                    // Muat ulang = halaman baru: balik-panggil
                    // onLoadStarted di WebView mereset keadaan.
                    setState(() => _loadFailed = false);
                  },
                  onSkip: widget.consentMode
                      ? () => Navigator.pop(context, false)
                      : null,
                )
              : viewBuilder(
                  context,
                  url: url,
                  onReachedBottom: _onReachedBottom,
                  onLoadFailed: _onLoadFailed,
                  onLoadStarted: _onLoadStarted,
                ),
        ),
        if (widget.consentMode && !_loadFailed) _ConsentBar(
          reachedBottom: _reachedBottom,
          checked: _checked,
          onCheckedChanged: _reachedBottom
              ? (v) => setState(() => _checked = v ?? false)
              : null,
          onContinue: _checked ? () => Navigator.pop(context, true) : null,
        ),
      ],
    );
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(l10n.privacyPolicy),
        automaticallyImplyLeading: !widget.consentMode,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(child: body),
    );
    // Mode persetujuan: tidak bisa keluar lewat back — satu-satunya
    // jalan keluar adalah mencentang + Lanjut, atau Lewati saat
    // halaman gagal dimuat.
    if (!widget.consentMode) return scaffold;
    return PopScope(canPop: false, child: scaffold);
  }

  /// Pembangun bawaan: WebView sungguhan ke URL kebijakan.
  Widget _defaultViewBuilder(
    BuildContext context, {
    required String url,
    required VoidCallback onReachedBottom,
    required VoidCallback onLoadFailed,
    required VoidCallback onLoadStarted,
  }) {
    return _PolicyWebView(
      url: url,
      onReachedBottom: onReachedBottom,
      onLoadFailed: onLoadFailed,
      onLoadStarted: onLoadStarted,
      onPageFinished: _onPageFinished,
    );
  }
}

/// Baris bawah mode persetujuan: petunjuk gulir + centangan + Lanjut.
///
/// Polanya mengikuti layar backup frasa: centangan
/// [CheckboxListTile] mengunci tombol Lanjut — bedanya, centangan di
/// sini baru AKTIF sesudah halaman digulir sampai bawah.
class _ConsentBar extends StatelessWidget {
  final bool reachedBottom;
  final bool checked;
  final ValueChanged<bool?>? onCheckedChanged;
  final VoidCallback? onContinue;

  const _ConsentBar({
    required this.reachedBottom,
    required this.checked,
    required this.onCheckedChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!reachedBottom)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.arrow_downward_rounded,
                    size: 16,
                    color: Color(0xFF34D399),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.privacyScrollHint,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.palette.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Material sendiri (transparan): tanpa ini, ListTile
          // menuntut ink splash pada Material terdekat dan
          // Container ber-decorasi di atas menelan efeknya
          // (assertion Flutter saat centangan aktif).
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              value: checked,
              onChanged: onCheckedChanged,
              title: Text(
                l10n.privacyConsentCheck,
                style: const TextStyle(fontSize: 14),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: const Color(0xFF10B981),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 4),
          ElevatedButton(
            onPressed: onContinue,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              l10n.privacyConsentContinue,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tampilan saat halaman kebijakan gagal dimuat (mis. tanpa internet):
/// pesan + Muat Ulang, dan — hanya di mode persetujuan — Lewati untuk
/// sekarang (tanpa mencatat persetujuan).
class _LoadFailedView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback? onSkip;

  const _LoadFailedView({required this.onRetry, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.privacyLoadFailed,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(l10n.privacyRetry),
            ),
            if (onSkip != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onSkip,
                child: Text(l10n.privacySkipForNow),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// WebView kebijakan + deteksi gulir-sampai-bawah lewat JavaScript.
///
/// Tiap halaman selesai dimuat, dipasang pengait scroll yang
/// memanggil channel `ScrollBottom` saat
/// `scrollY + innerHeight >= scrollHeight - 24` — ambang yang sama
/// dengan [isScrolledToBottom]. Pengait juga langsung memeriksa sekali
/// saat dipasang, supaya halaman yang muat tanpa guliran langsung
/// mengaktifkan centangan.
class _PolicyWebView extends StatefulWidget {
  final String url;
  final VoidCallback onReachedBottom;
  final VoidCallback onLoadFailed;
  final VoidCallback onLoadStarted;
  final VoidCallback onPageFinished;

  const _PolicyWebView({
    required this.url,
    required this.onReachedBottom,
    required this.onLoadFailed,
    required this.onLoadStarted,
    required this.onPageFinished,
  });

  @override
  State<_PolicyWebView> createState() => _PolicyWebViewState();
}

class _PolicyWebViewState extends State<_PolicyWebView> {
  late final WebViewController _controller;

  static const _scrollHookJs =
      '''
(function(){
  if (window.__elnuxPrivacyHooked) return;
  window.__elnuxPrivacyHooked = true;
  function check(){
    var d = document.documentElement;
    if (window.scrollY + window.innerHeight >= d.scrollHeight - 24) {
      ScrollBottom.postMessage('bottom');
    }
  }
  window.addEventListener('scroll', check, {passive:true});
  check();
})();
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => widget.onLoadStarted(),
          onPageFinished: (_) async {
            widget.onPageFinished();
            try {
              await _controller.runJavaScript(_scrollHookJs);
            } catch (_) {
              // Halaman tanpa JS (atau WebView lama): centangan tetap
              // terkunci — user bisa memakai tautan bahasa di halaman
              // dan memuat ulang; tidak ada jalan pintas diam-diam.
            }
          },
          onWebResourceError: (error) {
            // Hanya kegagalan frame utama yang berarti halaman tidak
            // termuat; kegagalan sub-sumber (mis. favicon) diabaikan.
            if (error.isForMainFrame == true) widget.onLoadFailed();
          },
        ),
      )
      ..addJavaScriptChannel(
        'ScrollBottom',
        onMessageReceived: (_) => widget.onReachedBottom(),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
