import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';
import 'pending_screen.dart';
import 'worker_profile_setup.dart';

// ─────────────────────────────────────────────
// COLORS
// ─────────────────────────────────────────────
const Color kCyan = Color(0xFF06B6D4);
const Color kCyanDark = Color(0xFF0891B2);
const Color kBg = Color(0xFFF4FBFD);
const Color kWhite = Colors.white;
const Color kBlack = Color(0xFF111827);
const Color kGrey = Color(0xFF6B7280);
const Color kBorder = Color(0xFFE5E7EB);
const Color kField = Color(0xFFF8FAFC);
const Color kError = Color(0xFFEF4444);
const Color kSuccess = Color(0xFF10B981);

// ─────────────────────────────────────────────
// LOGIN SCREEN
// ─────────────────────────────────────────────
class WorkerLoginScreen extends StatefulWidget {
  const WorkerLoginScreen({super.key});

  @override
  State<WorkerLoginScreen> createState() => _WorkerLoginScreenState();
}

class _WorkerLoginScreenState extends State<WorkerLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  int _tab = 0;
  bool _isLogin = true;
  bool _obscure = true;
  bool _loading = false;

  bool _otpSent = false;
  String _verificationId = '';

  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // EMAIL LOGIN / SIGNUP
  // ─────────────────────────────────────────────
  Future<void> _handleEmailAuth() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _snack('Enter valid email', true);
      return;
    }

    if (pass.length < 6) {
      _snack('Password must be 6+ characters', true);
      return;
    }

    setState(() => _loading = true);

    try {
      UserCredential cred;

      if (_isLogin) {
        cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: pass,
        );
      } else {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );

        // ✅ FIX 1: Save new user to 'workers' collection (not 'users')
        //    so AuthGate, PendingScreen, and WorkerProfileSetup can all find it.
        await FirebaseFirestore.instance
            .collection('workers')
            .doc(cred.user!.uid)
            .set({
          'uid': cred.user!.uid,
          'email': email,
          'role': 'worker',
          'verificationStatus': 'new',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await _routeAfterAuth(cred.user!.uid);
    } on FirebaseAuthException catch (e) {
      _snack(
          _friendlyAuthError(e.code), true); // ✅ FIX 2: friendly error messages
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────
  // FORGOT PASSWORD
  // ─────────────────────────────────────────────
  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty) {
      _snack('Enter email first', true);
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _snack('Password reset email sent');
    } on FirebaseAuthException catch (e) {
      _snack(_friendlyAuthError(e.code), true);
    } catch (_) {
      _snack('Failed to send reset email', true);
    }
  }

  // ─────────────────────────────────────────────
  // SEND OTP
  // ─────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();

    if (phone.length != 10) {
      _snack('Enter valid 10 digit number', true);
      return;
    }

    setState(() => _loading = true);

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: '+91$phone',
      verificationCompleted: (credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) await _routeAfterAuth(uid);
      },
      verificationFailed: (e) {
        if (mounted) {
          _snack(e.message ?? 'Verification failed', true);
          setState(() => _loading = false);
        }
      },
      codeSent: (id, _) {
        _verificationId = id;
        if (mounted) {
          setState(() {
            _loading = false;
            _otpSent = true;
          });
        }
        _snack('OTP sent');
        _startCooldown();
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  // ─────────────────────────────────────────────
  // VERIFY OTP
  // ─────────────────────────────────────────────
  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();

    if (otp.length != 6) {
      _snack('Enter valid OTP', true);
      return;
    }

    setState(() => _loading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      // ✅ FIX 1: Check & create in 'workers' collection (not 'users')
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(userCredential.user!.uid)
          .get();

      if (!doc.exists) {
        await FirebaseFirestore.instance
            .collection('workers')
            .doc(userCredential.user!.uid)
            .set({
          'uid': userCredential.user!.uid,
          'phone': _phoneCtrl.text.trim(),
          'role': 'worker',
          'verificationStatus': 'new',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await _routeAfterAuth(userCredential.user!.uid);
    } catch (_) {
      _snack('Invalid OTP. Please try again.', true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─────────────────────────────────────────────
  // ROUTING
  // ─────────────────────────────────────────────
  Future<void> _routeAfterAuth(String uid) async {
    // ✅ FIX 1: Read from 'workers' collection (not 'users')
    final doc =
        await FirebaseFirestore.instance.collection('workers').doc(uid).get();

    final data = doc.data();
    final status = data?['verificationStatus'] ?? 'new';
    final hasProfile = (data?['name'] ?? '').toString().isNotEmpty;

    if (!mounted) return;

    if (!hasProfile || status == 'new') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WorkerProfileSetup()),
      );
    } else if (status == 'approved') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WorkerMainScreen()),
      );
    } else if (status == 'rejected') {
      // ✅ FIX 3: Handle 'rejected' status — was falling through to PendingScreen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => const WorkerProfileSetup(showRejectedBanner: true)),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PendingScreen()),
      );
    }
  }

  // ─────────────────────────────────────────────
  // FRIENDLY AUTH ERRORS  ✅ FIX 2
  // ─────────────────────────────────────────────
  String _friendlyAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Try again.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use 6+ characters.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'No internet connection.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  // ─────────────────────────────────────────────
  // SNACKBAR
  // ─────────────────────────────────────────────
  void _snack(String msg, [bool error = false]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? kError : kSuccess,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // COOLDOWN
  // ─────────────────────────────────────────────
  void _startCooldown() {
    _resendCooldown = 30;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _resendCooldown--;
          if (_resendCooldown <= 0) timer.cancel();
        });
      },
    );
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          // TOP CYAN AREA
          Container(
            height: 270,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(36),
                bottomRight: Radius.circular(36),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: [
                  const SizedBox(height: 30),

                  // LOGO
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/logoo.jpeg',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.engineering_rounded,
                          color: kCyan,
                          size: 42,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    _isLogin ? 'Welcome Back 👋' : 'Join as Professional',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'India\'s trusted home service platform',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),

                  const SizedBox(height: 36),

                  // MAIN CARD
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // TAB SWITCH
                        Container(
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              _modernTab('Email', 0),
                              _modernTab('Phone', 1),
                            ],
                          ),
                        ),

                        const SizedBox(height: 26),

                        if (_tab == 0) _buildEmailForm() else _buildPhoneForm(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // INFO CARD
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2F3F8)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6FAFD),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.verified_user_rounded,
                              color: kCyanDark),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Verification Required',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: kBlack),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Upload your documents and complete profile for admin approval.',
                                style: TextStyle(
                                    fontSize: 12, color: kGrey, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),

          // LOADER
          if (_loading)
            Container(
              color: Colors.black.withOpacity(0.15),
              child:
                  const Center(child: CircularProgressIndicator(color: kCyan)),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // TAB
  // ─────────────────────────────────────────────
  Widget _modernTab(String title, int index) {
    final active = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _tab = index;
            _otpSent = false;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: active ? kCyan : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: active ? Colors.white : kGrey,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // EMAIL FORM
  // ─────────────────────────────────────────────
  Widget _buildEmailForm() {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _authMode('Sign In', true)),
          Expanded(child: _authMode('Sign Up', false)),
        ]),
        const SizedBox(height: 22),
        _modernField(
          controller: _emailCtrl,
          hint: 'Email address',
          icon: Icons.email_outlined,
          keyboard: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        _modernField(
          controller: _passCtrl,
          hint: 'Password',
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          suffix: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(_obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
          ),
        ),
        const SizedBox(height: 10),
        if (_isLogin)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _forgotPassword,
              child: const Text('Forgot Password?',
                  style:
                      TextStyle(color: kCyanDark, fontWeight: FontWeight.w700)),
            ),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _loading ? null : _handleEmailAuth,
            style: ElevatedButton.styleFrom(
              backgroundColor: kCyan,
              disabledBackgroundColor: kCyan.withOpacity(0.4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            child: Text(
              _isLogin ? 'Sign In' : 'Create Account',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // PHONE FORM
  // ─────────────────────────────────────────────
  Widget _buildPhoneForm() {
    return Column(
      children: [
        _modernField(
          controller: _phoneCtrl,
          hint: 'Phone Number (10 digits)',
          icon: Icons.phone_rounded,
          keyboard: TextInputType.phone,
          formatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
        ),
        if (_otpSent) ...[
          const SizedBox(height: 16),
          _modernField(
            controller: _otpCtrl,
            hint: 'Enter 6-digit OTP',
            icon: Icons.lock_outline_rounded,
            keyboard: TextInputType.number,
            formatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _loading ? null : (_otpSent ? _verifyOtp : _sendOtp),
            style: ElevatedButton.styleFrom(
              backgroundColor: kCyan,
              disabledBackgroundColor: kCyan.withOpacity(0.4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            child: Text(
              _otpSent ? 'Verify OTP' : 'Send OTP',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_otpSent)
          _resendCooldown > 0
              ? Text('Resend OTP in $_resendCooldown sec',
                  style: const TextStyle(color: kGrey))
              : TextButton(
                  onPressed: () => setState(() => _otpSent = false),
                  child: const Text('Resend OTP',
                      style: TextStyle(
                          color: kCyanDark, fontWeight: FontWeight.w700)),
                ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // INPUT FIELD
  // ─────────────────────────────────────────────
  Widget _modernField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? formatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: kField,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        inputFormatters: formatters,
        style: const TextStyle(color: kBlack, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: kGrey),
          prefixIcon: Icon(icon, color: kCyanDark),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SIGN IN / SIGN UP TOGGLE
  // ─────────────────────────────────────────────
  Widget _authMode(String title, bool login) {
    final active = _isLogin == login;
    return GestureDetector(
      onTap: () => setState(() => _isLogin = login),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? kCyan : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              color: active ? kCyanDark : kGrey,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
