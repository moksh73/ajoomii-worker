import 'package:cloud_firestore/cloud_firestore.dart';
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

class ChatScreen extends StatefulWidget {
  final String chatRoomId;
  final String currentUserId;
  final String otherUserName;
  final String otherUserImage;
  final bool isWorker;

  const ChatScreen({
    super.key,
    required this.chatRoomId,
    required this.currentUserId,
    required this.otherUserName,
    required this.otherUserImage,
    this.isWorker = false,
    required String chatId,
    required String workerPhone,
    required String otherUserId,
    required String requestId,
    required String workerName,
    required String serviceName,
    required String workerId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _isSending = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _msgCtrl.addListener(() {
      final has = _msgCtrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _msgCtrl.clear();

    try {
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(widget.chatRoomId)
          .collection('messages')
          .add({
        'text': text,
        'senderId': widget.currentUserId,
        'senderType': widget.isWorker ? 'worker' : 'user',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(widget.chatRoomId)
          .update({
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'lastSenderId': widget.currentUserId,
      });

      _scrollToBottom();
    } catch (e) {
      debugPrint('Send error: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  // group messages by date
  String _dateLabel(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.day == yesterday.day &&
        dt.month == yesterday.month &&
        dt.year == yesterday.year) {
      return 'Yesterday';
    }
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
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final initials = widget.otherUserName
        .trim()
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(children: [
          // ── Top Bar ─────────────────────────────────────────────────────
          _buildTopBar(initials),

          // ── Messages ────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chatRooms')
                  .doc(widget.chatRoomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _cyan));
                }

                final msgs = snap.data?.docs ?? [];

                if (msgs.isEmpty) {
                  return _buildEmptyState();
                }

                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final data = msgs[i].data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == widget.currentUserId;
                    final text = data['text'] as String? ?? '';
                    final ts = data['timestamp'] as Timestamp?;

                    // Show date label when day changes
                    bool showDate = false;
                    if (i == 0) {
                      showDate = true;
                    } else {
                      final prevTs = (msgs[i - 1].data()
                          as Map<String, dynamic>)['timestamp'] as Timestamp?;
                      if (_dateLabel(ts) != _dateLabel(prevTs)) showDate = true;
                    }

                    return Column(children: [
                      if (showDate) _buildDateChip(_dateLabel(ts)),
                      _buildBubble(text, _formatTime(ts), isMe),
                    ]);
                  },
                );
              },
            ),
          ),

          // ── Input Bar ───────────────────────────────────────────────────
          _buildInputBar(),
        ]),
      ),
    );
  }

  // ─── Top Bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar(String initials) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: _card,
      padding: EdgeInsets.fromLTRB(8, top + 8, 16, 10),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: _txtDark),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        ),

        // Avatar
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: widget.otherUserImage.isNotEmpty
              ? ClipOval(
                  child:
                      Image.network(widget.otherUserImage, fit: BoxFit.cover))
              : Center(
                  child: Text(initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
        ),
        const SizedBox(width: 10),

        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.otherUserName,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _txtDark)),
            Row(children: [
              Container(
                width: 7,
                height: 7,
                decoration:
                    const BoxDecoration(color: _green, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              const Text('Online',
                  style: TextStyle(
                      fontSize: 11,
                      color: _green,
                      fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),

        // Call button
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _surface,
            shape: BoxShape.circle,
            border: Border.all(color: _border),
          ),
          child: const Icon(Icons.call_rounded, size: 17, color: _cyan),
        ),
      ]),
    );
  }

  // ─── Date chip ─────────────────────────────────────────────────────────────

  Widget _buildDateChip(String label) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _border),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11, color: _txtMuted, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  // ─── Message bubble ────────────────────────────────────────────────────────

  Widget _buildBubble(String text, String time, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? _cyan : _card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          border: isMe ? null : Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(text,
              style: TextStyle(
                  color: isMe ? Colors.white : _txtDark,
                  fontSize: 14,
                  height: 1.4)),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(time,
                style: TextStyle(
                    color: isMe ? Colors.white.withOpacity(0.7) : _txtMuted,
                    fontSize: 10)),
            if (isMe) ...[
              const SizedBox(width: 4),
              Icon(Icons.done_all_rounded,
                  size: 13, color: Colors.white.withOpacity(0.7)),
            ],
          ]),
        ]),
      ),
    );
  }

  // ─── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: _surface,
            shape: BoxShape.circle,
            border: Border.all(color: _border),
          ),
          child: const Icon(Icons.chat_bubble_outline_rounded,
              color: _cyan, size: 32),
        ),
        const SizedBox(height: 16),
        const Text('No messages yet',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: _txtDark)),
        const SizedBox(height: 6),
        const Text('Say hello to get started!',
            style: TextStyle(fontSize: 13, color: _txtMuted)),
      ]),
    );
  }

  // ─── Input bar ─────────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return Container(
      color: _card,
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // Text field
        Expanded(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 120),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border),
            ),
            child: TextField(
              controller: _msgCtrl,
              style:
                  const TextStyle(color: _txtDark, fontSize: 14, height: 1.4),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: _txtMuted, fontSize: 14),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
        ),

        const SizedBox(width: 8),

        // Send button
        GestureDetector(
          onTap: (_hasText && !_isSending) ? _sendMessage : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _hasText ? _cyan : _surface,
              shape: BoxShape.circle,
              border: Border.all(color: _hasText ? _cyan : _border),
            ),
            child: _isSending
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        color: _hasText ? Colors.white : _txtMuted,
                        strokeWidth: 2))
                : Icon(Icons.send_rounded,
                    color: _hasText ? Colors.white : _txtMuted, size: 20),
          ),
        ),
      ]),
    );
  }
}
