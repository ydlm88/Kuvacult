// user_profile.dart — Redesigned friend profile page with CustomScrollView,
// frosted-glass back button, inline follow pill, and new review/film/lists tabs.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart' hide Config;
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../widgets/app_image.dart';
import '../widgets/kuvacult_loader.dart';
import '../widgets/profile_banner.dart' show DissolveBanner;
import '../widgets/review_text.dart';
import 'detail.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}

enum _ReviewSort { recent, highest, lowest, liked }

extension _ReviewSortLabel on _ReviewSort {
  String get label => switch (this) {
        _ReviewSort.recent  => 'Most recent',
        _ReviewSort.highest => 'Highest rated',
        _ReviewSort.lowest  => 'Lowest rated',
        _ReviewSort.liked   => 'Most liked',
      };
}

// ─── Page widget ──────────────────────────────────────────────────────────────

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String initialName;

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.initialName = '',
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  double _contentOpacity = 0.0;
  int _followerCount = 0;
  int _followingCount = 0;

  // New tab / toolbar state
  int _tab = 0;
  _ReviewSort _sort = _ReviewSort.recent;
  String _query = '';

  // Optimistic follow: null = use server state
  bool? _localFollowing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final requesterId = state.currentUser?.id;
    state.loadUserWatchedMovies(widget.userId);
    state.loadUserReviews(widget.userId);
    try {
      final results = await Future.wait<dynamic>([
        ApiService.fetchUser(widget.userId, requesterId: requesterId),
        ApiService.fetchUserSocialStats(widget.userId),
        Future.delayed(const Duration(milliseconds: 1500)),
      ]);
      if (mounted) {
        final prof        = results[0] as Map<String, dynamic>;
        final socialStats = results[1] as Map<String, dynamic>;
        final rawUrl   = prof['avatarUrl'] as String?;
        final cacheUrl = rawUrl != null && rawUrl.isNotEmpty
            ? (rawUrl.startsWith('/') ? '${Config.httpBase}$rawUrl' : rawUrl)
            : null;
        state.cacheMemberProfile(
          widget.userId,
          prof['displayName'] as String? ?? '',
          prof['username']    as String? ?? '',
          cacheUrl,
        );
        setState(() {
          _profile        = prof;
          _followerCount  = (socialStats['followerCount']  as num?)?.toInt() ?? 0;
          _followingCount = (socialStats['followingCount'] as num?)?.toInt() ?? 0;
          _loading        = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _contentOpacity = 1.0);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _contentOpacity = 1.0);
        });
      }
    }
  }

  Future<void> _toggleFollow(bool currentlyFollowing) async {
    setState(() => _localFollowing = !currentlyFollowing);
    try {
      if (currentlyFollowing) {
        await context.read<AppState>().unfollowUser(widget.userId);
      } else {
        await context.read<AppState>().followUser(widget.userId);
      }
    } catch (_) {
      if (mounted) setState(() => _localFollowing = currentlyFollowing);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ProfileLoadingScreen();

    final state = context.watch<AppState>();
    final myId  = state.currentUser?.id;
    final isMe  = myId == widget.userId;

    final reviews       = state.reviewsForUser(widget.userId);
    final watchedMovies = state.watchedMoviesForUser(widget.userId);

    final displayName = _profile?['displayName'] as String? ??
        (widget.initialName.isNotEmpty ? widget.initialName : widget.userId);
    final username = _profile?['username'] as String? ?? '';

    final rawAvatarUrl = _profile?['avatarUrl'] as String?;
    final avatarUrl = rawAvatarUrl != null && rawAvatarUrl.isNotEmpty
        ? (rawAvatarUrl.startsWith('/') ? '${Config.httpBase}$rawAvatarUrl' : rawAvatarUrl)
        : null;

    final colors = [
      const Color(0xFFF6C453), const Color(0xFF7AB9F2),
      const Color(0xFFE98AA8), const Color(0xFF85C9A8), const Color(0xFFB39DDB),
    ];
    final avatarColor = colors[widget.userId.hashCode.abs() % colors.length];
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    final serverBannerUrls = (_profile?['bannerUrls'] as List?)?.cast<String>() ?? [];
    final bannerPosters = serverBannerUrls.isNotEmpty
        ? serverBannerUrls.take(4).toList()
        : (List<Review>.from(reviews)
              ..sort((a, b) => b.stars.compareTo(a.stars)))
            .where((r) => r.moviePosterUrl != null && r.moviePosterUrl!.isNotEmpty)
            .take(4)
            .map((r) {
              final u = r.moviePosterUrl!;
              return u.startsWith('/') ? '${Config.httpBase}$u' : u;
            })
            .toList();

    final serverFollowing = state.isFollowing(widget.userId);
    final following = _localFollowing ?? serverFollowing;

    final topPad = MediaQuery.of(context).padding.top;

    // Filtered + sorted reviews for tab 0
    final q = _query.trim().toLowerCase();
    var filteredReviews = q.isEmpty
        ? List<Review>.from(reviews)
        : reviews.where((r) => r.movieTitle.toLowerCase().contains(q)).toList();
    switch (_sort) {
      case _ReviewSort.highest: filteredReviews.sort((a, b) => b.stars.compareTo(a.stars));
      case _ReviewSort.lowest:  filteredReviews.sort((a, b) => a.stars.compareTo(b.stars));
      case _ReviewSort.liked:   filteredReviews.sort((a, b) => b.likes.compareTo(a.likes));
      case _ReviewSort.recent:  filteredReviews.sort((a, b) => b.at.compareTo(a.at));
    }

    return AnimatedOpacity(
      opacity: _contentOpacity,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOut,
      child: Scaffold(
        backgroundColor: MC.bg0,
        body: CustomScrollView(
          slivers: [
            // ── Banner + back button + header ──────────────────────────────
            SliverToBoxAdapter(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Banner 204px (original height)
                  DissolveBanner(posterUrls: bannerPosters, height: 204),

                  // Frosted-glass back button
                  Positioned(
                    top: topPad + 12, left: 20,
                    child: ClipOval(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Material(
                          color: const Color(0x8C0B0A09),
                          child: InkWell(
                            onTap: () => Navigator.pop(context),
                            child: const SizedBox(
                              width: 34, height: 34,
                              child: Icon(Icons.arrow_back_ios_new_rounded,
                                  color: Color(0xFFEDE6DA), size: 16),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Header anchored to bottom of banner
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: _Header(
                        displayName: displayName,
                        username: username,
                        avatarUrl: avatarUrl,
                        avatarColor: avatarColor,
                        avatarInitial: initial,
                        watchedCount: watchedMovies.length,
                        reviewCount: reviews.length,
                        followerCount: _followerCount,
                        followingCount: _followingCount,
                        isMe: isMe,
                        following: following,
                        onToggleFollow: () => _toggleFollow(following),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Tabs + toolbar ─────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              sliver: SliverList.list(
                children: [
                  _TabBar(
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _SearchField(
                          hint: 'Search ${displayName.split(' ').first}\'s reviews…',
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _SortButton(
                        value: _sort,
                        onChanged: (s) => setState(() => _sort = s),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),

            // ── Content ────────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 64),
              sliver: _buildContent(
                state:          state,
                tab:            _tab,
                reviews:        filteredReviews,
                watchedMovies:  watchedMovies,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent({
    required AppState state,
    required int tab,
    required List<Review> reviews,
    required List<WatchedMovie> watchedMovies,
  }) {
    switch (tab) {
      case 0:
        if (reviews.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  'No reviews yet.',
                  style: MT.mono(size: 14, color: const Color(0xFF6F665C)),
                ),
              ),
            ),
          );
        }
        return SliverList.separated(
          itemCount: reviews.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) => _ReviewCard(
            review: reviews[i],
            onLike: () => state.likeReview(reviews[i].id),
          ),
        );

      case 1:
        if (watchedMovies.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  'No watched films yet.',
                  style: MT.mono(size: 14, color: const Color(0xFF6F665C)),
                ),
              ),
            ),
          );
        }
        return SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2 / 3,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final m   = watchedMovies[i];
              final raw = m.posterUrl;
              final url = raw != null && raw.isNotEmpty
                  ? (raw.startsWith('/') ? '${Config.httpBase}$raw' : raw)
                  : null;
              return GestureDetector(
                onTap: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => DetailScreen(movie: _watchedToStubMovie(m)),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: url != null
                      ? AppImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _posterPlaceholder(m.title))
                      : _posterPlaceholder(m.title),
                ),
              );
            },
            childCount: watchedMovies.length,
          ),
        );

      case 2:
      default:
        return SliverToBoxAdapter(
          child: _WatchlistsTab(userId: widget.userId),
        );
    }
  }

  static Movie _watchedToStubMovie(WatchedMovie wm) => Movie(
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

  Widget _posterPlaceholder(String title) => Container(
    color: const Color(0xFF1B1714),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.movie_outlined, color: Color(0xFF6F665C), size: 20),
        if (title.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(title,
                style: const TextStyle(color: Color(0xFF6F665C), fontSize: 9, height: 1.3),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ),
        ],
      ],
    ),
  );
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.displayName,
    required this.username,
    required this.avatarUrl,
    required this.avatarColor,
    required this.avatarInitial,
    required this.watchedCount,
    required this.reviewCount,
    required this.followerCount,
    required this.followingCount,
    required this.isMe,
    required this.following,
    required this.onToggleFollow,
  });

  final String   displayName;
  final String   username;
  final String?  avatarUrl;
  final Color    avatarColor;
  final String   avatarInitial;
  final int      watchedCount;
  final int      reviewCount;
  final int      followerCount;
  final int      followingCount;
  final bool     isMe;
  final bool     following;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Avatar 88px
        Container(
          width: 88, height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: avatarColor,
            boxShadow: const [
              BoxShadow(color: Color(0xFF0B0A09), spreadRadius: 3),
              BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 8)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: avatarUrl != null
              ? AppImage(
                  imageUrl: avatarUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _avatarInitialWidget())
              : _avatarInitialWidget(),
        ),
        const SizedBox(width: 16),
        // Name column
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: GoogleFonts.newsreader().fontFamily,
                          fontSize: 26,
                          height: 1,
                          color: const Color(0xFFEDE6DA),
                          shadows: const [
                            Shadow(
                              color: Color(0xCC000000),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isMe) ...[
                      const SizedBox(width: 10),
                      _FollowPill(following: following, onTap: onToggleFollow),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (username.isNotEmpty)
                  Text(
                    '@$username',
                    style: MT.mono(size: 11, letterSpacing: 0.5, color: MC.accent1),
                  ),
              ],
            ),
          ),
        ),
      ],
    );

    final stats = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        children: [
          _Stat(watchedCount,   'FILMS'),
          _Stat(reviewCount,    'REVIEWS'),
          _Stat(followerCount,  'FOLLOWERS'),
          _Stat(followingCount, 'FOLLOWING'),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [identity, const SizedBox(height: 20), stats],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Align(alignment: Alignment.bottomLeft, child: identity)),
            const SizedBox(width: 16),
            stats,
          ],
        );
      },
    );
  }

  Widget _avatarInitialWidget() => Center(
    child: Text(
      avatarInitial,
      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: MC.accentInk),
    ),
  );
}

// ─── Follow pill ─────────────────────────────────────────────────────────────

class _FollowPill extends StatelessWidget {
  const _FollowPill({required this.following, required this.onTap});
  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: following ? const Color(0x1FD3592C) : const Color(0xFFD3592C),
    shape: const StadiumBorder(side: BorderSide(color: Color(0xFFD3592C))),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          following ? 'Following' : 'Follow',
          style: TextStyle(
            fontSize: 12,
            fontWeight: following ? FontWeight.w400 : FontWeight.w600,
            color: following ? const Color(0xFFE8774C) : const Color(0xFF140805),
          ),
        ),
      ),
    ),
  );
}

// ─── Stat widget ─────────────────────────────────────────────────────────────

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final int    value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$value',
        style: TextStyle(
          fontFamily: GoogleFonts.newsreader().fontFamily,
          fontSize: 19,
          height: 1,
          color: const Color(0xFFEDE6DA),
          shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 8)],
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: MT.mono(size: 9, letterSpacing: 1, color: MC.dim),
      ),
    ],
  );
}

// ─── Tab bar ─────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onChanged});
  final int                index;
  final ValueChanged<int>  onChanged;

  static const _labels = ['REVIEWS', 'FILMS', 'LISTS'];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFF141110),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        for (var i = 0; i < _labels.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == index ? const Color(0xFF221A17) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _labels[i],
                  style: TextStyle(
                    fontFamily: GoogleFonts.martianMono().fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    color: i == index
                        ? const Color(0xFFEDE6DA)
                        : const Color(0xFF8D8377),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

// ─── Search field ─────────────────────────────────────────────────────────────

BoxDecoration _fieldDecoration() => BoxDecoration(
  color: const Color(0xFF141110),
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: const Color(0xFF221C19)),
);

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onChanged});
  final String             hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: _fieldDecoration(),
    child: Row(
      children: [
        const Icon(Icons.search, size: 16, color: Color(0xFF8D8377)),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13, color: Color(0xFFEDE6DA)),
            cursorColor: MC.accent1,
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'Search reviews…',
              hintStyle: TextStyle(color: Color(0xFF6F665C), fontSize: 13),
            ),
          ),
        ),
      ],
    ),
  );
}

// ─── Sort button ─────────────────────────────────────────────────────────────

class _SortButton extends StatelessWidget {
  const _SortButton({required this.value, required this.onChanged});
  final _ReviewSort             value;
  final ValueChanged<_ReviewSort> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_ReviewSort>(
    onSelected: onChanged,
    offset: const Offset(0, 46),
    color: const Color(0xFF171311),
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: Color(0xFF2A231F)),
    ),
    itemBuilder: (_) => [
      for (final s in _ReviewSort.values)
        PopupMenuItem<_ReviewSort>(
          value: s,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            width: 160,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: s == value
                          ? const Color(0xFFEDE6DA)
                          : const Color(0xFFA69C90),
                    ),
                  ),
                ),
                if (s == value)
                  const Icon(Icons.check, size: 13, color: MC.accent1),
              ],
            ),
          ),
        ),
    ],
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: _fieldDecoration(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SORT',
            style: MT.mono(size: 10, letterSpacing: 1.2, color: const Color(0xFF8D8377)),
          ),
          const SizedBox(width: 8),
          Text(value.label, style: const TextStyle(fontSize: 12, color: Color(0xFFEDE6DA))),
          const SizedBox(width: 6),
          const Icon(Icons.expand_more, size: 14, color: Color(0xFF8D8377)),
        ],
      ),
    ),
  );
}

// ─── Review card ─────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.onLike});
  final Review       review;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final r = review;
    final meta = r.movieDirector.isEmpty
        ? '${r.movieYear}'
        : '${r.movieYear}  ·  ${r.movieDirector}';

    final rawUrl = r.moviePosterUrl;
    final posterUrl = rawUrl != null && rawUrl.isNotEmpty
        ? (rawUrl.startsWith('/') ? '${Config.httpBase}$rawUrl' : rawUrl)
        : null;

    return GestureDetector(
      onTap: () {
        final resolvedForNav = posterUrl;
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
          poster: resolvedForNav != null
              ? PosterData(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1C1C2E), Color(0xFF2D2D44)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  accent: const Color(0xFFF6C453),
                  imageUrl: resolvedForNav,
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
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailScreen(movie: m, scrollToReviewId: r.id),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF141110),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF221C19)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster 40×60
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 40, height: 60,
                child: posterUrl != null
                    ? AppImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: Color(0xFF1B1714)))
                    : const ColoredBox(color: Color(0xFF1B1714)),
              ),
            ),
            const SizedBox(width: 12),
            // Text column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.movieTitle,
                    style: TextStyle(
                      fontFamily: GoogleFonts.newsreader().fontFamily,
                      fontSize: 14,
                      height: 1.1,
                      color: const Color(0xFFEDE6DA),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(meta, style: MT.mono(size: 10, letterSpacing: 0, color: const Color(0xFF8D8377))),
                  const SizedBox(height: 6),
                  _Stars(rating: r.stars),
                  if (r.text.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ExpandableReviewText(
                      text: r.text,
                      style: const TextStyle(
                        fontSize: 13, height: 1.45, color: Color(0xFFEDE6DA),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  // Footer
                  Row(
                    children: [
                      GestureDetector(
                        onTap: onLike,
                        child: Row(
                          children: [
                            Icon(
                              r.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 13,
                              color: r.likedByMe
                                  ? const Color(0xFFE0577A)
                                  : const Color(0xFF6F665C),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${r.likes}',
                              style: MT.mono(
                                size: 9,
                                color: r.likedByMe
                                    ? const Color(0xFFE0577A)
                                    : const Color(0xFF6F665C),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _timeAgo(r.at),
                        style: MT.mono(size: 9, color: const Color(0xFF6F665C)),
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
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating});
  final double rating;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < 5; i++)
        Padding(
          padding: const EdgeInsets.only(right: 1),
          child: Icon(
            rating >= i + 1
                ? Icons.star_rounded
                : rating >= i + 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: 13,
            color: MC.kuvacultScore,
          ),
        ),
    ],
  );
}

// ─── Loading screen ───────────────────────────────────────────────────────────

class _ProfileLoadingScreen extends StatelessWidget {
  const _ProfileLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: MC.bg0,
      body: Stack(
        children: [
          Positioned(
            top: topPad + 12, left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MC.bg1.withAlpha(220),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: MC.ink, size: 16),
              ),
            ),
          ),
          const Center(child: KuvacultLoader()),
        ],
      ),
    );
  }
}

// ─── Pagination row ───────────────────────────────────────────────────────────

class _PaginationRow extends StatelessWidget {
  final int page;
  final int pageCount;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _PaginationRow({
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

// ─── Watchlists tab ───────────────────────────────────────────────────────────

class _WatchlistsTab extends StatefulWidget {
  final String userId;
  const _WatchlistsTab({required this.userId});

  @override
  State<_WatchlistsTab> createState() => _WatchlistsTabState();
}

class _WatchlistsTabState extends State<_WatchlistsTab> {
  static const _kPageSize    = 10;
  static const _kSearchAfter = 8;

  List<Map<String, dynamic>> _watchlists = [];
  bool    _loading = true;
  String  _query   = '';
  int     _page    = 0;
  final   _ctrl    = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.fetchUserWatchlists(widget.userId);
      if (mounted) setState(() { _watchlists = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state         = context.watch<AppState>();
    final currentUserId = state.currentUser?.id;

    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(color: MC.accent1, strokeWidth: 2),
          ),
        ),
      );
    }

    if (_watchlists.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Text('No watchlists yet.',
              style: TextStyle(color: MC.dim, fontSize: 13),
              textAlign: TextAlign.center),
        ),
      );
    }

    final filtered = _query.isEmpty
        ? _watchlists
        : _watchlists
            .where((w) => (w['name'] as String? ?? '')
                .toLowerCase()
                .contains(_query.toLowerCase()))
            .toList();

    final paginate  = filtered.length > _kPageSize;
    final pageCount = paginate ? (filtered.length / _kPageSize).ceil() : 1;
    final page      = _page.clamp(0, pageCount - 1);
    final pageItems = paginate
        ? filtered.skip(page * _kPageSize).take(_kPageSize).toList()
        : filtered;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_watchlists.length > _kSearchAfter) ...[
          _WatchlistSearchField(
            ctrl: _ctrl,
            hint: 'Search watchlists…',
            onChanged: (v) => setState(() { _query = v; _page = 0; }),
          ),
          const SizedBox(height: 12),
        ],
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No results.', style: TextStyle(color: MC.dim, fontSize: 13)),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.68,
            ),
            itemCount: pageItems.length,
            itemBuilder: (ctx, i) {
              final wl          = pageItems[i];
              final watchlistId = wl['id'] as String? ?? '';
              final name        = wl['name'] as String? ?? '';
              final movies      = wl['movies'] as List? ?? [];
              final movieCount  = movies.length;
              final likes       = (wl['likes'] as num?)?.toInt() ?? 0;
              final likedBy     = (wl['likedBy'] as List? ?? []).cast<String>();
              final isLikedFromApi = currentUserId != null && likedBy.contains(currentUserId);
              final isLiked = watchlistId.isNotEmpty &&
                  (isLikedFromApi || state.isCommunityWatchlistLiked(watchlistId));
              final posterUrls = movies
                  .map((m) {
                    final mv = m as Map<String, dynamic>;
                    return mv['imageUrl'] as String? ?? mv['posterUrl'] as String? ?? '';
                  })
                  .where((u) => u.isNotEmpty)
                  .take(4)
                  .toList();
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PublicWatchlistScreen(
                      watchlistId: watchlistId,
                      name: name,
                      initialLikes: likes,
                    ),
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: MC.bg1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                          child: _buildMosaic(posterUrls),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: MT.display(size: 13, letterSpacing: -0.3),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  '$movieCount ${movieCount == 1 ? "film" : "films"}',
                                  style: MT.mono(size: 9, letterSpacing: 1, color: MC.mute),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: watchlistId.isNotEmpty
                                      ? () => state.likeCommunityWatchlist(watchlistId)
                                      : null,
                                  child: Row(
                                    children: [
                                      Icon(
                                        isLiked
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        size: 13,
                                        color: isLiked
                                            ? const Color(0xFFE05A7A)
                                            : MC.dim,
                                      ),
                                      const SizedBox(width: 3),
                                      Text('$likes',
                                          style: MT.mono(
                                              size: 9, letterSpacing: 0,
                                              color: isLiked
                                                  ? const Color(0xFFE05A7A)
                                                  : MC.dim)),
                                    ],
                                  ),
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
            },
          ),
        if (paginate) ...[
          const SizedBox(height: 16),
          _PaginationRow(
            page: page,
            pageCount: pageCount,
            onPrev: page > 0 ? () => setState(() => _page = page - 1) : null,
            onNext: page < pageCount - 1 ? () => setState(() => _page = page + 1) : null,
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildMosaic(List<String> urls) {
    Widget img(String url) => SizedBox.expand(
      child: AppImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(color: MC.bg2),
      ),
    );

    if (urls.isEmpty) {
      return Container(
        color: MC.bg2,
        child: const Center(child: Icon(Icons.movie_outlined, color: MC.dim, size: 32)),
      );
    }
    if (urls.length == 1) return img(urls[0]);
    if (urls.length < 4) {
      return Row(children: [
        Expanded(child: img(urls[0])),
        const SizedBox(width: 1),
        Expanded(child: img(urls[1])),
      ]);
    }
    return Column(children: [
      Expanded(child: Row(children: [
        Expanded(child: img(urls[0])),
        const SizedBox(width: 1),
        Expanded(child: img(urls[1])),
      ])),
      const SizedBox(height: 1),
      Expanded(child: Row(children: [
        Expanded(child: img(urls[2])),
        const SizedBox(width: 1),
        Expanded(child: img(urls[3])),
      ])),
    ]);
  }
}

// Simple search field used only inside _WatchlistsTab (keeps old _SearchField name
// used by WatchlistsTab separate from the new top-level _SearchField).
class _WatchlistSearchField extends StatelessWidget {
  const _WatchlistSearchField({
    required this.ctrl,
    required this.hint,
    required this.onChanged,
  });
  final TextEditingController  ctrl;
  final String                 hint;
  final ValueChanged<String>   onChanged;

  @override
  Widget build(BuildContext context) => Container(
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
      decoration: const InputDecoration(
        hintText: 'Search…',
        hintStyle: TextStyle(color: MC.dim, fontSize: 13),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: InputBorder.none,
        prefixIcon: Icon(Icons.search_rounded, color: MC.dim, size: 18),
        prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36),
      ),
      cursorColor: MC.accent1,
    ),
  );
}

// ─── Public watchlist screen ──────────────────────────────────────────────────

class PublicWatchlistScreen extends StatefulWidget {
  final String watchlistId;
  final String name;
  final int    initialLikes;

  const PublicWatchlistScreen({
    super.key,
    required this.watchlistId,
    required this.name,
    this.initialLikes = 0,
  });

  @override
  State<PublicWatchlistScreen> createState() => _PublicWatchlistScreenState();
}

class _PublicWatchlistScreenState extends State<PublicWatchlistScreen> {
  bool   _loading = true;
  String? _error;
  List<Movie>              _movies  = [];
  List<Map<String, dynamic>> _members = [];
  int    _likes  = 0;
  String _search = '';
  int    _page   = 0;
  static const _kPageSize = 18;
  final _searchCtrl = TextEditingController();

  static const _fallback = PosterData(
    gradient: LinearGradient(
      colors: [Color(0xFF1C1C2E), Color(0xFF2D2D44)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    accent: Color(0xFFF6C453),
  );

  @override
  void initState() {
    super.initState();
    _likes = widget.initialLikes;
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data      = await ApiService.fetchWatchlistById(widget.watchlistId);
      final rawMovies = (data['movies'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _movies  = rawMovies.map(_parseMovie).where((m) => m.id.isNotEmpty).toList();
        _members = (data['members'] as List? ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Failed to load watchlist'; });
    }
  }

  static Movie _parseMovie(Map<String, dynamic> m) {
    final imageUrl = m['imageUrl'] as String?;
    return Movie(
      id: m['id'] ?? m['movieId'] ?? '',
      title: m['title'] ?? '',
      year: (m['year'] as num?)?.toInt() ?? 0,
      runtime: (m['runtime'] as num?)?.toInt() ?? 0,
      rating: (m['rating'] as num?)?.toDouble() ?? 0.0,
      genres: (m['genres'] as List? ?? []).cast<String>(),
      director: m['director'] ?? '',
      streamId: m['streamId'] ?? '',
      addedBy: m['addedBy'] ?? '',
      section: WatchSection.want,
      synopsis: m['synopsis'] ?? '',
      mediaType: m['mediaType'] as String? ?? 'movie',
      watchedBy: (m['watchedBy'] as List? ?? []).cast<String>(),
      poster: imageUrl != null && imageUrl.isNotEmpty
          ? PosterData(gradient: _fallback.gradient, accent: _fallback.accent, imageUrl: imageUrl)
          : _fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state  = context.watch<AppState>();
    final isLiked = widget.watchlistId.isNotEmpty &&
        state.isCommunityWatchlistLiked(widget.watchlistId);
    final communityCache = state.communityTopWatchlists
        .where((w) => w['id'] == widget.watchlistId)
        .firstOrNull;
    final likes = (communityCache?['likes'] as int?) ??
        state.watchlists.where((w) => w.id == widget.watchlistId).firstOrNull?.likes ??
        _likes;

    final filtered = _search.isEmpty
        ? _movies
        : _movies.where((m) => m.title.toLowerCase().contains(_search.toLowerCase())).toList();
    final pageCount  = filtered.isEmpty ? 0 : (filtered.length / _kPageSize).ceil();
    final page       = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final pageMovies = filtered.skip(page * _kPageSize).take(_kPageSize).toList();
    final topPad     = MediaQuery.of(context).padding.top;
    final crossCount = (MediaQuery.of(context).size.width / 180).floor().clamp(3, 8);

    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, topPad + 12, 16, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: MC.bg1.withAlpha(220)),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: MC.ink, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(widget.name,
                        style: MT.display(size: 22, letterSpacing: -0.4),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  GestureDetector(
                    onTap: widget.watchlistId.isNotEmpty
                        ? () => state.likeCommunityWatchlist(widget.watchlistId)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            size: 20,
                            color: isLiked ? const Color(0xFFE05A7A) : MC.dim,
                          ),
                          const SizedBox(width: 5),
                          Text('$likes',
                              style: MT.mono(
                                size: 11, letterSpacing: 0,
                                color: isLiked ? const Color(0xFFE05A7A) : MC.dim,
                              )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(60),
                child: Center(child: KuvacultLoader()),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Center(
                  child: Text(_error!,
                      style: const TextStyle(color: MC.dim, fontSize: 13)),
                ),
              ),
            )
          else ...[
            if (_members.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MEMBERS', style: MT.mono(size: 9, letterSpacing: 2, color: MC.dim)),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _members.map((m) {
                            final displayName = m['displayName'] as String? ?? '';
                            final avatarUrl   = m['avatarUrl'] as String?;
                            final userId      = m['id'] as String? ?? '';
                            final resolved = avatarUrl != null && avatarUrl.isNotEmpty
                                ? (avatarUrl.startsWith('/')
                                    ? '${Config.httpBase}$avatarUrl'
                                    : avatarUrl)
                                : null;
                            return GestureDetector(
                              onTap: userId.isNotEmpty
                                  ? () => Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => UserProfileScreen(
                                          userId: userId, initialName: displayName)))
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 14),
                                child: Column(
                                  children: [
                                    ClipOval(
                                      child: resolved != null
                                          ? AppImage(
                                              imageUrl: resolved,
                                              width: 40, height: 40,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) =>
                                                  _avatarFallback(displayName))
                                          : _avatarFallback(displayName),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      displayName.isNotEmpty
                                          ? displayName.split(' ').first
                                          : '?',
                                      style: MT.mono(size: 9, letterSpacing: 0, color: MC.dim),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '${_movies.length} ${_movies.length == 1 ? "film" : "films"}',
                  style: MT.mono(size: 10, letterSpacing: 1, color: MC.dim),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: MC.ink, fontSize: 13),
                  onChanged: (v) => setState(() { _search = v; _page = 0; }),
                  decoration: InputDecoration(
                    hintText: 'Search movies…',
                    hintStyle: const TextStyle(color: MC.dim, fontSize: 13),
                    prefixIcon:
                        const Icon(Icons.search_rounded, color: MC.dim, size: 18),
                    suffixIcon: _search.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              setState(() { _search = ''; _page = 0; });
                              _searchCtrl.clear();
                            },
                            child:
                                const Icon(Icons.close_rounded, color: MC.dim, size: 16),
                          )
                        : null,
                    filled: true,
                    fillColor: MC.bg1,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: MC.line, width: 0.5)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: MC.line, width: 0.5)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: MC.accent1, width: 1)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
            ),

            if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      _search.isNotEmpty
                          ? 'No movies match your search'
                          : 'No movies in this list yet',
                      style: const TextStyle(color: MC.dim, fontSize: 13),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossCount,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 12,
                    childAspectRatio: 110 / 185,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final m      = pageMovies[i];
                      final rawUrl = m.poster.imageUrl;
                      final url = rawUrl != null && rawUrl.isNotEmpty
                          ? (rawUrl.startsWith('/')
                              ? '${Config.httpBase}$rawUrl'
                              : rawUrl)
                          : null;
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DetailScreen(movie: m)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: url != null
                                    ? AppImage(
                                        imageUrl: url,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        errorWidget: (_, __, ___) =>
                                            _posterPlaceholder(m))
                                    : _posterPlaceholder(m),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(m.title,
                                style: const TextStyle(color: MC.ink, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text('${m.year}',
                                style: MT.mono(size: 9, letterSpacing: 0, color: MC.dim)),
                          ],
                        ),
                      );
                    },
                    childCount: pageMovies.length,
                  ),
                ),
              ),

            if (pageCount > 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: page > 0 ? () => setState(() => _page = page - 1) : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: page > 0 ? MC.bg1 : MC.bg0,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: MC.line, width: 0.5),
                          ),
                          child: Text('← Prev',
                              style: TextStyle(
                                  color: page > 0 ? MC.ink : MC.dim, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${page + 1} / $pageCount',
                          style: MT.mono(size: 11, letterSpacing: 0.5, color: MC.mute)),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: page < pageCount - 1
                            ? () => setState(() => _page = page + 1)
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: page < pageCount - 1 ? MC.bg1 : MC.bg0,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: MC.line, width: 0.5),
                          ),
                          child: Text('Next →',
                              style: TextStyle(
                                  color: page < pageCount - 1 ? MC.ink : MC.dim,
                                  fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ],
      ),
    );
  }

  Widget _avatarFallback(String name) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 40, height: 40,
      color: const Color(0xFF3A3A4A),
      child: Center(
        child: Text(initial,
            style: const TextStyle(
                color: MC.ink, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _posterPlaceholder(Movie m) => Container(
    color: MC.bg2,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.movie_outlined, color: MC.dim, size: 20),
        if (m.title.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(m.title,
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
