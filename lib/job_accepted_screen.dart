// job_request_screen.dart
// Worker Side — Job Accepted Screen (Instant + Scheduled)
//
// ENHANCED TRACKING:
//   • Full-screen prominent map showing customer's pinned location
//   • Worker's live GPS position streamed to Firestore & shown on map
//   • Camera auto-fits both worker + customer markers with padding
//   • Distance + ETA chip updated every GPS tick
//   • Reverse geocoded exact address shown below map
//   • "Navigate" opens Google Maps turn-by-turn to customer
//   • Map recenter FAB always brings both pins into view
//   • Removed customer profile sheet — clean, focused job screen
//
// STATUS MACHINE:
//   accepted            → worker heads to customer
//   arrived             → worker tapped "I've Arrived" → arrivalOtp generated
//   working             → customer verified arrival OTP → job timer runs
//   waitingCompletionOtp→ customer generated completion OTP, worker must enter it
//   completed           → worker entered correct completion OTP → commission shown
//
// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_screen.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
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
const _orange = Color(0xFFFF6B35);
const _orangeBg = Color(0xFFFFF3EE);
const _orangeBdr = Color(0xFFFFCDB8);

const _cyanBorder30 = Color(0x4D06B6D4);

// ─── Admin constants ──────────────────────────────────────────────────────────
const _adminUpi = 'bhardwajkrishna@fam';
const _adminPhone = '9179369730';
const _adminName = 'Krishna Bhardwaj';

// ─── Helpers ──────────────────────────────────────────────────────────────────
String _genOtp() => (1000 + Random.secure().nextInt(9000)).toString();

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * (pi / 180);
  final dLon = (lon2 - lon1) * (pi / 180);
  final a = pow(sin(dLat / 2), 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * pow(sin(dLon / 2), 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

Future<Map<String, dynamic>> _calcCommission(String workerId) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));
  final snap = await FirebaseFirestore.instance
      .collection('requests')
      .where('workerId', isEqualTo: workerId)
      .where('status', isEqualTo: 'completed')
      .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('completedAt', isLessThan: Timestamp.fromDate(end))
      .get();
  final jobs = snap.docs.length;
  double earned = 0;
  for (final d in snap.docs) {
    earned += ((d.data()['total'] as num?) ?? 0).toDouble();
  }
  double amt = 0;
  String rule = '';
  if (jobs == 0) {
    rule = 'No jobs today';
  } else if (jobs == 1) {
    amt = 20;
    rule = '₹20 flat  (1 job / day)';
  } else if (jobs < 5) {
    amt = (earned * 0.10).roundToDouble();
    rule = '10% of ₹${earned.toStringAsFixed(0)}';
  } else {
    amt = (earned * 0.15).roundToDouble();
    rule = '15% of ₹${earned.toStringAsFixed(0)}';
  }
  return {
    'jobs': jobs,
    'earned': earned,
    'amt': amt,
    'rule': rule,
    'mustPay': jobs > 0 && amt > 0,
  };
}

Future<void> _launchUpi(double amount, String note) async {
  final uri = Uri.parse(
    'upi://pay?pa=$_adminUpi'
    '&pn=${Uri.encodeComponent(_adminName)}'
    '&am=${amount.toStringAsFixed(2)}'
    '&cu=INR'
    '&tn=${Uri.encodeComponent(note)}',
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  MAIN SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class JobRequestScreen extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final String workerId;
  final Map<String, dynamic> workerData;

  const JobRequestScreen({
    super.key,
    required this.requestId,
    required this.data,
    required this.workerId,
    required this.workerData,
  });

  @override
  State<JobRequestScreen> createState() => _JobRequestScreenState();
}

class _JobRequestScreenState extends State<JobRequestScreen> {
  bool _busy = false;
  final _completionOtpCtrl = TextEditingController();

  // Job timer
  Timer? _jobTimer;
  Duration _elapsed = Duration.zero;

  // Countdown timer for scheduled
  Timer? _countdownTimer;
  Duration _countdown = Duration.zero;

  // Location tracking
  Position? _workerPos;
  StreamSubscription<Position>? _posStream;
  double? _distanceKm;
  String _etaText = '';
  String _resolvedAddress = '';
  bool _addressLoading = false;
  bool _locationPermissionDenied = false;

  // Map controller
  final Completer<GoogleMapController> _mapCtrl = Completer();
  Set<Marker> _markers = {};
  bool _mapReady = false;

  // Customer location (from Firestore)
  LatLng? _customerLatLng;

  @override
  void initState() {
    super.initState();
    _initWorkerLocation();
    _resolveCustomerLocation();
  }

  @override
  void dispose() {
    _completionOtpCtrl.dispose();
    _jobTimer?.cancel();
    _countdownTimer?.cancel();
    _posStream?.cancel();
    super.dispose();
  }

  // ── Firestore ref ─────────────────────────────────────────────────────────
  DocumentReference get _ref =>
      FirebaseFirestore.instance.collection('requests').doc(widget.requestId);

  // ═══════════════════════════════════════════════════════
  //  LOCATION TRACKING
  // ═══════════════════════════════════════════════════════

  Future<void> _initWorkerLocation() async {
    try {
      final svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) {
        if (mounted) setState(() => _locationPermissionDenied = true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationPermissionDenied = true);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() => _workerPos = pos);
        _updateDistanceEta(pos);
        _updateWorkerMarker(pos);
      }

      _posStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 8,
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() => _workerPos = p);
        _updateDistanceEta(p);
        _updateWorkerMarker(p);
        // Push worker location to Firestore so customer can track
        _ref.update({
          'workerLat': p.latitude,
          'workerLng': p.longitude,
          'workerLocationUpdatedAt': FieldValue.serverTimestamp(),
        }).catchError((_) {});
      });
    } catch (e) {
      debugPrint('Location init error: $e');
    }
  }

  void _updateDistanceEta(Position workerPos) {
    if (_customerLatLng == null) return;
    final km = _haversineKm(workerPos.latitude, workerPos.longitude,
        _customerLatLng!.latitude, _customerLatLng!.longitude);
    final minutes = (km / 30.0 * 60).round();
    if (mounted) {
      setState(() {
        _distanceKm = km;
        _etaText = minutes < 1
            ? 'You are here'
            : minutes < 60
                ? '$minutes min away'
                : '${(minutes / 60).toStringAsFixed(1)} hr away';
      });
    }
  }

  Future<void> _updateWorkerMarker(Position pos) async {
    if (!_mapReady) return;
    try {
      final ctrl = await _mapCtrl.future;
      final workerMarker = Marker(
        markerId: const MarkerId('worker'),
        position: LatLng(pos.latitude, pos.longitude),
        infoWindow: const InfoWindow(title: 'You (Worker)'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        zIndex: 2,
      );
      if (mounted) {
        setState(() {
          _markers = {
            ..._markers.where((m) => m.markerId.value != 'worker'),
            workerMarker,
          };
        });
        _fitBothMarkers(ctrl, pos.latitude, pos.longitude);
      }
    } catch (_) {}
  }

  void _fitBothMarkers(
      GoogleMapController ctrl, double workerLat, double workerLng) {
    if (_customerLatLng == null) {
      ctrl.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(workerLat, workerLng), 16));
      return;
    }
    final sw = LatLng(
      min(workerLat, _customerLatLng!.latitude) - 0.004,
      min(workerLng, _customerLatLng!.longitude) - 0.004,
    );
    final ne = LatLng(
      max(workerLat, _customerLatLng!.latitude) + 0.004,
      max(workerLng, _customerLatLng!.longitude) + 0.004,
    );
    ctrl.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: sw, northeast: ne), 56));
  }

  Future<void> _recenterMap() async {
    if (!_mapReady) return;
    try {
      final ctrl = await _mapCtrl.future;
      if (_workerPos != null) {
        _fitBothMarkers(ctrl, _workerPos!.latitude, _workerPos!.longitude);
      } else if (_customerLatLng != null) {
        ctrl.animateCamera(CameraUpdate.newLatLngZoom(_customerLatLng!, 16));
      }
    } catch (_) {}
  }

  Future<void> _resolveCustomerLocation() async {
    try {
      final requestData = widget.data;
      double? lat, lng;

      if (requestData['customerLocation'] is GeoPoint) {
        final gp = requestData['customerLocation'] as GeoPoint;
        lat = gp.latitude;
        lng = gp.longitude;
      } else if (requestData['customerLat'] != null &&
          requestData['customerLng'] != null) {
        lat = (requestData['customerLat'] as num).toDouble();
        lng = (requestData['customerLng'] as num).toDouble();
      } else if (requestData['latitude'] != null &&
          requestData['longitude'] != null) {
        lat = (requestData['latitude'] as num).toDouble();
        lng = (requestData['longitude'] as num).toDouble();
      }

      if (lat == null || lng == null) {
        final userId = requestData['userId'] as String?;
        if (userId != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();
          final ud = userDoc.data() ?? {};
          if (ud['location'] is GeoPoint) {
            final gp = ud['location'] as GeoPoint;
            lat = gp.latitude;
            lng = gp.longitude;
          } else if (ud['latitude'] != null && ud['longitude'] != null) {
            lat = (ud['latitude'] as num).toDouble();
            lng = (ud['longitude'] as num).toDouble();
          }
        }
      }

      if (lat == null || lng == null) return;

      final latlng = LatLng(lat, lng);
      if (mounted) setState(() => _customerLatLng = latlng);

      final customerMarker = Marker(
        markerId: const MarkerId('customer'),
        position: latlng,
        infoWindow: InfoWindow(
          title: requestData['userName'] as String? ?? 'Customer',
          snippet: 'Service location',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        zIndex: 1,
      );
      if (mounted) {
        setState(() {
          _markers = {
            ..._markers.where((m) => m.markerId.value != 'customer'),
            customerMarker,
          };
        });
      }

      // Reverse geocode
      if (mounted) setState(() => _addressLoading = true);
      try {
        final placemarks = await placemarkFromCoordinates(lat!, lng!);
        if (placemarks.isNotEmpty && mounted) {
          final p = placemarks.first;
          final parts = [
            if ((p.name ?? '').isNotEmpty && p.name != p.street) p.name,
            if ((p.subThoroughfare ?? '').isNotEmpty) p.subThoroughfare,
            if ((p.thoroughfare ?? '').isNotEmpty) p.thoroughfare,
            if ((p.subLocality ?? '').isNotEmpty) p.subLocality,
            if ((p.locality ?? '').isNotEmpty) p.locality,
            if ((p.postalCode ?? '').isNotEmpty) p.postalCode,
          ].whereType<String>().toList();
          if (mounted) {
            setState(() {
              _resolvedAddress = parts.join(', ');
              _addressLoading = false;
            });
          }
        }
      } catch (_) {
        if (mounted) setState(() => _addressLoading = false);
      }

      if (_workerPos != null) _updateDistanceEta(_workerPos!);
    } catch (e) {
      debugPrint('Customer location resolve error: $e');
    }
  }

  Future<void> _navigate() async {
    if (_customerLatLng == null) {
      _snack('Customer location not available yet');
      return;
    }
    final lat = _customerLatLng!.latitude;
    final lng = _customerLatLng!.longitude;
    final gmapsUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(gmapsUri)) {
      await launchUrl(gmapsUri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Timers ────────────────────────────────────────────────────────────────
  void _startJobTimer(Timestamp? startedAt) {
    if (_jobTimer != null) return;
    final base = startedAt?.toDate() ?? DateTime.now();
    _jobTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(base));
    });
  }

  void _startCountdown(String? dateStr, String? timeStr) {
    if (_countdownTimer != null || dateStr == null || timeStr == null) return;
    try {
      final parts = dateStr.split('/');
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      final tp = timeStr.toUpperCase();
      final isPm = tp.contains('PM');
      final hm = tp.replaceAll(RegExp(r'[APM\s]'), '').split(':');
      int hour = int.parse(hm[0]);
      final minute = int.parse(hm[1]);
      if (isPm && hour != 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      final scheduled = DateTime(year, month, day, hour, minute);
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final diff = scheduled.difference(DateTime.now());
        setState(() => _countdown = diff.isNegative ? Duration.zero : diff);
      });
    } catch (_) {}
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ── STEP 1 : Worker arrives ───────────────────────────────────────────────
  Future<void> _markArrived() async {
    _setBusy(true);
    try {
      await _ref.update({
        'status': 'arrived',
        'arrivedAt': FieldValue.serverTimestamp(),
        'arrivalOtp': _genOtp(),
        'otpVerified': false,
      });
      _snack('Show the arrival OTP to the customer.', ok: true);
    } catch (e) {
      _snack('Error: $e');
    } finally {
      _setBusy(false);
    }
  }

  // ── STEP 4 : Worker enters completion OTP ─────────────────────────────────
  Future<void> _verifyCompletionOtp({
    required String storedOtp,
    required double total,
  }) async {
    final entered = _completionOtpCtrl.text.trim();
    if (entered.length != 4) {
      _snack('Enter the 4-digit OTP shown on customer\'s screen.');
      return;
    }
    if (entered != storedOtp) {
      _snack('Wrong OTP — ask the customer to show their screen again.');
      return;
    }
    _setBusy(true);
    try {
      await _ref.update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'completionOtpVerified': true,
      });
      if (!mounted) return;
      await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.workerId)
          .update({
        'totalJobs': FieldValue.increment(1),
        'totalEarnings': FieldValue.increment(total),
      });
      if (!mounted) return;
      _jobTimer?.cancel();
      _posStream?.cancel();
      _snack('Job completed! Great work.', ok: true);
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      final cm = await _calcCommission(widget.workerId);
      if (!mounted) return;
      if (cm['mustPay'] == true) {
        await _showCommissionSheet(cm);
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  Future<void> _showCommissionSheet(Map<String, dynamic> cm) async {
    final jobs = cm['jobs'] as int;
    final earned = cm['earned'] as double;
    final amt = cm['amt'] as double;
    final rule = cm['rule'] as String;
    final color = jobs == 1
        ? _cyan
        : jobs < 5
            ? _amber
            : _orange;
    final note =
        'Worker commission – $jobs job${jobs > 1 ? 's' : ''} – ₹${amt.toStringAsFixed(0)}';
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PopScope(
        canPop: false,
        child: _CommissionSheet(
          jobs: jobs,
          earned: earned,
          amt: amt,
          rule: rule,
          color: color,
          note: note,
          onPay: () => _launchUpi(amt, note),
          onDone: () {
            Navigator.pop(context);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _openChat(Map<String, dynamic> live) {
    final uid = live['userId'] as String? ?? '';
    final userName = live['userName'] as String? ?? 'Customer';
    final userImg = live['userImage'] as String? ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatRoomId: 'chat_${widget.requestId}_${widget.workerId}_$uid',
          currentUserId: widget.workerId,
          otherUserId: uid,
          otherUserName: userName,
          otherUserImage: userImg,
          isWorker: true,
          chatId: 'chat_${widget.requestId}',
          workerName: widget.workerData['name'] as String? ?? '',
          workerId: widget.workerId,
          workerPhone: widget.workerData['phone'] as String? ?? '',
          serviceName: live['category'] as String? ?? '',
          requestId: widget.requestId,
        ),
      ),
    );
  }

  void _setBusy(bool v) {
    if (mounted) setState(() => _busy = v);
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
    return StreamBuilder<DocumentSnapshot>(
      stream: _ref.snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const _Loader();
        final live = snap.data!.data() as Map<String, dynamic>? ?? {};
        final status = live['status'] as String? ?? 'accepted';
        final isScheduled = live['isScheduled'] == true;
        final arrivalOtp = live['arrivalOtp'] as String? ?? '';
        final otpVerified = live['otpVerified'] == true;
        final completionOtp = live['completionOtp'] as String? ?? '';
        final total = ((live['total'] as num?) ?? 0).toDouble();
        final scheduledDate = live['scheduledDate'] as String?;
        final scheduledTime = live['scheduledTime'] as String?;

        if (status == 'working') {
          _startJobTimer(live['workStartedAt'] as Timestamp?);
        }
        if (status == 'accepted' && isScheduled) {
          _startCountdown(scheduledDate, scheduledTime);
        }

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark
              .copyWith(statusBarColor: Colors.transparent),
          child: Scaffold(
            backgroundColor: _bg,
            body: Column(children: [
              _TopBar(
                isScheduled: isScheduled,
                status: status,
                onBack: () => Navigator.pop(context),
                onChat: () => _openChat(live),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Status Banner ─────────────────────────────────────
                      _StatusBanner(
                        status: status,
                        otpVerified: otpVerified,
                        isScheduled: isScheduled,
                      ),
                      const SizedBox(height: 12),

                      // ══ STRONG LIVE MAP SECTION ═══════════════════════════
                      _StrongTrackingCard(
                        customerLatLng: _customerLatLng,
                        markers: _markers,
                        mapCtrl: _mapCtrl,
                        distanceKm: _distanceKm,
                        etaText: _etaText,
                        resolvedAddress: _resolvedAddress,
                        addressLoading: _addressLoading,
                        locationPermissionDenied: _locationPermissionDenied,
                        rawAddress: live['location'] as String? ??
                            live['address'] as String? ??
                            '',
                        customerName: live['userName'] as String? ?? 'Customer',
                        onNavigate: _navigate,
                        onRecenter: _recenterMap,
                        onMapCreated: (c) {
                          if (!_mapCtrl.isCompleted) {
                            _mapCtrl.complete(c);
                            setState(() => _mapReady = true);
                            // After map created, if we already have customer loc, zoom to it
                            if (_customerLatLng != null) {
                              Future.delayed(const Duration(milliseconds: 400),
                                  () {
                                c.animateCamera(CameraUpdate.newLatLngZoom(
                                    _customerLatLng!, 15));
                              });
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // ── Countdown (scheduled) ─────────────────────────────
                      if (status == 'accepted' && isScheduled) ...[
                        _CountdownCard(
                          countdown: _countdown,
                          fmtFn: _fmt,
                          dateStr: scheduledDate ?? '',
                          timeStr: scheduledTime ?? '',
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Job timer (working) ───────────────────────────────
                      if (status == 'working') ...[
                        _JobTimerCard(elapsed: _elapsed, fmtFn: _fmt),
                        const SizedBox(height: 12),
                      ],

                      // ── Job + Payment summary ─────────────────────────────
                      _JobCard(data: live, isScheduled: isScheduled),
                      const SizedBox(height: 12),
                      _PaymentCard(data: live, isScheduled: isScheduled),
                      const SizedBox(height: 20),

                      // ── Action: Arrived ───────────────────────────────────
                      if (status == 'accepted')
                        _BigBtn(
                          label: "I've Arrived at Customer's Location",
                          icon: Icons.location_on_rounded,
                          color: _cyan,
                          loading: _busy,
                          onTap: _markArrived,
                        ),

                      // ── Arrival OTP display ───────────────────────────────
                      if (status == 'arrived' && arrivalOtp.isNotEmpty) ...[
                        _ArrivalOtpCard(otp: arrivalOtp, verified: otpVerified),
                        const SizedBox(height: 10),
                        if (!otpVerified)
                          const _InfoBanner(
                            icon: Icons.hourglass_top_rounded,
                            color: _amber,
                            bg: _amberBg,
                            border: _amberBdr,
                            title: 'Waiting for customer to verify arrival OTP',
                            sub:
                                'Ask the customer to open their app and enter the OTP shown above.',
                          ),
                        if (otpVerified)
                          const _VerifiedBadge(label: 'Arrival OTP Verified ✓'),
                      ],

                      // ── Working ───────────────────────────────────────────
                      if (status == 'working') ...[
                        const _VerifiedBadge(label: 'Arrival OTP Verified ✓'),
                        const SizedBox(height: 10),
                        const _InfoBanner(
                          icon: Icons.construction_rounded,
                          color: _cyan,
                          bg: _cyanLight,
                          border: _cyanBorder30,
                          title: 'Work in progress',
                          sub:
                              'When you finish, ask the customer to tap "Work Done?" in their app and share the OTP with you.',
                        ),
                      ],

                      // ── Completion OTP entry ──────────────────────────────
                      if (status == 'waitingCompletionOtp' &&
                          completionOtp.isNotEmpty) ...[
                        const _VerifiedBadge(label: 'Arrival OTP Verified ✓'),
                        const SizedBox(height: 12),
                        _EnterCompletionOtpCard(
                          ctrl: _completionOtpCtrl,
                          loading: _busy,
                          onVerify: () => _verifyCompletionOtp(
                            storedOtp: completionOtp,
                            total: total,
                          ),
                        ),
                      ],

                      if (status == 'completed') const _CompletedCard(),

                      const SizedBox(height: 20),
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

// ═════════════════════════════════════════════════════════════════════════════
//  STRONG TRACKING CARD — full-featured map for worker
// ═════════════════════════════════════════════════════════════════════════════
class _StrongTrackingCard extends StatelessWidget {
  final LatLng? customerLatLng;
  final Set<Marker> markers;
  final Completer<GoogleMapController> mapCtrl;
  final double? distanceKm;
  final String etaText;
  final String resolvedAddress;
  final String rawAddress;
  final String customerName;
  final bool addressLoading;
  final bool locationPermissionDenied;
  final VoidCallback onNavigate;
  final VoidCallback onRecenter;
  final void Function(GoogleMapController) onMapCreated;

  const _StrongTrackingCard({
    required this.customerLatLng,
    required this.markers,
    required this.mapCtrl,
    required this.distanceKm,
    required this.etaText,
    required this.resolvedAddress,
    required this.rawAddress,
    required this.customerName,
    required this.addressLoading,
    required this.locationPermissionDenied,
    required this.onNavigate,
    required this.onRecenter,
    required this.onMapCreated,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocation = customerLatLng != null;
    // Fallback to Indore if no location yet
    const defaultLatLng = LatLng(22.7196, 75.8577);
    final target = customerLatLng ?? defaultLatLng;
    final displayAddress =
        resolvedAddress.isNotEmpty ? resolvedAddress : rawAddress;

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: hasLocation ? _cyan.withOpacity(0.45) : _border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _cyan.withOpacity(hasLocation ? 0.14 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header row ───────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: hasLocation ? _cyanLight : _surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.my_location_rounded,
                color: hasLocation ? _cyan : _txtMuted,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Customer Location',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _txtDark)),
                    Text(
                      hasLocation
                          ? 'Live GPS tracking active'
                          : 'Fetching location...',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: hasLocation ? _cyan : _txtMuted,
                          fontWeight: FontWeight.w500),
                    ),
                  ]),
            ),
            // Live badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: hasLocation ? _greenBg : _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: hasLocation ? _greenBdr : _border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: hasLocation ? _green : _txtMuted,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  hasLocation ? 'LIVE' : 'LOCATING',
                  style: TextStyle(
                      color: hasLocation ? _greenTxt : _txtMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5),
                ),
              ]),
            ),
          ]),
        ),

        // ── Distance + ETA chips ─────────────────────────────────────────────
        if (distanceKm != null || etaText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              if (distanceKm != null)
                _InfoChip(
                  icon: Icons.straighten_rounded,
                  label: distanceKm! < 1
                      ? '${(distanceKm! * 1000).round()} m away'
                      : '${distanceKm!.toStringAsFixed(2)} km away',
                  color: _cyan,
                  bg: _cyanLight,
                ),
              if (distanceKm != null && etaText.isNotEmpty)
                const SizedBox(width: 8),
              if (etaText.isNotEmpty)
                _InfoChip(
                  icon: Icons.access_time_filled_rounded,
                  label: etaText,
                  color: _amber,
                  bg: _amberBg,
                ),
            ]),
          ),

        // ── Map — tall for strong visibility ────────────────────────────────
        Stack(children: [
          SizedBox(
            height: 260,
            child: hasLocation
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: target,
                      zoom: 15.5,
                    ),
                    markers: markers,
                    onMapCreated: onMapCreated,
                    myLocationEnabled: !locationPermissionDenied,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    compassEnabled: true,
                    trafficEnabled: true,
                    mapType: MapType.normal,
                  )
                : Container(
                    color: _surface,
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _cyanLight,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.location_searching_rounded,
                              color: _cyan, size: 32),
                        ),
                        const SizedBox(height: 12),
                        const Text('Fetching customer location...',
                            style: TextStyle(
                                color: _txtDark,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        const Text('Please wait a moment',
                            style: TextStyle(color: _txtMuted, fontSize: 12)),
                        const SizedBox(height: 14),
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: _cyan),
                        ),
                      ]),
                    ),
                  ),
          ),

          // Recenter FAB
          if (hasLocation)
            Positioned(
              top: 10,
              right: 10,
              child: GestureDetector(
                onTap: onRecenter,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: const Icon(Icons.center_focus_strong_rounded,
                      color: _cyan, size: 20),
                ),
              ),
            ),

          // Legend overlay (bottom-left of map)
          if (hasLocation)
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08), blurRadius: 6)
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.circle, color: _red, size: 10),
                  const SizedBox(width: 4),
                  const Text('Customer',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _txtDark)),
                  const SizedBox(width: 10),
                  const Icon(Icons.circle, color: _cyan, size: 10),
                  const SizedBox(width: 4),
                  const Text('You',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _txtDark)),
                ]),
              ),
            ),
        ]),

        // ── Exact address block ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: addressLoading
                ? const Row(children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _cyan),
                    ),
                    SizedBox(width: 10),
                    Text('Resolving exact address...',
                        style: TextStyle(fontSize: 12.5, color: _txtMuted)),
                  ])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_pin, color: _red, size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayAddress.isNotEmpty
                            ? displayAddress
                            : 'Address not available',
                        style: const TextStyle(
                            fontSize: 13,
                            color: _txtDark,
                            fontWeight: FontWeight.w600,
                            height: 1.45),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: displayAddress));
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _cyanLight,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(Icons.copy_rounded,
                            size: 13, color: _cyan),
                      ),
                    ),
                  ]),
          ),
        ),

        // ── Navigate button ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onNavigate,
              icon: const Icon(Icons.navigation_rounded,
                  color: Colors.white, size: 18),
              label: Text(
                hasLocation
                    ? 'Navigate to Customer'
                    : 'Navigate (location pending...)',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasLocation ? _cyan : _txtMuted,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color, bg;
  const _InfoChip(
      {required this.icon,
      required this.label,
      required this.color,
      required this.bg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w700)),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  TOP BAR
// ═════════════════════════════════════════════════════════════════════════════
class _TopBar extends StatelessWidget {
  final bool isScheduled;
  final String status;
  final VoidCallback onBack, onChat;
  const _TopBar({
    required this.isScheduled,
    required this.status,
    required this.onBack,
    required this.onChat,
  });

  Color get _statusColor {
    switch (status) {
      case 'working':
        return _green;
      case 'arrived':
        return _cyan;
      case 'waitingCompletionOtp':
        return _amber;
      case 'completed':
        return _green;
      default:
        return isScheduled ? _purple : _cyan;
    }
  }

  String get _statusLabel {
    switch (status) {
      case 'accepted':
        return 'Head to customer';
      case 'arrived':
        return 'Show OTP';
      case 'working':
        return 'Working';
      case 'waitingCompletionOtp':
        return 'Enter OTP';
      case 'completed':
        return 'Completed ✓';
      default:
        return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: _card,
      padding: EdgeInsets.fromLTRB(14, top + 10, 14, 12),
      child: Row(children: [
        _CircleBtn(
            icon: Icons.arrow_back_ios_new_rounded, onTap: onBack, size: 15),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Job Details',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _txtDark)),
            Row(children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 5),
                decoration:
                    BoxDecoration(color: _statusColor, shape: BoxShape.circle),
              ),
              Text(
                _statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: _statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isScheduled ? '· Scheduled' : '· Instant',
                style: const TextStyle(fontSize: 11, color: _txtMuted),
              ),
            ]),
          ]),
        ),
        _CircleBtn(
          icon: Icons.chat_bubble_outline_rounded,
          onTap: onChat,
          filled: true,
        ),
      ]),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool filled;
  const _CircleBtn({
    required this.icon,
    required this.onTap,
    this.size = 18,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: filled ? _cyan : _card,
            shape: BoxShape.circle,
            border: Border.all(color: filled ? _cyan : _border),
            boxShadow: filled
                ? [
                    BoxShadow(
                        color: _cyan.withOpacity(0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]
                : [],
          ),
          child:
              Icon(icon, size: size, color: filled ? Colors.white : _txtDark),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  STATUS BANNER
// ═════════════════════════════════════════════════════════════════════════════
class _StatusBanner extends StatelessWidget {
  final String status;
  final bool otpVerified, isScheduled;
  const _StatusBanner({
    required this.status,
    required this.otpVerified,
    required this.isScheduled,
  });

  @override
  Widget build(BuildContext context) {
    Color c;
    String label;
    IconData icon;

    switch (status) {
      case 'accepted':
        c = isScheduled ? _purple : _amber;
        label = isScheduled
            ? 'Scheduled — head out before your appointment time'
            : 'Instant — head to customer location now';
        icon = isScheduled
            ? Icons.event_available_rounded
            : Icons.directions_walk_rounded;
        break;
      case 'arrived':
        c = otpVerified ? _green : _cyan;
        label = otpVerified
            ? 'Arrival confirmed — work in progress'
            : 'Arrived — show OTP to customer';
        icon = otpVerified ? Icons.verified_rounded : Icons.location_on_rounded;
        break;
      case 'working':
        c = _cyan;
        label = 'Working — ask customer for completion OTP when done';
        icon = Icons.construction_rounded;
        break;
      case 'waitingCompletionOtp':
        c = _amber;
        label = 'Enter the completion OTP shown on customer\'s screen';
        icon = Icons.password_rounded;
        break;
      case 'completed':
        c = _green;
        label = 'Job completed successfully ✓';
        icon = Icons.check_circle_rounded;
        break;
      default:
        c = _txtMuted;
        label = status.toUpperCase();
        icon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.25)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration:
              BoxDecoration(color: c.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, color: c, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  COUNTDOWN CARD
// ═════════════════════════════════════════════════════════════════════════════
class _CountdownCard extends StatelessWidget {
  final Duration countdown;
  final String Function(Duration) fmtFn;
  final String dateStr, timeStr;
  const _CountdownCard({
    required this.countdown,
    required this.fmtFn,
    required this.dateStr,
    required this.timeStr,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _purpleBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _purpleBdr),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _purple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.timer_outlined, color: _purple, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Time until appointment',
                  style: TextStyle(
                      fontSize: 11,
                      color: _purpleTxt,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                countdown == Duration.zero ? 'Time to go!' : fmtFn(countdown),
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: _purple,
                    letterSpacing: -0.5),
              ),
              if (dateStr.isNotEmpty && timeStr.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text('$dateStr  ·  $timeStr',
                    style: const TextStyle(fontSize: 11.5, color: _purpleTxt)),
              ],
            ]),
          ),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  JOB TIMER CARD
// ═════════════════════════════════════════════════════════════════════════════
class _JobTimerCard extends StatelessWidget {
  final Duration elapsed;
  final String Function(Duration) fmtFn;
  const _JobTimerCard({required this.elapsed, required this.fmtFn});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _cyanLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cyan.withOpacity(0.3)),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: _cyan.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.timer_rounded, color: _cyan, size: 20),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Job timer',
                style: TextStyle(
                    fontSize: 11,
                    color: _cyanDark,
                    fontWeight: FontWeight.w600)),
            Text(fmtFn(elapsed),
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: _cyanDark,
                    letterSpacing: -0.5)),
          ]),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, color: _green, size: 7),
              SizedBox(width: 5),
              Text('Live',
                  style: TextStyle(
                      color: _green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  JOB CARD
// ═════════════════════════════════════════════════════════════════════════════
class _JobCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isScheduled;
  const _JobCard({required this.data, required this.isScheduled});

  @override
  Widget build(BuildContext context) {
    final scheduledDate = data['scheduledDate'] as String?;
    final scheduledTime = data['scheduledTime'] as String?;
    return _Section(
      icon: Icons.home_repair_service_rounded,
      title: 'Job Details',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (data['category'] != null)
          _Row('Category', data['category'] as String),
        if (data['subCategory'] != null)
          _Row('Service', data['subCategory'] as String),
        if ((data['description'] as String?)?.isNotEmpty == true)
          _Row('Description', data['description'] as String),
        if (isScheduled &&
            (scheduledDate != null || scheduledTime != null)) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _purpleBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _purpleBdr),
            ),
            child: Row(children: [
              const Icon(Icons.event_rounded, color: _purple, size: 16),
              const SizedBox(width: 8),
              Text(
                [
                  if (scheduledDate != null) scheduledDate,
                  if (scheduledTime != null) scheduledTime,
                ].join('  ·  '),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _purpleTxt),
              ),
            ]),
          ),
        ] else if (!isScheduled) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _cyanLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _cyan.withOpacity(0.3)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bolt_rounded, color: _cyan, size: 13),
              SizedBox(width: 4),
              Text('Instant — arrive as soon as possible',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: _cyanDark,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
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
            width: 92,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: _txtMuted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _txtDark,
                    height: 1.4)),
          ),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  PAYMENT CARD
// ═════════════════════════════════════════════════════════════════════════════
class _PaymentCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isScheduled;
  const _PaymentCard({required this.data, required this.isScheduled});

  @override
  Widget build(BuildContext context) {
    final promoDisc = (data['promoDiscount'] as num?)?.toDouble() ?? 0;
    final goldDisc = (data['goldDiscount'] as num?)?.toDouble() ?? 0;
    final isPaid = data['isPaid'] == true;
    final isCash = data['paymentMethod'] == 'COD';
    final commissionHint = isScheduled
        ? '10% or 15% depending on daily jobs'
        : '₹20 flat for instant booking';

    return _Section(
      icon: Icons.receipt_long_outlined,
      title: 'Payment',
      child: Column(children: [
        _PR('Base Price', '₹${data['basePrice'] ?? 0}'),
        _PR('Platform Fee', '₹${data['platformFee'] ?? 0}'),
        if (promoDisc > 0) _PR('Promo Discount', '−₹$promoDisc', vc: _green),
        if (goldDisc > 0) _PR('Gold Discount', '−₹$goldDisc', vc: _amber),
        const SizedBox(height: 6),
        const Divider(color: _border, height: 1),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _txtDark)),
          Text('₹${data['total'] ?? 0}',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, color: _cyan)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: Row(children: [
            Icon(
              isCash ? Icons.money_rounded : Icons.credit_card_rounded,
              size: 15,
              color: isPaid ? _green : _amber,
            ),
            const SizedBox(width: 8),
            Text(
              isCash
                  ? 'Cash on delivery'
                  : (isPaid ? 'Paid online ✓' : 'Online payment — pending'),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isPaid ? _green : _amber),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isScheduled ? _amberBg : _cyanLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isScheduled ? _amberBdr : _cyan.withOpacity(0.3)),
          ),
          child: Row(children: [
            Icon(Icons.info_outline_rounded,
                size: 14, color: isScheduled ? _amber : _cyan),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'Your commission: $commissionHint',
                style: TextStyle(
                    fontSize: 11.5,
                    color: isScheduled ? _amberTxt : _cyanDark,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _PR extends StatelessWidget {
  final String label, value;
  final Color? vc;
  const _PR(this.label, this.value, {this.vc});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: _txtMuted, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: vc ?? _txtDark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  ARRIVAL OTP CARD
// ═════════════════════════════════════════════════════════════════════════════
class _ArrivalOtpCard extends StatelessWidget {
  final String otp;
  final bool verified;
  const _ArrivalOtpCard({required this.otp, required this.verified});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: verified ? _greenBg : _cyanLight,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: verified ? _greenBdr : _cyan.withOpacity(0.35)),
        ),
        child: Column(children: [
          Row(children: [
            Icon(
              verified ? Icons.verified_rounded : Icons.lock_open_rounded,
              color: verified ? _green : _cyan,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              verified
                  ? 'Arrival OTP verified ✓'
                  : 'Show this OTP to the customer',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: verified ? _greenTxt : _cyanDark),
            ),
          ]),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: otp
                .split('')
                .map((d) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      width: 56,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color:
                                verified ? _greenBdr : _cyan.withOpacity(0.4),
                            width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (verified ? _green : _cyan).withOpacity(0.10),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(d,
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: verified ? _green : _txtDark)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          Text(
            verified
                ? 'Customer confirmed your arrival'
                : 'Customer enters this OTP on their tracking screen',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                color: verified ? _greenTxt : _txtMuted,
                height: 1.4),
          ),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  ENTER COMPLETION OTP CARD
// ═════════════════════════════════════════════════════════════════════════════
class _EnterCompletionOtpCard extends StatelessWidget {
  final TextEditingController ctrl;
  final bool loading;
  final VoidCallback onVerify;
  const _EnterCompletionOtpCard({
    required this.ctrl,
    required this.loading,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _amberBdr),
          boxShadow: [
            BoxShadow(
                color: _amber.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: _amberBg, borderRadius: BorderRadius.circular(10)),
              child:
                  const Icon(Icons.password_rounded, color: _amber, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Enter completion OTP',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _txtDark)),
                    SizedBox(height: 2),
                    Text(
                        'Ask the customer to show you the OTP from their screen',
                        style: TextStyle(fontSize: 11.5, color: _txtMuted)),
                  ]),
            ),
          ]),
          const SizedBox(height: 18),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 14,
                color: _txtDark),
            decoration: InputDecoration(
              counterText: '',
              hintText: '· · · ·',
              hintStyle: TextStyle(
                  color: Colors.grey.shade300, fontSize: 26, letterSpacing: 14),
              filled: true,
              fillColor: _surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _amber, width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: loading ? null : onVerify,
              style: ElevatedButton.styleFrom(
                backgroundColor: _amber,
                disabledBackgroundColor: _amber.withOpacity(0.5),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('Verify & complete job',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ],
                    ),
            ),
          ),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  SMALL REUSABLE WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class _BigBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;
  const _BigBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: loading ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: color.withOpacity(0.5),
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ]),
        ),
      );
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color, bg, border;
  final String title, sub;
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.bg,
    required this.border,
    required this.title,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: border)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
              const SizedBox(height: 3),
              Text(sub,
                  style: const TextStyle(
                      fontSize: 11.5, color: _txtMuted, height: 1.4)),
            ]),
          ),
        ]),
      );
}

class _VerifiedBadge extends StatelessWidget {
  final String label;
  const _VerifiedBadge({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: _greenBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _greenBdr)),
        child: Row(children: [
          const Icon(Icons.verified_rounded, color: _green, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: _greenTxt, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
}

class _CompletedCard extends StatelessWidget {
  const _CompletedCard();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30),
        decoration: BoxDecoration(
            color: _greenBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _greenBdr)),
        child: const Column(children: [
          Icon(Icons.check_circle_rounded, color: _green, size: 52),
          SizedBox(height: 12),
          Text('Job Completed!',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: _greenTxt)),
          SizedBox(height: 6),
          Text('Earnings updated in your account.',
              style: TextStyle(fontSize: 13, color: _txtMuted)),
        ]),
      );
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  const _Section(
      {required this.icon, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 13, color: _cyan),
            const SizedBox(width: 6),
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: _cyan,
                    letterSpacing: 0.5)),
          ]),
          const Divider(color: _border, height: 16),
          child,
        ]),
      );
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: CircularProgressIndicator(color: _cyan, strokeWidth: 2.5),
        ),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  COMMISSION SHEET
// ═════════════════════════════════════════════════════════════════════════════
class _CommissionSheet extends StatelessWidget {
  final int jobs;
  final double earned, amt;
  final String rule, note;
  final Color color;
  final VoidCallback onPay, onDone;
  const _CommissionSheet({
    required this.jobs,
    required this.earned,
    required this.amt,
    required this.rule,
    required this.note,
    required this.color,
    required this.onPay,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(18, 18, 18, bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
              color: _border, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 16),
        Icon(Icons.currency_rupee_rounded, color: color, size: 36),
        const SizedBox(height: 8),
        const Text('Daily Commission',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: _txtDark)),
        const SizedBox(height: 4),
        Text(
          '$jobs job${jobs > 1 ? 's' : ''} completed today — great work!',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: _txtMuted),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border)),
          child: Row(children: [
            _CStat(label: 'Jobs', value: '$jobs', color: _cyan),
            _CVDivider(),
            _CStat(
                label: 'Earned',
                value: '₹${earned.toStringAsFixed(0)}',
                color: _green),
            _CVDivider(),
            _CStat(
                label: 'Commission',
                value: '₹${amt.toStringAsFixed(0)}',
                color: color),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
              color: color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.20))),
          child: Column(children: [
            Text('Pay to Admin',
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('₹${amt.toStringAsFixed(0)}',
                style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: -1)),
            Text(rule, style: const TextStyle(fontSize: 12, color: _txtMuted)),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
              color: _greenBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _greenBdr)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Admin UPI details',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _greenTxt)),
            const SizedBox(height: 8),
            const _CUpiRow('UPI ID', _adminUpi),
            const SizedBox(height: 4),
            const _CUpiRow('Phone', _adminPhone),
            const SizedBox(height: 4),
            const _CUpiRow('Name', _adminName),
          ]),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: onPay,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text('Pay ₹${amt.toStringAsFixed(0)} via UPI',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: _adminUpi));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('UPI ID copied'),
                  backgroundColor: _cyan,
                  behavior: SnackBarBehavior.floating));
            },
            icon: const Icon(Icons.copy_rounded, size: 14),
            label: const Text('Copy UPI ID',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
                foregroundColor: _cyan,
                side: const BorderSide(color: _cyan),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
          ),
        ),
        TextButton(
          onPressed: onDone,
          child: const Text('Already paid / pay later',
              style: TextStyle(color: _txtMuted, fontSize: 13)),
        ),
      ]),
    );
  }
}

class _CStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _CStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 3),
          Text(label,
              style: const TextStyle(fontSize: 10.5, color: _txtMuted),
              textAlign: TextAlign.center),
        ]),
      );
}

class _CVDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 1,
      height: 30,
      color: _border,
      margin: const EdgeInsets.symmetric(horizontal: 8));
}

class _CUpiRow extends StatelessWidget {
  final String label, value;
  const _CUpiRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(children: [
        SizedBox(
          width: 52,
          child: Text(label,
              style: const TextStyle(fontSize: 11.5, color: _txtMuted)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _greenTxt)),
        ),
      ]);
}
