import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'main.dart';
import 'pending_screen.dart';
import 'worker_login_screen.dart';
import 'worker_profile_setup.dart';

// ─── Colors ──────────────────────────────────────────────────────────────────
const Color kCyan = Color(0xFF06B6D4);
const Color kCyanDark = Color(0xFF0891B2);
const Color kCyanDeep = Color(0xFF0E7490);
const Color kCyanLight = Color(0xFF22D3EE);
const Color kWhite = Colors.white;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Controllers
  late AnimationController _bgCtrl; // background circles pulse
  late AnimationController _logoCtrl; // logo pop-in
  late AnimationController _heroCtrl; // "Ajoomi Heroes" text reveal
  late AnimationController _starsCtrl; // floating stars/sparkles
  late AnimationController _loaderCtrl; // dots loader
  late AnimationController _taglineCtrl; // tagline fade

  // Animations
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _bgScale;
  late Animation<double> _heroFade;
  late Animation<Offset> _heroSlide;
  late Animation<double> _taglineFade;
  late Animation<Offset> _taglineSlide;

  String _version = '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    _bgCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..repeat(reverse: true);

    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));

    _heroCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));

    _starsCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();

    _loaderCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();

    _taglineCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));

    _bgScale = Tween<double>(begin: 1.0, end: 1.15)
        .animate(CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut));

    _logoScale = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));

    _logoFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _logoCtrl,
        curve: const Interval(0, 0.5, curve: Curves.easeIn)));

    _heroFade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut));

    _heroSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut));

    _taglineFade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOut));

    _taglineSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _taglineCtrl, curve: Curves.easeOut));

    _start();
  }

  Future<void> _start() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = 'v${info.version}';
    } catch (_) {
      _version = 'v1.0.0';
    }
    if (mounted) setState(() {});

    await Future.delayed(const Duration(milliseconds: 200));
    _logoCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 700));
    _heroCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    _taglineCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 1500));
    _navigate();
  }

  Future<void> _navigate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _go(const WorkerLoginScreen());
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final status = data?['verificationStatus'] ?? 'new';
      final name = (data?['name'] ?? '').toString();

      if (!mounted) return;

      if (name.isEmpty || status == 'new') {
        _go(const WorkerProfileSetup());
      } else if (status == 'approved') {
        _go(const WorkerMainScreen());
      } else if (status == 'rejected') {
        _go(const WorkerProfileSetup(showRejectedBanner: true));
      } else {
        _go(const PendingScreen());
      }
    } catch (_) {
      _go(const WorkerLoginScreen());
    }
  }

  void _go(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (_, __, ___) => screen,
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ));
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _logoCtrl.dispose();
    _heroCtrl.dispose();
    _starsCtrl.dispose();
    _loaderCtrl.dispose();
    _taglineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        // ── Cyan gradient background ──────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0E7490), kCyan, Color(0xFF22D3EE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),

        // ── Animated background blobs ────────────────────────────────────
        AnimatedBuilder(
          animation: _bgScale,
          builder: (_, __) => Stack(children: [
            Positioned(
              top: -80,
              left: -80,
              child: Transform.scale(
                scale: _bgScale.value,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 60,
              right: -60,
              child: Transform.scale(
                scale: 2 - _bgScale.value,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -100,
              right: -60,
              child: Transform.scale(
                scale: _bgScale.value,
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.07),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 100,
              left: -40,
              child: Transform.scale(
                scale: 2 - _bgScale.value,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ),
            ),
          ]),
        ),

        // ── Floating sparkle stars ────────────────────────────────────────
        AnimatedBuilder(
          animation: _starsCtrl,
          builder: (_, __) {
            final stars = [
              _StarConfig(top: 0.12, left: 0.08, size: 6, phase: 0.0),
              _StarConfig(top: 0.20, left: 0.85, size: 8, phase: 0.3),
              _StarConfig(top: 0.35, left: 0.06, size: 5, phase: 0.6),
              _StarConfig(top: 0.08, left: 0.60, size: 7, phase: 0.1),
              _StarConfig(top: 0.65, left: 0.88, size: 6, phase: 0.5),
              _StarConfig(top: 0.75, left: 0.10, size: 5, phase: 0.8),
              _StarConfig(top: 0.85, left: 0.70, size: 7, phase: 0.2),
              _StarConfig(top: 0.48, left: 0.92, size: 5, phase: 0.7),
              _StarConfig(top: 0.55, left: 0.03, size: 8, phase: 0.4),
              _StarConfig(top: 0.92, left: 0.40, size: 6, phase: 0.9),
            ];
            return Stack(
                children: stars.map((s) {
              final t = (_starsCtrl.value + s.phase) % 1.0;
              final opacity = (sin(t * 2 * pi) * 0.5 + 0.5).clamp(0.15, 0.8);
              final yShift = sin(t * 2 * pi) * 6;
              return Positioned(
                top: s.top * size.height + yShift,
                left: s.left * size.width,
                child: Opacity(
                  opacity: opacity,
                  child: _StarShape(size: s.size),
                ),
              );
            }).toList());
          },
        ),

        // ── Main content ─────────────────────────────────────────────────
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Logo
              AnimatedBuilder(
                animation: _logoCtrl,
                builder: (_, __) => FadeTransition(
                  opacity: _logoFade,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: _LogoBox(),
                  ),
                ),
              ),

              const SizedBox(height: 36),

              // "Ajoomi" + "Heroes" animated text
              FadeTransition(
                opacity: _heroFade,
                child: SlideTransition(
                  position: _heroSlide,
                  child: Column(children: [
                    // App name with hero flair
                    _AjoomiHeroText(),
                    const SizedBox(height: 10),
                    // "WORKER APP" pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3), width: 1),
                      ),
                      child: const Text(
                        'WORKER APP',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.5,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),

              const SizedBox(height: 20),

              // Tagline
              FadeTransition(
                opacity: _taglineFade,
                child: SlideTransition(
                  position: _taglineSlide,
                  child: Text(
                    'Connect with customers\nand grow your work',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.80),
                      fontSize: 14,
                      height: 1.6,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // Loader dots
              AnimatedBuilder(
                animation: _loaderCtrl,
                builder: (_, __) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final t = (_loaderCtrl.value + i * 0.25) % 1.0;
                    final scale = (sin(t * 2 * pi) * 0.3 + 0.7).clamp(0.4, 1.0);
                    final opacity =
                        (sin(t * 2 * pi) * 0.4 + 0.6).clamp(0.2, 1.0);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      child: Opacity(
                        opacity: opacity,
                        child: Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.4),
                                  blurRadius: 6,
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 18),

              Text(
                _version,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── Logo Box ─────────────────────────────────────────────────────────────────

class _LogoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.25),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Image.asset(
          'assets/logoo.jpeg',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.engineering_rounded, size: 52, color: kCyan),
          ),
        ),
      ),
    );
  }
}

// ─── Ajoomi Hero Text ─────────────────────────────────────────────────────────

class _AjoomiHeroText extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // "Ajoomi" big bold
      RichText(
        text: const TextSpan(
          children: [
            TextSpan(
              text: 'DonIn30',
              style: TextStyle(
                color: Colors.white,
                fontSize: 46,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                shadows: [
                  Shadow(
                    color: Color(0x55000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 2),

      // "Heroes" with shield icon + golden styling
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Left decorative line
        Container(
          width: 28,
          height: 1.5,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Colors.white.withOpacity(0.6)],
            ),
          ),
        ),
        const SizedBox(width: 8),

        const Icon(Icons.shield_rounded, color: Color(0xFFFBD38D), size: 18),
        const SizedBox(width: 6),

        const Text(
          'Heroes',
          style: TextStyle(
            color: Color(0xFFFBD38D), // warm gold
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 3.0,
            shadows: [
              Shadow(
                color: Color(0x66000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),

        const SizedBox(width: 6),
        const Icon(Icons.shield_rounded, color: Color(0xFFFBD38D), size: 18),

        const SizedBox(width: 8),
        // Right decorative line
        Container(
          width: 28,
          height: 1.5,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white.withOpacity(0.6), Colors.transparent],
            ),
          ),
        ),
      ]),
    ]);
  }
}

// ─── Star Shape ───────────────────────────────────────────────────────────────

class _StarShape extends StatelessWidget {
  final double size;
  const _StarShape({required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * 2, size * 2),
      painter: _StarPainter(),
    );
  }
}

class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = size.width / 2;
    final innerR = outerR * 0.45;
    const points = 4;

    final path = Path();
    for (int i = 0; i < points * 2; i++) {
      final angle = (i * pi / points) - pi / 2;
      final r = i.isEven ? outerR : innerR;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0)
        path.moveTo(x, y);
      else
        path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Star Config ─────────────────────────────────────────────────────────────

class _StarConfig {
  final double top, left, size, phase;
  const _StarConfig({
    required this.top,
    required this.left,
    required this.size,
    required this.phase,
  });
}
