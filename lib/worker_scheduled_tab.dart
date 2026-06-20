// worker_scheduled_tab.dart
// Worker Side — Scheduled Jobs Tab
//
// STATUS FLOW (scheduled only):
//   pending          → admin sees it, assigns worker
//   waiting          → worker sees it HERE, can accept or reject
//   accepted         → worker accepted → job appears in active jobs
//   (rest of flow handled by job_request_screen.dart)
//
// This tab queries:
//   collection('requests')
//   where isScheduled == true
//   where workerId == currentWorkerId
//   where status in ['waiting', 'accepted', 'working', 'waitingCompletionOtp', 'completed']

// ignore_for_file: library_private_types_in_public_api

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:my_new_app/job_accepted_screen.dart';

import 'job_request_screen.dart';

// ─── Design tokens (match job_request_screen.dart exactly) ───────────────────
const _cyan = Color(0xFF06B6D4);
const _cyanDark = Color(0xFF0891B2);
const _cyanLight = Color(0xFFE0F8FC);
const _bg = Color(0xFFF5FAFE);
const _card = Color(0xFFFFFFFF);
const _surface = Color(0xFFF0F8FC);
const _txtDark = Color(0xFF0D2B35);
const _txtMuted = Color(0xFF6B9BAD);
const _border = Color(0xFFD4ECF5);

const _green = Color(0xFF00C073);
const _greenBg = Color(0xFFDCFCE7);
const _greenBdr = Color(0xFF86EFAC);
const _greenTxt = Color(0xFF166534);

const _amber = Color(0xFFF59E0B);
const _amberBg = Color(0xFFFEF3C7);
const _amberBdr = Color(0xFFFDE68A);
const _amberTxt = Color(0xFF92400E);

const _purple = Color(0xFF8B5CF6);
const _purpleBg = Color(0xFFF5F3FF);
const _purpleBdr = Color(0xFFDDD6FE);
const _purpleTxt = Color(0xFF5B21B6);

const _red = Color(0xFFF43F5E);
const _redBg = Color(0xFFFFF1F2);
const _redBdr = Color(0xFFFFCDD2);

// ─── Status helpers ───────────────────────────────────────────────────────────
Color _statusColor(String s) {
  switch (s) {
    case 'waiting':
      return _amber;
    case 'accepted':
      return _purple;
    case 'working':
      return _cyan;
    case 'waitingCompletionOtp':
      return _amber;
    case 'completed':
      return _green;
    case 'cancelled':
      return _red;
    default:
      return _txtMuted;
  }
}

String _statusLabel(String s) {
  switch (s) {
    case 'waiting':
      return 'New — Awaiting your response';
    case 'accepted':
      return 'Accepted — Upcoming';
    case 'working':
      return 'In Progress';
    case 'waitingCompletionOtp':
      return 'Awaiting completion OTP';
    case 'completed':
      return 'Completed';
    case 'cancelled':
      return 'Cancelled';
    default:
      return s;
  }
}

IconData _statusIcon(String s) {
  switch (s) {
    case 'waiting':
      return Icons.notifications_active_rounded;
    case 'accepted':
      return Icons.event_available_rounded;
    case 'working':
      return Icons.construction_rounded;
    case 'waitingCompletionOtp':
      return Icons.password_rounded;
    case 'completed':
      return Icons.check_circle_rounded;
    case 'cancelled':
      return Icons.cancel_outlined;
    default:
      return Icons.schedule_rounded;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  MAIN WIDGET — drop this directly into your worker home as a tab body
// ═════════════════════════════════════════════════════════════════════════════
class WorkerScheduledTab extends StatefulWidget {
  final String workerId;
  final Map<String, dynamic> workerData;

  const WorkerScheduledTab({
    super.key,
    required this.workerId,
    required this.workerData,
  });

  @override
  State<WorkerScheduledTab> createState() => _WorkerScheduledTabState();
}

class _WorkerScheduledTabState extends State<WorkerScheduledTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Streams ───────────────────────────────────────────────────────────────
  Stream<QuerySnapshot> _stream(List<String> statuses) {
    return FirebaseFirestore.instance
        .collection('requests')
        .where('isScheduled', isEqualTo: true)
        .where('workerId', isEqualTo: widget.workerId)
        .where('status', whereIn: statuses)
        .snapshots();
  }

  // ── Accept job ─────────────────────────────────────────────────────────────
  Future<void> _accept(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(docId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _snack('Job accepted! Check upcoming tab.', ok: true);
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
  }

  // ── Reject job ─────────────────────────────────────────────────────────────
  Future<void> _reject(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Reject job?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
            'The booking will go back to admin to assign another worker.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: _txtMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      // Reset worker assignment → admin can re-assign
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(docId)
          .update({
        'status': 'pending',
        'workerId': null,
        'workerName': null,
        'workerPhone': null,
        'workerImage': null,
        'rejectedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _snack('Job rejected. Admin will reassign.');
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
  }

  // ── Open job screen ────────────────────────────────────────────────────────
  void _openJob(String docId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobRequestScreen(
          requestId: docId,
          data: data,
          workerId: widget.workerId,
          workerData: widget.workerData,
        ),
      ),
    );
  }

  void _snack(String msg, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor: ok ? _green : _red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Tab bar ─────────────────────────────────────────────────────────
      Container(
        color: _card,
        child: TabBar(
          controller: _tabs,
          labelColor: _purple,
          unselectedLabelColor: _txtMuted,
          indicatorColor: _purple,
          indicatorWeight: 2.5,
          labelStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: 'New'),
            Tab(text: 'Upcoming'),
            Tab(text: 'History'),
          ],
        ),
      ),

      // ── Tab views ───────────────────────────────────────────────────────
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [
            // NEW — status: waiting (admin assigned, worker must respond)
            _JobList(
              stream: _stream(['waiting']),
              emptyIcon: Icons.notifications_none_rounded,
              emptyMsg: 'No new job assignments',
              emptySub: 'Admin will assign jobs here when available',
              workerId: widget.workerId,
              workerData: widget.workerData,
              showActions: true,
              onAccept: _accept,
              onReject: _reject,
              onTap: _openJob,
            ),

            // UPCOMING — status: accepted (worker accepted, job not started)
            _JobList(
              stream: _stream(['accepted', 'working', 'waitingCompletionOtp']),
              emptyIcon: Icons.event_busy_rounded,
              emptyMsg: 'No upcoming scheduled jobs',
              emptySub: 'Accepted jobs will appear here',
              workerId: widget.workerId,
              workerData: widget.workerData,
              showActions: false,
              onAccept: _accept,
              onReject: _reject,
              onTap: _openJob,
            ),

            // HISTORY — status: completed / cancelled
            _JobList(
              stream: _stream(['completed', 'cancelled']),
              emptyIcon: Icons.history_rounded,
              emptyMsg: 'No completed scheduled jobs yet',
              emptySub: 'Finished jobs will appear here',
              workerId: widget.workerId,
              workerData: widget.workerData,
              showActions: false,
              onAccept: _accept,
              onReject: _reject,
              onTap: _openJob,
            ),
          ],
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  JOB LIST
// ═════════════════════════════════════════════════════════════════════════════
class _JobList extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  final IconData emptyIcon;
  final String emptyMsg, emptySub;
  final String workerId;
  final Map<String, dynamic> workerData;
  final bool showActions;
  final Future<void> Function(String) onAccept;
  final Future<void> Function(String) onReject;
  final void Function(String, Map<String, dynamic>) onTap;

  const _JobList({
    required this.stream,
    required this.emptyIcon,
    required this.emptyMsg,
    required this.emptySub,
    required this.workerId,
    required this.workerData,
    required this.showActions,
    required this.onAccept,
    required this.onReject,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child:
                  CircularProgressIndicator(color: _purple, strokeWidth: 2.5));
        }

        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return _EmptyState(icon: emptyIcon, msg: emptyMsg, sub: emptySub);
        }

        // Sort: newest first, but 'waiting' (new) always on top
        final docs = snap.data!.docs.toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aStatus = aData['status'] as String? ?? '';
            final bStatus = bData['status'] as String? ?? '';
            // 'waiting' first
            if (aStatus == 'waiting' && bStatus != 'waiting') return -1;
            if (bStatus == 'waiting' && aStatus != 'waiting') return 1;
            // Then by scheduledAt ascending (soonest job first)
            final aTs = aData['scheduledAt'];
            final bTs = bData['scheduledAt'];
            if (aTs is Timestamp && bTs is Timestamp) {
              return aTs.compareTo(bTs);
            }
            return 0;
          });

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _JobCard(
              docId: doc.id,
              data: data,
              showActions: showActions,
              onAccept: () => onAccept(doc.id),
              onReject: () => onReject(doc.id),
              onTap: () => onTap(doc.id, data),
            );
          },
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  JOB CARD
// ═════════════════════════════════════════════════════════════════════════════
class _JobCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final bool showActions;
  final VoidCallback onAccept, onReject, onTap;

  const _JobCard({
    required this.docId,
    required this.data,
    required this.showActions,
    required this.onAccept,
    required this.onReject,
    required this.onTap,
  });

  @override
  State<_JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<_JobCard> {
  bool _accepting = false;
  bool _rejecting = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final status = data['status'] as String? ?? 'waiting';
    final isNew = status == 'waiting';
    final statusColor = _statusColor(status);
    final total = ((data['total'] as num?) ?? 0).toDouble();
    final isCOD = data['paymentMethod'] == 'COD';

    final scheduledDate = data['scheduledDate'] as String? ?? '';
    final scheduledTime = data['scheduledTime'] as String? ?? '';
    final category = data['category'] as String? ?? '';
    final subCategory = data['subCategory'] as String? ?? category;
    final userName = data['userName'] as String? ?? 'Customer';
    final address =
        data['location'] as String? ?? data['address'] as String? ?? '';

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isNew ? _amber.withOpacity(0.6) : _border,
            width: isNew ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isNew
                  ? _amber.withOpacity(0.10)
                  : Colors.black.withOpacity(0.04),
              blurRadius: isNew ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isNew ? _amberBg : statusColor.withOpacity(0.06),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                ),
              ),
              child: Row(children: [
                Icon(_statusIcon(status),
                    size: 13, color: isNew ? _amber : statusColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isNew ? _amberTxt : statusColor,
                    ),
                  ),
                ),
                // NEW badge
                if (isNew)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _amber,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('NEW',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                  ),
                // Tap to view hint for non-new cards
                if (!isNew &&
                    status != 'completed' &&
                    status != 'cancelled') ...[
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: _txtMuted),
                ],
              ]),
            ),

            // ── Body ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Service + customer row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _purpleBg,
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: _purpleBdr),
                        ),
                        child: const Icon(Icons.calendar_month_rounded,
                            color: _purple, size: 22),
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
                                    color: _txtDark)),
                            const SizedBox(height: 2),
                            Text(category,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: _cyan,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 3),
                            Row(children: [
                              const Icon(Icons.person_outline_rounded,
                                  size: 12, color: _txtMuted),
                              const SizedBox(width: 4),
                              Text(userName,
                                  style: const TextStyle(
                                      fontSize: 12, color: _txtMuted)),
                            ]),
                          ],
                        ),
                      ),
                      // Amount
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('₹${total.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: _txtDark)),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: isCOD ? _amberBg : _cyanLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: isCOD
                                      ? _amberBdr
                                      : _cyan.withOpacity(0.3)),
                            ),
                            child: Text(
                              isCOD ? 'COD' : 'Online',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isCOD ? _amberTxt : _cyanDark),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ── Scheduled date/time pill ───────────────────────────
                  if (scheduledDate.isNotEmpty || scheduledTime.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: _purpleBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _purpleBdr),
                      ),
                      child: Row(children: [
                        const Icon(Icons.event_rounded,
                            color: _purple, size: 15),
                        const SizedBox(width: 8),
                        Text(
                          [
                            if (scheduledDate.isNotEmpty) scheduledDate,
                            if (scheduledTime.isNotEmpty) scheduledTime,
                          ].join('  ·  '),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _purpleTxt),
                        ),
                      ]),
                    ),

                  // ── Address ───────────────────────────────────────────
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 13, color: _txtMuted),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(address,
                              style: const TextStyle(
                                  fontSize: 12, color: _txtMuted, height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],

                  // ── COD commission hint ───────────────────────────────
                  if (isCOD) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _border),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 12, color: _txtMuted),
                        const SizedBox(width: 6),
                        Text(
                          'Commission: 10%–15% of ₹${total.toStringAsFixed(0)} payable to admin',
                          style:
                              const TextStyle(fontSize: 11, color: _txtMuted),
                        ),
                      ]),
                    ),
                  ],

                  // ── ACCEPT / REJECT buttons (only for 'waiting') ──────
                  if (widget.showActions && status == 'waiting') ...[
                    const SizedBox(height: 14),
                    Row(children: [
                      // Reject
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: _rejecting || _accepting
                                ? null
                                : () async {
                                    setState(() => _rejecting = true);
                                    widget.onReject();
                                    if (mounted)
                                      setState(() => _rejecting = false);
                                  },
                            icon: _rejecting
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: _red))
                                : const Icon(Icons.close_rounded, size: 15),
                            label: const Text('Reject',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _red,
                              side: const BorderSide(color: _red),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Accept
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _accepting || _rejecting
                                ? null
                                : () async {
                                    setState(() => _accepting = true);
                                    widget.onAccept();
                                    if (mounted)
                                      setState(() => _accepting = false);
                                  },
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
                              backgroundColor: _green,
                              disabledBackgroundColor: _green.withOpacity(0.5),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ],

                  // ── View job button for accepted/active jobs ───────────
                  if (!widget.showActions &&
                      status != 'completed' &&
                      status != 'cancelled') ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: widget.onTap,
                        icon: const Icon(Icons.open_in_new_rounded,
                            size: 14, color: Colors.white),
                        label: const Text('View Job',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _purple,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  EMPTY STATE
// ═════════════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String msg, sub;
  const _EmptyState({required this.icon, required this.msg, required this.sub});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _purpleBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: _purpleBdr),
                ),
                child: Icon(icon, color: _purple, size: 36),
              ),
              const SizedBox(height: 16),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _txtDark)),
              const SizedBox(height: 6),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, color: _txtMuted, height: 1.4)),
            ],
          ),
        ),
      );
}
