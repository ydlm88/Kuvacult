// friends.dart — Friend search, pending requests, and friends-list screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models.dart';
import '../app_state.dart';
import '../widgets/avatar.dart';
import '../widgets/sign_in_sheet.dart';
import 'friend_profile.dart';
import 'dart:async';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<UserAccount> _searchResults = [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q, AppState state) {
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() { _searchResults = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final results = await state.searchUsers(q);
      if (mounted) setState(() { _searchResults = results; _searching = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.isGuest) {
      return Scaffold(
        backgroundColor: MC.bg0,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: MC.ink, size: 18),
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.group_outlined,
                            color: MC.accent1, size: 48),
                        const SizedBox(height: 20),
                        Text('Friends', style: MT.display(size: 26)),
                        const SizedBox(height: 10),
                        const Text(
                          'Sign in to add friends, send requests, and see who\'s watching what.',
                          style: TextStyle(
                              color: MC.mute, fontSize: 14, height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        GestureDetector(
                          onTap: () => showSignInSheet(context),
                          child: Container(
                            width: double.infinity,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [MC.accent1, MC.accent2]),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: const Text('Sign in / Create account',
                                style: TextStyle(
                                    color: MC.accentInk,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final currentUserId = state.currentUser?.id ?? 'guest';

    final pending = state.friendRequests
        .where((r) => r.toId == currentUserId && !r.accepted)
        .toList();

    final sentToIds = state.friendRequests
        .where((r) => r.fromId == currentUserId && !r.accepted)
        .map((r) => r.toId)
        .toSet();

    final friendIds = state.currentUser?.friendIds ?? [];
    final isSearching = _searchCtrl.text.isNotEmpty;

    return Scaffold(
      backgroundColor: MC.bg0,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: MC.ink, size: 18),
                    ),
                    const SizedBox(width: 16),
                    Text('Friends', style: MT.display(size: 28)),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: MC.bg1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: MC.mute, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (q) {
                            setState(() {});
                            _onSearchChanged(q, state);
                          },
                          style: const TextStyle(color: MC.ink, fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: 'Search by username…',
                            hintStyle: TextStyle(color: MC.dim),
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                          ),
                          cursorColor: MC.accent1,
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() { _searchResults = []; _searching = false; });
                          },
                          child: const Icon(Icons.close_rounded, color: MC.dim, size: 16),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            if (isSearching) ...[
              if (_searching)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: CircularProgressIndicator(color: MC.accent1, strokeWidth: 2),
                    ),
                  ),
                )
              else if (_searchResults.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Text(
                      'No users found. Search requires a backend connection.',
                      style: TextStyle(color: MC.dim, fontSize: 13),
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text('RESULTS', style: MT.mono(size: 10, letterSpacing: 2)),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final user = _searchResults[i];
                      final alreadyFriend = friendIds.contains(user.id);
                      final requestSent = sentToIds.contains(user.id);
                      final isMe = user.id == currentUserId;
                      return _UserRow(
                        user: user,
                        trailing: isMe
                            ? const SizedBox.shrink()
                            : alreadyFriend
                                ? _StatusBadge(label: 'Friends', accent: false)
                                : requestSent
                                    ? _StatusBadge(label: 'Requested', accent: false)
                                    : _ActionButton(
                                        label: 'Add friend',
                                        onTap: () {
                                          if (state.isGuest) {
                                            showSignInSheet(context);
                                          } else {
                                            state.sendFriendRequest(user.id);
                                          }
                                        },
                                      ),
                      );
                    },
                    childCount: _searchResults.length,
                  ),
                ),
              ],
            ] else ...[
              if (pending.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text('PENDING REQUESTS',
                        style: MT.mono(size: 10, letterSpacing: 2)),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final req = pending[i];
                      return _PendingRow(
                        fromId:          req.fromId,
                        fromUsername:    req.fromUsername,
                        fromDisplayName: req.fromDisplayName,
                        fromAvatarUrl:   req.fromAvatarUrl,
                        onAccept:  () => state.acceptFriendRequest(req.id),
                        onDecline: () => state.declineFriendRequest(req.id),
                      );
                    },
                    childCount: pending.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],

              if (friendIds.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text('FRIENDS', style: MT.mono(size: 10, letterSpacing: 2)),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _FriendRow(friendId: friendIds[i]),
                    childCount: friendIds.length,
                  ),
                ),
              ] else if (pending.isEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
                    child: Column(
                      children: [
                        const Icon(Icons.group_outlined, color: MC.accent1, size: 40),
                        const SizedBox(height: 16),
                        Text('No friends yet', style: MT.display(size: 20)),
                        const SizedBox(height: 10),
                        const Text(
                          'Search for a username above to send a friend request.',
                          style: TextStyle(color: MC.mute, fontSize: 13, height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final UserAccount user;
  final Widget trailing;

  const _UserRow({required this.user, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MC.line, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: user.avatarBg,
            ),
            alignment: Alignment.center,
            child: Text(
              user.displayName.isNotEmpty
                  ? user.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName,
                    style: const TextStyle(
                        color: MC.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text('@${user.username}',
                    style: const TextStyle(color: MC.mute, fontSize: 12)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  final String friendId;

  const _FriendRow({required this.friendId});

  @override
  Widget build(BuildContext context) {
    // Use cached friend profile — populated by _loadFriends() after login.
    final friends = context.read<AppState>().friends;
    UserAccount? friend;
    try {
      friend = friends.firstWhere((f) => f.id == friendId);
    } catch (_) {}
    final displayName = friend?.displayName.isNotEmpty == true
        ? friend!.displayName
        : (friend?.username.isNotEmpty == true ? friend!.username : '');
    final username = friend?.username ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => FriendProfileScreen(userId: friendId))),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: MC.line, width: 0.5)),
        ),
        child: Row(
          children: [
            AvatarWidget(memberId: friendId, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName.isNotEmpty ? displayName : friendId,
                    style: const TextStyle(
                        color: MC.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                  Text(
                    username.isNotEmpty ? '@$username' : 'Friend',
                    style: const TextStyle(color: MC.mute, fontSize: 12)),
                ],
              ),
            ),
            _StatusBadge(label: 'Friends', accent: false),
          ],
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  final String fromId;
  final String? fromUsername;
  final String? fromDisplayName;
  final String? fromAvatarUrl;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _PendingRow({
    required this.fromId,
    this.fromUsername,
    this.fromDisplayName,
    this.fromAvatarUrl,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = fromDisplayName?.isNotEmpty == true
        ? fromDisplayName!
        : (fromUsername?.isNotEmpty == true ? fromUsername! : fromId);
    final handle = fromUsername?.isNotEmpty == true ? '@$fromUsername' : 'Wants to be friends';

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => FriendProfileScreen(userId: fromId))),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: MC.line, width: 0.5)),
        ),
        child: Row(
          children: [
            AvatarWidget(memberId: fromId, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                      style: const TextStyle(
                          color: MC.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(handle,
                      style: const TextStyle(color: MC.mute, fontSize: 12)),
                ],
              ),
            ),
            _ActionButton(label: 'Decline', onTap: onDecline, isSecondary: true),
            const SizedBox(width: 8),
            _ActionButton(label: 'Accept', onTap: onAccept),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isSecondary;

  const _ActionButton({
    required this.label,
    required this.onTap,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSecondary ? Colors.transparent : MC.accent1.withAlpha(21),
          border: Border.all(
              color: isSecondary ? MC.line : MC.accent1, width: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: isSecondary ? MC.dim : MC.accent1,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool accent;

  const _StatusBadge({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: MC.line, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(color: MC.dim, fontSize: 12),
      ),
    );
  }
}
