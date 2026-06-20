import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_new_app/services/cloudinary_service.dart';

import 'app_theme.dart';
import 'pending_screen.dart'
    hide kCyan, kCyanDark, kTextMuted, kSuccess, kError;

// ─────────────────────────────────────────────
// SERVICE MODEL
// ─────────────────────────────────────────────
class _ServiceItem {
  final String name;
  final String emoji;

  const _ServiceItem(this.name, this.emoji);
}

const List<_ServiceItem> _services = [
  _ServiceItem("Plumber", "🔧"),
  _ServiceItem("Electrician", "⚡"),
  _ServiceItem("Cleaning", "🧹"),
  _ServiceItem("Carpenter", "🪚"),
  _ServiceItem("Painter", "🎨"),
  _ServiceItem("AC Repair", "❄️"),
  _ServiceItem("Salon", "✂️"),
  _ServiceItem("Maid", "🏠"),
  _ServiceItem("Phone Repairing", "📱"),
  _ServiceItem("Laundry and Dry Cleaning", "👕"),
  _ServiceItem("Tailor", "🧵"),
  _ServiceItem("Staff(Boy/Girls)", "👥"),
];

// ─────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────
class WorkerProfileSetup extends StatefulWidget {
  final bool showRejectedBanner;

  const WorkerProfileSetup({
    super.key,
    this.showRejectedBanner = false,
  });

  @override
  State<WorkerProfileSetup> createState() => _WorkerProfileSetupState();
}

class _WorkerProfileSetupState extends State<WorkerProfileSetup>
    with TickerProviderStateMixin {
  // ─────────────────────────────────────────
  // CONTROLLERS
  // ─────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  final _scrollCtrl = ScrollController();

  final ImagePicker _picker = ImagePicker();

  // ─────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────
  final Set<String> _selectedServices = {};

  bool _availableToday = true;

  File? _profileImg;
  File? _aadhaarImg;
  File? _selfieImg;

  bool _isLoading = false;
  String _uploadStatus = "";

  // ─────────────────────────────────────────
  // ANIMATION
  // ─────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;

    if (user?.email != null) {
      _emailCtrl.text = user!.email!;
    }

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnim = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeOut,
    );

    _fadeCtrl.forward();

    if (widget.showRejectedBanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRejectedBanner();
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _expCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    _bioCtrl.dispose();
    _scrollCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────
  // BANNER
  // ─────────────────────────────────────────
  void _showRejectedBanner() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: kError,
        content: const Text(
          "Your profile was rejected. Please update details and resubmit.",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.white,
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
            },
            child: const Text(
              "OK",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // IMAGE PICKERS
  // ─────────────────────────────────────────
  Future<void> _pickProfile() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (file != null && mounted) {
      setState(() {
        _profileImg = File(file.path);
      });
    }
  }

  Future<void> _pickAadhaar() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (file != null && mounted) {
      setState(() {
        _aadhaarImg = File(file.path);
      });
    }
  }

  Future<void> _pickSelfie() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 70,
    );

    if (file != null && mounted) {
      setState(() {
        _selfieImg = File(file.path);
      });
    }
  }

  // ─────────────────────────────────────────
  // SUBMIT
  // ─────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      _snack("Please complete all required fields", error: true);
      return;
    }

    if (_selectedServices.isEmpty) {
    _snack("Select at least one service", error: true);
    return;
    }

    if (_profileImg == null) {
      _snack("Upload profile photo", error: true);
      return;
    }

    if (_aadhaarImg == null) {
      _snack("Upload Aadhaar card", error: true);
      return;
    }

    if (_selfieImg == null) {
      _snack("Capture live selfie", error: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _uploadStatus = "Uploading profile photo...";
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _snack("Session expired", error: true);
        return;
      }

      // PROFILE
      final profileUrl = await CloudinaryService.uploadImage(
        _profileImg!,
        folder: "worker_app/profile",
      );

      if (!mounted) return;
      setState(() => _uploadStatus = "Uploading Aadhaar...");

      // AADHAAR
      final aadhaarUrl = await CloudinaryService.uploadImage(
        _aadhaarImg!,
        folder: "worker_app/aadhaar",
      );

      if (!mounted) return;
      setState(() => _uploadStatus = "Uploading selfie...");

      // SELFIE
      final selfieUrl = await CloudinaryService.uploadImage(
        _selfieImg!,
        folder: "worker_app/selfie",
      );

      if (!mounted) return;
      setState(() => _uploadStatus = "Saving profile...");

      // Use Firebase email if available, else use what user typed
      final emailToSave = (user.email?.isNotEmpty == true)
          ? user.email!
          : _emailCtrl.text.trim();

      // ✅ FIX: Save to 'workers' collection — must match what AuthGate reads.
      //    Using 'users' was the bug causing the app to return to setup on reopen.
      await FirebaseFirestore.instance.collection('workers').doc(user.uid).set({
        'uid': user.uid,

        // BASIC
        'name': _nameCtrl.text.trim(),
        'email': emailToSave,
        'phone': _phoneCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),

        // SERVICE
        'category': _selectedServices.toList(),
        'service': _selectedServices.first, // keep for backward compat
        'experience': _expCtrl.text.trim(),

        // MEDIA
        'profileImage': profileUrl,

        // DOCUMENTS
        'documents': {
          'aadhaar': aadhaarUrl,
          'selfie': selfieUrl,
        },

        // STATUS
        'role': 'worker',
        'verificationStatus': 'pending',
        'isVerified': false,

        // STATS
        'stats': {
          'rating': 0.0,
          'reviews': 0,
          'jobsCompleted': 0,
        },

        // AVAILABILITY
        'availability': {
          'availableToday': _availableToday,
          'isOnline': false,
        },

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _snack("Profile submitted successfully");

      await Future.delayed(const Duration(milliseconds: 700));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const PendingScreen(),
        ),
      );
    } catch (e) {
      _snack("Something went wrong: ${e.toString()}", error: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadStatus = "";
        });
      }
    }
  }

  // ─────────────────────────────────────────
  // SNACK
  // ─────────────────────────────────────────
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? kError : kCyanDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        content: Text(
          msg,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      body: Stack(
        children: [
          FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(18),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _welcomeCard(),
                          const SizedBox(height: 24),
                          _avatar(),
                          const SizedBox(height: 30),
                          _section("Personal Information"),
                          _card(
                            child: Column(
                              children: [
                                _field(
                                  "Full Name",
                                  Icons.person_outline_rounded,
                                  _nameCtrl,
                                ),
                                _field(
                                  "Email (Optional)",
                                  Icons.email_outlined,
                                  _emailCtrl,
                                  readOnly: false,
                                  requiredField: false,
                                  keyboard: TextInputType.emailAddress,
                                ),
                                _field(
                                  "Phone Number",
                                  Icons.phone_outlined,
                                  _phoneCtrl,
                                  keyboard: TextInputType.phone,
                                  maxLength: 10,
                                  formatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                ),
                                _field(
                                  "City",
                                  Icons.location_city_rounded,
                                  _cityCtrl,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _section("Select Service"),
                          _card(
                            child: _serviceChips(),
                          ),
                          const SizedBox(height: 24),
                          _section("Work Details"),
                          _card(
                            child: Column(
                              children: [
                                _field(
                                  "Experience (Years)",
                                  Icons.workspace_premium_outlined,
                                  _expCtrl,
                                  keyboard: TextInputType.number,
                                  formatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                ),
                                _field(
                                  "Work Address",
                                  Icons.location_on_outlined,
                                  _addressCtrl,
                                ),
                                _field(
                                  "Short Bio",
                                  Icons.notes_rounded,
                                  _bioCtrl,
                                  maxLines: 3,
                                  requiredField: false,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          _section("Availability"),
                          _card(
                            child: SwitchListTile(
                              value: _availableToday,
                              activeColor: kCyan,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                "Available for work today",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: const Text(
                                "Customers can instantly book you",
                              ),
                              onChanged: (v) {
                                setState(() {
                                  _availableToday = v;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          _section("Verification Documents"),
                          _docCard(
                            title: "Aadhaar Card",
                            subtitle: "Upload government ID",
                            file: _aadhaarImg,
                            icon: Icons.credit_card_rounded,
                            onTap: _pickAadhaar,
                          ),
                          const SizedBox(height: 14),
                          _docCard(
                            title: "Live Selfie",
                            subtitle: "Face verification",
                            file: _selfieImg,
                            icon: Icons.camera_alt_rounded,
                            onTap: _pickSelfie,
                          ),
                          const SizedBox(height: 28),
                          _progress(),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 58,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kCyan,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text(
                                "Submit for Verification",
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // LOADER
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.45),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: kCyan),
                      const SizedBox(height: 20),
                      Text(
                        _uploadStatus,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Securing and verifying your documents...",
                        style: TextStyle(color: kTextMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────
  Widget _header() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF00BCD4),
            Color(0xFF00ACC1),
            Color(0xFF0097A7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.engineering_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Worker Profile Setup",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Complete profile to get verified",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // WELCOME
  // ─────────────────────────────────────────
  Widget _welcomeCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kCyan.withOpacity(0.10),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kCyan.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: kCyanBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: kCyan,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Become a verified professional",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                SizedBox(height: 6),
                Text(
                  "Verified workers receive more bookings and customer trust.",
                  style:
                      TextStyle(fontSize: 12, color: kTextMuted, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // AVATAR
  // ─────────────────────────────────────────
  Widget _avatar() {
    return Hero(
      tag: "worker-profile",
      child: GestureDetector(
        onTap: _pickProfile,
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: kCyan, width: 3),
                  ),
                  child: ClipOval(
                    child: _profileImg != null
                        ? Image.file(_profileImg!, fit: BoxFit.cover)
                        : Container(
                            color: kCyanBg,
                            child: const Icon(
                              Icons.person_rounded,
                              size: 54,
                              color: kCyan,
                            ),
                          ),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kCyan,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _profileImg != null
                  ? "Profile photo added"
                  : "Tap to upload profile photo",
              style: const TextStyle(
                color: kTextMuted,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            )
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // SECTION TITLE
  // ─────────────────────────────────────────
  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // CARD
  // ─────────────────────────────────────────
  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kDivider),
      ),
      child: child,
    );
  }

  // ─────────────────────────────────────────
  // FIELD
  // ─────────────────────────────────────────
  Widget _field(
    String hint,
    IconData icon,
    TextEditingController ctrl, {
    bool readOnly = false,
    bool requiredField = true,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    int? maxLength,
    List<TextInputFormatter>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        readOnly: readOnly,
        keyboardType: keyboard,
        maxLines: maxLines,
        maxLength: maxLength,
        inputFormatters: formatters,
        validator: (v) {
          if (!requiredField) return null;
          if (v == null || v.trim().isEmpty) return "Required field";
          return null;
        },
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: kCyan),
          filled: true,
          fillColor: kBgPage,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kDivider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kDivider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kCyan, width: 1.5),
          ),
          suffixIcon: !requiredField
              ? const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: kTextMuted,
                    size: 18,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // SERVICES
  // ─────────────────────────────────────────
  Widget _serviceChips() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _selectedServices.isEmpty
            ? "Select at least one service"
            : "${_selectedServices.length} selected",
        style: TextStyle(
          color: _selectedServices.isEmpty ? kError : kCyan,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _services.map((s) {
          final selected = _selectedServices.contains(s.name);
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (selected) {
                  _selectedServices.remove(s.name);
                } else {
                  _selectedServices.add(s.name);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? kCyan : kBgPage,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: selected ? kCyan : kDivider,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.emoji),
                  const SizedBox(width: 6),
                  Text(
                    s.name,
                    style: TextStyle(
                      color: selected ? Colors.white : kTextDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 14),
                  ]
                ],
              ),
            ),
          );
        }).toList(),
      ),
    ],
  );
}

  // ─────────────────────────────────────────
  // DOC CARD
  // ─────────────────────────────────────────
  Widget _docCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required File? file,
    required VoidCallback onTap,
  }) {
    final done = file != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: done ? kCyanBg : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: done ? kCyan : kDivider),
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: kCyanBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: done
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(file!, fit: BoxFit.cover),
                    )
                  : Icon(icon, color: kCyan),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(
                    done ? "Uploaded successfully" : subtitle,
                    style: const TextStyle(color: kTextMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              done
                  ? Icons.check_circle_rounded
                  : Icons.arrow_forward_ios_rounded,
              color: done ? kSuccess : kTextMuted,
              size: 18,
            )
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // PROGRESS
  // ─────────────────────────────────────────
  Widget _progress() {
  const int total = 8; 
  int done = 0;

  if (_nameCtrl.text.isNotEmpty) done++;
  if (_phoneCtrl.text.length == 10) done++;
  if (_cityCtrl.text.isNotEmpty) done++;
  if (_expCtrl.text.isNotEmpty) done++;
  if (_selectedServices.isNotEmpty) done++;
  if (_profileImg != null) done++;
  if (_aadhaarImg != null) done++;
  if (_selfieImg != null) done++;

    final double progress = done / total;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: kDivider,
                  valueColor: const AlwaysStoppedAnimation(kCyan),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              "${(progress * 100).toInt()}%",
              style: const TextStyle(
                color: kCyanDark,
                fontWeight: FontWeight.w700,
              ),
            )
          ],
        ),
      ],
    );
  }
}
