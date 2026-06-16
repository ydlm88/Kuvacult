import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/poster.dart';
import '../widgets/sign_in_sheet.dart';
import 'friend_profile.dart';
import 'friends.dart';
import 'onboarding.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;

    final displayName = user?.displayName ?? 'Guest';
    final username = user?.username ?? 'guest';
    // Deduplicate by movie ID across every watchlist the user belongs to
    final watched = {
      for (final wl in state.watchlists)
        for (final m in wl.movies)
          if (m.section.name == 'watched') m.id: m,
    }.values.toList();
    final friendIds = user?.friendIds ?? [];
    final pendingRequests = state.friendRequests
        .where((r) => r.toId == (user?.id ?? '') && !r.accepted)
        .toList();
    final reviews = state.reviewsForUser(user?.id ?? '');
    final watchlists = state.watchlists.toList();

    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        slivers: [
          // ── Profile hero ─────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 72, 24, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [MC.bg1, MC.bg0],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _ProfileAvatar(user: user, size: 64),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName, style: MT.display(size: 24)),
                            Text('@$username',
                                style: MT.mono(size: 11, letterSpacing: 1)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showEditProfile(context, user),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: MC.line, width: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Edit',
                              style: TextStyle(color: MC.mute, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _statBox('${watched.length}', 'Watched'),
                      const SizedBox(width: 8),
                      _statBox('${reviews.length}', 'Reviews'),
                      const SizedBox(width: 8),
                      _statBox('${state.myFollowerCount}', 'Followers'),
                      const SizedBox(width: 8),
                      _statBox('${state.myFollowingCount}', 'Following'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Tab selector ─────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              height: 40,
              decoration: BoxDecoration(
                color: MC.bg1,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children:
                    ['Reviews', 'Watchlists', 'Watched'].asMap().entries.map((e) {
                  final isActive = _tab == e.key;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _tab = e.key),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isActive ? MC.bg2 : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          e.value.toUpperCase(),
                          style: MT.mono(
                            size: 10,
                            letterSpacing: 1.5,
                            color: isActive ? MC.ink : MC.dim,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Tab content ──────────────────────────────────────────────────────
          if (_tab == 0) ...[
            // Reviews tab
            if (reviews.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('No reviews yet',
                      style: TextStyle(color: MC.dim, fontSize: 13)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _buildReviewRow(reviews[i], state),
                    childCount: reviews.length,
                  ),
                ),
              ),
          ] else if (_tab == 1) ...[
            // Watchlists tab
            if (watchlists.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('No watchlists yet',
                      style: TextStyle(color: MC.dim, fontSize: 13)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final wl = watchlists[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: MC.bg1,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: MC.line, width: 0.5),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(wl.name,
                                      style: const TextStyle(
                                          color: MC.ink,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                  Text('${wl.movies.length} movies',
                                      style: MT.mono(
                                          size: 10,
                                          letterSpacing: 0,
                                          color: MC.dim)),
                                  if (wl.listKey.isNotEmpty)
                                    Text(wl.listKey,
                                        style: MT.mono(
                                            size: 9,
                                            letterSpacing: 2,
                                            color: MC.mute)),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => state.likeWatchlist(wl.id),
                              child: Row(
                                children: [
                                  Icon(
                                    wl.likedByMe
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    size: 16,
                                    color: wl.likedByMe
                                        ? const Color(0xFFE05A7A)
                                        : MC.dim,
                                  ),
                                  const SizedBox(width: 4),
                                  Text('${wl.likes}',
                                      style: MT.mono(
                                          size: 10,
                                          letterSpacing: 0,
                                          color: wl.likedByMe
                                              ? const Color(0xFFE05A7A)
                                              : MC.dim)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    childCount: watchlists.length,
                  ),
                ),
              ),
          ] else ...[
            // Watched tab
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _WatchedGrid(movies: watched),
              ),
            ),
          ],

          // ── My Room ──────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              child: Text('My Room', style: MT.display(size: 22)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  if (user?.roomKey != null)
                    _RoomCodeCard(
                        roomKey: user!.roomKey!, parentContext: context)
                  else
                    _CreateRoomCard(
                      onGenerate: () {
                        if (context.read<AppState>().isGuest) {
                          showSignInSheet(context);
                        } else {
                          context.read<AppState>().generateRoomKey();
                        }
                      },
                    ),
                ],
              ),
            ),
          ),

          // ── Join a List ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              child: Text('Join a List', style: MT.display(size: 22)),
            ),
          ),
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(child: _JoinListCard()),
          ),

          // ── Friends ───────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
              child: Row(
                children: [
                  Text('Friends', style: MT.display(size: 22)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const FriendsScreen())),
                    child: Text('See all',
                        style: MT.mono(
                            size: 10, color: MC.accent1, letterSpacing: 1)),
                  ),
                ],
              ),
            ),
          ),
          if (pendingRequests.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PENDING',
                        style: MT.mono(size: 10, letterSpacing: 2)),
                    const SizedBox(height: 8),
                    ...pendingRequests.map((req) => _PendingRequestTile(
                          fromId: req.fromId,
                          onAccept: () =>
                              state.acceptFriendRequest(req.id),
                          onDecline: () =>
                              state.declineFriendRequest(req.id),
                        )),
                  ],
                ),
              ),
            ),
          if (friendIds.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const FriendsScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 20),
                    decoration: BoxDecoration(
                      color: MC.bg1,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: MC.line, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_add_outlined,
                            color: MC.accent1, size: 22),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Add your first friend',
                                  style: TextStyle(
                                      color: MC.ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              SizedBox(height: 2),
                              Text(
                                  'Find people to share your watchlist with.',
                                  style: TextStyle(
                                      color: MC.mute,
                                      fontSize: 12,
                                      height: 1.4)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: MC.dim, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemCount: friendIds.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == friendIds.length) {
                      return GestureDetector(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const FriendsScreen())),
                        child: Column(children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: MC.line, width: 0.5),
                            ),
                            child: const Icon(Icons.person_add_outlined,
                                color: MC.mute, size: 20),
                          ),
                          const SizedBox(height: 6),
                          Text('Add',
                              style: MT.mono(size: 9, letterSpacing: 1)),
                        ]),
                      );
                    }
                    final fid = friendIds[i];
                    UserAccount? friend;
                    try {
                      friend = state.friends.firstWhere((f) => f.id == fid);
                    } catch (_) {}
                    final name = friend?.displayName.isNotEmpty == true
                        ? friend!.displayName
                        : (friend?.username.isNotEmpty == true
                            ? friend!.username
                            : '');
                    final initial = name.isNotEmpty
                        ? name[0].toUpperCase()
                        : (fid.isNotEmpty ? fid[0].toUpperCase() : '?');
                    final rawLabel = name.isNotEmpty
                        ? name
                        : (fid.contains('|')
                            ? fid.split('|').last
                            : fid);
                    final label = rawLabel.length > 10
                        ? '${rawLabel.substring(0, 10)}…'
                        : rawLabel;
                    const colors = [
                      Color(0xFFF6C453), Color(0xFF7AB9F2),
                      Color(0xFFE98AA8), Color(0xFF85C9A8),
                      Color(0xFFB39DDB),
                    ];
                    final avatarColor =
                        colors[fid.hashCode.abs() % colors.length];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  FriendProfileScreen(userId: fid))),
                      child: Column(children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: avatarColor,
                            border: Border.all(color: MC.line, width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initial,
                            style: const TextStyle(
                                color: MC.accentInk,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(label,
                            style:
                                const TextStyle(color: MC.mute, fontSize: 10)),
                      ]),
                    );
                  },
                ),
              ),
            ),

          // ── Settings ──────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
              child: Text('Settings', style: MT.display(size: 22)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _settingsRow(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    onTap: () {},
                  ),
                  _settingsRow(
                    icon: Icons.lock_outline_rounded,
                    label: 'Privacy',
                    onTap: () {},
                  ),
                  _settingsRow(
                    icon: Icons.palette_outlined,
                    label: 'Theme',
                    onTap: () {},
                  ),
                  _settingsRow(
                    icon: Icons.logout_rounded,
                    label: 'Sign out',
                    color: Colors.redAccent,
                    onTap: () => _signOut(context),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _buildReviewRow(Review r, AppState state) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MC.line, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: r.moviePosterUrl != null
                ? Image.network(r.moviePosterUrl!,
                    width: 40,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _reviewPosterPlaceholder())
                : _reviewPosterPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.movieTitle,
                    style: MT.display(size: 14, letterSpacing: -0.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('${r.movieYear}',
                    style: MT.mono(size: 10, letterSpacing: 0, color: MC.dim)),
                const SizedBox(height: 6),
                _ReviewStarRow(stars: r.stars),
                const SizedBox(height: 6),
                if (r.text.isNotEmpty)
                  Text(r.text,
                      style: const TextStyle(
                          fontSize: 13, color: MC.ink, height: 1.45),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => state.likeReview(r.id),
                      child: Row(children: [
                        Icon(
                          r.likedByMe
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 13,
                          color: r.likedByMe
                              ? const Color(0xFFE05A7A)
                              : MC.dim,
                        ),
                        const SizedBox(width: 3),
                        Text('${r.likes}',
                            style: MT.mono(
                                size: 9,
                                letterSpacing: 0,
                                color: r.likedByMe
                                    ? const Color(0xFFE05A7A)
                                    : MC.dim)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewPosterPlaceholder() => Container(
        width: 40,
        height: 60,
        decoration: BoxDecoration(
          color: MC.bg2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.movie_outlined, color: MC.dim, size: 16),
      );

  // ── Stat box ─────────────────────────────────────────────────────────────────
  Widget _statBox(String value, String label, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: MC.bg1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MC.line, width: 0.5),
          ),
          child: Column(
            children: [
              Text(value, style: MT.display(size: 18, color: MC.accent1)),
              const SizedBox(height: 2),
              Text(label,
                  style: MT.mono(size: 8, letterSpacing: 0.8),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  // ── Settings row ─────────────────────────────────────────────────────────────
  Widget _settingsRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: MC.line, width: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color ?? MC.mute, size: 20),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    color: color ?? MC.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                color: color ?? MC.dim, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────────
  void _showEditProfile(BuildContext context, UserAccount? user) {
    if (context.read<AppState>().isGuest) {
      showSignInSheet(context);
      return;
    }
    if (user == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.bg1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditProfileSheet(user: user),
    );
  }

  void _signOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.bg1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign out?', style: TextStyle(color: MC.ink)),
        content: const Text(
            'You will need to sign in again to access your lists.',
            style: TextStyle(color: MC.mute, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: MC.mute)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<AppState>().logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  (_) => false,
                );
              }
            },
            child: const Text('Sign out',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

// ─── Mini star row for profile reviews ───────────────────────────────────────
class _ReviewStarRow extends StatelessWidget {
  final double stars;
  const _ReviewStarRow({required this.stars});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = (i + 1) <= stars;
        final half = !filled && (i + 0.5) <= stars;
        return Padding(
          padding: const EdgeInsets.only(right: 1),
          child: Icon(
            half
                ? Icons.star_half_rounded
                : filled
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
            size: 13,
            color: MC.marqueeScore,
          ),
        );
      }),
    );
  }
}

// ── Profile avatar — shows uploaded photo, falls back to initials ─────────────
class _ProfileAvatar extends StatelessWidget {
  final UserAccount? user;
  final double size;

  const _ProfileAvatar({required this.user, required this.size});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user?.avatarUrl;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      final isNetwork = avatarUrl.startsWith('http');
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: MC.accent1, width: 2),
        ),
        child: ClipOval(
          child: isNetwork
              ? Image.network(avatarUrl,
                  width: size, height: size, fit: BoxFit.cover)
              : Image.file(File(avatarUrl),
                  width: size, height: size, fit: BoxFit.cover),
        ),
      );
    }

    final initial = user?.displayName.isNotEmpty == true
        ? user!.displayName[0].toUpperCase()
        : 'G';
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: user?.avatarBg ?? const Color(0xFF5A5A5A),
        border: Border.all(color: MC.accent1, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(initial,
          style: TextStyle(
              fontSize: size * 0.44,
              fontWeight: FontWeight.w700,
              color: MC.accentInk)),
    );
  }
}

// ── Room code card (user already has a key) ───────────────────────────────────
class _RoomCodeCard extends StatelessWidget {
  final String roomKey;
  final BuildContext parentContext;

  const _RoomCodeCard(
      {required this.roomKey, required this.parentContext});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: MC.accent1.withAlpha(80), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('YOUR ROOM CODE',
                  style: MT.mono(size: 10, letterSpacing: 2)),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    context.read<AppState>().generateRoomKey(),
                child: Text('Regenerate',
                    style: MT.mono(
                        size: 10,
                        color: MC.accent1,
                        letterSpacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Copyable code display
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: roomKey));
              ScaffoldMessenger.of(parentContext).showSnackBar(
                SnackBar(
                  content: const Text('Room code copied',
                      style:
                          TextStyle(color: MC.ink, fontSize: 13)),
                  backgroundColor: MC.bg1,
                  behavior: SnackBarBehavior.floating,
                  margin:
                      const EdgeInsets.fromLTRB(20, 0, 20, 104),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: MC.bg2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        roomKey.split('').join('  '),
                        style: MT.mono(
                            size: 24,
                            letterSpacing: 4,
                            color: MC.accent1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.copy_rounded,
                      color: MC.mute, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Share this with friends — they enter it to join your room.',
            style: TextStyle(
                color: MC.mute, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ── Create room card (no key yet) ─────────────────────────────────────────────
class _CreateRoomCard extends StatelessWidget {
  final VoidCallback onGenerate;

  const _CreateRoomCard({required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MC.line, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Start a Room', style: MT.display(size: 18, letterSpacing: -0.5)),
          const SizedBox(height: 6),
          const Text(
            'Generate a unique 6-character code. Friends enter it to join your shared room.',
            style: TextStyle(
                color: MC.mute, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onGenerate,
            child: Container(
              width: double.infinity,
              height: 46,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [MC.accent1, MC.accent2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text('Generate Room Code',
                  style: TextStyle(
                      color: MC.accentInk,
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Join list card (joins a specific watchlist by list key) ──────────────────
class _JoinListCard extends StatefulWidget {
  const _JoinListCard();

  @override
  State<_JoinListCard> createState() => _JoinListCardState();
}

class _JoinListCardState extends State<_JoinListCard> {
  final _ctrl = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MC.line, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: MT.mono(size: 15, letterSpacing: 3, color: MC.ink),
              decoration: const InputDecoration(
                hintText: 'Enter list key',
                hintStyle: TextStyle(
                    color: MC.dim,
                    fontSize: 13,
                    fontFamily: 'monospace',
                    letterSpacing: 0),
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                counterText: '',
              ),
              cursorColor: MC.accent1,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _ctrl.text.length == 6 && !_joining ? _join : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _ctrl.text.length == 6 ? MC.accent1 : MC.bg2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: _joining
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                          color: MC.accentInk, strokeWidth: 2))
                  : Text('Join',
                      style: TextStyle(
                          color: _ctrl.text.length == 6 ? MC.accentInk : MC.dim,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      await context.read<AppState>().joinRoomByKey(_ctrl.text);
      if (mounted) {
        _ctrl.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Watchlist joined!',
              style: TextStyle(color: MC.ink, fontSize: 13)),
          backgroundColor: MC.bg1,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }
}

// ── Edit profile bottom sheet ─────────────────────────────────────────────────
class _EditProfileSheet extends StatefulWidget {
  final UserAccount user;

  const _EditProfileSheet({required this.user});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  XFile? _pickedImage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.displayName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: MC.dim,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 24),

          // ── Avatar picker ───────────────────────────────────────────────────
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _buildSheetAvatar(),
                Positioned(
                  right: -2, bottom: -2,
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: MC.accent1,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: MC.bg1, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: MC.accentInk, size: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('Tap to change photo',
              style: MT.mono(size: 10, letterSpacing: 1)),
          const SizedBox(height: 28),

          // ── Display name ────────────────────────────────────────────────────
          Align(
            alignment: Alignment.centerLeft,
            child: Text('DISPLAY NAME',
                style: MT.mono(size: 10, letterSpacing: 2)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: MC.ink, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Your name…',
              hintStyle: const TextStyle(color: MC.dim),
              filled: true,
              fillColor: MC.bg2,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: MC.accent1, width: 1)),
            ),
            cursorColor: MC.accent1,
          ),
          const SizedBox(height: 16),

          // ── Username (read-only) ─────────────────────────────────────────────
          Align(
            alignment: Alignment.centerLeft,
            child: Text('USERNAME',
                style: MT.mono(size: 10, letterSpacing: 2)),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: MC.bg2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Text('@${widget.user.username}',
                    style: const TextStyle(
                        color: MC.mute, fontSize: 15)),
                const Spacer(),
                Text('Cannot be changed',
                    style: MT.mono(
                        size: 9, letterSpacing: 1, color: MC.dim)),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Save button ──────────────────────────────────────────────────────
          GestureDetector(
            onTap: _saving ? null : _save,
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [MC.accent1, MC.accent2],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: MC.accentInk, strokeWidth: 2))
                  : const Text('Save Changes',
                      style: TextStyle(
                          color: MC.accentInk,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
            ),
          ),
          const SizedBox(height: 12),

          // ── Sign out ──────────────────────────────────────────────────────────
          GestureDetector(
            onTap: _signOut,
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.redAccent.withAlpha(80),
                    width: 0.5),
              ),
              alignment: Alignment.center,
              child: const Text('Sign Out',
                  style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w500,
                      fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetAvatar() {
    const double size = 80;
    if (_pickedImage != null) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: MC.accent1, width: 2),
        ),
        child: ClipOval(
          child: Image.file(
            File(_pickedImage!.path),
            width: size, height: size,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    final avatarUrl = widget.user.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      final isNetwork = avatarUrl.startsWith('http');
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: MC.accent1, width: 2),
        ),
        child: ClipOval(
          child: isNetwork
              ? Image.network(avatarUrl,
                  width: size, height: size, fit: BoxFit.cover)
              : Image.file(File(avatarUrl),
                  width: size, height: size, fit: BoxFit.cover),
        ),
      );
    }
    final initial = widget.user.displayName.isNotEmpty
        ? widget.user.displayName[0].toUpperCase()
        : 'G';
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.user.avatarBg,
        border: Border.all(color: MC.accent1, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(initial,
          style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: MC.accentInk)),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (image != null) setState(() => _pickedImage = image);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<AppState>().updateProfile(
        displayName: _nameCtrl.text,
        avatarFilePath: _pickedImage?.path,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _signOut() {
    Navigator.pop(context);
    final nav = Navigator.of(context);
    context.read<AppState>().logout().then((_) {
      if (mounted) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
          (_) => false,
        );
      }
    });
  }
}

// ─── Pending friend request tile (profile page) ───────────────────────────────
class _PendingRequestTile extends StatelessWidget {
  final String fromId;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _PendingRequestTile({
    required this.fromId,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFFF6C453), const Color(0xFF7AB9F2),
      const Color(0xFFE98AA8), const Color(0xFF85C9A8), const Color(0xFFB39DDB),
    ];
    final color = colors[fromId.hashCode.abs() % colors.length];
    // Strip "auth0|" or "google-oauth2|" prefix for a cleaner placeholder until profile loads
    final cleanId = fromId.contains('|') ? fromId.split('|').last : fromId;
    final initial = cleanId.isNotEmpty ? cleanId[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => FriendProfileScreen(userId: fromId))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: MC.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MC.line, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              alignment: Alignment.center,
              child: Text(initial,
                  style: const TextStyle(
                      color: MC.accentInk,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cleanId,
                      style: const TextStyle(
                          color: MC.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const Text('Wants to be friends',
                      style: TextStyle(color: MC.mute, fontSize: 11)),
                ],
              ),
            ),
            GestureDetector(
              onTap: onDecline,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: MC.line, width: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Decline',
                    style: TextStyle(color: MC.dim, fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onAccept,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: MC.accent1.withAlpha(21),
                  border: Border.all(color: MC.accent1, width: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Accept',
                    style: TextStyle(
                        color: MC.accent1,
                        fontWeight: FontWeight.w600,
                        fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Paginated watched grid ────────────────────────────────────────────────────
class _WatchedGrid extends StatefulWidget {
  final List<Movie> movies;
  const _WatchedGrid({required this.movies});

  @override
  State<_WatchedGrid> createState() => _WatchedGridState();
}

class _WatchedGridState extends State<_WatchedGrid> {
  int _page = 0;
  static const int _perPage = 9;

  @override
  void didUpdateWidget(_WatchedGrid old) {
    super.didUpdateWidget(old);
    // Clamp page if the list shrunk
    final pages = _pageCount;
    if (_page >= pages && pages > 0) setState(() => _page = pages - 1);
  }

  int get _pageCount => (widget.movies.length / _perPage).ceil().clamp(1, 999);

  @override
  Widget build(BuildContext context) {
    if (widget.movies.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: MC.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MC.line, width: 0.5),
        ),
        child: const Text(
          'Movies you mark as watched will appear here.',
          style: TextStyle(color: MC.mute, fontSize: 13, height: 1.5),
          textAlign: TextAlign.center,
        ),
      );
    }

    final total = widget.movies.length;
    final pages = _pageCount;
    final start = _page * _perPage;
    final end = (start + _perPage).clamp(0, total);
    final pageMovies = widget.movies.sublist(start, end);

    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2 / 3,
          ),
          itemCount: pageMovies.length,
          itemBuilder: (ctx, i) => RepaintBoundary(
            child: LayoutBuilder(
              builder: (lctx, constraints) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: PosterWidget(
                  movie: pageMovies[i],
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                ),
              ),
            ),
          ),
        ),
        if (pages > 1) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _page > 0 ? () => setState(() => _page--) : null,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: MC.bg1,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.chevron_left_rounded,
                    color: _page > 0 ? MC.ink : MC.dim,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${_page + 1} / $pages',
                style: MT.mono(size: 11, letterSpacing: 0),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: _page < pages - 1 ? () => setState(() => _page++) : null,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: MC.bg1,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: _page < pages - 1 ? MC.ink : MC.dim,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}
