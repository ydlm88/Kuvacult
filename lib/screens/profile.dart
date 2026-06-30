// profile.dart — Displays the current user's profile, reviews, watchlists, watched history, friends, room code, and settings.
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/api_service.dart';
import '../config.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/profile_banner.dart';
import '../widgets/review_text.dart';
import '../widgets/sign_in_sheet.dart';
import 'detail.dart';
import 'friend_profile.dart';
import 'friends.dart';
import 'letterboxd_import.dart';
import 'invites_screen.dart';
import 'onboarding.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _tab = 0;
  bool _refreshing = false;

  int _reviewPage = 0;
  String _reviewSearch = '';
  final _reviewSearchCtrl = TextEditingController();

  int _watchlistPage = 0;
  String _watchlistSearch = '';
  final _watchlistSearchCtrl = TextEditingController();

  @override
  void dispose() {
    _reviewSearchCtrl.dispose();
    _watchlistSearchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;

    final displayName = user?.displayName ?? 'Guest';
    final username = user?.username ?? 'guest';
    final watched = state.myWatchedMovies;
    final friendIds = user?.friendIds ?? [];
    final pendingRequests = state.friendRequests
        .where((r) => r.toId == (user?.id ?? '') && !r.accepted)
        .toList();
    final reviews = state.reviewsForUser(user?.id ?? '');
    const int _kPerPage = 5;
    final filteredReviews = _reviewSearch.isEmpty
        ? reviews
        : reviews.where((r) => r.movieTitle.toLowerCase().contains(_reviewSearch.toLowerCase())).toList();
    final reviewPageCount = filteredReviews.isEmpty ? 1 : (filteredReviews.length / _kPerPage).ceil();
    final reviewPage = _reviewPage.clamp(0, reviewPageCount - 1);
    final visibleReviews = filteredReviews.skip(reviewPage * _kPerPage).take(_kPerPage).toList();
    final reviewPaginate = filteredReviews.length > _kPerPage;

    final watchlists = state.watchlists.toList();
    final filteredWatchlists = _watchlistSearch.isEmpty
        ? watchlists
        : watchlists.where((w) => w.name.toLowerCase().contains(_watchlistSearch.toLowerCase())).toList();
    final watchlistPageCount = filteredWatchlists.isEmpty ? 1 : (filteredWatchlists.length / _kPerPage).ceil();
    final watchlistPage = _watchlistPage.clamp(0, watchlistPageCount - 1);
    final visibleWatchlists = filteredWatchlists.skip(watchlistPage * _kPerPage).take(_kPerPage).toList();
    final watchlistPaginate = filteredWatchlists.length > _kPerPage;

    final topPad = MediaQuery.of(context).padding.top;

    const avatarColors = [
      Color(0xFFF6C453), Color(0xFF7AB9F2),
      Color(0xFFE98AA8), Color(0xFF85C9A8), Color(0xFFB39DDB),
    ];
    final avatarColor = user != null
        ? avatarColors[user.id.hashCode.abs() % avatarColors.length]
        : const Color(0xFFF6C453);

    final bannerPosters = (List<Review>.from(reviews)
          ..sort((a, b) => b.stars.compareTo(a.stars)))
        .where((r) => r.moviePosterUrl != null && r.moviePosterUrl!.isNotEmpty)
        .take(4)
        .map((r) {
          final u = r.moviePosterUrl!;
          return u.startsWith('/') ? '${Config.httpBase}$u' : u;
        })
        .toList();

    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 160 + 44,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: 0, left: 0, right: 0, height: 160,
                        child: ProfileBannerWidget(
                          posterUrls: bannerPosters,
                          avatarColor: avatarColor,
                        ),
                      ),

                      Positioned(
                        top: topPad + 12, right: 16,
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: _refreshing
                                  ? null
                                  : () async {
                                      setState(() => _refreshing = true);
                                      await context.read<AppState>().refreshProfile();
                                      if (mounted) setState(() => _refreshing = false);
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: MC.bg0.withAlpha(200),
                                  border: Border.all(color: MC.line, width: 0.5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: _refreshing
                                    ? const SizedBox(
                                        width: 15, height: 15,
                                        child: CircularProgressIndicator(
                                            color: MC.mute, strokeWidth: 1.5))
                                    : const Icon(Icons.refresh_rounded,
                                        color: MC.mute, size: 15),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _showEditProfile(context, user),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: MC.bg0.withAlpha(200),
                                  border: Border.all(color: MC.line, width: 0.5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('Edit',
                                    style: TextStyle(color: MC.mute, fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Positioned(
                        top: 116, left: 20,
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                          child: _ProfileAvatar(user: user, size: 88),
                        ),
                      ),

                      Positioned(
                        bottom: 6, right: 20,
                        child: Row(
                          children: [
                            _InlineStat(n: watched.length, label: 'Films'),
                            const SizedBox(width: 20),
                            _InlineStat(n: reviews.length, label: 'Reviews'),
                            const SizedBox(width: 20),
                            _InlineStat(n: state.myFollowerCount, label: 'Followers'),
                            const SizedBox(width: 20),
                            _InlineStat(n: state.myFollowingCount, label: 'Following'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName,
                          style: MT.display(size: 26, letterSpacing: -0.6)),
                      if (username.isNotEmpty)
                        Text('@$username',
                            style: MT.mono(
                                size: 11, letterSpacing: 0.5, color: MC.accent1)),
                    ],
                  ),
                ),
              ],
            ),
          ),

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

          if (_tab == 0) ...[
            if (reviews.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('No reviews yet',
                      style: TextStyle(color: MC.dim, fontSize: 13)),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _ProfileSearchField(
                    ctrl: _reviewSearchCtrl,
                    hint: 'Search reviews…',
                    onChanged: (v) => setState(() { _reviewSearch = v; _reviewPage = 0; }),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _buildReviewRow(visibleReviews[i], state),
                    childCount: visibleReviews.length,
                  ),
                ),
              ),
              if (reviewPaginate)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _ProfilePaginationRow(
                      page: reviewPage,
                      pageCount: reviewPageCount,
                      onPrev: reviewPage > 0 ? () => setState(() => _reviewPage = reviewPage - 1) : null,
                      onNext: reviewPage < reviewPageCount - 1 ? () => setState(() => _reviewPage = reviewPage + 1) : null,
                    ),
                  ),
                ),
            ],
          ] else if (_tab == 1) ...[
            if (watchlists.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('No watchlists yet',
                      style: TextStyle(color: MC.dim, fontSize: 13)),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _ProfileSearchField(
                    ctrl: _watchlistSearchCtrl,
                    hint: 'Search watchlists…',
                    onChanged: (v) => setState(() { _watchlistSearch = v; _watchlistPage = 0; }),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final wl = visibleWatchlists[i];
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
                    childCount: visibleWatchlists.length,
                  ),
                ),
              ),
              if (watchlistPaginate)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _ProfilePaginationRow(
                      page: watchlistPage,
                      pageCount: watchlistPageCount,
                      onPrev: watchlistPage > 0 ? () => setState(() => _watchlistPage = watchlistPage - 1) : null,
                      onNext: watchlistPage < watchlistPageCount - 1 ? () => setState(() => _watchlistPage = watchlistPage + 1) : null,
                    ),
                  ),
                ),
            ],
          ] else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: _WatchedGrid(movies: watched),
              ),
            ),
          ],

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              child: Text('My Room - Coming Soon..', style: MT.display(size: 22)),
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
                          fromUsername: req.fromUsername,
                          fromDisplayName: req.fromDisplayName,
                          fromAvatarUrl: req.fromAvatarUrl,
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
                    final rawFriendUrl = friend?.avatarUrl;
                    final resolvedFriendUrl = rawFriendUrl != null &&
                            rawFriendUrl.isNotEmpty
                        ? (rawFriendUrl.startsWith('http')
                            ? rawFriendUrl
                            : '${Config.httpBase}$rawFriendUrl')
                        : null;
                    return GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => FriendProfileScreen(
                                  userId: fid, initialName: name))),
                      child: Column(children: [
                        Container(
                          width: 48,
                          height: 48,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: avatarColor,
                          ),
                          child: resolvedFriendUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: resolvedFriendUrl,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Center(
                                    child: Text(initial,
                                        style: const TextStyle(
                                            color: MC.accentInk,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                        color: MC.accentInk,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700),
                                  ),
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  _settingsRow(
                    icon: Icons.mail_outline_rounded,
                    label: 'View Invites',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const InvitesScreen())),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
              child: Text('Settings', style: MT.display(size: 22)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  _settingsRow(
                    icon: Icons.movie_filter_rounded,
                    label: 'Import from Letterboxd',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const LetterboxdImportScreen())),
                  ),
                  _settingsRow(
                    icon: Icons.lock_outline_rounded,
                    label: 'Privacy',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const _ComingSoonScreen(title: 'Privacy'))),
                  ),
                  _settingsRow(
                    icon: Icons.palette_outlined,
                    label: 'Theme',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const _ComingSoonScreen(title: 'Theme'))),
                  ),
                  _settingsRow(
                    icon: Icons.bug_report_outlined,
                    label: 'Report a bug',
                    onTap: () => _showBugReportSheet(context, state),
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
    final rawUrl = r.moviePosterUrl;
    final posterUrl = rawUrl != null && rawUrl.isNotEmpty
        ? (rawUrl.startsWith('/') ? '${Config.httpBase}$rawUrl' : rawUrl)
        : null;

    return GestureDetector(
      onTap: () {
        final m = Movie(
          id: r.movieId,
          title: r.movieTitle,
          year: r.movieYear,
          runtime: 0,
          rating: 0,
          genres: [],
          director: r.movieDirector,
          streamId: '',
          addedBy: '',
          section: WatchSection.want,
          synopsis: '',
          poster: posterUrl != null
              ? PosterData(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1C1C2E), Color(0xFF2D2D44)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  accent: const Color(0xFFF6C453),
                  imageUrl: posterUrl,
                )
              : const PosterData(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1C1C2E), Color(0xFF2D2D44)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  accent: Color(0xFFF6C453),
                ),
        );
        Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(movie: m, scrollToReviewId: r.id)));
      },
      child: Container(
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
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: posterUrl != null
                  ? CachedNetworkImage(
                      imageUrl: posterUrl,
                      width: 40, height: 60, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _reviewPosterPlaceholder())
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
                  Text(
                    '${r.movieYear}'
                    '${r.movieDirector.isNotEmpty ? "  ·  ${r.movieDirector}" : ""}',
                    style: MT.mono(size: 10, letterSpacing: 0, color: MC.dim),
                  ),
                  const SizedBox(height: 6),
                  _ReviewStarRow(stars: r.stars),
                  if (r.rewatch) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.replay_rounded,
                          size: 10, color: MC.kuvacultScore.withAlpha(180)),
                      const SizedBox(width: 3),
                      Text('Rewatch',
                          style: MT.mono(size: 9, letterSpacing: 0, color: MC.kuvacultScore)),
                    ]),
                  ],
                  if (r.text.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ExpandableReviewText(
                        text: r.text,
                        style: const TextStyle(
                            fontSize: 13, color: MC.ink, height: 1.45)),
                  ],
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
                            color: r.likedByMe ? const Color(0xFFE05A7A) : MC.dim,
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
                      if (state.isWatched(r.movieId)) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.remove_red_eye_rounded, size: 12, color: MC.mute),
                      ],
                      const Spacer(),
                      Text(_timeAgo(r.at),
                          style: MT.mono(size: 9, letterSpacing: 0, color: MC.dim)),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _confirmDeleteReview(context, r.id, state),
                        child: const Icon(Icons.delete_outline_rounded,
                            size: 14, color: MC.dim),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteReview(BuildContext context, String reviewId, AppState state) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.bg1,
        title: const Text('Delete review?',
            style: TextStyle(color: MC.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('This cannot be undone.',
            style: TextStyle(color: MC.dim, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: MC.dim)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              state.deleteReview(reviewId);
            },
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFE05A7A), fontWeight: FontWeight.w600)),
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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  Widget _settingsRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    int badge = 0,
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
            if (badge > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE05A7A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right_rounded,
                color: color ?? MC.dim, size: 18),
          ],
        ),
      ),
    );
  }

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

  void _showBugReportSheet(BuildContext context, AppState state) {
    if (state.isGuest) {
      showSignInSheet(context);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.bg1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _BugReportSheet(userId: state.currentUser?.id),
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
            color: MC.kuvacultScore,
          ),
        );
      }),
    );
  }
}


class _InlineStat extends StatelessWidget {
  final int n;
  final String label;
  const _InlineStat({required this.n, required this.label});

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(_fmt(n), style: MT.display(size: 19)),
        const SizedBox(height: 3),
        Text(label.toUpperCase(),
            style: MT.mono(size: 9, letterSpacing: 1, color: MC.dim)),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final UserAccount? user;
  final double size;

  const _ProfileAvatar({required this.user, required this.size});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user?.avatarUrl;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      final resolvedUrl = avatarUrl.startsWith('http')
          ? avatarUrl
          : '${Config.httpBase}$avatarUrl';
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
        ),
        child: ClipOval(
          child: CachedNetworkImage(
              imageUrl: resolvedUrl,
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
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: MC.dim,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 24),

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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Tap to change photo',
                  style: MT.mono(size: 10, letterSpacing: 1)),
              const SizedBox(width: 8),
              Text('· Max 50 KB',
                  style: MT.mono(size: 10, letterSpacing: 0, color: MC.dim)),
            ],
          ),
          const SizedBox(height: 28),

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
      final resolvedUrl = avatarUrl.startsWith('http')
          ? avatarUrl
          : '${Config.httpBase}$avatarUrl';
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
        ),
        child: ClipOval(
          child: CachedNetworkImage(
              imageUrl: resolvedUrl,
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
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (bytes.length > 50 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Image too large — max 50 KB',
                style: TextStyle(color: MC.ink, fontSize: 13)),
            backgroundColor: MC.bg1,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }
    setState(() => _pickedImage = image);
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

class _PendingRequestTile extends StatelessWidget {
  final String fromId;
  final String? fromUsername;
  final String? fromDisplayName;
  final String? fromAvatarUrl;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _PendingRequestTile({
    required this.fromId,
    this.fromUsername,
    this.fromDisplayName,
    this.fromAvatarUrl,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [
      const Color(0xFFF6C453), const Color(0xFF7AB9F2),
      const Color(0xFFE98AA8), const Color(0xFF85C9A8), const Color(0xFFB39DDB),
    ];
    final displayName = fromDisplayName?.isNotEmpty == true
        ? fromDisplayName!
        : (fromUsername ?? fromId);
    final handle = fromUsername != null ? '@$fromUsername' : null;
    final color = colors[fromId.hashCode.abs() % colors.length];
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    Widget avatar;
    if (fromAvatarUrl != null && fromAvatarUrl!.isNotEmpty) {
      final resolvedUrl = fromAvatarUrl!.startsWith('http')
          ? fromAvatarUrl!
          : '${Config.httpBase}$fromAvatarUrl';
      avatar = ClipOval(
        child: CachedNetworkImage(
            imageUrl: resolvedUrl,
            width: 36, height: 36, fit: BoxFit.cover),
      );
    } else {
      avatar = Container(
        width: 36, height: 36,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        alignment: Alignment.center,
        child: Text(initial,
            style: const TextStyle(
                color: MC.accentInk,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      );
    }

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
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                      style: const TextStyle(
                          color: MC.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  if (handle != null)
                    Text(handle,
                        style: const TextStyle(color: MC.mute, fontSize: 11))
                  else
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

Movie _watchedToStubMovie(WatchedMovie wm) => Movie(
  id: wm.id,
  title: wm.title,
  year: wm.year,
  runtime: 0,
  rating: 0,
  genres: [],
  director: '',
  streamId: '',
  addedBy: '',
  section: WatchSection.watched,
  synopsis: '',
  poster: PosterData(
    gradient: const LinearGradient(
      colors: [Color(0xFF1C1C2E), Color(0xFF2D2D44)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    accent: const Color(0xFFF6C453),
    imageUrl: wm.posterUrl,
  ),
);

class _WatchedGrid extends StatefulWidget {
  final List<WatchedMovie> movies;
  const _WatchedGrid({required this.movies});

  @override
  State<_WatchedGrid> createState() => _WatchedGridState();
}

class _WatchedGridState extends State<_WatchedGrid> {
  static const int _perPage = 18;
  static const int _paginateAfter = 20;
  int _page = 0;
  String _query = '';
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

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

    final filtered = _query.isEmpty
        ? widget.movies
        : widget.movies
            .where((m) => m.title.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    final paginate = filtered.length > _paginateAfter;
    final pageCount = paginate ? (filtered.length / _perPage).ceil() : 1;
    final page = _page.clamp(0, pageCount - 1);
    final pageMovies = paginate
        ? filtered.skip(page * _perPage).take(_perPage).toList()
        : filtered;

    return Column(
      children: [
        _ProfileSearchField(
          ctrl: _ctrl,
          hint: 'Search watched…',
          onChanged: (v) => setState(() { _query = v; _page = 0; }),
        ),
        const SizedBox(height: 4),
        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: const Text('No results.',
                style: TextStyle(color: MC.dim, fontSize: 13)),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: (MediaQuery.of(context).size.width / 180).floor().clamp(3, 8),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2 / 3,
            ),
            itemCount: pageMovies.length,
            itemBuilder: (ctx, i) {
              final wm = pageMovies[i];
              final url = wm.posterUrl != null && wm.posterUrl!.isNotEmpty
                  ? (wm.posterUrl!.startsWith('/')
                      ? '${Config.httpBase}${wm.posterUrl}'
                      : wm.posterUrl!)
                  : null;
              return GestureDetector(
                onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => DetailScreen(movie: _watchedToStubMovie(wm)),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: url != null
                      ? CachedNetworkImage(
                          imageUrl: url, fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _watchedPlaceholder(wm))
                      : _watchedPlaceholder(wm),
                ),
              );
            },
          ),
        if (paginate) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: page > 0 ? () => setState(() => _page = page - 1) : null,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: MC.bg1,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.chevron_left_rounded,
                      color: page > 0 ? MC.ink : MC.dim, size: 20),
                ),
              ),
              const SizedBox(width: 16),
              Text('${page + 1} / $pageCount', style: MT.mono(size: 11, letterSpacing: 0)),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: page < pageCount - 1 ? () => setState(() => _page = page + 1) : null,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: MC.bg1,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.chevron_right_rounded,
                      color: page < pageCount - 1 ? MC.ink : MC.dim, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _watchedPlaceholder(WatchedMovie wm) => Container(
    color: MC.bg2,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.movie_outlined, color: MC.dim, size: 20),
        if (wm.title.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(wm.title,
                style: const TextStyle(color: MC.mute, fontSize: 9, height: 1.3),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ),
        ],
      ],
    ),
  );
}

class _ProfileSearchField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final ValueChanged<String> onChanged;
  const _ProfileSearchField({required this.ctrl, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MC.line, width: 0.5),
      ),
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        style: const TextStyle(color: MC.ink, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: MC.dim, fontSize: 13),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search_rounded, color: MC.dim, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        cursorColor: MC.accent1,
      ),
    );
  }
}

class _ProfileExpandButton extends StatelessWidget {
  final bool expanded;
  final String expandLabel;
  final VoidCallback onTap;
  const _ProfileExpandButton({required this.expanded, required this.expandLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: MC.bg1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MC.line, width: 0.5),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? 'Show less' : expandLabel,
              style: const TextStyle(
                  color: MC.accent1, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 4),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: MC.accent1,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePaginationRow extends StatelessWidget {
  final int page;
  final int pageCount;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _ProfilePaginationRow({
    required this.page,
    required this.pageCount,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: onPrev,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: MC.bg1,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MC.line, width: 0.5),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.chevron_left_rounded,
                color: onPrev != null ? MC.ink : MC.dim, size: 20),
          ),
        ),
        const SizedBox(width: 16),
        Text('${page + 1} / $pageCount', style: MT.mono(size: 11, letterSpacing: 0)),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: onNext,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: MC.bg1,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MC.line, width: 0.5),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.chevron_right_rounded,
                color: onNext != null ? MC.ink : MC.dim, size: 20),
          ),
        ),
      ],
    );
  }
}

class _BugReportSheet extends StatefulWidget {
  final String? userId;
  const _BugReportSheet({this.userId});

  @override
  State<_BugReportSheet> createState() => _BugReportSheetState();
}

class _BugReportSheetState extends State<_BugReportSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  static const int _maxLen = 1000;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final charCount = _ctrl.text.length;
    final hasText = charCount > 0;

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: MC.dim, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Text('Report a bug', style: MT.display(size: 20, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          const Text(
            'Describe what went wrong and we\'ll look into it.',
            style: TextStyle(color: MC.mute, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: MC.bg2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MC.line, width: 0.5),
            ),
            child: TextField(
              controller: _ctrl,
              maxLength: _maxLen,
              maxLines: 6,
              minLines: 4,
              autofocus: true,
              style: const TextStyle(color: MC.ink, fontSize: 14, height: 1.5),
              decoration: const InputDecoration(
                hintText: 'What happened?',
                hintStyle: TextStyle(color: MC.dim, fontSize: 14),
                contentPadding: EdgeInsets.all(14),
                border: InputBorder.none,
                counterText: '',
              ),
              cursorColor: MC.accent1,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$charCount / $_maxLen',
              style: MT.mono(
                size: 10,
                letterSpacing: 0,
                color: charCount > 900 ? const Color(0xFFE05A7A) : MC.dim,
              ),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: hasText && !_sending ? _send : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                gradient: hasText
                    ? const LinearGradient(
                        colors: [MC.accent1, MC.accent2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight)
                    : null,
                color: hasText ? null : MC.bg2,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: _sending
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: MC.accentInk, strokeWidth: 2))
                  : Text(
                      'Send',
                      style: TextStyle(
                        color: hasText ? MC.accentInk : MC.dim,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await ApiService.submitBugReport(
          text: _ctrl.text.trim(), userId: widget.userId);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Bug report sent — thanks!',
              style: TextStyle(color: MC.ink, fontSize: 13)),
          backgroundColor: MC.bg1,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Failed to send — please try again.',
              style: TextStyle(color: MC.ink, fontSize: 13)),
          backgroundColor: MC.bg1,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }
}

class _ComingSoonScreen extends StatelessWidget {
  final String title;
  const _ComingSoonScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MC.bg0,
      appBar: AppBar(
        backgroundColor: MC.bg0,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Icon(Icons.arrow_back_ios_new_rounded, color: MC.ink, size: 18),
        ),
        title: Text(title, style: MT.display(size: 18)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.construction_rounded, color: MC.dim, size: 48),
            const SizedBox(height: 16),
            Text('Coming Soon', style: MT.display(size: 24)),
            const SizedBox(height: 8),
            Text('$title settings are on the way.',
                style: const TextStyle(color: MC.mute, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
