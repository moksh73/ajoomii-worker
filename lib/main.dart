import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_theme.dart';
import 'splash_screen.dart' hide kCyan, kWhite;
import 'worker_login_screen.dart' hide kCyan, kWhite;
import 'worker_profile_setup.dart';
import 'pending_screen.dart' hide kTextMuted, kCyan;
import 'worker_home_screen.dart';
import 'worker_jobs_screen.dart';
import 'worker_earnings_screen.dart';
import 'worker_chat_list_screen.dart';
import 'worker_profile_screen.dart';

// ── FCM background handler ───────────────────────────────────
@pragma('vm:entry-point') // ✅ FIX 1: Required for release builds — without this
//    the background handler gets tree-shaken away
Future<void> _bgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

// ── Entry point ──────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_bgHandler);
  await FirebaseMessaging.instance.requestPermission();
  await _saveInitialFcmToken();
  FirebaseMessaging.instance.onTokenRefresh.listen(_saveFcmToken);
  runApp(const WorkerApp());
}

Future<void> _saveInitialFcmToken() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _saveFcmToken(token);
  } catch (_) {}
}

Future<void> _saveFcmToken(String token) async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('workers') // ✅ correct collection
        .doc(uid)
        .set({'fcmToken': token},
            SetOptions(merge: true)); // ✅ FIX 2: use set+merge
    // update() throws if doc doesn't exist yet (new user); set+merge is safe always
  } catch (_) {}
}

// ── App root ─────────────────────────────────────────────────
class WorkerApp extends StatelessWidget {
  const WorkerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ajoomi Worker',
      theme: appTheme,
      home: const SplashScreen(),
    );
  }
}

// ── Auth gate ─────────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (!authSnap.hasData) return const WorkerLoginScreen();

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('workers')
              .doc(authSnap.data!.uid)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) return const _ErrorView();
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingView();
            }
            final data = snap.data?.data() as Map<String, dynamic>?;
            final status = data?['verificationStatus'] ?? 'new';
            final name = (data?['name'] ?? '').toString();

            if (name.isEmpty || status == 'new') {
              return const WorkerProfileSetup();
            }
            if (status == 'approved') return const WorkerMainScreen();
            if (status == 'rejected') {
              return const WorkerProfileSetup(showRejectedBanner: true);
            }
            return const PendingScreen();
          },
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: kDivider,
                  borderRadius: BorderRadius.circular(20),
                ),
                child:
                    Icon(Icons.wifi_off_rounded, color: kTextMuted, size: 32),
              ),
              const SizedBox(height: 20),
              const Text('Connection error', style: kHeading),
              const SizedBox(height: 8),
              const Text(
                'Check your internet and try again.',
                style: kSubhead,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  style: kPrimaryButton(),
                  child: const Text('Sign Out'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: kBgPage,
      body: Center(
        child: CircularProgressIndicator(color: kCyan, strokeWidth: 2.5),
      ),
    );
  }
}

// ── Main screen with bottom nav ──────────────────────────────
class WorkerMainScreen extends StatefulWidget {
  const WorkerMainScreen({super.key});
  @override
  State<WorkerMainScreen> createState() => _WorkerMainScreenState();
}

class _WorkerMainScreenState extends State<WorkerMainScreen> {
  int _index = 0;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    // ✅ FIX 3: Moved pages inside build() so context is available if needed,
    //    and widgets rebuild correctly on hot reload
    final pages = [
      const WorkerHomeScreen(),
      WorkerJobsScreen(uid: _uid),
      WorkerChatListScreen(uid: _uid, isWorker: true),
      WorkerEarningsScreen(uid: _uid), // ✅ FIX 4: pass uid consistently —
      // WorkerEarningsScreen() with no args fails if it declares a required uid param
      WorkerProfileScreen(uid: _uid, isEditable: true),
    ];

    return Scaffold(
      backgroundColor: kBgPage,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      {
        'icon': Icons.home_outlined,
        'active': Icons.home_rounded,
        'label': 'Home'
      },
      {
        'icon': Icons.work_outline_rounded,
        'active': Icons.work_rounded,
        'label': 'Jobs'
      },
      {
        'icon': Icons.chat_bubble_outline_rounded,
        'active': Icons.chat_bubble_rounded,
        'label': 'Chats'
      },
      {
        'icon': Icons.account_balance_wallet_outlined,
        'active': Icons.account_balance_wallet_rounded,
        'label': 'Earnings'
      },
      {
        'icon': Icons.person_outline_rounded,
        'active': Icons.person_rounded,
        'label': 'Profile'
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: kWhite,
        border: const Border(top: BorderSide(color: kDivider, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(items.length, (i) {
              final active = _index == i;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _index = i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: active
                              ? kCyan.withOpacity(0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          active
                              ? items[i]['active'] as IconData
                              : items[i]['icon'] as IconData,
                          color: active ? kCyan : kTextMuted,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i]['label'] as String,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w400,
                          color: active ? kCyan : kTextMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
