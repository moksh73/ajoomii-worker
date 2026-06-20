import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Design Tokens ───────────────────────────────────────────────────────────
const Color _cyan = Color(0xFF06B6D4);
const Color _bg = Color(0xFFF5FAFE);
const Color _card = Color(0xFFFFFFFF);
const Color _surface = Color(0xFFF0F8FC);
const Color _border = Color(0xFFD4ECF5);
const Color _txtDark = Color(0xFF0D2B35);
const Color _txtMuted = Color(0xFF6B9BAD);
const Color _green = Color(0xFF00C073);
const Color _greenBg = Color(0xFFDCFCE7);
const Color _greenBorder = Color(0xFF86EFAC);
const Color _greenTxt = Color(0xFF166534);
const Color _amber = Color(0xFFF59E0B);
const Color _amberBg = Color(0xFFFEF3C7);
const Color _amberBorder = Color(0xFFFDE68A);
const Color _amberTxt = Color(0xFF92400E);
const Color _red = Color(0xFFF43F5E);
const Color _redBg = Color(0xFFFFF0F0);
const Color _redBorder = Color(0xFFFFCDD2);
const Color _redTxt = Color(0xFF9B1C1C);
const Color _cyanBg = Color(0xFFE0F8FC);
const Color _cyanBorder = Color(0xFF99E8D2);
const Color _cyanTxt = Color(0xFF0E7490);

// ─────────────────────────────────────────────────────────────────────────────

class UserBookingDetailsScreen extends StatefulWidget {
  final String bookingId;

  const UserBookingDetailsScreen({super.key, required this.bookingId});

  @override
  State<UserBookingDetailsScreen> createState() =>
      _UserBookingDetailsScreenState();
}

class _UserBookingDetailsScreenState extends State<UserBookingDetailsScreen> {
  bool _loading = true;
  Map<String, dynamic>? _booking;
  Map<String, dynamic>? _worker;

  @override
  void initState() {
    super.initState();
    _loadBooking();
  }

  Future<void> _loadBooking() async {
    try {
      final bookingDoc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .get();

      if (!bookingDoc.exists) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final booking = bookingDoc.data()!;
      final workerId = booking['workerId'];

      final workerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(workerId)
          .get();

      if (mounted) {
        setState(() {
          _booking = booking;
          _worker = workerDoc.data();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Cancel ───────────────────────────────────────────────────────────────

  Future<void> _cancelBooking() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Cancel Booking?',
        message: 'Are you sure you want to cancel this booking?',
        confirmLabel: 'Yes, Cancel',
        confirmColor: _red,
      ),
    );

    if (confirm != true) return;

    await FirebaseFirestore.instance
        .collection('bookings')
        .doc(widget.bookingId)
        .update({'status': 'cancelled'});

    HapticFeedback.mediumImpact();

    if (mounted) {
      _showSnack('Booking cancelled.', isError: true);
      _loadBooking();
    }
  }

  // ─── Rating ───────────────────────────────────────────────────────────────

  Future<void> _showRatingDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _RatingDialog(
        workerId: _booking?['workerId'] ?? '',
        bookingId: widget.bookingId,
      ),
    );

    if (result == true && mounted) {
      _showSnack('Thanks for your review!', isSuccess: true);
      _loadBooking();
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            isError
                ? Icons.cancel_rounded
                : isSuccess
                    ? Icons.check_circle_rounded
                    : Icons.info_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
        ]),
        backgroundColor: isError
            ? _red
            : isSuccess
                ? _green
                : _cyan,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
      final m = d.minute.toString().padLeft(2, '0');
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      final months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${d.day} ${months[d.month - 1]} ${d.year}  $h:$m $ampm';
    }
    return '—';
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(children: [
          // Top bar
          Container(
            color: _card,
            padding: EdgeInsets.fromLTRB(14, top + 10, 14, 12),
            child: Row(children: [
              _CircleBtn(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Booking Details',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _txtDark),
                ),
              ),
            ]),
          ),

          // Body
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _cyan))
                : _booking == null
                    ? const Center(
                        child: Text('Booking not found',
                            style: TextStyle(color: _txtMuted)))
                    : _buildBody(),
          ),
        ]),
      ),
    );
  }

  Widget _buildBody() {
    final booking = _booking!;
    final worker = _worker;
    final status = booking['status'] as String? ?? 'pending';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Worker card ──────────────────────────────────────────────────
        _SectionCard(
          child: Column(children: [
            // Avatar
            _WorkerAvatar(worker: worker),
            const SizedBox(height: 12),
            Text(
              worker?['name'] ?? 'Worker',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: _txtDark),
            ),
            const SizedBox(height: 3),
            Text(
              worker?['service'] ?? '',
              style: const TextStyle(fontSize: 12.5, color: _txtMuted),
            ),
            const SizedBox(height: 16),
            // Rating row
            _RatingRow(worker: worker),
            const SizedBox(height: 16),
            // Action buttons
            Row(children: [
              Expanded(
                child: _ActionBtn(
                  icon: Icons.call_rounded,
                  label: 'Call',
                  color: _green,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionBtn(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Chat',
                  color: _cyan,
                  onTap: () {},
                ),
              ),
            ]),
          ]),
        ),

        const SizedBox(height: 12),

        // ── Status pill ──────────────────────────────────────────────────
        _StatusPill(status: status),

        const SizedBox(height: 12),

        // ── Booking info ─────────────────────────────────────────────────
        _SectionCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SectionHeader(
                icon: Icons.receipt_long_outlined, label: 'Booking Info'),
            const SizedBox(height: 14),
            _InfoRow(
              icon: Icons.home_repair_service_rounded,
              label: 'Service',
              value: booking['service'] ?? '—',
            ),
            _InfoRow(
              icon: Icons.currency_rupee_rounded,
              label: 'Amount',
              value: '₹${booking['amount'] ?? 0}',
              valueColor: _cyan,
            ),
            _InfoRow(
              icon: Icons.phone_rounded,
              label: 'Phone',
              value: booking['phone'] ?? '—',
            ),
            _InfoRow(
              icon: Icons.location_on_outlined,
              label: 'Address',
              value: booking['address'] ?? '—',
            ),
            _InfoRow(
              icon: Icons.calendar_today_rounded,
              label: 'Date',
              value: _formatDate(booking['createdAt']),
              isLast: true,
            ),
          ]),
        ),

        const SizedBox(height: 20),

        // ── CTA buttons ──────────────────────────────────────────────────
        if (status == 'pending')
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _cancelBooking,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel Booking',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _red,
                side: const BorderSide(color: _redBorder, width: 1.5),
                backgroundColor: _redBg,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

        if (status == 'completed' && booking['rated'] != true) ...[
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _showRatingDialog,
              icon:
                  const Icon(Icons.star_rounded, color: Colors.white, size: 18),
              label: const Text('Rate Your Experience',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _cyan,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],

        if (status == 'completed' && booking['rated'] == true)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: _greenBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _greenBorder),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle_rounded, color: _green, size: 18),
              SizedBox(width: 8),
              Text('You have already rated this booking.',
                  style: TextStyle(
                      color: _greenTxt,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }
}

// ─── Worker Avatar ────────────────────────────────────────────────────────────

class _WorkerAvatar extends StatelessWidget {
  final Map<String, dynamic>? worker;
  const _WorkerAvatar({required this.worker});

  @override
  Widget build(BuildContext context) {
    final image = worker?['profileImage'] as String?;
    final name = worker?['name'] as String? ?? 'W';
    final initials =
        name.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _border, width: 3),
      ),
      child: image != null && image.isNotEmpty
          ? ClipOval(child: Image.network(image, fit: BoxFit.cover))
          : Center(
              child: Text(initials,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ),
    );
  }
}

// ─── Rating Row ───────────────────────────────────────────────────────────────

class _RatingRow extends StatelessWidget {
  final Map<String, dynamic>? worker;
  const _RatingRow({required this.worker});

  @override
  Widget build(BuildContext context) {
    final rating = (worker?['rating'] as num?)?.toDouble() ?? 0;
    final jobs = worker?['totalJobs'] as int? ?? 0;

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.star_rounded, color: _amber, size: 18),
      const SizedBox(width: 4),
      Text(
        rating > 0 ? rating.toStringAsFixed(1) : '—',
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _txtDark),
      ),
      const SizedBox(width: 10),
      Container(width: 1, height: 14, color: _border),
      const SizedBox(width: 10),
      const Icon(Icons.work_outline_rounded, size: 15, color: _txtMuted),
      const SizedBox(width: 4),
      Text('$jobs jobs',
          style: const TextStyle(fontSize: 13, color: _txtMuted)),
    ]);
  }
}

// ─── Action Button ────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}

// ─── Status Pill ─────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    late Color bg, border, dot, txt;
    late String label;
    late IconData icon;

    switch (status) {
      case 'completed':
        bg = _greenBg;
        border = _greenBorder;
        dot = _green;
        txt = _greenTxt;
        label = 'Booking Completed';
        icon = Icons.check_circle_rounded;
        break;
      case 'active':
      case 'ongoing':
        bg = _cyanBg;
        border = _cyanBorder;
        dot = _cyan;
        txt = _cyanTxt;
        label = 'Job In Progress';
        icon = Icons.construction_rounded;
        break;
      case 'cancelled':
        bg = _redBg;
        border = _redBorder;
        dot = _red;
        txt = _redTxt;
        label = 'Booking Cancelled';
        icon = Icons.cancel_rounded;
        break;
      default: // pending
        bg = _amberBg;
        border = _amberBorder;
        dot = _amber;
        txt = _amberTxt;
        label = 'Pending Confirmation';
        icon = Icons.hourglass_top_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Icon(icon, size: 15, color: txt),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: txt)),
      ]),
    );
  }
}

// ─── Section Card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 15, color: _cyan),
      const SizedBox(width: 7),
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _cyan,
          letterSpacing: .6,
        ),
      ),
    ]);
  }
}

// ─── Info Row ─────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isLast;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _border),
          ),
          child: Icon(icon, size: 16, color: _cyan),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 11, color: _txtMuted)),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? _txtDark,
                  height: 1.4,
                )),
          ]),
        ),
      ]),
      if (!isLast) ...[
        const SizedBox(height: 12),
        const Divider(color: _border, height: 1),
        const SizedBox(height: 12),
      ],
    ]);
  }
}

// ─── Circle Button ────────────────────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _card,
          shape: BoxShape.circle,
          border: Border.all(color: _border),
        ),
        child: Icon(icon, size: 16, color: _txtDark),
      ),
    );
  }
}

// ─── Confirm Dialog ───────────────────────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _redBg,
              shape: BoxShape.circle,
              border: Border.all(color: _redBorder),
            ),
            child:
                const Icon(Icons.warning_amber_rounded, color: _red, size: 26),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: _txtDark)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 13, color: _txtMuted, height: 1.5)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _txtMuted,
                  side: const BorderSide(color: _border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('No, Keep',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(confirmLabel,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ─── Rating Dialog ────────────────────────────────────────────────────────────

class _RatingDialog extends StatefulWidget {
  final String workerId;
  final String bookingId;

  const _RatingDialog({required this.workerId, required this.bookingId});

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  double _rating = 5;
  final _reviewCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.workerId)
          .collection('reviews')
          .add({
        'rating': _rating,
        'review': _reviewCtrl.text.trim(),
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(widget.bookingId)
          .update({'rated': true});

      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _amberBg,
              shape: BoxShape.circle,
              border: Border.all(color: _amberBorder),
            ),
            child: const Icon(Icons.star_rounded, color: _amber, size: 28),
          ),
          const SizedBox(height: 12),
          const Text('Rate Your Experience',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: _txtDark)),
          const SizedBox(height: 4),
          const Text('How was the service?',
              style: TextStyle(fontSize: 12.5, color: _txtMuted)),
          const SizedBox(height: 16),

          // Stars
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              return GestureDetector(
                onTap: () => setState(() => _rating = i + 1.0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    i < _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: _amber,
                    size: 36,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Review field
          TextField(
            controller: _reviewCtrl,
            maxLines: 3,
            style: const TextStyle(fontSize: 13.5, color: _txtDark),
            decoration: InputDecoration(
              hintText: 'Share your experience (optional)...',
              hintStyle: const TextStyle(color: _txtMuted, fontSize: 13),
              filled: true,
              fillColor: _surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _cyan, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Buttons
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _txtMuted,
                  side: const BorderSide(color: _border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cyan,
                  disabledBackgroundColor: _cyan.withOpacity(.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Submit',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
