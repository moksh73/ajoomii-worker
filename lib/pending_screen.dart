import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'main.dart'; // ✅ FIX 1: import WorkerMainScreen for navigation after approval
import 'worker_login_screen.dart' hide kCyan, kWhite; // for sign-out navigation
import 'worker_profile_setup.dart'; // for rejected navigation

// ─────────────────────────────────────────────
// THEME
// ─────────────────────────────────────────────
const Color kCyan = Color(0xFF06B6D4);
const Color kCyanDark = Color(0xFF0891B2);
const Color kWarning = Color(0xFFFFB020);
const Color kSuccess = Color(0xFF22C55E);
const Color kError = Color(0xFFFF5A5A);
const Color kTextMuted = Color(0xFF7BAABF);

// ─────────────────────────────────────────────
// PENDING SCREEN
// ─────────────────────────────────────────────
class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotCtrl;
  StreamSubscription<DocumentSnapshot>? _statusSub;

  String _workerName = '';
  String _service = '';
  String _status = 'pending';

  @override
  void initState() {
    super.initState();

    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _loadUser();
    _listenVerification();
  }

  @override
  void dispose() {
    _dotCtrl.dispose();
    _statusSub?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────
  // DATA
  // ─────────────────────────────────────────
  Future<void> _loadUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // ✅ FIX 2: changed 'users' → 'workers' to match the rest of the app
    final doc =
        await FirebaseFirestore.instance.collection('workers').doc(uid).get();

    if (!mounted) return;
    setState(() {
      _workerName = doc.data()?['name'] ?? '';
      _service = doc.data()?['service'] ?? '';
    });
  }

  void _listenVerification() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // ✅ FIX 2: changed 'users' → 'workers' to match the rest of the app
    _statusSub = FirebaseFirestore.instance
        .collection('workers')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final status = snap.data()?['verificationStatus'] ?? 'pending';

      // ✅ FIX 3: act on status changes — navigate automatically when
      //    admin approves or rejects instead of just storing in local state
      if (status == 'approved') {
        _navigate(const WorkerMainScreen());
      } else if (status == 'rejected') {
        _navigate(const WorkerProfileSetup(showRejectedBanner: true));
      } else {
        setState(() => _status = status);
      }
    });
  }

  void _navigate(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WorkerLoginScreen()),
    );
  }

  // ─────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final firstName =
        _workerName.isEmpty ? 'there' : _workerName.split(' ').first;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _topBar(),
              const SizedBox(height: 32),
              _statusBadge(),
              const SizedBox(height: 24),
              _greeting(firstName),
              const SizedBox(height: 32),
              _stepsCard(),
              const SizedBox(height: 20),
              _tipsCard(),
              const SizedBox(height: 32),
              _signOutBtn(),
              const SizedBox(height: 16),
              _autoUpdateNote(),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // TOP BAR
  // ─────────────────────────────────────────
  Widget _topBar() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kCyan,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.verified_user_rounded,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        const Text(
          "WorkerApp",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const Spacer(),
        if (_service.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: kCyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _service,
              style: const TextStyle(
                color: kCyan,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────
  // STATUS BADGE  (animated dot)
  // ─────────────────────────────────────────
  Widget _statusBadge() {
    return AnimatedBuilder(
      animation: _dotCtrl,
      builder: (_, __) {
        return Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kWarning.withOpacity(0.4 + 0.6 * _dotCtrl.value),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              "Under Review",
              style: TextStyle(
                color: kWarning,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.4,
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────
  // GREETING
  // ─────────────────────────────────────────
  Widget _greeting(String firstName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Hey $firstName 👋",
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Your profile is being reviewed by our team.\nWe'll notify you once it's approved.",
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF64748B),
            height: 1.6,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────
  // STEPS CARD
  // ─────────────────────────────────────────
  Widget _stepsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Verification Steps",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 20),
          _step(
            index: 1,
            title: "Profile Submitted",
            sub: "Details received successfully.",
            state: _StepState.done,
          ),
          _stepLine(),
          _step(
            index: 2,
            title: "Admin Review",
            sub: "Documents are being verified.",
            state: _StepState.active,
          ),
          _stepLine(),
          _step(
            index: 3,
            title: "Account Activated",
            sub: "Your worker profile goes live.",
            state: _StepState.pending,
          ),
        ],
      ),
    );
  }

  Widget _stepLine() {
    return Padding(
      padding: const EdgeInsets.only(left: 18, top: 4, bottom: 4),
      child: Container(
        width: 2,
        height: 20,
        color: const Color(0xFFE2E8F0),
      ),
    );
  }

  Widget _step({
    required int index,
    required String title,
    required String sub,
    required _StepState state,
  }) {
    final Color dotColor = state == _StepState.done
        ? kSuccess
        : state == _StepState.active
            ? kWarning
            : const Color(0xFFCBD5E1);

    final Color titleColor = state == _StepState.pending
        ? const Color(0xFF94A3B8)
        : const Color(0xFF0F172A);

    Widget dotChild;
    if (state == _StepState.done) {
      dotChild = const Icon(Icons.check_rounded, color: Colors.white, size: 14);
    } else if (state == _StepState.active) {
      dotChild = AnimatedBuilder(
        animation: _dotCtrl,
        builder: (_, __) => Icon(
          Icons.hourglass_top_rounded,
          color: Colors.white.withOpacity(0.7 + 0.3 * _dotCtrl.value),
          size: 14,
        ),
      );
    } else {
      dotChild = Text(
        "$index",
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
          child: Center(child: dotChild),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────
  // TIPS CARD
  // ─────────────────────────────────────────
  Widget _tipsCard() {
    final tips = [
      "Keep your phone reachable for verification calls.",
      "Ensure Aadhaar details match your selfie.",
      "Approval usually takes less than 48 hours.",
    ];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.lightbulb_outline_rounded, color: kCyan, size: 16),
              SizedBox(width: 8),
              Text(
                "While You Wait",
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...tips.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: CircleAvatar(
                      radius: 3,
                      backgroundColor: kCyan,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // SIGN OUT BUTTON
  // ─────────────────────────────────────────
  Widget _signOutBtn() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _signOut,
        icon: const Icon(Icons.logout_rounded, size: 18, color: kError),
        label: const Text(
          "Sign Out",
          style: TextStyle(
            color: kError,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: kError.withOpacity(0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // NOTE
  // ─────────────────────────────────────────
  Widget _autoUpdateNote() {
    return const Center(
      child: Text(
        "This page updates automatically after approval.",
        style: TextStyle(
          fontSize: 11.5,
          color: Color(0xFFB0BEC5),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // REUSABLE CARD
  // ─────────────────────────────────────────
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────
// STEP STATE ENUM
// ─────────────────────────────────────────────
enum _StepState { done, active, pending }
