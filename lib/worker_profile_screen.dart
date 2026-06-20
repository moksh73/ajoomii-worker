import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';

import 'app_theme.dart';

// ─── Cloudinary ───────────────────────────────────────────────────────────────
final _cloudinary =
    CloudinaryPublic('doeswlkl3', 'worker_upload', cache: false);

// ─── All available service categories ────────────────────────────────────────
const List<String> _kAllCategories = [
  'Plumber',
  'Electrician',
  'Cleaning',
  'AC Repair',
  'Carpenter',
  'Maid',
  'Phone Repairing',
  'Salon',
  'Painter',
  'Laundry and Dry Cleaning',
  'Tailor',
  'Staff(Boy/Girls)',
];

const Map<String, IconData> _kCategoryIcons = {
  'Plumber': Icons.water_damage_outlined,
  'Electrician': Icons.electrical_services_rounded,
  'Cleaning': Icons.cleaning_services_rounded,
  'AC Repair': Icons.ac_unit_rounded,
  'Carpenter': Icons.carpenter,
  'Maid': Icons.home_outlined,
  'Phone Repairing': Icons.phone_android_rounded,
  'Salon': Icons.content_cut_rounded,
  'Painter': Icons.format_paint_rounded,
  'Laundry and Dry Cleaning': Icons.local_laundry_service_rounded,
  'Tailor': Icons.design_services_rounded,
  'Staff(Boy/Girls)': Icons.people_outline_rounded,
};

// ═════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class WorkerProfileScreen extends StatelessWidget {
  final String? uid;
  final bool isEditable;

  const WorkerProfileScreen({
    super.key,
    required this.uid,
    this.isEditable = false,
  });

  @override
  Widget build(BuildContext context) {
    if (uid == null) {
      return const Scaffold(
        backgroundColor: kBgPage,
        body: Center(
            child:
                Text('Worker not found', style: TextStyle(color: kTextMuted))),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance.collection('workers').doc(uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: kBgPage,
            body: Center(child: CircularProgressIndicator(color: kCyan)),
          );
        }
        final data = snap.data!.data() as Map<String, dynamic>? ?? {};
        return _ProfileBody(data: data, uid: uid!, isEditable: isEditable);
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PROFILE BODY
// ═════════════════════════════════════════════════════════════════════════════
class _ProfileBody extends StatefulWidget {
  final Map<String, dynamic> data;
  final String uid;
  final bool isEditable;

  const _ProfileBody(
      {required this.data, required this.uid, required this.isEditable});

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.data['name'] ?? 'Worker';
    final image = widget.data['profileImage'] ?? '';
    final phone = widget.data['phone'] ?? '';
    final cats = widget.data['category'];
    final categories =
        cats is List ? cats.map((e) => e.toString()).toList() : <String>[];
    final rating = (widget.data['rating'] as num?)?.toDouble() ?? 0.0;
    final totalJobs = widget.data['totalJobs'] ?? 0;
    final isOnline = widget.data['isOnline'] ?? false;
    final bio = widget.data['bio'] ?? '';
    final experience = widget.data['experience'] ?? '';
    final city = widget.data['city'] ?? '';

    return Scaffold(
      backgroundColor: kBgPage,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          _buildSliverHeader(
            name: name,
            image: image,
            categories: categories,
            rating: rating,
            totalJobs: totalJobs,
            isOnline: isOnline,
            city: city,
          ),
        ],
        body: Column(children: [
          // Tab bar
          Container(
            color: kWhite,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: kCyan,
              unselectedLabelColor: kTextMuted,
              indicatorColor: kCyan,
              indicatorWeight: 2.5,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(text: 'About'),
                Tab(text: 'Services'),
                Tab(text: 'Reviews'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // ── About tab
                _AboutTab(
                  data: widget.data,
                  uid: widget.uid,
                  isEditable: widget.isEditable,
                  bio: bio,
                  phone: phone,
                  experience: experience,
                  city: city,
                ),
                // ── Services tab
                _ServicesTab(
                  uid: widget.uid,
                  categories: categories,
                  isEditable: widget.isEditable,
                ),
                // ── Reviews tab
                _ReviewsTab(uid: widget.uid),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Sliver app bar header ─────────────────────────────────
  Widget _buildSliverHeader({
    required String name,
    required String image,
    required List<String> categories,
    required double rating,
    required int totalJobs,
    required bool isOnline,
    required String city,
  }) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: kWhite,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: widget.isEditable
          ? const SizedBox()
          : IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
      actions: [
        if (widget.isEditable)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => _openEditProfileSheet(context),
              icon:
                  const Icon(Icons.edit_rounded, color: Colors.white, size: 16),
              label: const Text('Edit',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Stack(fit: StackFit.expand, children: [
          // Gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0077B6), Color(0xFF00B4D8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // Decorative circles
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            left: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),
          // Wave at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 36,
              decoration: const BoxDecoration(
                color: kBgPage,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
            ),
          ),
          // Profile content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Avatar with edit button
                  Stack(alignment: Alignment.center, children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: image.isNotEmpty
                            ? Image.network(image,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _avatarPlaceholder())
                            : _avatarPlaceholder(),
                      ),
                    ),
                    // Online dot
                    if (isOnline)
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: kSuccess,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                        ),
                      ),
                    // Camera button (editable mode)
                    if (widget.isEditable)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () => _pickAndUploadAvatar(context),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: kCyan,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt_rounded,
                                color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3)),
                  const SizedBox(height: 4),
                  if (city.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on_rounded,
                            color: Colors.white70, size: 13),
                        const SizedBox(width: 3),
                        Text(city,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  const SizedBox(height: 12),
                  // Stats row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _headerStat(rating.toStringAsFixed(1), 'Rating',
                          Icons.star_rounded, Colors.amber),
                      _headerDivider(),
                      _headerStat('$totalJobs', 'Jobs',
                          Icons.check_circle_rounded, Colors.greenAccent),
                      _headerDivider(),
                      _headerStat(
                          isOnline ? 'Online' : 'Offline',
                          'Status',
                          isOnline
                              ? Icons.sensors_rounded
                              : Icons.sensors_off_rounded,
                          isOnline ? Colors.greenAccent : Colors.white38),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _avatarPlaceholder() => Container(
        color: const Color(0xFFE0F7FA),
        child: const Icon(Icons.person, color: kCyan, size: 44),
      );

  Widget _headerStat(String value, String label, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800)),
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ]),
    );
  }

  Widget _headerDivider() => Container(
        width: 1,
        height: 36,
        color: Colors.white24,
      );

  // ── Pick & upload avatar ──────────────────────────────────
  Future<void> _pickAndUploadAvatar(BuildContext context) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Change Photo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _imgOption(Icons.camera_alt_rounded, 'Camera',
                  () => Navigator.pop(context, ImageSource.camera)),
              _imgOption(Icons.photo_library_rounded, 'Gallery',
                  () => Navigator.pop(context, ImageSource.gallery)),
            ]),
            const SizedBox(height: 10),
          ]),
        ),
      ),
    );
    if (src == null || !mounted) return;

    final img = await ImagePicker()
        .pickImage(source: src, imageQuality: 85, maxWidth: 1024);
    if (img == null || !mounted) return;

    // Upload to Cloudinary
    final overlay = _showUploadOverlay(context);
    try {
      final res = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          img.path,
          resourceType: CloudinaryResourceType.Image,
          folder: 'worker_profiles',
        ),
      );
      await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.uid)
          .update({'profileImage': res.secureUrl});
      if (mounted) {
        _showSnack('Profile photo updated ✓');
      }
    } catch (e) {
      if (mounted) _showSnack('Upload failed. Try again.', isError: true);
    } finally {
      overlay.remove();
    }
  }

  OverlayEntry _showUploadOverlay(BuildContext context) {
    final entry = OverlayEntry(
      builder: (_) => const Positioned.fill(
        child: ColoredBox(
          color: Colors.black38,
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    return entry;
  }

  // ── Edit profile bottom sheet ─────────────────────────────
  void _openEditProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        uid: widget.uid,
        data: widget.data,
      ),
    );
  }

  Widget _imgOption(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
              color: const Color(0xFFEAF5EA),
              borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, color: kCyan, size: 28),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? kError : kSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ABOUT TAB
// ═════════════════════════════════════════════════════════════════════════════
class _AboutTab extends StatelessWidget {
  final Map<String, dynamic> data;
  final String uid;
  final bool isEditable;
  final String bio, phone, experience, city;

  const _AboutTab({
    required this.data,
    required this.uid,
    required this.isEditable,
    required this.bio,
    required this.phone,
    required this.experience,
    required this.city,
  });

  @override
  Widget build(BuildContext context) {
    final totalJobs = data['totalJobs'] ?? 0;
    final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
    final completionRate = data['completionRate'] ?? 0;
    final joinedDate = data['joinedAt'] as Timestamp?;
    final joinedStr =
        joinedDate != null ? _formatDate(joinedDate.toDate()) : 'N/A';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Bio card
        _Card(
          title: 'About Me',
          icon: Icons.person_outline_rounded,
          child: bio.isNotEmpty
              ? Text(bio,
                  style: const TextStyle(
                      color: kTextMid, fontSize: 13, height: 1.6))
              : const Text('No bio added yet.',
                  style: TextStyle(
                      color: kTextMuted,
                      fontSize: 13,
                      fontStyle: FontStyle.italic)),
        ),
        const SizedBox(height: 14),

        // Info details card
        _Card(
          title: 'Details',
          icon: Icons.info_outline_rounded,
          child: Column(children: [
            if (phone.isNotEmpty)
              _DetailRow(Icons.phone_outlined, 'Phone', phone),
            if (city.isNotEmpty)
              _DetailRow(Icons.location_on_outlined, 'City', city),
            if (experience.isNotEmpty)
              _DetailRow(
                  Icons.workspace_premium_outlined, 'Experience', experience),
            _DetailRow(Icons.calendar_today_rounded, 'Joined', joinedStr),
          ]),
        ),
        const SizedBox(height: 14),

        // Performance card
        _Card(
          title: 'Performance',
          icon: Icons.insights_rounded,
          child: Column(children: [
            _PerfRow(
                label: 'Rating',
                value: rating.toStringAsFixed(1),
                icon: Icons.star_rounded,
                color: kWarning),
            const SizedBox(height: 12),
            _PerfRow(
                label: 'Total Jobs',
                value: '$totalJobs',
                icon: Icons.work_rounded,
                color: kCyan),
            const SizedBox(height: 12),
            _PerfRow(
                label: 'Completion Rate',
                value: '$completionRate%',
                icon: Icons.check_circle_rounded,
                color: kSuccess),
          ]),
        ),
        const SizedBox(height: 14),

        // Completed jobs list
        _CompletedJobsCard(uid: uid),
      ],
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  static const _months = [
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
}

// ═════════════════════════════════════════════════════════════════════════════
// SERVICES TAB
// ═════════════════════════════════════════════════════════════════════════════
class _ServicesTab extends StatefulWidget {
  final String uid;
  final List<String> categories;
  final bool isEditable;

  const _ServicesTab({
    required this.uid,
    required this.categories,
    required this.isEditable,
  });

  @override
  State<_ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<_ServicesTab> {
  late List<String> _selected;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.categories);
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      _showSnack('Select at least one service.', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.uid)
          .update({'category': _selected});
      _showSnack('Services updated ✓');
    } catch (e) {
      _showSnack('Failed to save. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? kError : kSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF006064), Color(0xFF00BCD4)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded,
                color: Colors.white, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.isEditable
                    ? 'Tap to toggle the services you offer. Changes are saved automatically.'
                    : 'These are the services offered by this worker.',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Category grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _kAllCategories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.2,
          ),
          itemBuilder: (context, i) {
            final cat = _kAllCategories[i];
            final isSelected = _selected.contains(cat);
            final canTap = widget.isEditable;

            return GestureDetector(
              onTap: canTap
                  ? () {
                      setState(() {
                        if (isSelected) {
                          _selected.remove(cat);
                        } else {
                          _selected.add(cat);
                        }
                      });
                    }
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFE0F7FA) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? kCyan : const Color(0xFFE0E4DF),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: kCyan.withOpacity(0.12),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ]
                      : [],
                ),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSelected ? kCyan : const Color(0xFFF4F6F3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _kCategoryIcons[cat] ?? Icons.home_repair_service_rounded,
                      color: isSelected ? Colors.white : kTextMuted,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? const Color(0xFF006064) : kTextDark,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle_rounded,
                        color: kCyan, size: 16),
                ]),
              ),
            );
          },
        ),

        // Save button (editable only)
        if (widget.isEditable) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: kCyan,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.save_rounded,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Save Services (${_selected.length} selected)',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                      ],
                    ),
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// REVIEWS TAB
// ═════════════════════════════════════════════════════════════════════════════
class _ReviewsTab extends StatelessWidget {
  final String uid;
  const _ReviewsTab({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('workers')
          .doc(uid)
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kCyan));
        }

        final reviews = snap.data?.docs ?? [];

        // Compute rating breakdown
        final counts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
        double sum = 0;
        for (final doc in reviews) {
          final r = doc.data() as Map<String, dynamic>;
          final rating = (r['rating'] as num?)?.toInt() ?? 0;
          if (rating >= 1 && rating <= 5) {
            counts[rating] = (counts[rating] ?? 0) + 1;
            sum += rating;
          }
        }
        final avg = reviews.isEmpty ? 0.0 : sum / reviews.length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Rating summary card
            if (reviews.isNotEmpty) ...[
              _RatingSummaryCard(
                  avg: avg, total: reviews.length, counts: counts),
              const SizedBox(height: 16),
            ],

            // Reviews list
            if (reviews.isEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE8ECE7))),
                child: Column(children: [
                  Icon(Icons.star_border_rounded,
                      color: Colors.grey[300], size: 56),
                  const SizedBox(height: 14),
                  const Text('No reviews yet',
                      style: TextStyle(
                          color: kTextDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text('Completed jobs will show customer reviews here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kTextMuted, fontSize: 13)),
                ]),
              )
            else
              ...reviews.map((doc) {
                final r = doc.data() as Map<String, dynamic>;
                return _ReviewCard(review: r);
              }),
          ],
        );
      },
    );
  }
}

// ─── Rating summary ───────────────────────────────────────────────────────────
class _RatingSummaryCard extends StatelessWidget {
  final double avg;
  final int total;
  final Map<int, int> counts;

  const _RatingSummaryCard(
      {required this.avg, required this.total, required this.counts});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8ECE7))),
      child: Row(children: [
        // Big average
        Column(children: [
          Text(avg.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 42, fontWeight: FontWeight.w900, color: kTextDark)),
          Row(
              children: List.generate(
                  5,
                  (i) => Icon(
                        i < avg.round()
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: kWarning,
                        size: 16,
                      ))),
          const SizedBox(height: 4),
          Text('$total review${total != 1 ? 's' : ''}',
              style: const TextStyle(color: kTextMuted, fontSize: 12)),
        ]),
        const SizedBox(width: 20),
        const VerticalDivider(width: 1),
        const SizedBox(width: 20),
        // Bar breakdown
        Expanded(
          child: Column(
            children: [5, 4, 3, 2, 1].map((star) {
              final count = counts[star] ?? 0;
              final pct = total == 0 ? 0.0 : count / total;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Text('$star',
                      style: const TextStyle(
                          fontSize: 11,
                          color: kTextMuted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  const Icon(Icons.star_rounded, color: kWarning, size: 11),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFF0F0F0),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(kWarning),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 22,
                    child: Text('$count',
                        style:
                            const TextStyle(fontSize: 11, color: kTextMuted)),
                  ),
                ]),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }
}

// ─── Single review card ───────────────────────────────────────────────────────
class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['review'] ?? review['comment'] ?? '';
    final userName = review['userName'] ?? 'Customer';
    final userImage = review['userImage'] ?? '';
    final ts = review['createdAt'] as Timestamp?;
    final dateStr = ts != null ? _formatDate(ts.toDate()) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8ECE7))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFE0F7FA),
            backgroundImage:
                userImage.isNotEmpty ? NetworkImage(userImage) : null,
            child: userImage.isEmpty
                ? const Icon(Icons.person, color: kCyan, size: 18)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(userName,
                  style: const TextStyle(
                      color: kTextDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              if (dateStr.isNotEmpty)
                Text(dateStr,
                    style: const TextStyle(color: kTextMuted, fontSize: 11)),
            ]),
          ),
          // Stars
          Row(
              children: List.generate(
                  5,
                  (i) => Icon(
                        i < rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: kWarning,
                        size: 15,
                      ))),
        ]),
        if (comment.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(comment,
              style:
                  const TextStyle(color: kTextMid, fontSize: 13, height: 1.5)),
        ],
      ]),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
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
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ─── Completed jobs card ──────────────────────────────────────────────────────
class _CompletedJobsCard extends StatelessWidget {
  final String uid;
  const _CompletedJobsCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('workerId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox();

        return _Card(
          title: 'Recent Completed Jobs',
          icon: Icons.history_rounded,
          child: Column(
            children: docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final cat = d['category'] ?? 'Service';
              final sub = d['subCategory'] ?? '';
              final total = d['total'] ?? 0;
              final ts = d['completedAt'] as Timestamp?;
              final dateStr = ts != null ? _formatDate(ts.toDate()) : '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF5EA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.check_circle_rounded,
                        color: kSuccess, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(cat,
                              style: const TextStyle(
                                  color: kTextDark,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          if (sub.isNotEmpty)
                            Text(sub,
                                style: const TextStyle(
                                    color: kTextMuted, fontSize: 11)),
                        ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('₹$total',
                        style: const TextStyle(
                            color: kSuccess,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    if (dateStr.isNotEmpty)
                      Text(dateStr,
                          style:
                              const TextStyle(color: kTextMuted, fontSize: 10)),
                  ]),
                ]),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime d) {
    const months = [
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
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// EDIT PROFILE BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════
class _EditProfileSheet extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;

  const _EditProfileSheet({required this.uid, required this.data});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _experienceCtrl;
  late final TextEditingController _phoneCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.data['name'] ?? '');
    _bioCtrl = TextEditingController(text: widget.data['bio'] ?? '');
    _cityCtrl = TextEditingController(text: widget.data['city'] ?? '');
    _experienceCtrl =
        TextEditingController(text: widget.data['experience'] ?? '');
    _phoneCtrl = TextEditingController(text: widget.data['phone'] ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _cityCtrl.dispose();
    _experienceCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnack('Name cannot be empty.', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('workers')
          .doc(widget.uid)
          .update({
        'name': _nameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'experience': _experienceCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context);
        _showSnack('Profile updated ✓');
      }
    } catch (e) {
      _showSnack('Failed to save. Try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? kError : kSuccess,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),
              const Text('Edit Profile',
                  style: TextStyle(
                      color: kTextDark,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),
              _Field(
                  label: 'Full Name',
                  ctrl: _nameCtrl,
                  icon: Icons.person_outline_rounded,
                  hint: 'Enter your name'),
              const SizedBox(height: 14),
              _Field(
                  label: 'Phone Number',
                  ctrl: _phoneCtrl,
                  icon: Icons.phone_outlined,
                  hint: '+91 XXXXX XXXXX',
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 14),
              _Field(
                  label: 'City',
                  ctrl: _cityCtrl,
                  icon: Icons.location_on_outlined,
                  hint: 'e.g. Indore, Mumbai'),
              const SizedBox(height: 14),
              _Field(
                  label: 'Experience',
                  ctrl: _experienceCtrl,
                  icon: Icons.workspace_premium_outlined,
                  hint: 'e.g. 3 years'),
              const SizedBox(height: 14),
              _Field(
                  label: 'Bio',
                  ctrl: _bioCtrl,
                  icon: Icons.info_outline_rounded,
                  hint: 'Tell customers about yourself and your expertise…',
                  maxLines: 4),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kCyan,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text('Save Changes',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                          ],
                        ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SHARED HELPER WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _Card({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8ECE7)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: kCyan, size: 16),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  color: kTextDark, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: const Color(0xFFE0F7FA),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: kCyan, size: 16),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: kTextMuted, fontSize: 11)),
          const SizedBox(height: 1),
          Text(value,
              style: const TextStyle(
                  color: kTextDark, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class _PerfRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _PerfRow(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child:
            Text(label, style: const TextStyle(color: kTextMid, fontSize: 13)),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 13)),
      ),
    ]);
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController ctrl;
  final IconData icon;
  final int maxLines;
  final TextInputType keyboardType;

  const _Field({
    required this.label,
    required this.ctrl,
    required this.icon,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              color: kTextDark, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 13, color: kTextDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: kTextMuted, fontSize: 13),
          prefixIcon: Icon(icon, color: kCyan, size: 18),
          filled: true,
          fillColor: const Color(0xFFF4F6F3),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E4DF))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E4DF))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kCyan, width: 1.5)),
        ),
      ),
    ]);
  }
}
