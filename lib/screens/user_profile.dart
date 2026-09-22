// user_profile.dart — Displays a user's public profile with tabs for reviews, watched films, and watchlists, including follow/unfollow and a public watchlist detail screen.
import 'package:flutter/material.dart';
import '../widgets/app_image.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../widgets/kuvacult_loader.dart';
import '../widgets/profile_banner.dart';
import '../widgets/review_text.dart';
import 'detail.dart';

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}

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

class _UserProfileScreenState extends State<UserProfileScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  double _contentOpacity = 0.0;
  late final TabController _tabCtrl;
  int _followerCount = 0;
  int _followingCount = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final requesterId = state.currentUser?.id;
    state.loadUserWatchedMovies(widget.userId);
    state.loadUserReviews(widget.userId);
    try {
      // Run fetch and minimum-display timer in parallel so the animation never
      // flashes away instantly on fast desktop connections.
      final results = await Future.wait<dynamic>([
        ApiService.fetchUser(widget.userId, requesterId: requesterId),
        ApiService.fetchUserSocialStats(widget.userId),
        Future.delayed(const Duration(milliseconds: 1500)),
      ]);
      if (mounted) {
        final prof        = results[0] as Map<String, dynamic>;
        final socialStats = results[1] as Map<String, dynamic>;
        // Cache avatar URL so _AvatarWidget on other screens resolves correctly
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _ProfileLoadingScreen();

    final state = context.watch<AppState>();
    final myId = state.currentUser?.id;
    final isMe = myId == widget.userId;
    final reviews = state.reviewsForUser(widget.userId);
    final watchedMovies = state.watchedMoviesForUser(widget.userId);
    final watchedCount = watchedMovies.length;

    final displayName = _profile?['displayName'] as String? ??
        (widget.initialName.isNotEmpty ? widget.initialName : widget.userId);
    final username = _profile?['username'] as String? ?? '';
    final bio = _profile?['bio'] as String?;
    final location = _profile?['location'] as String?;
    final friendCount = (_profile?['friendIds'] as List?)?.length ?? 0;

    final colors = [
      const Color(0xFFF6C453), const Color(0xFF7AB9F2),
      const Color(0xFFE98AA8), const Color(0xFF85C9A8), const Color(0xFFB39DDB),
    ];
    final avatarColor = colors[widget.userId.hashCode.abs() % colors.length];
    final rawAvatarUrl = _profile?['avatarUrl'] as String?;
    final avatarUrl = rawAvatarUrl != null && rawAvatarUrl.isNotEmpty
        ? (rawAvatarUrl.startsWith('/') ? '${Config.httpBase}$rawAvatarUrl' : rawAvatarUrl)
        : null;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    // Top 4 movie poster URLs for the favorites banner
    final serverBannerUrls = (_profile?['bannerUrls'] as List?)?.cast<String>() ?? [];
    final bannerPosters = serverBannerUrls.isNotEmpty
        ? serverBannerUrls
        : (List<Review>.from(reviews)
              ..sort((a, b) => b.stars.compareTo(a.stars)))
            .where((r) => r.moviePosterUrl != null && r.moviePosterUrl!.isNotEmpty)
            .take(4)
            .map((r) {
              final u = r.moviePosterUrl!;
              return u.startsWith('/') ? '${Config.httpBase}$u' : u;
            })
            .toList();

    final topPad = MediaQuery.of(context).padding.top;

    return AnimatedOpacity(
      opacity: _contentOpacity,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOut,
      child: Scaffold(
      backgroundColor: MC.bg0,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
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
                        top: topPad + 12, left: 16,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 34, height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: MC.bg0.withAlpha(200),
                            ),
                            child: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: MC.ink, size: 16),
                          ),
                        ),
                      ),

                      // Avatar 
                      Positioned(
                        top: 116, left: 20,
                        child: Container(
                          width: 88, height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: avatarColor,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: avatarUrl != null
                              ? AppImage(
                                  imageUrl: avatarUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _avatarInitial(initial),
                                )
                              : _avatarInitial(initial),
                        ),
                      ),

                      Positioned(
                        bottom: 6, right: 20,
                        child: Row(
                          children: [
                            _StatNum(n: watchedCount, label: 'Films'),
                            const SizedBox(width: 22),
                            _StatNum(n: _followerCount, label: 'Followers'),
                            const SizedBox(width: 22),
                            _StatNum(n: _followingCount, label: 'Following'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(displayName,
                                style: MT.display(size: 26, letterSpacing: -0.6)),
                          ),
                          if (username.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text('@$username',
                                style: MT.mono(
                                    size: 11, letterSpacing: 0.5, color: MC.accent1)),
                          ],
                        ],
                      ),
                      if (bio != null && bio.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(bio,
                            style: const TextStyle(
                                fontSize: 13.5,
                                color: MC.ink,
                                height: 1.5),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                      ],
                      if (location != null && location.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 12, color: MC.dim),
                            const SizedBox(width: 4),
                            Text(location.toUpperCase(),
                                style: MT.mono(
                                    size: 10, letterSpacing: 0.5, color: MC.dim)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),

                      if (!isMe)
                        Builder(builder: (ctx) {
                          final following =
                              context.watch<AppState>().isFollowing(widget.userId);
                          return Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    if (following) {
                                      context.read<AppState>().unfollowUser(widget.userId);
                                    } else {
                                      context.read<AppState>().followUser(widget.userId);
                                    }
                                  },
                                  child: Container(
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: following
                                          ? MC.kuvacultScore.withAlpha(30)
                                          : MC.kuvacultScore,
                                      borderRadius: BorderRadius.circular(12),
                                      border: following
                                          ? Border.all(
                                              color: MC.kuvacultScore, width: 1)
                                          : null,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      following ? 'Following' : 'Follow',
                                      style: TextStyle(
                                        color: following
                                            ? MC.kuvacultScore
                                            : MC.kuvacultScoreInk,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: MC.bg1,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TabBar(
                      controller: _tabCtrl,
                      indicator: BoxDecoration(
                        color: MC.bg2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelStyle: MT.mono(
                          size: 10,
                          letterSpacing: 1.5,
                          color: MC.ink,
                          weight: FontWeight.w600),
                      unselectedLabelStyle:
                          MT.mono(size: 10, letterSpacing: 1.5, color: MC.dim),
                      tabs: const [
                        Tab(text: 'REVIEWS'),
                        Tab(text: 'FILMS'),
                        Tab(text: 'LISTS'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _ReviewsTab(reviews: reviews, state: state),
            _FilmsTab(watchedMovies: watchedMovies),
            _WatchlistsTab(userId: widget.userId),
          ],
        ),
      ),
    ),
    );
  }

  Widget _avatarInitial(String initial) => Center(
        child: Text(initial,
            style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: MC.accentInk)),
      );

}


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


class _StatNum extends StatelessWidget {
  final int n;
  final String label;
  const _StatNum({required this.n, required this.label});

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


class _ReviewsTab extends StatefulWidget {
  final List<Review> reviews;
  final AppState state;
  const _ReviewsTab({required this.reviews, required this.state});
  @override
  State<_ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<_ReviewsTab> {
  static const _kPerPage = 5;
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
    final all = widget.reviews;
    if (all.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No public reviews yet.',
              style: TextStyle(color: MC.dim, fontSize: 13),
              textAlign: TextAlign.center),
        ),
      );
    }

    final filtered = _query.isEmpty
        ? all
        : all.where((r) => r.movieTitle.toLowerCase().contains(_query.toLowerCase())).toList();
    final pageCount = filtered.isEmpty ? 1 : (filtered.length / _kPerPage).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final visible = filtered.skip(page * _kPerPage).take(_kPerPage).toList();
    final paginate = filtered.length > _kPerPage;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        _SearchField(ctrl: _ctrl, hint: 'Search reviews…', onChanged: (v) => setState(() { _query = v; _page = 0; })),
        const SizedBox(height: 10),
        ...visible.map((r) => _ProfileReviewCard(review: r, onLike: () => widget.state.likeReview(r.id))),
        if (paginate) ...[
          const SizedBox(height: 4),
          _PaginationRow(
            page: page,
            pageCount: pageCount,
            onPrev: page > 0 ? () => setState(() => _page = page - 1) : null,
            onNext: page < pageCount - 1 ? () => setState(() => _page = page + 1) : null,
          ),
        ],
      ],
    );
  }
}


class _ProfileReviewCard extends StatelessWidget {
  final Review review;
  final VoidCallback onLike;

  const _ProfileReviewCard({required this.review, required this.onLike});

  @override
  Widget build(BuildContext context) {
    final posterUrl = review.moviePosterUrl != null &&
            review.moviePosterUrl!.isNotEmpty
        ? (review.moviePosterUrl!.startsWith('/')
            ? '${Config.httpBase}${review.moviePosterUrl}'
            : review.moviePosterUrl!)
        : null;

    final rawPosterUrl = review.moviePosterUrl;
    final resolvedPosterForNav = rawPosterUrl != null && rawPosterUrl.isNotEmpty
        ? (rawPosterUrl.startsWith('/') ? '${Config.httpBase}$rawPosterUrl' : rawPosterUrl)
        : null;

    return GestureDetector(
      onTap: () {
        final m = Movie(
          id: review.movieId,
          title: review.movieTitle,
          year: review.movieYear,
          runtime: 0,
          rating: 0,
          genres: [],
          director: review.movieDirector,
          streamId: '',
          addedBy: '',
          section: WatchSection.want,
          synopsis: '',
          poster: resolvedPosterForNav != null
              ? PosterData(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1C1C2E), Color(0xFF2D2D44)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  accent: const Color(0xFFF6C453),
                  imageUrl: resolvedPosterForNav,
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
            context, MaterialPageRoute(builder: (_) => DetailScreen(
                movie: m, scrollToReviewId: review.id)));
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
                ? AppImage(
                    imageUrl: posterUrl,
                    width: 40,
                    height: 60,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _placeholder())
                : _placeholder(),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(review.movieTitle,
                    style: MT.display(size: 14, letterSpacing: -0.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${review.movieYear}'
                  '${review.movieDirector.isNotEmpty ? "  ·  ${review.movieDirector}" : ""}',
                  style: MT.mono(size: 10, letterSpacing: 0, color: MC.dim),
                ),
                const SizedBox(height: 6),
                _StarRow(stars: review.stars),
                if (review.rewatch) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.replay_rounded,
                        size: 10,
                        color: MC.kuvacultScore.withAlpha(180)),
                    const SizedBox(width: 3),
                    Text('Rewatch',
                        style: MT.mono(
                            size: 9,
                            letterSpacing: 0,
                            color: MC.kuvacultScore)),
                  ]),
                ],
                if (review.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ExpandableReviewText(
                      text: review.text,
                      style: const TextStyle(
                          fontSize: 13, color: MC.ink, height: 1.45)),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    GestureDetector(
                      onTap: onLike,
                      child: Row(children: [
                        Icon(
                          review.likedByMe
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 13,
                          color: review.likedByMe
                              ? const Color(0xFFE05A7A)
                              : MC.dim,
                        ),
                        const SizedBox(width: 3),
                        Text('${review.likes}',
                            style: MT.mono(
                                size: 9,
                                letterSpacing: 0,
                                color: review.likedByMe
                                    ? const Color(0xFFE05A7A)
                                    : MC.dim)),
                      ]),
                    ),
                    if (context.watch<AppState>().isWatched(review.movieId)) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.remove_red_eye_rounded, size: 12, color: MC.mute),
                    ],
                    const Spacer(),
                    Text(_timeAgo(review.at),
                        style: MT.mono(size: 9, letterSpacing: 0, color: MC.dim)),
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

  Widget _placeholder() => Container(
        width: 40,
        height: 60,
        decoration: BoxDecoration(
          color: MC.bg2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.movie_outlined, color: MC.dim, size: 16),
      );
}


class _FilmsTab extends StatefulWidget {
  final List<WatchedMovie> watchedMovies;
  const _FilmsTab({required this.watchedMovies});
  @override
  State<_FilmsTab> createState() => _FilmsTabState();
}

class _FilmsTabState extends State<_FilmsTab> {
  static const _kPageSize = 18;
  static const _kPaginateAfter = 20;
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
    final all = widget.watchedMovies;
    if (all.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No watched films yet.',
              style: TextStyle(color: MC.dim, fontSize: 13),
              textAlign: TextAlign.center),
        ),
      );
    }

    final filtered = _query.isEmpty
        ? all
        : all.where((m) => m.title.toLowerCase().contains(_query.toLowerCase())).toList();

    final paginate = filtered.length > _kPaginateAfter;
    final pageCount = paginate ? (filtered.length / _kPageSize).ceil() : 1;
    final page = _page.clamp(0, pageCount - 1);
    final pageItems = paginate
        ? filtered.skip(page * _kPageSize).take(_kPageSize).toList()
        : filtered;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        _SearchField(
          ctrl: _ctrl,
          hint: 'Search films…',
          onChanged: (v) => setState(() { _query = v; _page = 0; }),
        ),
        const SizedBox(height: 4),
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
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: (MediaQuery.of(context).size.width / 180).floor().clamp(3, 8),
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 2 / 3,
            ),
            itemCount: pageItems.length,
            itemBuilder: (ctx, i) {
              final m = pageItems[i];
              final rawUrl = m.posterUrl;
              final url = rawUrl != null && rawUrl.isNotEmpty
                  ? (rawUrl.startsWith('/') ? '${Config.httpBase}$rawUrl' : rawUrl)
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
                          errorWidget: (_, __, ___) => _posterPlaceholder(m))
                      : _posterPlaceholder(m),
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
      ],
    );
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

  Widget _posterPlaceholder(WatchedMovie m) => Container(
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



class _WatchlistsTab extends StatefulWidget {
  final String userId;
  const _WatchlistsTab({required this.userId});

  @override
  State<_WatchlistsTab> createState() => _WatchlistsTabState();
}

class _WatchlistsTabState extends State<_WatchlistsTab> {
  static const _kPageSize = 10;
  static const _kSearchAfter = 8;

  List<Map<String, dynamic>> _watchlists = [];
  bool _loading = true;
  String _query = '';
  int _page = 0;
  final _ctrl = TextEditingController();

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
    final state = context.watch<AppState>();
    final currentUserId = state.currentUser?.id;

    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(color: MC.accent1, strokeWidth: 2),
        ),
      );
    }

    if (_watchlists.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
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

    final paginate = filtered.length > _kPageSize;
    final pageCount = paginate ? (filtered.length / _kPageSize).ceil() : 1;
    final page = _page.clamp(0, pageCount - 1);
    final pageItems = paginate
        ? filtered.skip(page * _kPageSize).take(_kPageSize).toList()
        : filtered;

    return CustomScrollView(
      slivers: [
        if (_watchlists.length > _kSearchAfter)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: _SearchField(
                ctrl: _ctrl,
                hint: 'Search watchlists…',
                onChanged: (v) => setState(() { _query = v; _page = 0; }),
              ),
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (filtered.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No results.',
                    style: TextStyle(color: MC.dim, fontSize: 13)),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.68,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final wl = pageItems[i];
                  final watchlistId = wl['id'] as String? ?? '';
                  final name = wl['name'] as String? ?? '';
                  final movies = wl['movies'] as List? ?? [];
                  final movieCount = movies.length;
                  final likes = (wl['likes'] as num?)?.toInt() ?? 0;
                  final likedBy = (wl['likedBy'] as List? ?? []).cast<String>();
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
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(13)),
                              child: _buildProfileWatchlistMosaic(posterUrls),
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
                                      '$movieCount ${movieCount == 1 ? 'film' : 'films'}',
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
                                                  size: 9,
                                                  letterSpacing: 0,
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
                childCount: pageItems.length,
              ),
            ),
          ),
        if (paginate)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              child: _PaginationRow(
                page: page,
                pageCount: pageCount,
                onPrev: page > 0 ? () => setState(() => _page = page - 1) : null,
                onNext: page < pageCount - 1
                    ? () => setState(() => _page = page + 1)
                    : null,
              ),
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildProfileWatchlistMosaic(List<String> posterUrls) {
    Widget img(String url) => SizedBox.expand(
      child: AppImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(color: MC.bg2),
      ),
    );

    if (posterUrls.isEmpty) {
      return Container(
        color: MC.bg2,
        child: const Center(
          child: Icon(Icons.movie_outlined, color: MC.dim, size: 32),
        ),
      );
    }
    if (posterUrls.length == 1) return img(posterUrls[0]);
    if (posterUrls.length < 4) {
      return Row(children: [
        Expanded(child: img(posterUrls[0])),
        const SizedBox(width: 1),
        Expanded(child: img(posterUrls[1])),
      ]);
    }
    return Column(children: [
      Expanded(child: Row(children: [
        Expanded(child: img(posterUrls[0])),
        const SizedBox(width: 1),
        Expanded(child: img(posterUrls[1])),
      ])),
      const SizedBox(height: 1),
      Expanded(child: Row(children: [
        Expanded(child: img(posterUrls[2])),
        const SizedBox(width: 1),
        Expanded(child: img(posterUrls[3])),
      ])),
    ]);
  }
}


class _SearchField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.ctrl, required this.hint, required this.onChanged});

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
}


class _ExpandButton extends StatelessWidget {
  final bool expanded;
  final String expandLabel;
  final VoidCallback onTap;
  const _ExpandButton({required this.expanded, required this.expandLabel, required this.onTap});

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
              style: const TextStyle(color: MC.accent1, fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 4),
            Icon(
              expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              color: MC.accent1,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}


class _PaginationRow extends StatelessWidget {
  final int page;
  final int pageCount;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _PaginationRow({required this.page, required this.pageCount, this.onPrev, this.onNext});

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


class _StarRow extends StatelessWidget {
  final double stars;
  const _StarRow({required this.stars});

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


class PublicWatchlistScreen extends StatefulWidget {
  final String watchlistId;
  final String name;
  final int initialLikes;

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
  bool _loading = true;
  String? _error;
  List<Movie> _movies = [];
  List<Map<String, dynamic>> _members = [];
  int _likes = 0;
  String _search = '';
  int _page = 0;
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
      final data = await ApiService.fetchWatchlistById(widget.watchlistId);
      final rawMovies = (data['movies'] as List? ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _movies = rawMovies.map(_parseMovie).where((m) => m.id.isNotEmpty).toList();
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
    final state = context.watch<AppState>();
    final isLiked = widget.watchlistId.isNotEmpty &&
        state.isCommunityWatchlistLiked(widget.watchlistId);
    // Prefer live community cache for like count; fall back to own watchlist or initial value
    final communityCache = state.communityTopWatchlists
        .where((w) => w['id'] == widget.watchlistId)
        .firstOrNull;
    final likes = (communityCache?['likes'] as int?) ??
        state.watchlists.where((w) => w.id == widget.watchlistId).firstOrNull?.likes ??
        _likes;

    final filtered = _search.isEmpty
        ? _movies
        : _movies.where((m) => m.title.toLowerCase().contains(_search.toLowerCase())).toList();
    final pageCount = filtered.isEmpty ? 0 : (filtered.length / _kPageSize).ceil();
    final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final pageMovies = filtered.skip(page * _kPageSize).take(_kPageSize).toList();
    final topPad = MediaQuery.of(context).padding.top;
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
                      decoration: BoxDecoration(shape: BoxShape.circle, color: MC.bg1.withAlpha(220)),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: MC.ink, size: 16),
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
                  child: Text(_error!, style: const TextStyle(color: MC.dim, fontSize: 13)),
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
                            final avatarUrl = m['avatarUrl'] as String?;
                            final userId = m['id'] as String? ?? '';
                            final resolved = avatarUrl != null && avatarUrl.isNotEmpty
                                ? (avatarUrl.startsWith('/') ? '${Config.httpBase}$avatarUrl' : avatarUrl)
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
                                              errorWidget: (_, __, ___) => _avatarFallback(displayName))
                                          : _avatarFallback(displayName),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      displayName.isNotEmpty ? displayName.split(' ').first : '?',
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
                    prefixIcon: const Icon(Icons.search_rounded, color: MC.dim, size: 18),
                    suffixIcon: _search.isNotEmpty
                        ? GestureDetector(
                            onTap: () { setState(() { _search = ''; _page = 0; }); _searchCtrl.clear(); },
                            child: const Icon(Icons.close_rounded, color: MC.dim, size: 16),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      _search.isNotEmpty ? 'No movies match your search' : 'No movies in this list yet',
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
                      final m = pageMovies[i];
                      final rawUrl = m.poster.imageUrl;
                      final url = rawUrl != null && rawUrl.isNotEmpty
                          ? (rawUrl.startsWith('/') ? '${Config.httpBase}$rawUrl' : rawUrl)
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
                                        errorWidget: (_, __, ___) => _posterPlaceholder(m))
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
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: page > 0 ? MC.bg1 : MC.bg0,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: MC.line, width: 0.5),
                          ),
                          child: Text('← Prev',
                              style: TextStyle(color: page > 0 ? MC.ink : MC.dim, fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('${page + 1} / $pageCount',
                          style: MT.mono(size: 11, letterSpacing: 0.5, color: MC.mute)),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: page < pageCount - 1 ? () => setState(() => _page = page + 1) : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: page < pageCount - 1 ? MC.bg1 : MC.bg0,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: MC.line, width: 0.5),
                          ),
                          child: Text('Next →',
                              style: TextStyle(
                                  color: page < pageCount - 1 ? MC.ink : MC.dim, fontSize: 12)),
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
            style: const TextStyle(color: MC.ink, fontSize: 16, fontWeight: FontWeight.w600)),
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
