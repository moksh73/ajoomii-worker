// ignore_for_file: library_private_types_in_public_api
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:my_new_app/job_accepted_screen.dart';

import 'app_theme.dart';
import 'job_request_screen.dart';
import 'worker_login_screen.dart' hide kCyan, kWhite, kSuccess, kError;
import 'worker_jobs_screen.dart';
import 'worker_profile_screen.dart';
import 'worker_chat_list_screen.dart';

class WorkerHomeScreen extends StatefulWidget {
  const WorkerHomeScreen({super.key});
  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _workerData;
  bool _isLoading = true;
  bool _isOnline = false;
  StreamSubscription<Position>? _locationSub;
  late AnimationController _pulseCtrl;

  String _currentAddress = 'Detecting location...';
  int _tabIndex = 0;

  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _loadWorkerData();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _locationSub?.cancel();
    super.dispose();
  }

  Future<void> _loadWorkerData() async {
    if (_uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(_uid)
          .get();
      if (!mounted) return;
      setState(() {
        _workerData = doc.data() ?? {};
        _isOnline = _workerData?['isOnline'] ?? false;
        _isLoading = false;
      });
      if (_isOnline) _startLocationUpdates();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleOnline(bool value) async {
    if (_uid == null) return;
    setState(() => _isOnline = value);
    if (value) {
      _startLocationUpdates();
    } else {
      _locationSub?.cancel();
      if (mounted) setState(() => _currentAddress = 'Location paused');
    }
    await FirebaseFirestore.instance.collection('workers').doc(_uid).update({
      'isOnline': value,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _updateAddress(Position pos) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = <String>[
          if ((p.street ?? '').isNotEmpty) p.street!,
          if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
          if ((p.locality ?? '').isNotEmpty) p.locality!,
          if ((p.postalCode ?? '').isNotEmpty) p.postalCode!,
        ];
        setState(() {
          _currentAddress =
              parts.isNotEmpty ? parts.join(', ') : 'Address unavailable';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _currentAddress = 'Address unavailable');
    }
  }

  Future<void> _startLocationUpdates() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      if (mounted) setState(() => _currentAddress = 'Permission denied');
      return;
    }

    try {
      final initial = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _updateAddress(initial);
    } catch (_) {}

    _locationSub?.cancel();
    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 30),
    ).listen((pos) async {
      if (_uid == null) return;
      await FirebaseFirestore.instance.collection('workers').doc(_uid).update({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      });
      await _updateAddress(pos);
    });
  }

  Future<void> _signOut() async {
    if (_uid != null) {
      await FirebaseFirestore.instance.collection('workers').doc(_uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
    _locationSub?.cancel();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WorkerLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: kBgPage,
        body: Center(child: CircularProgressIndicator(color: kCyan)),
      );
    }

    return Scaffold(
      backgroundColor: kBgPage,
      body: _HomeBody(
        workerData: _workerData,
        isOnline: _isOnline,
        uid: _uid,
        currentAddress: _currentAddress,
        onToggleOnline: _toggleOnline,
        onSignOut: _signOut,
        pulseCtrl: _pulseCtrl,
        onRefresh: _loadWorkerData,
        tabIndex: _tabIndex,
        onTabChanged: (i) => setState(() => _tabIndex = i),
      ),
    );
  }
}

// ── Home Body ─────────────────────────────────────────────────────────────────
class _HomeBody extends StatelessWidget {
  final Map<String, dynamic>? workerData;
  final bool isOnline;
  final String? uid;
  final String currentAddress;
  final ValueChanged<bool> onToggleOnline;
  final VoidCallback onSignOut;
  final AnimationController pulseCtrl;
  final Future<void> Function() onRefresh;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  const _HomeBody({
    required this.workerData,
    required this.isOnline,
    required this.uid,
    required this.currentAddress,
    required this.onToggleOnline,
    required this.onSignOut,
    required this.pulseCtrl,
    required this.onRefresh,
    required this.tabIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: kCyan,
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 16),
                _buildOnlineCard(),
                const SizedBox(height: 16),
                _buildStatsRow(context),
                const SizedBox(height: 16),
                _buildEarningsCard(context),
                const SizedBox(height: 24),
                _sectionHeader(
                  'Incoming Requests',
                  Icons.notifications_active_rounded,
                ),
                const SizedBox(height: 12),
                _buildRequestTabs(context),
                const SizedBox(height: 12),
                _buildRequestsForTab(context),
                const SizedBox(height: 24),
                _buildTipBanner(),
                const SizedBox(height: 12),
                _buildLogoutBtn(context),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tab selector ─────────────────────────────────────────
  Widget _buildRequestTabs(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kBgLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kDivider),
      ),
      child: Row(
        children: [
          _tabItem(context, 0, Icons.bolt_rounded, 'Instant'),
          _tabItem(context, 1, Icons.calendar_today_rounded, 'Scheduled'),
        ],
      ),
    );
  }

  Widget _tabItem(
      BuildContext context, int index, IconData icon, String label) {
    final selected = tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? kCyan : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : kTextMuted),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : kTextMuted,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Requests for the selected tab ────────────────────────
  Widget _buildRequestsForTab(BuildContext context) {
    if (!isOnline) {
      return _emptyState(
        icon: Icons.sensors_off_rounded,
        title: 'You\'re Offline',
        subtitle: 'Go online to receive job requests from customers nearby.',
        action: ElevatedButton(
          onPressed: () => onToggleOnline(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: kSuccess,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: const Text('Go Online',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      );
    }

    final cats = workerData?['category'];
    final categories =
        cats is List ? cats.map((e) => e.toString()).toList() : <String>[];

    // ── INSTANT TAB ──────────────────────────────────────────
    if (tabIndex == 0) {
      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('requests')
            .where('status', isEqualTo: 'pending')
            .where('isScheduled', isEqualTo: false)
            .limit(30)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: kCyan)));
          }

          final docs = List.from(snap.data?.docs ?? []);
          docs.sort((a, b) {
            final aTs = (a.data() as Map)['createdAt'] as Timestamp?;
            final bTs = (b.data() as Map)['createdAt'] as Timestamp?;
            if (aTs == null || bTs == null) return 0;
            return bTs.compareTo(aTs);
          });

          final filtered = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final cat = data['category'] as String? ?? '';
            return categories.isEmpty || categories.contains(cat);
          }).toList();

          if (filtered.isEmpty) {
            return _emptyState(
              icon: Icons.inbox_rounded,
              title: 'No Instant Requests',
              subtitle: 'New customer bookings will appear here.',
            );
          }

          return Column(
            children: filtered.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _RequestCard(
                requestId: doc.id,
                data: data,
                workerId: uid,
                workerData: workerData,
                isScheduled: false,
              );
            }).toList(),
          );
        },
      );
    }

    // ── SCHEDULED TAB ────────────────────────────────────────
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('isScheduled', isEqualTo: true)
          .where('workerId', isEqualTo: uid)
          .where('status', whereIn: [
        'waiting',
        'accepted',
        'working',
        'waitingCompletionOtp',
      ]).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: kCyan)));
        }

        final docs = List.from(snap.data?.docs ?? []);

        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aStatus = aData['status'] as String? ?? '';
          final bStatus = bData['status'] as String? ?? '';
          if (aStatus == 'waiting' && bStatus != 'waiting') return -1;
          if (bStatus == 'waiting' && aStatus != 'waiting') return 1;
          final aTs = aData['scheduledAt'] as Timestamp?;
          final bTs = bData['scheduledAt'] as Timestamp?;
          if (aTs != null && bTs != null) return aTs.compareTo(bTs);
          return 0;
        });

        if (docs.isEmpty) {
          return _emptyState(
            icon: Icons.calendar_today_rounded,
            title: 'No Scheduled Jobs',
            subtitle:
                'When admin assigns you a scheduled job, it will appear here.',
          );
        }

        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'] as String? ?? '';

            if (status == 'waiting') {
              return _ScheduledAssignedCard(
                requestId: doc.id,
                data: data,
                workerId: uid,
                workerData: workerData,
              );
            }

            return _RequestCard(
              requestId: doc.id,
              data: data,
              workerId: uid,
              workerData: workerData,
              isScheduled: true,
            );
          }).toList(),
        );
      },
    );
  }

  // ─── App Bar ──────────────────────────────────────────────
  Widget _buildAppBar(BuildContext context) {
    final name = workerData?['name'] ?? 'Worker';
    final cats = workerData?['category'];
    final service = (cats is List && cats.isNotEmpty)
        ? cats.first.toString()
        : (workerData?['service'] ?? 'Service');
    final image = workerData?['profileImage'];

    return SliverAppBar(
      pinned: true,
      expandedHeight: 120,
      backgroundColor: kWhite,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: kDivider),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: kWhite,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isOnline ? kSuccess : kDivider,
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: image != null
                              ? Image.network(image,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                        color: kCyanBg,
                                        child: const Icon(Icons.person,
                                            color: kCyan, size: 26),
                                      ))
                              : Container(
                                  color: kCyanBg,
                                  child: const Icon(Icons.person,
                                      color: kCyan, size: 26)),
                        ),
                      ),
                      if (isOnline)
                        Positioned(
                          bottom: 2,
                          right: 2,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: kSuccess,
                              shape: BoxShape.circle,
                              border: Border.all(color: kWhite, width: 2),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_greeting()}, 👋',
                              style: const TextStyle(
                                  color: kTextMuted, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: kTextDark,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: kCyanBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(service,
                          style: const TextStyle(
                              color: kCyanDeep,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kBgPage,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kDivider),
                      ),
                      child: const Icon(Icons.notifications_none_rounded,
                          color: kTextMid, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        color: kCyan, size: 14),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        currentAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kTextMid,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Online Toggle Card ───────────────────────────────────
  Widget _buildOnlineCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: isOnline ? const Color(0xFFECFDF5) : kWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOnline ? kSuccess.withOpacity(0.4) : kDivider,
          width: isOnline ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isOnline
                ? kSuccess.withOpacity(0.1)
                : Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              AnimatedBuilder(
                animation: pulseCtrl,
                builder: (_, __) => Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOnline
                        ? kSuccess.withOpacity(0.1 + 0.08 * pulseCtrl.value)
                        : kBgPage,
                    border: Border.all(
                      color: isOnline ? kSuccess : kStroke,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    isOnline
                        ? Icons.sensors_rounded
                        : Icons.sensors_off_rounded,
                    color: isOnline ? kSuccess : kTextMuted,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOnline ? 'You\'re Online' : 'You\'re Offline',
                        style: TextStyle(
                          color: isOnline ? kSuccess : kTextDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isOnline
                            ? 'Customers nearby can book you now'
                            : 'Go online to receive job requests',
                        style: const TextStyle(color: kTextMuted, fontSize: 12),
                      ),
                    ]),
              ),
              Transform.scale(
                scale: 0.9,
                child: Switch.adaptive(
                  value: isOnline,
                  onChanged: onToggleOnline,
                  activeColor: kSuccess,
                  activeTrackColor: kSuccess.withOpacity(0.3),
                  inactiveThumbColor: kTextMuted,
                  inactiveTrackColor: kBgLight,
                ),
              ),
            ]),
            if (isOnline) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kSuccess.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kSuccess.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded,
                        color: kSuccess, size: 14),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        currentAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kSuccess,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Stats Row ────────────────────────────────────────────
  Widget _buildStatsRow(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('workerId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final total = docs.length;
        final completed = docs
            .where((e) => (e.data() as Map)['status'] == 'completed')
            .length;
        final active = docs
            .where((e) =>
                ['accepted', 'ongoing'].contains((e.data() as Map)['status']))
            .length;

        return Row(children: [
          Expanded(
              child: _statCard('Total', '$total', Icons.work_rounded, kCyan)),
          const SizedBox(width: 10),
          Expanded(
              child: _statCard(
                  'Done', '$completed', Icons.check_circle_rounded, kSuccess)),
          const SizedBox(width: 10),
          Expanded(
              child: _statCard('Active', '$active',
                  Icons.pending_actions_rounded, kWarning)),
        ]);
      },
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kDivider),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 10),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: kTextMuted, fontSize: 11)),
      ]),
    );
  }

  // ─── Earnings Card ────────────────────────────────────────
  Widget _buildEarningsCard(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .snapshots(),
      builder: (context, snap) {
        double total = 0;
        double todayEarnings = 0;
        final today = DateTime.now();
        for (final doc in snap.data?.docs ?? []) {
          final data = doc.data() as Map<String, dynamic>;
          final amount = (data['total'] as num? ?? 0).toDouble();
          total += amount;
          final ts = data['completedAt'] as Timestamp?;
          if (ts != null) {
            final dt = ts.toDate();
            if (dt.year == today.year &&
                dt.month == today.month &&
                dt.day == today.day) {
              todayEarnings += amount;
            }
          }
        }

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0EA5E9), Color(0xFF1AC8DB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: kCyan.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.currency_rupee_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Today's Earnings",
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('₹${todayEarnings.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900)),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('Total',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
              const SizedBox(height: 2),
              Text('₹${total.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ]),
          ]),
        );
      },
    );
  }

  // ─── Empty state ──────────────────────────────────────────
  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kDivider),
      ),
      child: Column(children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: kBgPage,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, color: kTextMuted, size: 28),
        ),
        const SizedBox(height: 14),
        Text(title,
            style: const TextStyle(
                color: kTextDark, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(subtitle,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: kTextMuted, fontSize: 13, height: 1.5)),
        if (action != null) ...[const SizedBox(height: 16), action],
      ]),
    );
  }

  Widget _buildTipBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kWarningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kWarning.withOpacity(0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_rounded, color: kWarning, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Workers who stay online longer receive more bookings and better ratings.',
              style: TextStyle(
                  color: Color(0xFF92400E), fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutBtn(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: kWhite,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Logout?',
                style:
                    TextStyle(color: kTextDark, fontWeight: FontWeight.w700)),
            content: const Text('Are you sure you want to logout?',
                style: TextStyle(color: kTextMid)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel',
                      style: TextStyle(color: kTextMuted))),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Logout',
                      style: TextStyle(
                          color: kError, fontWeight: FontWeight.w700))),
            ],
          ),
        );
        if (confirm == true) onSignOut();
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: kErrorLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kError.withOpacity(0.2)),
        ),
        child:
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.logout_rounded, color: kError, size: 18),
          SizedBox(width: 8),
          Text('Logout',
              style: TextStyle(
                  color: kError, fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(children: [
      Icon(icon, color: kCyan, size: 18),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(
              color: kTextDark, fontSize: 16, fontWeight: FontWeight.w800)),
    ]);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
}

// ── Request Card ──────────────────────────────────────────────────────────────
class _RequestCard extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final String? workerId;
  final Map<String, dynamic>? workerData;
  final bool isScheduled;

  const _RequestCard({
    required this.requestId,
    required this.data,
    required this.workerId,
    required this.workerData,
    required this.isScheduled,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _isAccepting = false;

  Future<void> _acceptJob() async {
    if (widget.workerId == null) return;
    setState(() => _isAccepting = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.data['userId'])
          .get();
      final userData = userDoc.data() ?? {};

      final requestRef = FirebaseFirestore.instance
          .collection('requests')
          .doc(widget.requestId);

      final expectedStatus = widget.isScheduled ? 'scheduled' : 'pending';

      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(requestRef);
        final currentStatus = (snap.data() as Map?)?['status'] ?? '';
        if (currentStatus != expectedStatus) {
          throw Exception('Job already taken');
        }
        txn.update(requestRef, {
          'status': 'accepted',
          'workerId': widget.workerId,
          'workerName': widget.workerData?['name'] ?? 'Worker',
          'workerPhone': widget.workerData?['phone'] ?? '',
          'workerImage': widget.workerData?['profileImage'] ?? '',
          'workerCategory': widget.workerData?['category'] ?? [],
          'workerRating': widget.workerData?['rating'] ?? 0.0,
          'workerTotalJobs': widget.workerData?['totalJobs'] ?? 0,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });

      final chatRoomId =
          'chat_${widget.requestId}_${widget.workerId}_${widget.data['userId']}';
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(chatRoomId)
          .set({
        'requestId': widget.requestId,
        'workerId': widget.workerId,
        'userId': widget.data['userId'],
        'workerName': widget.workerData?['name'] ?? 'Worker',
        'userName': userData['name'] ?? 'Customer',
        'workerImage': widget.workerData?['profileImage'] ?? '',
        'userImage': userData['profileImage'] ?? '',
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JobRequestScreen(
            requestId: widget.requestId,
            data: widget.data,
            workerId: widget.workerId!,
            workerData: widget.workerData ?? {},
          ),
        ),
      );
    } catch (e) {
      debugPrint('Accept error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().contains('already taken')
              ? 'This job was already accepted by another worker.'
              : 'Error: $e'),
          backgroundColor: kError,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.data['category'] ?? 'Service';
    final subCategory = widget.data['subCategory'] ?? '';
    final location = widget.data['location'] ?? 'Unknown';
    final total = widget.data['total'] ?? 0;
    final description = widget.data['description'] ?? '';
    final payMethod = widget.data['paymentMethod'] ?? 'COD';
    final isPaid = widget.data['isPaid'] == true;
    final scheduledDate = widget.data['scheduledDate'] as String?;
    final scheduledTime = widget.data['scheduledTime'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.isScheduled
              ? const Color(0xFF9C27B0).withOpacity(0.35)
              : kDivider,
          width: widget.isScheduled ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.isScheduled ? const Color(0xFFF3E5F5) : kCyanBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kWhite,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color:
                          (widget.isScheduled ? const Color(0xFF9C27B0) : kCyan)
                              .withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Icon(
                widget.isScheduled
                    ? Icons.calendar_today_rounded
                    : Icons.home_repair_service_rounded,
                color: widget.isScheduled ? const Color(0xFF9C27B0) : kCyan,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category,
                        style: const TextStyle(
                            color: kTextDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                    Text(subCategory,
                        style:
                            const TextStyle(color: kTextMuted, fontSize: 12)),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: kSuccess.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('₹$total',
                    style: const TextStyle(
                        color: kSuccess,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPaid ? kSuccessLight : kWarningLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  payMethod == 'ONLINE' ? '✓ Paid' : 'COD',
                  style: TextStyle(
                      color: isPaid ? kSuccess : kWarning,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.isScheduled &&
                scheduledDate != null &&
                scheduledTime != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E5F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF9C27B0).withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.event_rounded,
                      color: Color(0xFF9C27B0), size: 15),
                  const SizedBox(width: 8),
                  Text(
                    'Scheduled: $scheduledDate at $scheduledTime',
                    style: const TextStyle(
                        color: Color(0xFF4A148C),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
            ],
            Row(children: [
              const Icon(Icons.location_on_outlined, color: kCyan, size: 15),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(location,
                      style: const TextStyle(color: kTextMid, fontSize: 12))),
            ]),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.notes_rounded, color: kTextMuted, size: 14),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: kTextMuted, fontSize: 12))),
              ]),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isAccepting ? null : _acceptJob,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      widget.isScheduled ? const Color(0xFF9C27B0) : kCyan,
                  disabledBackgroundColor:
                      (widget.isScheduled ? const Color(0xFF9C27B0) : kCyan)
                          .withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  elevation: 0,
                ),
                child: _isAccepting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.isScheduled
                                ? Icons.calendar_today_rounded
                                : Icons.check_circle_outline_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.isScheduled
                                ? 'Accept Scheduled Job'
                                : 'Accept Job',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                        ],
                      ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── Scheduled Assigned Card (status = 'waiting') ──────────────────────────────
class _ScheduledAssignedCard extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final String? workerId;
  final Map<String, dynamic>? workerData;

  const _ScheduledAssignedCard({
    required this.requestId,
    required this.data,
    required this.workerId,
    required this.workerData,
  });

  @override
  State<_ScheduledAssignedCard> createState() => _ScheduledAssignedCardState();
}

class _ScheduledAssignedCardState extends State<_ScheduledAssignedCard> {
  bool _accepting = false;
  bool _rejecting = false;

  Future<void> _accept() async {
    if (widget.workerId == null) return;
    setState(() => _accepting = true);
    try {
      final uid = widget.data['userId'] as String? ?? '';
      final chatRoomId = 'chat_${widget.requestId}_${widget.workerId}_$uid';
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};

      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(chatRoomId)
          .set({
        'requestId': widget.requestId,
        'workerId': widget.workerId,
        'userId': uid,
        'workerName': widget.workerData?['name'] ?? 'Worker',
        'userName': userData['name'] ?? 'Customer',
        'workerImage': widget.workerData?['profileImage'] ?? '',
        'userImage': userData['profileImage'] ?? '',
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('requests')
          .doc(widget.requestId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'workerName': widget.workerData?['name'] ?? 'Worker',
        'workerPhone': widget.workerData?['phone'] ?? '',
        'workerImage': widget.workerData?['profileImage'] ?? '',
        'workerRating': widget.workerData?['rating'] ?? 0.0,
        'workerTotalJobs': widget.workerData?['totalJobs'] ?? 0,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Job accepted! Check scheduled tab.'),
        backgroundColor: Color(0xFF00C073),
        behavior: SnackBarBehavior.floating,
      ));

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JobRequestScreen(
            requestId: widget.requestId,
            data: widget.data,
            workerId: widget.workerId!,
            workerData: widget.workerData ?? {},
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _reject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Reject this job?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            'The booking goes back to admin to assign another worker.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _rejecting = true);
    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(widget.requestId)
          .update({
        'status': 'pending',
        'workerId': null,
        'workerName': null,
        'workerPhone': null,
        'workerImage': null,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final category = data['category'] as String? ?? 'Service';
    final subCategory = data['subCategory'] as String? ?? category;
    final scheduledDate = data['scheduledDate'] as String? ?? '';
    final scheduledTime = data['scheduledTime'] as String? ?? '';
    final location =
        data['location'] as String? ?? data['address'] as String? ?? '';
    final total = ((data['total'] as num?) ?? 0).toDouble();
    final isCOD = data['paymentMethod'] == 'COD';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: const Color(0xFFF59E0B).withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFF59E0B).withOpacity(0.10),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFFFEF3C7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_active_rounded,
                size: 14, color: Color(0xFFF59E0B)),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('New Assignment — Admin assigned you this job',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF92400E))),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(20)),
              child: const Text('NEW',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFFDDD6FE)),
                ),
                child: const Icon(Icons.calendar_month_rounded,
                    color: Color(0xFF8B5CF6), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(subCategory,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0D2B35))),
                      const SizedBox(height: 2),
                      Text(category,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF06B6D4),
                              fontWeight: FontWeight.w600)),
                    ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('₹${total.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0D2B35))),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isCOD
                        ? const Color(0xFFFEF3C7)
                        : const Color(0xFFE0F8FC),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(isCOD ? 'COD' : 'Online',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isCOD
                              ? const Color(0xFF92400E)
                              : const Color(0xFF0891B2))),
                ),
              ]),
            ]),
            const SizedBox(height: 10),
            if (scheduledDate.isNotEmpty || scheduledTime.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFDDD6FE)),
                ),
                child: Row(children: [
                  const Icon(Icons.event_rounded,
                      color: Color(0xFF8B5CF6), size: 15),
                  const SizedBox(width: 8),
                  Text(
                    [
                      if (scheduledDate.isNotEmpty) scheduledDate,
                      if (scheduledTime.isNotEmpty) scheduledTime,
                    ].join('  ·  '),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF5B21B6)),
                  ),
                ]),
              ),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.location_on_outlined,
                    size: 13, color: Color(0xFF6B9BAD)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(location,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B9BAD), height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _rejecting || _accepting ? null : _reject,
                    icon: _rejecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.red))
                        : const Icon(Icons.close_rounded, size: 15),
                    label: const Text('Reject',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _accepting || _rejecting ? null : _accept,
                    icon: _accepting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded,
                            size: 16, color: Colors.white),
                    label: const Text('Accept Job',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00C073),
                      disabledBackgroundColor:
                          const Color(0xFF00C073).withOpacity(0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
