import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:my_new_app/job_accepted_screen.dart';

import 'app_theme.dart';
import 'job_request_screen.dart';

class WorkerJobsScreen extends StatefulWidget {
  final String? uid;
  const WorkerJobsScreen({super.key, required this.uid});

  @override
  State<WorkerJobsScreen> createState() => _WorkerJobsScreenState();
}

class _WorkerJobsScreenState extends State<WorkerJobsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        backgroundColor: kWhite,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('My Jobs', style: kHeading),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Container(
            decoration: const BoxDecoration(
              color: kWhite,
              border: Border(bottom: BorderSide(color: kDivider)),
            ),
            child: TabBar(
              controller: _tab,
              indicatorColor: kCyan,
              indicatorWeight: 2.5,
              labelColor: kCyan,
              unselectedLabelColor: kTextMuted,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: const [
                Tab(text: 'Active'),
                Tab(text: 'Completed'),
                Tab(text: 'All'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _JobList(uid: widget.uid, statusFilter: ['accepted', 'ongoing']),
          _JobList(uid: widget.uid, statusFilter: ['completed']),
          _JobList(uid: widget.uid, statusFilter: null),
        ],
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  final String? uid;
  final List<String>? statusFilter;

  const _JobList({required this.uid, required this.statusFilter});

  @override
  Widget build(BuildContext context) {
    // ✅ FIX 1: Removed .orderBy('createdAt') from the base query.
    //    Combining .where('workerId') + .where('status') + .orderBy('createdAt')
    //    requires a composite Firestore index that may not exist, causing a
    //    runtime FirebaseException. Sort client-side instead (safe & index-free).
    Query query = FirebaseFirestore.instance
        .collection('requests')
        .where('workerId', isEqualTo: uid);

    if (statusFilter != null && statusFilter!.length == 1) {
      query = query.where('status', isEqualTo: statusFilter!.first);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          // ✅ FIX 2: Show error state instead of silently showing empty list.
          //    Without this, a Firestore index error is swallowed and the user
          //    just sees "No Jobs Here" with no indication of what went wrong.
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: kTextMuted, size: 36),
                  const SizedBox(height: 12),
                  const Text('Failed to load jobs',
                      style: TextStyle(
                          color: kTextDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(snap.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: kTextMuted, fontSize: 12, height: 1.5)),
                ],
              ),
            ),
          );
        }

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kCyan));
        }

        var docs = snap.data?.docs ?? [];

        // ✅ FIX 1 continued: multi-status filter applied client-side
        if (statusFilter != null && statusFilter!.length > 1) {
          docs = docs.where((d) {
            final s = (d.data() as Map)['status'] as String? ?? '';
            return statusFilter!.contains(s);
          }).toList();
        }

        // ✅ FIX 1 continued: sort client-side by createdAt descending
        docs.sort((a, b) {
          final aTs = (a.data() as Map)['createdAt'] as Timestamp?;
          final bTs = (b.data() as Map)['createdAt'] as Timestamp?;
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          return bTs.compareTo(aTs);
        });

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: kBgLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.work_off_outlined,
                      color: kTextMuted, size: 32),
                ),
                const SizedBox(height: 16),
                const Text('No Jobs Here',
                    style: TextStyle(
                        color: kTextDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  statusFilter == null
                      ? 'Accept requests from the Home tab.'
                      : statusFilter!.contains('completed')
                          ? 'Completed jobs will appear here.'
                          : 'Active jobs will appear here.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: kTextMuted, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            return _JobTile(requestId: doc.id, data: data, workerId: uid);
          },
        );
      },
    );
  }
}

class _JobTile extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final String? workerId;

  const _JobTile(
      {required this.requestId, required this.data, required this.workerId});

  @override
  Widget build(BuildContext context) {
    final status = data['status'] ?? 'pending';
    final category = data['category'] ?? 'Service';
    final subCategory = data['subCategory'] ?? '';
    final location = data['location'] ?? '';
    final total = data['total'] ?? 0;
    final createdAt = data['createdAt'] as Timestamp?;
    final timeStr = createdAt != null
        ? '${createdAt.toDate().day}/${createdAt.toDate().month}/${createdAt.toDate().year}'
        : '';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case 'accepted':
        statusColor = kWarning;
        statusLabel = 'Accepted';
        statusIcon = Icons.directions_walk_rounded;
        break;
      case 'ongoing':
        statusColor = kCyan;
        statusLabel = 'Ongoing';
        statusIcon = Icons.construction_rounded;
        break;
      case 'completed':
        statusColor = kSuccess;
        statusLabel = 'Completed';
        statusIcon = Icons.check_circle_rounded;
        break;
      default:
        statusColor = kTextMuted;
        statusLabel = status;
        statusIcon = Icons.circle_outlined;
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JobRequestScreen(
            requestId: requestId,
            data: data,
            workerId: workerId ?? '',
            workerData: const {},
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
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
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(statusIcon, color: statusColor, size: 22),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withOpacity(0.3)),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 12),
          Container(height: 1, color: kDivider),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.location_on_outlined, color: kCyan, size: 14),
            const SizedBox(width: 5),
            Expanded(
                child: Text(location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kTextMid, fontSize: 12))),
            Text('₹$total',
                style: const TextStyle(
                    color: kSuccess,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ]),
          if (timeStr.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.calendar_today_rounded,
                  color: kTextMuted, size: 12),
              const SizedBox(width: 5),
              Text(timeStr,
                  style: const TextStyle(color: kTextMuted, fontSize: 11)),
            ]),
          ],
        ]),
      ),
    );
  }
}
