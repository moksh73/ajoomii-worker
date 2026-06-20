import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

class WorkerEarningsScreen extends StatefulWidget {
  const WorkerEarningsScreen({super.key, String? uid});

  @override
  State<WorkerEarningsScreen> createState() => _WorkerEarningsScreenState();
}

class _WorkerEarningsScreenState extends State<WorkerEarningsScreen> {
  double _totalEarnings = 0;
  double _thisMonth = 0;
  double _thisWeek = 0;
  int _completedJobs = 0;
  double _avgPerJob = 0;
  bool _loading = true;

  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  // FIX: query 'requests' collection (not 'bookings'), use 'total' field (not 'amount')
  Future<void> _loadSummary() async {
    if (_uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('requests')
          .where('workerId', isEqualTo: _uid)
          .where('status', isEqualTo: 'completed')
          .get();

      double total = 0;
      double monthly = 0;
      double weekly = 0;
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));

      for (final doc in snap.docs) {
        final data = doc.data();
        final amount = double.tryParse((data['total'] ?? 0).toString()) ?? 0;
        total += amount;

        final ts = data['completedAt'] ?? data['createdAt'];
        if (ts is Timestamp) {
          final dt = ts.toDate();
          if (dt.month == now.month && dt.year == now.year) {
            monthly += amount;
          }
          if (dt.isAfter(weekStart)) {
            weekly += amount;
          }
        }
      }

      if (mounted) {
        setState(() {
          _totalEarnings = total;
          _thisMonth = monthly;
          _thisWeek = weekly;
          _completedJobs = snap.docs.length;
          _avgPerJob = snap.docs.isEmpty ? 0 : total / snap.docs.length;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Earnings load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      body: SafeArea(
        child: RefreshIndicator(
          color: kCyan,
          onRefresh: _loadSummary,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Container(
                  color: kWhite,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Earnings', style: kHeading),
                      const SizedBox(height: 2),
                      const Text('Track your income',
                          style: TextStyle(color: kTextMuted, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                  child: Divider(height: 1, color: kDivider)),

              if (_loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator(color: kCyan)),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildBalanceCard(),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: _miniCard(
                            label: 'This Month',
                            value: '₹${_thisMonth.toStringAsFixed(0)}',
                            icon: Icons.calendar_month_rounded,
                            color: kCyan,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _miniCard(
                            label: 'This Week',
                            value: '₹${_thisWeek.toStringAsFixed(0)}',
                            icon: Icons.date_range_rounded,
                            color: kWarning,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: _miniCard(
                            label: 'Jobs Done',
                            value: '$_completedJobs',
                            icon: Icons.work_rounded,
                            color: kSuccess,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _miniCard(
                            label: 'Avg / Job',
                            value: '₹${_avgPerJob.toStringAsFixed(0)}',
                            icon: Icons.trending_up_rounded,
                            color: kOrange,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 24),
                      const Text('Recent Transactions',
                          style: TextStyle(
                              color: kTextDark,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      _buildTransactions(),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF1AC8DB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: kCyan.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          const Text('Ajoomi Wallet',
              style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ]),
        const SizedBox(height: 18),
        const Text('Total Earnings',
            style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 6),
        Text('₹${_totalEarnings.toStringAsFixed(0)}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('$_completedJobs jobs completed',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _miniCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(color: kTextMuted, fontSize: 11)),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }

  // FIX: query 'requests', use 'total' and 'subCategory' fields
  Widget _buildTransactions() {
    if (_uid == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('workerId', isEqualTo: _uid)
          .where('status', isEqualTo: 'completed')
          .orderBy('createdAt', descending: true)
          .limit(30)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: kCyan)));
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: kWhite,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kDivider),
            ),
            child: const Column(children: [
              Icon(Icons.receipt_long_rounded, color: kTextMuted, size: 40),
              SizedBox(height: 10),
              Text('No transactions yet',
                  style: TextStyle(color: kTextMuted, fontSize: 13)),
            ]),
          );
        }

        return Column(
          children: docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            return _transactionTile(d);
          }).toList(),
        );
      },
    );
  }

  Widget _transactionTile(Map<String, dynamic> data) {
    String date = '';
    final ts = data['completedAt'] ?? data['createdAt'];
    if (ts is Timestamp) {
      final d = ts.toDate();
      date = '${d.day}/${d.month}/${d.year}';
    }
    final serviceName =
        data['subCategory'] ?? data['category'] ?? data['service'] ?? 'Service';
    final amount = data['total'] ?? data['amount'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDivider),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: kSuccessLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child:
              const Icon(Icons.check_circle_rounded, color: kSuccess, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(serviceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: kTextDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(date, style: const TextStyle(color: kTextMuted, fontSize: 11)),
          ]),
        ),
        Text('+₹$amount',
            style: const TextStyle(
                color: kSuccess, fontSize: 15, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
