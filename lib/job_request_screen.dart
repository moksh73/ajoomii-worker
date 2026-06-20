// scheduled_job_screen.dart
// Full scheduled booking flow for workers:
//   • Shows countdown to scheduled time
//   • Sends "Be Ready" reminders at 24h, 2h, 30min before
//   • Same arrive → OTP → work → completion OTP → complete → commission flow

// ignore_for_file: library_private_types_in_public_api
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_screen.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
const Color _cyan = Color(0xFF06B6D4);
const Color _cyanLight = Color(0xFFE0F8FC);
const Color _bg = Color(0xFFF5FAFE);
const Color _card = Color(0xFFFFFFFF);
const Color _surface = Color(0xFFF0F8FC);
const Color _txtDark = Color(0xFF0D2B35);
const Color _txtMuted = Color(0xFF6B9BAD);
const Color _border = Color(0xFFD4ECF5);
const Color _green = Color(0xFF00C073);
const Color _greenBg = Color(0xFFDCFCE7);
const Color _greenBorder = Color(0xFF86EFAC);
const Color _greenTxt = Color(0xFF166534);
const Color _amber = Color(0xFFF59E0B);
const Color _amberBg = Color(0xFFFEF3C7);
const Color _amberBorder = Color(0xFFFDE68A);
const Color _amberTxt = Color(0xFF92400E);
const Color _purple = Color(0xFF9C27B0);
const Color _purpleBg = Color(0xFFF3E5F5);
const Color _purpleBorder = Color(0xFFCE93D8);
const Color _purpleTxt = Color(0xFF4A148C);
const Color _red = Color(0xFFF43F5E);
const Color _orange = Color(0xFFFF6B35);
const Color _orangeBg = Color(0xFFFFF3EE);
const Color _orangeBorder = Color(0xFFFFCDB8);

// ─── Admin UPI Details ────────────────────────────────────────────────────────
const String _adminUpiId = 'bhardwajkrishna@fam';
const String _adminPhone = '9179369730';
const String _adminName = 'Krishna Bhardwaj';

// ─── OTP Generator ────────────────────────────────────────────────────────────
String _generateOtp() => (1000 + Random.secure().nextInt(9000)).toString();

// ─── Commission Calculator ────────────────────────────────────────────────────
Future<Map<String, dynamic>> _calculateTodayCommission(String workerId) async {
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));

  final snap = await FirebaseFirestore.instance
      .collection('requests')
      .where('workerId', isEqualTo: workerId)
      .where('status', isEqualTo: 'completed')
      .where('completedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
      .where('completedAt', isLessThan: Timestamp.fromDate(endOfDay))
      .get();

  final jobsToday = snap.docs.length;
  double totalEarningsToday = 0;
  for (final doc in snap.docs) {
    totalEarningsToday += ((doc.data()['total'] as num?) ?? 0).toDouble();
  }

  double commissionAmount = 0;
  double commissionRate = 0;
  String ruleLabel = '';

  if (jobsToday == 0) {
    ruleLabel = 'No jobs today';
  } else if (jobsToday == 1) {
    commissionAmount = 20;
    ruleLabel = '₹20 flat (1 job/day)';
  } else if (jobsToday < 5) {
    commissionRate = 0.10;
    commissionAmount = (totalEarningsToday * commissionRate).roundToDouble();
    ruleLabel = '10% of ₹${totalEarningsToday.toStringAsFixed(0)}';
  } else {
    commissionRate = 0.15;
    commissionAmount = (totalEarningsToday * commissionRate).roundToDouble();
    ruleLabel = '15% of ₹${totalEarningsToday.toStringAsFixed(0)}';
  }

  return {
    'jobsToday': jobsToday,
    'totalEarningsToday': totalEarningsToday,
    'commissionAmount': commissionAmount,
    'commissionRate': commissionRate,
    'ruleLabel': ruleLabel,
    'mustPay': jobsToday > 0 && commissionAmount > 0,
  };
}

// ─── UPI Launch ───────────────────────────────────────────────────────────────
Future<void> _launchUpi(double amount, String note) async {
  final uri = Uri.parse(
    'upi://pay?pa=$_adminUpiId&pn=${Uri.encodeComponent(_adminName)}'
    '&am=${amount.toStringAsFixed(2)}&cu=INR&tn=${Uri.encodeComponent(note)}',
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ─── Scheduled Job Screen ─────────────────────────────────────────────────────
class ScheduledJobScreen extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final String workerId;
  final Map<String, dynamic> workerData;

  const ScheduledJobScreen({
    super.key,
    required this.requestId,
    required this.data,
    required this.workerId,
    required this.workerData,
  });

  @override
  State<ScheduledJobScreen> createState() => _ScheduledJobScreenState();
}

class _ScheduledJobScreenState extends State<ScheduledJobScreen> {
  bool _isUpdating = false;
  Timer? _countdownTimer;
  Duration _timeUntilJob = Duration.zero;
  bool _jobTimeReached = false;

  // Reminder flags
  bool _shown24h = false;
  bool _shown2h = false;
  bool _shown30min = false;
  bool _shownNow = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  // ─── Parse scheduled datetime ─────────────────────────────────────────────
  DateTime? _parseScheduledAt() {
    final ts = widget.data['scheduledAt'];
    if (ts is Timestamp) return ts.toDate();

    final dateStr = widget.data['scheduledDate'] as String? ?? '';
    final timeStr = widget.data['scheduledTime'] as String? ?? '';
    if (dateStr.isEmpty || timeStr.isEmpty) return null;

    try {
      final parts = dateStr.split('/');
      if (parts.length < 3) return null;
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      final timeParts = timeStr.replaceAll(RegExp(r'[APM ]'), '').split(':');
      int hour = int.parse(timeParts[0]);
      final min = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
      final isPm = timeStr.toUpperCase().contains('PM');
      if (isPm && hour != 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;

      return DateTime(year, month, day, hour, min);
    } catch (_) {
      return null;
    }
  }

  // ─── Countdown + reminders ────────────────────────────────────────────────
  void _startCountdown() {
    _tick();
    _countdownTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  void _tick() {
    final scheduledAt = _parseScheduledAt();
    if (scheduledAt == null) return;
    final diff = scheduledAt.difference(DateTime.now());

    if (!mounted) return;
    setState(() {
      _timeUntilJob = diff.isNegative ? Duration.zero : diff;
      _jobTimeReached = diff.isNegative || diff.inMinutes <= 0;
    });

    final hours = diff.inHours;
    final minutes = diff.inMinutes;

    if (_jobTimeReached && !_shownNow) {
      _shownNow = true;
      _showReminderBanner(
          '🔔 Time for your scheduled job! Head to customer now.');
    } else if (minutes <= 30 && minutes > 0 && !_shown30min) {
      _shown30min = true;
      _showReminderBanner('🚨 Job starts in $minutes minutes — Leave now!');
    } else if (hours <= 2 && hours > 0 && !_shown2h) {
      _shown2h = true;
      _showReminderBanner(
          '⏰ Job in ${hours}h ${diff.inMinutes % 60}min — Start heading to customer!');
    } else if (hours <= 24 && hours > 2 && !_shown24h) {
      _shown24h = true;
      _showReminderBanner(
          '📅 Scheduled job tomorrow! Be prepared and on time.');
    }
  }

  void _showReminderBanner(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.notifications_active_rounded,
            color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
      ]),
      backgroundColor: _purple,
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ));
  }

  // ─── Snack ────────────────────────────────────────────────────────────────
  void _showSnack(String msg, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isSuccess ? _green : _red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ─── Chat ─────────────────────────────────────────────────────────────────
  void _openChat() {
    final userId = widget.data['userId'] as String? ?? '';
    final userName = widget.data['userName'] as String? ?? 'Customer';
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            requestId: widget.requestId,
            currentUserId: widget.workerId,
            otherUserId: userId,
            otherUserName: userName,
            chatRoomId: '',
            otherUserImage: '',
            chatId: '',
            workerPhone: '',
            workerName: '',
            serviceName: '',
            workerId: '',
          ),
        ));
  }

  // ─── Mark Arrived — generates arrival OTP ─────────────────────────────────
  // FIX: Always generate a fresh OTP when marking arrived so the customer
  //      can verify the worker's presence. Previously the OTP could be
  //      silently skipped if 'otp' already existed from a prior state.
  Future<void> _markArrived() async {
    setState(() => _isUpdating = true);
    try {
      final ref = FirebaseFirestore.instance
          .collection('requests')
          .doc(widget.requestId);

      // Always write a fresh OTP so it is guaranteed to exist and be unverified.
      await ref.update({
        'status': 'arrived',
        'arrivedAt': FieldValue.serverTimestamp(),
        'otp': _generateOtp(),
        'otpVerified': false,
      });

      if (mounted) {
        _showSnack('Marked as arrived! Show the OTP to the customer.',
            isSuccess: true);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ─── Complete Job ─────────────────────────────────────────────────────────
  // FIX 1: After arrival OTP verified, transition status to 'working' so the
  //         UI correctly reflects in-progress work.
  // FIX 2: completionOtp step — if not yet verified, update status to
  //         'waitingCompletionOtp' and return; don't silently stall.
  Future<void> _completeJob() async {
    setState(() => _isUpdating = true);
    try {
      final ref = FirebaseFirestore.instance
          .collection('requests')
          .doc(widget.requestId);
      final snap = await ref.get();
      final data = snap.data() ?? {};
      final currentStatus = data['status'] as String? ?? '';
      final existingCompletionOtp = data['completionOtp'] as String?;

      // ── Transition arrived → working ─────────────────────────────────────
      if (currentStatus == 'arrived' && data['otpVerified'] == true) {
        await ref.update({'status': 'working'});
        // Fall through to generate completion OTP below
      }

      // ── STEP 1: Generate completion OTP ──────────────────────────────────
      if (existingCompletionOtp == null || existingCompletionOtp.isEmpty) {
        await ref.update({
          'status': 'waitingCompletionOtp',
          'completionOtp': _generateOtp(),
          'completionOtpVerified': false,
          'completionOtpGeneratedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          _showSnack('Completion OTP generated. Show it to customer.',
              isSuccess: true);
        }
        return;
      }

      // ── STEP 2: Guard — wait for customer to verify ───────────────────────
      if (data['completionOtpVerified'] != true) {
        if (mounted) {
          _showSnack('Waiting for customer to verify completion OTP.');
        }
        return;
      }

      // ── STEP 3: Final completion ──────────────────────────────────────────
      final jobTotal = ((data['total'] as num?) ?? 0).toDouble();
      await ref.update(
          {'status': 'completed', 'completedAt': FieldValue.serverTimestamp()});
      await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.workerId)
          .update({
        'totalJobs': FieldValue.increment(1),
        'totalEarnings': FieldValue.increment(jobTotal),
      });

      if (!mounted) return;
      _showSnack('Job completed successfully!', isSuccess: true);
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;

      final commission = await _calculateTodayCommission(widget.workerId);
      if (!mounted) return;

      if (commission['mustPay'] == true) {
        await _showCommissionSheet(commission);
      } else {
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ─── Commission Sheet ─────────────────────────────────────────────────────
  Future<void> _showCommissionSheet(Map<String, dynamic> commission) async {
    final int jobs = commission['jobsToday'] as int;
    final double earnings = commission['totalEarningsToday'] as double;
    final double amount = commission['commissionAmount'] as double;
    final String ruleLabel = commission['ruleLabel'] as String;

    Color tierColor;
    String tierTitle;
    if (jobs == 1) {
      tierColor = _cyan;
      tierTitle = 'Daily Flat Fee';
    } else if (jobs < 5) {
      tierColor = _amber;
      tierTitle = '10% Commission';
    } else {
      tierColor = _orange;
      tierTitle = '15% Commission';
    }

    final upiNote =
        'Worker commission - $jobs job${jobs > 1 ? 's' : ''} today - ₹${amount.toStringAsFixed(0)}';

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CommissionSheet(
        jobs: jobs,
        earnings: earnings,
        amount: amount,
        ruleLabel: ruleLabel,
        tierColor: tierColor,
        tierTitle: tierTitle,
        upiNote: upiNote,
        onPayUpi: () => _launchUpi(amount, upiNote),
        onDismiss: () {
          Navigator.pop(context); // close sheet
          Navigator.pop(context); // close screen
        },
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .doc(widget.requestId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: _bg,
            body: Center(child: CircularProgressIndicator(color: _cyan)),
          );
        }

        final live = snap.data!.data() as Map<String, dynamic>? ?? {};
        final status = live['status'] as String? ?? 'scheduled';
        final otp = live['otp'] as String? ?? '';
        final otpVerified = live['otpVerified'] == true;
        final completionOtp = live['completionOtp'] as String? ?? '';
        final completionOtpVerified = live['completionOtpVerified'] == true;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
          child: Scaffold(
            backgroundColor: _bg,
            body: Column(children: [
              _TopBar(onBack: () => Navigator.pop(context), onChat: _openChat),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 1. Scheduled time hero ─────────────────────────
                      _ScheduledHeroCard(
                        data: live,
                        timeUntilJob: _timeUntilJob,
                        jobTimeReached: _jobTimeReached,
                      ),
                      const SizedBox(height: 10),

                      // ── 2. Urgency reminder (compact) ──────────────────
                      if (!_jobTimeReached &&
                          (status == 'scheduled' || status == 'accepted')) ...[
                        _UrgencyBanner(timeUntilJob: _timeUntilJob),
                        const SizedBox(height: 10),
                      ],

                      // ── 3. Status pill ─────────────────────────────────
                      _StatusPill(
                        status: status,
                        otpVerified: otpVerified,
                        jobTimeReached: _jobTimeReached,
                      ),
                      const SizedBox(height: 10),

                      // ── 4. Arrival OTP card ────────────────────────────
                      // FIX: Show OTP card whenever an OTP exists and the
                      //      job is not yet fully completed. This ensures
                      //      the worker always sees the OTP to show customer.
                      if (otp.isNotEmpty && status != 'completed') ...[
                        _OtpDisplayCard(otp: otp, otpVerified: otpVerified),
                        const SizedBox(height: 10),
                      ],

                      // ── 5. Completion OTP card ─────────────────────────
                      if (completionOtp.isNotEmpty &&
                          status == 'waitingCompletionOtp') ...[
                        _CompletionOtpCard(
                            otp: completionOtp,
                            verified: completionOtpVerified),
                        const SizedBox(height: 10),
                      ],

                      // ── 6. Job / Customer / Payment info ───────────────
                      _JobCard(data: live),
                      const SizedBox(height: 10),
                      _CustomerCard(data: live, onChat: _openChat),
                      const SizedBox(height: 10),
                      _PaymentCard(data: live),
                      const SizedBox(height: 10),
                      const _CommissionInfoCard(),
                      const SizedBox(height: 14),

                      // ══════════════════════════════════════════════════
                      // ACTION AREA
                      // ══════════════════════════════════════════════════

                      // Locked: scheduled time not yet reached
                      if ((status == 'scheduled' || status == 'accepted') &&
                          !_jobTimeReached)
                        _LockedUntilCard(timeUntilJob: _timeUntilJob),

                      // Time reached: show arrive button
                      if ((status == 'scheduled' || status == 'accepted') &&
                          _jobTimeReached)
                        _ActionButton(
                          isLoading: _isUpdating,
                          onTap: _markArrived,
                          label: "I've Arrived at Customer's Location",
                          icon: Icons.location_on_rounded,
                          color: _cyan,
                        ),

                      // Arrived + OTP not yet verified → show waiting message
                      // (OTP card above already shows the digits)
                      if (status == 'arrived' && !otpVerified)
                        _InfoBanner(
                          icon: Icons.hourglass_top_rounded,
                          color: _amber,
                          bg: _amberBg,
                          border: _amberBorder,
                          title: 'Waiting for customer to verify arrival OTP',
                          subtitle:
                              'Ask the customer to open their app and enter the OTP shown above.',
                        ),

                      // Arrived + OTP verified → generate completion OTP
                      if (status == 'arrived' && otpVerified)
                        _ActionButton(
                          isLoading: _isUpdating,
                          onTap: _completeJob,
                          label: 'Generate Completion OTP',
                          icon: Icons.check_circle_rounded,
                          color: _green,
                        ),

                      // Working → generate completion OTP
                      if (status == 'working')
                        _ActionButton(
                          isLoading: _isUpdating,
                          onTap: _completeJob,
                          label: 'Generate Completion OTP',
                          icon: Icons.check_circle_rounded,
                          color: _green,
                        ),

                      // Waiting completion OTP → not yet verified
                      if (status == 'waitingCompletionOtp' &&
                          !completionOtpVerified)
                        _InfoBanner(
                          icon: Icons.pending_actions_rounded,
                          color: _amber,
                          bg: _amberBg,
                          border: _amberBorder,
                          title:
                              'Waiting for customer to verify completion OTP',
                          subtitle:
                              'Ask the customer to enter the completion OTP shown above.',
                        ),

                      // Completion OTP verified → finish job
                      if (status == 'waitingCompletionOtp' &&
                          completionOtpVerified)
                        _ActionButton(
                          isLoading: _isUpdating,
                          onTap: _completeJob,
                          label: 'Finish Job',
                          icon: Icons.done_all_rounded,
                          color: _green,
                        ),

                      if (status == 'completed') const _CompletedCard(),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// ─── Scheduled Hero Card ──────────────────────────────────────────────────────
class _ScheduledHeroCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final Duration timeUntilJob;
  final bool jobTimeReached;

  const _ScheduledHeroCard({
    required this.data,
    required this.timeUntilJob,
    required this.jobTimeReached,
  });

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final date = data['scheduledDate'] as String? ?? '—';
    final time = data['scheduledTime'] as String? ?? '—';
    final days = timeUntilJob.inDays;
    final hrs = timeUntilJob.inHours % 24;
    final mins = timeUntilJob.inMinutes % 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: jobTimeReached
              ? [const Color(0xFF00C073), const Color(0xFF00A86B)]
              : [_purple, const Color(0xFF7B1FA2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: (jobTimeReached ? _green : _purple).withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Icon(
            jobTimeReached ? Icons.directions_run_rounded : Icons.event_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                jobTimeReached ? '🔔 Time to Go!' : 'Scheduled Job',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800),
              ),
              Text(
                '$date  •  $time',
                style: const TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              jobTimeReached ? 'NOW' : 'SCHEDULED',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ]),

        const SizedBox(height: 14),

        if (!jobTimeReached) ...[
          const Text('Time until job',
              style: TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 8),
          // Compact countdown row
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _CountdownBox(value: _pad(days), label: 'Days'),
            const Text(':',
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            _CountdownBox(value: _pad(hrs), label: 'Hrs'),
            const Text(':',
                style: TextStyle(
                    color: Colors.white60,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            _CountdownBox(value: _pad(mins), label: 'Mins'),
          ]),
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(children: [
              Text('🚗 Head to customer location now!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
              SizedBox(height: 3),
              Text("Tap \"I've Arrived\" when you reach",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 11.5)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _CountdownBox extends StatelessWidget {
  final String value;
  final String label;
  const _CountdownBox({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Center(
          child: Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
        ),
      ),
      const SizedBox(height: 4),
      Text(label,
          style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
    ]);
  }
}

// ─── Urgency Banner (replaces heavy _BeReadyCard) ─────────────────────────────
class _UrgencyBanner extends StatelessWidget {
  final Duration timeUntilJob;
  const _UrgencyBanner({required this.timeUntilJob});

  String get _msg {
    final mins = timeUntilJob.inMinutes;
    if (mins <= 30) return '🚨 Leave NOW — job starts in $mins minutes!';
    if (mins <= 120)
      return '⏰ Job in ${timeUntilJob.inHours}h ${mins % 60}min — Start preparing';
    if (mins <= 1440) return '📋 Job tomorrow — confirm tools & availability';
    return '📅 Upcoming scheduled job — mark your calendar!';
  }

  Color get _color {
    final mins = timeUntilJob.inMinutes;
    if (mins <= 30) return _red;
    if (mins <= 120) return _orange;
    if (mins <= 1440) return _amber;
    return _purple;
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(Icons.notifications_active_rounded, color: c, size: 16),
        const SizedBox(width: 10),
        Expanded(
            child: Text(_msg,
                style: TextStyle(
                    fontSize: 12.5, color: c, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ─── Locked Until Card ────────────────────────────────────────────────────────
class _LockedUntilCard extends StatelessWidget {
  final Duration timeUntilJob;
  const _LockedUntilCard({required this.timeUntilJob});

  @override
  Widget build(BuildContext context) {
    final hrs = timeUntilJob.inHours;
    final mins = timeUntilJob.inMinutes % 60;
    final label = hrs > 0 ? '${hrs}h ${mins}min' : '${mins}min';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: _purpleBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _purpleBorder),
      ),
      child: Row(children: [
        const Icon(Icons.lock_clock_rounded, color: _purple, size: 22),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Arrive Button Locked',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _purpleTxt)),
          const SizedBox(height: 3),
          Text(
            'Unlocks in $label — use this time to travel & prepare.',
            style: const TextStyle(fontSize: 12, color: _txtMuted, height: 1.4),
          ),
        ])),
      ]),
    );
  }
}

// ─── Generic Info Banner ──────────────────────────────────────────────────────
class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color, bg, border;
  final String title, subtitle;
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.bg,
    required this.border,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 3),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 11.5, color: _amberTxt, height: 1.4)),
        ])),
      ]),
    );
  }
}

// ─── Status Pill ──────────────────────────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  final String status;
  final bool otpVerified;
  final bool jobTimeReached;
  const _StatusPill(
      {required this.status,
      required this.otpVerified,
      required this.jobTimeReached});

  @override
  Widget build(BuildContext context) {
    Color bg, border, dot, txt;
    String label;
    IconData icon;

    if (status == 'scheduled' || status == 'accepted') {
      if (jobTimeReached) {
        bg = _greenBg;
        border = _greenBorder;
        dot = _green;
        txt = _greenTxt;
        label = 'Time reached — Head to customer now!';
        icon = Icons.directions_run_rounded;
      } else {
        bg = _purpleBg;
        border = _purpleBorder;
        dot = _purple;
        txt = _purpleTxt;
        label = 'Scheduled — Waiting for appointment time';
        icon = Icons.event_rounded;
      }
    } else {
      switch (status) {
        case 'arrived':
          if (otpVerified) {
            bg = _greenBg;
            border = _greenBorder;
            dot = _green;
            txt = _greenTxt;
            label = 'Customer verified OTP — Ready to generate completion OTP';
            icon = Icons.verified_rounded;
          } else {
            bg = _amberBg;
            border = _amberBorder;
            dot = _amber;
            txt = _amberTxt;
            label = 'Arrived — Waiting for customer to verify OTP';
            icon = Icons.lock_clock_rounded;
          }
          break;
        case 'working':
          bg = const Color(0xFFE0FAF4);
          border = const Color(0xFF99E8D2);
          dot = _green;
          txt = const Color(0xFF047857);
          label = 'Work in Progress — Generate completion OTP when done';
          icon = Icons.construction_rounded;
          break;
        case 'waitingCompletionOtp':
          bg = _amberBg;
          border = _amberBorder;
          dot = _amber;
          txt = _amberTxt;
          label = 'Waiting for customer to verify completion OTP';
          icon = Icons.pending_actions_rounded;
          break;
        case 'completed':
          bg = _greenBg;
          border = _greenBorder;
          dot = const Color(0xFF16A34A);
          txt = _greenTxt;
          label = 'Job Completed Successfully';
          icon = Icons.check_circle_rounded;
          break;
        default:
          bg = _amberBg;
          border = _amberBorder;
          dot = _amber;
          txt = _amberTxt;
          label = 'Job Accepted — Head to customer location';
          icon = Icons.directions_walk_rounded;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Icon(icon, size: 14, color: txt),
        const SizedBox(width: 6),
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: txt))),
      ]),
    );
  }
}

// ─── OTP Display Card ─────────────────────────────────────────────────────────
class _OtpDisplayCard extends StatelessWidget {
  final String otp;
  final bool otpVerified;
  const _OtpDisplayCard({required this.otp, required this.otpVerified});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: otpVerified ? _greenBg : _cyanLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: otpVerified ? _greenBorder : _cyan.withOpacity(0.4)),
      ),
      child: Column(children: [
        Row(children: [
          Icon(otpVerified ? Icons.verified_rounded : Icons.lock_open_rounded,
              size: 15, color: otpVerified ? _green : _cyan),
          const SizedBox(width: 7),
          Text(
            otpVerified
                ? 'Arrival OTP Verified ✓'
                : 'Arrival OTP — Show to Customer',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: otpVerified ? _greenTxt : _cyan),
          ),
        ]),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: otp
              .split('')
              .map((digit) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 50,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: otpVerified
                              ? _greenBorder
                              : _cyan.withOpacity(0.4),
                          width: 1.5),
                    ),
                    child: Center(
                        child: Text(digit,
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: otpVerified ? _green : _txtDark))),
                  ))
              .toList(),
        ),
        const SizedBox(height: 10),
        Text(
          otpVerified
              ? 'Customer confirmed your arrival'
              : 'Customer must enter this OTP to confirm your arrival',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11.5,
              color: otpVerified ? _greenTxt : _txtMuted,
              height: 1.4),
        ),
      ]),
    );
  }
}

// ─── Completion OTP Card ──────────────────────────────────────────────────────
class _CompletionOtpCard extends StatelessWidget {
  final String otp;
  final bool verified;
  const _CompletionOtpCard({required this.otp, required this.verified});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: verified ? _greenBg : _amberBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: verified ? _greenBorder : _amberBorder),
      ),
      child: Column(children: [
        Row(children: [
          Icon(verified ? Icons.verified_rounded : Icons.password_rounded,
              color: verified ? _green : _amber, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
            verified
                ? 'Completion OTP Verified ✓'
                : 'Completion OTP — Show to Customer',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: verified ? _greenTxt : _amberTxt),
          )),
        ]),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: otp
              .split('')
              .map((digit) => Container(
                    width: 50,
                    height: 58,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: verified ? _greenBorder : _amberBorder),
                    ),
                    child: Center(
                        child: Text(digit,
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: verified ? _green : _txtDark))),
                  ))
              .toList(),
        ),
        const SizedBox(height: 10),
        Text(
          verified
              ? 'Customer confirmed work completion'
              : 'Customer must enter this OTP to confirm job completion',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11.5,
              color: verified ? _greenTxt : _amberTxt,
              height: 1.4),
        ),
      ]),
    );
  }
}

// ─── Unified Action Button ────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final Color color;

  const _ActionButton({
    required this.isLoading,
    required this.onTap,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withOpacity(0.5),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ]),
      ),
    );
  }
}

// ─── Commission Info Card ─────────────────────────────────────────────────────
class _CommissionInfoCard extends StatelessWidget {
  const _CommissionInfoCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _orangeBg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _orangeBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.currency_rupee_rounded, color: _orange, size: 15),
          const SizedBox(width: 7),
          const Text('Daily Commission Rules',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: _orange)),
        ]),
        const SizedBox(height: 10),
        _TierRow(
            icon: Icons.work_off_outlined,
            label: '0 jobs',
            value: 'No payment',
            color: _green),
        _TierRow(
            icon: Icons.looks_one_rounded,
            label: '1 job',
            value: '₹20 flat',
            color: _cyan),
        _TierRow(
            icon: Icons.looks_4_rounded,
            label: '2–4 jobs',
            value: '10% earnings',
            color: _amber),
        _TierRow(
            icon: Icons.local_fire_department_rounded,
            label: '5+ jobs',
            value: '15% earnings',
            color: _orange,
            isLast: true),
        const SizedBox(height: 8),
        const Divider(color: _orangeBorder, height: 1),
        const SizedBox(height: 8),
        RichText(
            text: const TextSpan(
          style: TextStyle(fontSize: 11.5, color: _amberTxt, height: 1.5),
          children: [
            TextSpan(text: 'Pay via UPI: '),
            TextSpan(
                text: _adminUpiId,
                style: TextStyle(fontWeight: FontWeight.w700, color: _orange)),
            TextSpan(text: '  •  '),
            TextSpan(
                text: _adminPhone,
                style: TextStyle(fontWeight: FontWeight.w700, color: _orange)),
          ],
        )),
      ]),
    );
  }
}

class _TierRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  final bool isLast;
  const _TierRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color,
      this.isLast = false});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 7),
      child: Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 7),
        Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: _txtDark))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20)),
          child: Text(value,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }
}

// ─── Commission Bottom Sheet ──────────────────────────────────────────────────
class _CommissionSheet extends StatelessWidget {
  final int jobs;
  final double earnings, amount;
  final String ruleLabel, tierTitle, upiNote;
  final Color tierColor;
  final VoidCallback onPayUpi, onDismiss;

  const _CommissionSheet({
    required this.jobs,
    required this.earnings,
    required this.amount,
    required this.ruleLabel,
    required this.tierTitle,
    required this.upiNote,
    required this.tierColor,
    required this.onPayUpi,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          18, 18, 18, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: _border, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Icon(Icons.currency_rupee_rounded, color: tierColor, size: 36),
        const SizedBox(height: 10),
        const Text('Commission Due',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: _txtDark)),
        const SizedBox(height: 4),
        Text('$jobs job${jobs > 1 ? 's' : ''} completed today — great work!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: _txtMuted)),
        const SizedBox(height: 16),
        // Stats row
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border)),
          child: Row(children: [
            _Stat(label: 'Jobs Today', value: '$jobs', color: _cyan),
            _HDivider(),
            _Stat(
                label: 'Earned',
                value: '₹${earnings.toStringAsFixed(0)}',
                color: _green),
            _HDivider(),
            _Stat(label: 'Tier', value: tierTitle, color: tierColor),
          ]),
        ),
        const SizedBox(height: 12),
        // Amount box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          decoration: BoxDecoration(
            color: tierColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tierColor.withOpacity(0.25)),
          ),
          child: Column(children: [
            Text('Amount to Pay Admin',
                style: TextStyle(
                    fontSize: 12,
                    color: tierColor,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('₹${amount.toStringAsFixed(0)}',
                style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: tierColor,
                    letterSpacing: -1)),
            Text(ruleLabel,
                style: const TextStyle(fontSize: 12, color: _txtMuted)),
          ]),
        ),
        const SizedBox(height: 12),
        // UPI details
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: _greenBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _greenBorder)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Admin UPI Details',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _greenTxt)),
            const SizedBox(height: 8),
            _UpiRow(label: 'UPI ID', value: _adminUpiId),
            const SizedBox(height: 4),
            _UpiRow(label: 'Phone', value: _adminPhone),
            const SizedBox(height: 4),
            _UpiRow(label: 'Name', value: _adminName),
          ]),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: onPayUpi,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text('Pay ₹${amount.toStringAsFixed(0)} via UPI',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: _adminUpiId));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('UPI ID copied'),
                backgroundColor: _cyan,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ));
            },
            icon: const Icon(Icons.copy_rounded, size: 15),
            label: const Text('Copy UPI ID',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _cyan,
              side: const BorderSide(color: _cyan),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: onDismiss,
          child: const Text('Already Paid / Pay Later',
              style: TextStyle(
                  fontSize: 13, color: _txtMuted, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
          child: Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 3),
        Text(label,
            style: const TextStyle(fontSize: 10.5, color: _txtMuted),
            textAlign: TextAlign.center),
      ]));
}

class _HDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 1,
      height: 32,
      color: _border,
      margin: const EdgeInsets.symmetric(horizontal: 4));
}

class _UpiRow extends StatelessWidget {
  final String label, value;
  const _UpiRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(
            width: 50,
            child: Text(label,
                style: const TextStyle(fontSize: 11.5, color: _txtMuted))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _greenTxt))),
      ]);
}

// ─── Top Bar ──────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final VoidCallback onBack, onChat;
  const _TopBar({required this.onBack, required this.onChat});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: _card,
      padding: EdgeInsets.fromLTRB(14, top + 8, 14, 10),
      child: Row(children: [
        _Btn(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack, size: 15),
        const SizedBox(width: 10),
        const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Scheduled Job',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _txtDark)),
          Text('Track & manage your booking',
              style: TextStyle(fontSize: 11, color: _txtMuted)),
        ])),
        _Btn(
            icon: Icons.chat_bubble_outline_rounded,
            onTap: onChat,
            filled: true),
      ]),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool filled;
  const _Btn(
      {required this.icon,
      required this.onTap,
      this.size = 18,
      this.filled = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: filled ? _cyan : _card,
            shape: BoxShape.circle,
            border: Border.all(color: filled ? _cyan : _border),
          ),
          child:
              Icon(icon, size: size, color: filled ? Colors.white : _txtDark),
        ),
      );
}

// ─── Job Card ─────────────────────────────────────────────────────────────────
class _JobCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _JobCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.home_repair_service_rounded,
      title: 'Job Details',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (data['category'] != null) _Row('Category', data['category']),
        if (data['subCategory'] != null) _Row('Service', data['subCategory']),
        if ((data['description'] as String?)?.isNotEmpty == true)
          _Row('Description', data['description']),
        if (data['location'] != null) _Row('Location', data['location']),
        if (data['tankSize'] != null) _Row('Tank Size', data['tankSize']),
        if (data['maidDuration'] != null)
          _Row('Duration', data['maidDuration']),
        if (data['clothSets'] != null)
          _Row('Cloth Sets', '${data['clothSets']}'),
        if (data['carpenterDesign'] != null)
          _Row('Design', data['carpenterDesign']),
        if (data['tailorDesign'] != null) _Row('Design', data['tailorDesign']),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _Tag(icon: Icons.event_rounded, label: data['scheduledDate'] ?? '—'),
          _Tag(
              icon: Icons.access_time_rounded,
              label: data['scheduledTime'] ?? '—'),
        ]),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 84,
              child: Text(label,
                  style: const TextStyle(fontSize: 12, color: _txtMuted))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _txtDark,
                      height: 1.4))),
        ]),
      );
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Tag({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: _txtMuted),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w500, color: _txtMuted)),
        ]),
      );
}

// ─── Customer Card ────────────────────────────────────────────────────────────
class _CustomerCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onChat;
  const _CustomerCard({required this.data, required this.onChat});
  @override
  Widget build(BuildContext context) {
    final name = data['userName'] ?? 'Customer';
    final phone = data['userPhone'] ?? '';
    final image = data['userImage'] ?? '';
    final initials = (name as String).isNotEmpty
        ? name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : 'C';
    return _SectionCard(
      icon: Icons.person_outline_rounded,
      title: 'Customer',
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: image.isNotEmpty
              ? ClipOval(child: Image.network(image, fit: BoxFit.cover))
              : Center(
                  child: Text(initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15))),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _txtDark)),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(phone, style: const TextStyle(fontSize: 12, color: _txtMuted)),
          ],
        ])),
        GestureDetector(
            onTap: onChat,
            child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: _surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: _border)),
                child: const Icon(Icons.chat_bubble_outline_rounded,
                    size: 16, color: _cyan))),
      ]),
    );
  }
}

// ─── Payment Card ─────────────────────────────────────────────────────────────
class _PaymentCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PaymentCard({required this.data});
  @override
  Widget build(BuildContext context) {
    final promoDisc = (data['promoDiscount'] as num?)?.toDouble() ?? 0;
    final goldDisc = (data['goldDiscount'] as num?)?.toDouble() ?? 0;
    final isPaid = data['isPaid'] == true;
    final isCash = data['paymentMethod'] == 'COD';
    return _SectionCard(
      icon: Icons.receipt_long_outlined,
      title: 'Payment',
      child: Column(children: [
        _BRow('Base Price', '₹${data['basePrice'] ?? 0}'),
        _BRow('Platform Fee', '₹${data['platformFee'] ?? 0}'),
        if (promoDisc > 0) _BRow('Promo Discount', '−₹$promoDisc', vc: _green),
        if (goldDisc > 0) _BRow('Gold Discount', '−₹$goldDisc', vc: _amber),
        const SizedBox(height: 6),
        const Divider(color: _border, height: 1),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _txtDark)),
          Text('₹${data['total'] ?? 0}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: _cyan)),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _border)),
          child: Row(children: [
            Icon(isCash ? Icons.money_rounded : Icons.credit_card_rounded,
                size: 15, color: isPaid ? _green : _amber),
            const SizedBox(width: 7),
            Text(
                isCash
                    ? 'Cash on Delivery'
                    : (isPaid ? 'Paid Online ✓' : 'Online — Pending'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isPaid ? _green : _amber)),
          ]),
        ),
      ]),
    );
  }
}

class _BRow extends StatelessWidget {
  final String label, value;
  final Color? vc;
  const _BRow(this.label, this.value, {this.vc});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: _txtMuted)),
          Text(value,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: vc ?? _txtDark)),
        ]),
      );
}

// ─── Section Card Shell ───────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _SectionCard(
      {required this.icon, required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 14, color: _cyan),
            const SizedBox(width: 6),
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _cyan,
                    letterSpacing: .5)),
          ]),
          const Divider(color: _border, height: 16),
          child,
        ]),
      );
}

// ─── Completed Card ───────────────────────────────────────────────────────────
class _CompletedCard extends StatelessWidget {
  const _CompletedCard();
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
            color: _greenBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _greenBorder)),
        child: const Column(children: [
          Icon(Icons.check_circle_rounded, color: _green, size: 46),
          SizedBox(height: 10),
          Text('Job Completed!',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: _greenTxt)),
          SizedBox(height: 5),
          Text('Your earnings will be credited to your account.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: _txtMuted, height: 1.5)),
        ]),
      );
}
