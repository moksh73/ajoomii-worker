import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_screen.dart';

// ─── Design Tokens ───────────────────────────────────────────────────────────
const Color _cyan = Color(0xFF06B6D4);
const Color _bg = Color(0xFFF5FAFE);
const Color _card = Color(0xFFFFFFFF);
const Color _surface = Color(0xFFF0F8FC);
const Color _border = Color(0xFFD4ECF5);
const Color _txtDark = Color(0xFF0D2B35);
const Color _txtMuted = Color(0xFF6B9BAD);
const Color _green = Color(0xFF00C073);

// ─────────────────────────────────────────────────────────────────────────────

class WorkerChatListScreen extends StatelessWidget {
  final String? uid;
  final bool isWorker;

  const WorkerChatListScreen({
    super.key,
    required this.uid,
    this.isWorker = true,
  });

  @override
  Widget build(BuildContext context) {
    if (uid == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Text('Not logged in',
              style: TextStyle(color: _txtMuted, fontSize: 14)),
        ),
      );
    }

    final field = isWorker ? 'workerId' : 'userId';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(children: [
          _TopBar(isWorker: isWorker),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chatRooms')
                  .where(field, isEqualTo: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _ErrorState(error: snap.error.toString());
                }

                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _cyan));
                }

                // Sort client-side by lastMessageTime desc (avoids composite index)
                final docs = List.from(snap.data?.docs ?? []);
                docs.sort((a, b) {
                  final aTs =
                      (a.data() as Map)['lastMessageTime'] as Timestamp?;
                  final bTs =
                      (b.data() as Map)['lastMessageTime'] as Timestamp?;
                  if (aTs == null && bTs == null) return 0;
                  if (aTs == null) return 1;
                  if (bTs == null) return -1;
                  return bTs.compareTo(aTs);
                });

                if (docs.isEmpty) {
                  return const _EmptyState();
                }

                return ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final chatRoomId = docs[i].id;
                    return _ChatTile(
                      data: data,
                      chatRoomId: chatRoomId,
                      uid: uid!,
                      isWorker: isWorker,
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Top Bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final bool isWorker;
  const _TopBar({required this.isWorker});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: _card,
      padding: EdgeInsets.fromLTRB(18, top + 12, 18, 14),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Messages',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _txtDark,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isWorker ? 'Customer conversations' : 'Worker conversations',
              style: const TextStyle(fontSize: 12, color: _txtMuted),
            ),
          ]),
        ),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _surface,
            shape: BoxShape.circle,
            border: Border.all(color: _border),
          ),
          child: const Icon(Icons.search_rounded, size: 18, color: _cyan),
        ),
      ]),
    );
  }
}

// ─── Chat Tile ────────────────────────────────────────────────────────────────

class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final String chatRoomId;
  final String uid;
  final bool isWorker;

  const _ChatTile({
    required this.data,
    required this.chatRoomId,
    required this.uid,
    required this.isWorker,
  });

  String _timeString(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ampm';
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
    return '${dt.day} ${months[dt.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final otherName = isWorker
        ? (data['userName'] ?? 'Customer')
        : (data['workerName'] ?? 'Worker');
    final otherImage =
        isWorker ? (data['userImage'] ?? '') : (data['workerImage'] ?? '');
    final lastMsg = data['lastMessage'] as String? ?? '';
    final lastSenderId = data['lastSenderId'] as String? ?? '';
    final isMyMsg = lastSenderId == uid;
    final unread = (data['unreadCount'] as int?) ?? 0;
    final ts = data['lastMessageTime'] as Timestamp?;
    final timeStr = _timeString(ts);

    final initials = otherName
        .trim()
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatRoomId: chatRoomId,
            currentUserId: uid,
            otherUserName: otherName,
            otherUserImage: otherImage,
            isWorker: isWorker,
            chatId: '',
            workerPhone: '',
            otherUserId: '',
            requestId: '',
            workerName: '',
            serviceName: '',
            workerId: '',
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          // Avatar
          Stack(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: otherImage.isNotEmpty
                  ? ClipOval(
                      child: Image.network(otherImage, fit: BoxFit.cover))
                  : Center(
                      child: Text(initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
            ),
            // Online dot (only show if online field exists)
            if (data['isOnline'] == true)
              Positioned(
                right: 1,
                bottom: 1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _green,
                    shape: BoxShape.circle,
                    border: Border.all(color: _card, width: 2),
                  ),
                ),
              ),
          ]),

          const SizedBox(width: 12),

          // Name + last message
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(otherName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600,
                    color: _txtDark,
                  )),
              const SizedBox(height: 3),
              Text(
                lastMsg.isEmpty
                    ? 'No messages yet'
                    : isMyMsg
                        ? 'You: $lastMsg'
                        : lastMsg,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: unread > 0 ? _txtDark : _txtMuted,
                  fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ]),
          ),

          const SizedBox(width: 8),

          // Time + unread badge
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(timeStr,
                style: TextStyle(
                  fontSize: 11,
                  color: unread > 0 ? _cyan : _txtMuted,
                  fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
                )),
            if (unread > 0) ...[
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _cyan,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _surface,
              shape: BoxShape.circle,
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.chat_bubble_outline_rounded,
                color: _cyan, size: 36),
          ),
          const SizedBox(height: 18),
          const Text('No Chats Yet',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: _txtDark)),
          const SizedBox(height: 8),
          const Text(
            'Conversations with customers\nwill appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _txtMuted, height: 1.6),
          ),
        ]),
      ),
    );
  }
}

// ─── Error State ──────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFFCDD2)),
            ),
            child: const Icon(Icons.wifi_off_rounded,
                color: Color(0xFFF43F5E), size: 30),
          ),
          const SizedBox(height: 16),
          const Text('Something went wrong',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: _txtDark)),
          const SizedBox(height: 6),
          Text(error,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 12, color: _txtMuted, height: 1.5)),
        ]),
      ),
    );
  }
}

// ─── User-facing chat list ────────────────────────────────────────────────────

class UserChatListScreen extends StatelessWidget {
  final String uid;
  const UserChatListScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return WorkerChatListScreen(uid: uid, isWorker: false);
  }
}
