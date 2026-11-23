import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../locale_controller.dart';
import '../theme.dart';

/// Layar awal ELNUX: logo di tengah, partikel modern melayang,
/// tagline di bawah logo, dan indikator proses boot di bawah.
///
/// Tampil selama `_booting` di HomeScreen (node LDK + LSPS2 sedang
/// diinisialisasi). Latar sengaja gelap di kedua tema: splash adalah
/// momen brand, bukan bagian dari tema terang/gelap aplikasi.
///
/// Jalan masuk offline (G1.1): bila boot memakan waktu lama, splash
/// menampilkan tawaran "Lanjutkan tanpa internet" sesudah
/// [waitThreshold] — pengguna tanpa internet tidak perlu menatap
/// spinner tanpa tahu ada jalan offline. Tawarannya hanya tampil
/// bila [onSkipToOffline] dipasang (pemilik layar yang memutuskan:
/// testnet saja, mengikuti tombol yang sama di layar gagal boot).
/// Timer milik layar ini: setiap boot baru memasang splash baru,
/// sehingga ambang diukur dari awal boot itu.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.waitThreshold = const Duration(seconds: 20),
    this.onSkipToOffline,
  });

  /// Batas tunggu sebelum tawaran offline tampil.
  final Duration waitThreshold;

  /// Dipanggil saat pengguna mengetuk "Lanjutkan tanpa internet".
  /// Future-nya selesai saat boot offline dimulai (atau saat boot
  /// online ternyata berhasil sementara itu) — selama menunggu,
  /// tombol menampilkan keadaan sibuk. Null = tidak ada tawaran.
  final Future<void> Function()? onSkipToOffline;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool _takingLong = false;
  bool _skipping = false;

  @override
  void initState() {
    super.initState();
    if (widget.onSkipToOffline != null) {
      _timer = Timer(widget.waitThreshold, () {
        if (mounted) setState(() => _takingLong = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _onSkipPressed() async {
    final callback = widget.onSkipToOffline;
    if (callback == null || _skipping) return;
    setState(() => _skipping = true);
    try {
      await callback();
    } catch (_) {
      // Gagal-diam: keadaan boot adalah wewenang pemilik layar;
      // layar ini hanya menampilkan tombolnya.
    }
    if (mounted) setState(() => _skipping = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Latar gradasi hijau gelap -> nyaris hitam.
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0A1F14), Color(0xFF0B0E0C)],
              ),
            ),
          ),
          // Halo hijau lembut di belakang logo.
          Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF10B981).withValues(alpha: 0.22),
                    const Color(0xFF10B981).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // Partikel melayang di atas latar.
          const Positioned.fill(child: _ParticleField()),
          // Logo + wordmark + tagline di tengah.
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/splash_logo.png',
                  width: 150,
                  height: 150,
                ),
                const SizedBox(height: 24),
                const Text(
                  'ELNUX',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.splashTagline,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    color: Color(0xFF6EE7B7),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Indikator proses boot di bawah.
          Positioned(
            left: 0,
            right: 0,
            bottom: 64,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: Color(0xFF10B981),
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.bootConnecting,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                // Tawaran jalan offline (G1.1): hanya sesudah ambang
                // tunggu terlewati dan hanya bila pemilik layar
                // memasang callback-nya.
                if (_takingLong && widget.onSkipToOffline != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    context.l10n.bootTakingLong,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  if (_skipping) ...[
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Color(0xFF10B981),
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.bootSkippingToOffline,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ] else
                    OutlinedButton(
                      onPressed: _onSkipPressed,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6EE7B7),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(context.l10n.bootOfflineButton),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lapisan partikel: titik-titik hijau/mint/putih yang melayang naik
/// perlahan sambil berkelip — memberi kesan "modern" tanpa membebani
/// perangkat (hanya lingkaran, tanpa gambar).
class _ParticleField extends StatefulWidget {
  const _ParticleField();

  @override
  State<_ParticleField> createState() => _ParticleFieldState();
}

class _ParticleFieldState extends State<_ParticleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    // Seed tetap: susunan partikel stabil tiap buka aplikasi.
    final random = math.Random(7);
    const colors = [
      Color(0xFF10B981),
      Color(0xFF6EE7B7),
      Color(0xFFFFFFFF),
    ];
    _particles = List.generate(55, (_) {
      return _Particle(
        x0: random.nextDouble(),
        y0: random.nextDouble(),
        radius: 1.0 + random.nextDouble() * 2.2,
        // Kecepatan naik: fraksi tinggi layar per satu putaran animasi.
        speed: 0.15 + random.nextDouble() * 0.35,
        swayAmp: 4.0 + random.nextDouble() * 10.0,
        swayFreq: 0.5 + random.nextDouble(),
        twinkleFreq: 0.5 + random.nextDouble() * 1.5,
        phase: random.nextDouble() * math.pi * 2,
        baseAlpha: 0.25 + random.nextDouble() * 0.65,
        color: colors[random.nextInt(colors.length)],
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => CustomPaint(
        painter: _ParticlePainter(_particles, _controller.value),
      ),
    );
  }
}

class _Particle {
  final double x0;
  final double y0;
  final double radius;
  final double speed;
  final double swayAmp;
  final double swayFreq;
  final double twinkleFreq;
  final double phase;
  final double baseAlpha;
  final Color color;

  const _Particle({
    required this.x0,
    required this.y0,
    required this.radius,
    required this.speed,
    required this.swayAmp,
    required this.swayFreq,
    required this.twinkleFreq,
    required this.phase,
    required this.baseAlpha,
    required this.color,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;

  _ParticlePainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      // Naik perlahan; kembali ke bawah saat mencapai atas.
      final progress = (p.y0 - t * p.speed) % 1.0;
      final x = p.x0 * size.width +
          math.sin(t * math.pi * 2 * p.swayFreq + p.phase) * p.swayAmp;
      final y = progress * size.height;
      // Berkelip halus di sekitar alpha dasarnya.
      final alpha = p.baseAlpha *
          (0.55 + 0.45 * math.sin(t * math.pi * 2 * p.twinkleFreq + p.phase));
      final paint = Paint()..color = p.color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), p.radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.t != t;
}
