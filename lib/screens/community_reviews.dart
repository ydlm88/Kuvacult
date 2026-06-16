import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models.dart';
import '../app_state.dart';
import 'detail.dart';
import 'user_profile.dart';
import 'activity.dart';

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}

class CommunityReviewsScreen extends StatefulWidget {
  const CommunityReviewsScreen({super.key});

  @override
  State<CommunityReviewsScreen> createState() => _CommunityReviewsScreenState();
}

class _CommunityReviewsScreenState extends State<CommunityReviewsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadPublicReviews();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final reviews = state.publicReviews;
    final loading = state.reviewsLoading;

    // Popular reviews this week sorted by likes
    final popularReviews = List<Review>.from(state.reviewsThisWeek)
      ..sort((a, b) => b.likes.compareTo(a.likes));
    final topWeekReviews = popularReviews.take(10).toList();

    // Top watchlists by likes
    final topWatchlists = List<Watchlist>.from(state.watchlists)
      ..sort((a, b) => b.likes.compareTo(a.likes));
    final topTenWatchlists = topWatchlists.take(10).toList();

    // Top reviewers
    final topReviewers = state.topReviewers();

    // Trending movies
    final trendingMovies = state.trendingMovies;

    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 62, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MARQUEE COMMUNITY',
                          style: MT.mono(
                              size: 10,
                              letterSpacing: 2,
                              color: MC.marqueeScore)),
                      const SizedBox(height: 4),
                      Text('Reviews', style: MT.display(size: 34)),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const _ActivityDrawer(),
                    ),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: MC.bg1,
                        border: Border.all(color: MC.line, width: 0.5),
                      ),
                      child: const Icon(Icons.notifications_outlined,
                          color: MC.mute, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Popular Movies carousel ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Row(
                    children: [
                      Text('POPULAR MOVIES',
                          style: MT.mono(size: 10, letterSpacing: 2)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const _ExploreListScreen(type: 'movies')),
                        ),
                        child: Text('See all',
                            style: MT.mono(
                                size: 10,
                                color: MC.accent1,
                                letterSpacing: 1)),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 200,
                  child: trendingMovies.isEmpty
                      ? Center(
                          child: state.trendingLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: MC.marqueeScore, strokeWidth: 2))
                              : Text('No movies',
                                  style:
                                      TextStyle(color: MC.dim, fontSize: 12)),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: trendingMovies.length,
                          itemBuilder: (ctx, i) {
                            final m = trendingMovies[i];
                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => DetailScreen(movie: m)),
                              ),
                              child: Container(
                                width: 110,
                                margin: const EdgeInsets.only(right: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: m.poster.imageUrl != null
                                          ? Image.network(
                                              m.poster.imageUrl!,
                                              width: 110,
                                              height: 155,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  _moviePlaceholder(),
                                            )
                                          : _moviePlaceholder(),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      m.title,
                                      style: const TextStyle(
                                          color: MC.ink,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // ── Popular Reviews carousel ────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    children: [
                      Text('POPULAR THIS WEEK',
                          style: MT.mono(size: 10, letterSpacing: 2)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const _ExploreListScreen(type: 'reviews')),
                        ),
                        child: Text('See all',
                            style: MT.mono(
                                size: 10,
                                color: MC.accent1,
                                letterSpacing: 1)),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 180,
                  child: topWeekReviews.isEmpty
                      ? Center(
                          child: Text('No reviews this week',
                              style: TextStyle(color: MC.dim, fontSize: 12)),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: topWeekReviews.length,
                          itemBuilder: (ctx, i) {
                            final r = topWeekReviews[i];
                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => UserProfileScreen(
                                        userId: r.byId,
                                        initialName: r.byName)),
                              ),
                              child: Container(
                                width: 220,
                                margin: const EdgeInsets.only(right: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: MC.bg1,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: MC.line, width: 0.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        _AvatarWidget(
                                            avatarUrl: r.byAvatarUrl,
                                            avatarColor: r.byAvatarColor,
                                            name: r.byName,
                                            size: 28),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            r.byName,
                                            style: const TextStyle(
                                                color: MC.ink,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      r.movieTitle,
                                      style: MT.display(
                                          size: 13, letterSpacing: -0.2),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    _StarRow(stars: r.stars),
                                    const SizedBox(height: 6),
                                    if (r.text.isNotEmpty)
                                      Expanded(
                                        child: Text(
                                          r.text,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: MC.mute,
                                              height: 1.4),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // ── Top Watchlists carousel ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    children: [
                      Text('TOP WATCHLISTS',
                          style: MT.mono(size: 10, letterSpacing: 2)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const _ExploreListScreen(type: 'watchlists')),
                        ),
                        child: Text('See all',
                            style: MT.mono(
                                size: 10,
                                color: MC.accent1,
                                letterSpacing: 1)),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 100,
                  child: topTenWatchlists.isEmpty
                      ? Center(
                          child: Text('No watchlists',
                              style: TextStyle(color: MC.dim, fontSize: 12)),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: topTenWatchlists.length,
                          itemBuilder: (ctx, i) {
                            final wl = topTenWatchlists[i];
                            return Container(
                              width: 160,
                              margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: MC.bg1,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: MC.line, width: 0.5),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    wl.name,
                                    style: const TextStyle(
                                        color: MC.ink,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '${wl.movies.length} movies',
                                        style: MT.mono(
                                            size: 9,
                                            letterSpacing: 0,
                                            color: MC.dim),
                                      ),
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: () =>
                                            state.likeWatchlist(wl.id),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              wl.likedByMe
                                                  ? Icons.favorite_rounded
                                                  : Icons.favorite_border_rounded,
                                              size: 14,
                                              color: wl.likedByMe
                                                  ? const Color(0xFFE05A7A)
                                                  : MC.dim,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              '${wl.likes}',
                                              style: MT.mono(
                                                  size: 9,
                                                  letterSpacing: 0,
                                                  color: wl.likedByMe
                                                      ? const Color(0xFFE05A7A)
                                                      : MC.dim),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // ── Top Reviewers carousel ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    children: [
                      Text('TOP REVIEWERS',
                          style: MT.mono(size: 10, letterSpacing: 2)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const _ExploreListScreen(type: 'reviewers')),
                        ),
                        child: Text('See all',
                            style: MT.mono(
                                size: 10,
                                color: MC.accent1,
                                letterSpacing: 1)),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 100,
                  child: topReviewers.isEmpty
                      ? Center(
                          child: Text('No reviewers yet',
                              style: TextStyle(color: MC.dim, fontSize: 12)),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: topReviewers.length,
                          itemBuilder: (ctx, i) {
                            final r = topReviewers[i];
                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => UserProfileScreen(
                                        userId: r['userId'] as String,
                                        initialName: r['name'] as String? ?? '')),
                              ),
                              child: SizedBox(
                                width: 80,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _AvatarWidget(
                                      avatarUrl: r['avatarUrl'] as String?,
                                      avatarColor:
                                          r['avatarColor'] as Color? ??
                                              MC.accent1,
                                      name: r['name'] as String? ?? '',
                                      size: 44,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      (r['name'] as String? ?? '').isNotEmpty
                                          ? (r['name'] as String)
                                          : (r['handle'] as String? ?? ''),
                                      style: const TextStyle(
                                          color: MC.ink,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                    Text(
                                      '${r['reviewCount']} reviews',
                                      style: MT.mono(
                                          size: 9,
                                          letterSpacing: 0,
                                          color: MC.dim),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // ── All Reviews header ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Text('ALL REVIEWS',
                  style: MT.mono(size: 10, letterSpacing: 2)),
            ),
          ),

          // ── Reviews feed ────────────────────────────────────────────────────
          if (loading && reviews.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: MC.marqueeScore, strokeWidth: 2),
                  ),
                ),
              ),
            )
          else if (reviews.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: MC.marqueeScore.withAlpha(20),
                        border: Border.all(
                            color: MC.marqueeScore.withAlpha(60), width: 1),
                      ),
                      child: const Icon(Icons.rate_review_outlined,
                          color: MC.marqueeScore, size: 26),
                    ),
                    const SizedBox(height: 16),
                    Text('No reviews yet', style: MT.display(size: 20)),
                    const SizedBox(height: 10),
                    const Text(
                      'Be the first to write a public review.\nOpen any movie and tap the review button.',
                      style:
                          TextStyle(color: MC.mute, fontSize: 13, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _ReviewCard(
                    review: reviews[i],
                    onLike: () => state.likeReview(reviews[i].id),
                    onUserTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => UserProfileScreen(
                                  userId: reviews[i].byId,
                                  initialName: reviews[i].byName,
                                ))),
                  ),
                  childCount: reviews.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

// ─── Activity Drawer ──────────────────────────────────────────────────────────

class _ActivityDrawer extends StatelessWidget {
  const _ActivityDrawer();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final activity = state.activity;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text('FRIEND ACTIVITY',
                    style: MT.mono(size: 10, letterSpacing: 2)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded,
                      color: MC.dim, size: 20),
                ),
              ],
            ),
          ),
          Divider(color: MC.line, thickness: 0.5, height: 1),
          if (activity.isEmpty)
            Expanded(
              child: Center(
                child: Text('No activity yet',
                    style: TextStyle(color: MC.dim, fontSize: 13)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                itemCount: activity.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (ctx, i) => ActivityItem(
                  event: activity[i],
                  isLast: i == activity.length - 1,
                  onMovieTap: (_) {},
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Explore List Screen ──────────────────────────────────────────────────────

class _ExploreListScreen extends StatefulWidget {
  final String type; // 'movies' | 'reviews' | 'watchlists' | 'reviewers'
  const _ExploreListScreen({required this.type});

  @override
  State<_ExploreListScreen> createState() => _ExploreListScreenState();
}

class _ExploreListScreenState extends State<_ExploreListScreen> {
  String _period = 'This Week';
  static const _periods = ['This Week', 'This Month', 'This Year', 'All Time'];

  String get _title {
    switch (widget.type) {
      case 'movies':
        return 'Popular Movies';
      case 'reviews':
        return 'Popular Reviews';
      case 'watchlists':
        return 'Top Watchlists';
      case 'reviewers':
        return 'Top Reviewers';
      default:
        return 'Explore';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 62, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: MC.ink, size: 18),
                  ),
                  const SizedBox(width: 16),
                  Text(_title, style: MT.display(size: 26)),
                ],
              ),
            ),
          ),

          // Period filter pills (not shown for movies or reviewers)
          if (widget.type == 'reviews' || widget.type == 'watchlists')
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: _periods.map((p) {
                    final isActive = _period == p;
                    return GestureDetector(
                      onTap: () => setState(() => _period = p),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive ? MC.accent1 : MC.bg1,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: isActive ? MC.accent1 : MC.line,
                              width: 0.5),
                        ),
                        child: Text(
                          p,
                          style: TextStyle(
                            color: isActive ? MC.accentInk : MC.mute,
                            fontSize: 12,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          // Content
          if (widget.type == 'movies') ..._buildMoviesList(state),
          if (widget.type == 'reviews') ..._buildReviewsList(state),
          if (widget.type == 'watchlists') ..._buildWatchlistsList(state),
          if (widget.type == 'reviewers') ..._buildReviewersList(state),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  List<Widget> _buildMoviesList(AppState state) {
    final movies = List.of(state.trendingMovies)
      ..sort((a, b) => b.rating.compareTo(a.rating));
    if (movies.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text('No movies found',
                  style: TextStyle(color: MC.dim, fontSize: 13)),
            ),
          ),
        )
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 110 / 175,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final m = movies[i];
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
                        child: m.poster.imageUrl != null
                            ? Image.network(
                                m.poster.imageUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) =>
                                    _moviePlaceholder(),
                              )
                            : _moviePlaceholder(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.title,
                      style: const TextStyle(color: MC.ink, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
            childCount: movies.length,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildReviewsList(AppState state) {
    final reviews = state.reviewsForPeriod(_period)
      ..sort((a, b) => b.likes.compareTo(a.likes));
    if (reviews.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text('No reviews for this period',
                  style: TextStyle(color: MC.dim, fontSize: 13)),
            ),
          ),
        )
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _ReviewCard(
              review: reviews[i],
              onLike: () => state.likeReview(reviews[i].id),
              onUserTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => UserProfileScreen(
                          userId: reviews[i].byId,
                          initialName: reviews[i].byName,
                        )),
              ),
            ),
            childCount: reviews.length,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildWatchlistsList(AppState state) {
    final watchlists = List.of(state.watchlists)
      ..sort((a, b) => b.likes.compareTo(a.likes));
    if (watchlists.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text('No watchlists yet',
                  style: TextStyle(color: MC.dim, fontSize: 13)),
            ),
          ),
        )
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                  size: 10, letterSpacing: 0, color: MC.dim)),
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
    ];
  }

  List<Widget> _buildReviewersList(AppState state) {
    final reviewers = state.topReviewers();
    if (reviewers.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text('No reviewers yet',
                  style: TextStyle(color: MC.dim, fontSize: 13)),
            ),
          ),
        )
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final r = reviewers[i];
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => UserProfileScreen(
                            userId: r['userId'] as String,
                            initialName: r['name'] as String? ?? '',
                          )),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MC.bg1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  child: Row(
                    children: [
                      _AvatarWidget(
                        avatarUrl: r['avatarUrl'] as String?,
                        avatarColor:
                            r['avatarColor'] as Color? ?? MC.accent1,
                        name: r['name'] as String? ?? '',
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['name'] as String? ?? '',
                                style: const TextStyle(
                                    color: MC.ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            Text('@${r['handle'] ?? ''}',
                                style: MT.mono(
                                    size: 10,
                                    letterSpacing: 0.5,
                                    color: MC.dim)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${r['reviewCount']}',
                              style: TextStyle(
                                  color: MC.marqueeScore,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          Text('reviews',
                              style: MT.mono(
                                  size: 9, letterSpacing: 0, color: MC.dim)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
            childCount: reviewers.length,
          ),
        ),
      ),
    ];
  }
}

// ─── Review Card ──────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final Review review;
  final VoidCallback onLike;
  final VoidCallback onUserTap;

  const _ReviewCard({
    required this.review,
    required this.onLike,
    required this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MC.line, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onUserTap,
                  child: _AvatarWidget(
                    avatarUrl: review.byAvatarUrl,
                    avatarColor: review.byAvatarColor,
                    name: review.byName,
                    size: 34,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: onUserTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          review.byName,
                          style: const TextStyle(
                            color: MC.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          '@${review.byHandle}',
                          style: MT.mono(
                              size: 10,
                              letterSpacing: 0.5,
                              color: MC.dim),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(_timeAgo(review.at),
                    style: MT.mono(
                        size: 10, letterSpacing: 0, color: MC.dim)),
              ],
            ),
          ),

          // Movie row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: review.moviePosterUrl != null
                      ? Image.network(
                          review.moviePosterUrl!,
                          width: 44,
                          height: 66,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _posterPlaceholder(),
                        )
                      : _posterPlaceholder(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.movieTitle,
                        style: MT.display(size: 15, letterSpacing: -0.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${review.movieYear}${review.movieDirector.isNotEmpty ? '  ·  ${review.movieDirector}' : ''}',
                        style: MT.mono(
                            size: 10, letterSpacing: 0, color: MC.mute),
                      ),
                      const SizedBox(height: 6),
                      _StarRow(stars: review.stars),
                      if (review.rewatch)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.replay_rounded,
                                  size: 11,
                                  color: MC.marqueeScore.withAlpha(200)),
                              const SizedBox(width: 3),
                              Text('Rewatch',
                                  style: MT.mono(
                                      size: 9,
                                      letterSpacing: 0,
                                      color: MC.marqueeScore)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Review text
          if (review.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                review.text,
                style:
                    const TextStyle(fontSize: 13, color: MC.ink, height: 1.5),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // Actions row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onLike,
                  child: Row(
                    children: [
                      Icon(
                        review.likedByMe
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 16,
                        color: review.likedByMe
                            ? const Color(0xFFE05A7A)
                            : MC.dim,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${review.likes}',
                        style: MT.mono(
                            size: 10,
                            letterSpacing: 0,
                            color: review.likedByMe
                                ? const Color(0xFFE05A7A)
                                : MC.dim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Row(
                  children: [
                    const Icon(Icons.mode_comment_outlined,
                        size: 14, color: MC.dim),
                    const SizedBox(width: 4),
                    Text(
                      '${review.commentCount}',
                      style:
                          MT.mono(size: 10, letterSpacing: 0, color: MC.dim),
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

  Widget _posterPlaceholder() => Container(
        width: 44,
        height: 66,
        decoration: BoxDecoration(
          color: MC.bg2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.movie_outlined, color: MC.dim, size: 18),
      );
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _AvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final Color avatarColor;
  final String name;
  final double size;

  const _AvatarWidget({
    required this.avatarUrl,
    required this.avatarColor,
    required this.name,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initials(initial),
        ),
      );
    }
    return _initials(initial);
  }

  Widget _initials(String initial) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: avatarColor,
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: TextStyle(
              fontSize: size * 0.4,
              fontWeight: FontWeight.w700,
              color: MC.accentInk),
        ),
      );
}

class _StarRow extends StatelessWidget {
  final double stars;
  const _StarRow({required this.stars});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) {
        final filled = (i + 1) <= stars;
        final half = !filled && (i + 0.5) <= stars;
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(
            half
                ? Icons.star_half_rounded
                : filled
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
            size: 14,
            color: MC.marqueeScore,
          ),
        );
      }),
    );
  }
}

Widget _moviePlaceholder() => Container(
      width: 110,
      height: 155,
      decoration: BoxDecoration(
        color: MC.bg2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.movie_outlined, color: MC.dim, size: 24),
    );

// ─── Write review bottom sheet ────────────────────────────────────────────────

Future<void> showWriteReviewSheet(
  BuildContext context, {
  required String movieId,
  required String movieTitle,
  required int movieYear,
  String movieDirector = '',
  String? moviePosterUrl,
}) async {
  final state = context.read<AppState>();
  if (state.isGuest || !state.isLoggedIn) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Sign in to write reviews',
          style: TextStyle(color: MC.ink)),
      backgroundColor: MC.bg1,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
    return;
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: MC.bg1,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _WriteReviewSheet(
      movieId: movieId,
      movieTitle: movieTitle,
      movieYear: movieYear,
      movieDirector: movieDirector,
      moviePosterUrl: moviePosterUrl,
    ),
  );
}

class _WriteReviewSheet extends StatefulWidget {
  final String movieId;
  final String movieTitle;
  final int movieYear;
  final String movieDirector;
  final String? moviePosterUrl;

  const _WriteReviewSheet({
    required this.movieId,
    required this.movieTitle,
    required this.movieYear,
    required this.movieDirector,
    this.moviePosterUrl,
  });

  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  double _stars = 0;
  bool _rewatch = false;
  bool _submitting = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: MC.dim, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Write a review', style: MT.display(size: 20)),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.movieTitle}  ·  ${widget.movieYear}',
                      style:
                          MT.mono(size: 11, letterSpacing: 0.5, color: MC.mute),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Star picker with half-star support
          Text('YOUR RATING', style: MT.mono(size: 9, letterSpacing: 2)),
          const SizedBox(height: 10),
          GestureDetector(
            onTapDown: (details) {
              const starWidth = 36.0;
              const gap = 6.0;
              final pos = details.localPosition.dx;
              final slotWidth = starWidth + gap;
              final starIdx = (pos / slotWidth).floor().clamp(0, 4);
              final frac = (pos - starIdx * slotWidth) / starWidth;
              final newStars =
                  (starIdx + (frac < 0.5 ? 0.5 : 1.0)).clamp(0.5, 5.0);
              setState(() => _stars = newStars);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(
                  5,
                  (i) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      _stars >= (i + 1)
                          ? Icons.star_rounded
                          : _stars > i
                              ? Icons.star_half_rounded
                              : Icons.star_border_rounded,
                      size: 36,
                      color: MC.marqueeScore,
                    ),
                  ),
                ),
                if (_stars > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${_stars % 1 == 0 ? _stars.toInt() : _stars} / 5',
                    style: MT.mono(
                        size: 14, color: MC.marqueeScore, letterSpacing: 1),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Rewatch toggle
          GestureDetector(
            onTap: () => setState(() => _rewatch = !_rewatch),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: _rewatch ? MC.marqueeScore : MC.dim,
                        width: 1.5),
                    color: _rewatch
                        ? MC.marqueeScore.withAlpha(30)
                        : Colors.transparent,
                  ),
                  child: _rewatch
                      ? const Icon(Icons.check_rounded,
                          size: 12, color: MC.marqueeScore)
                      : null,
                ),
                const SizedBox(width: 8),
                Text('Rewatch',
                    style: TextStyle(
                        fontSize: 13,
                        color: _rewatch ? MC.marqueeScore : MC.mute)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Review text field
          TextField(
            controller: _ctrl,
            maxLines: 4,
            style: const TextStyle(color: MC.ink, fontSize: 14),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Share your thoughts…',
              hintStyle: const TextStyle(color: MC.dim),
              filled: true,
              fillColor: MC.bg2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: MC.marqueeScore, width: 1),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Submit button
          GestureDetector(
            onTap: (_stars == 0 ||
                    _ctrl.text.trim().isEmpty ||
                    _submitting)
                ? null
                : () async {
                    setState(() => _submitting = true);
                    await context.read<AppState>().submitReview(
                          movieId: widget.movieId,
                          movieTitle: widget.movieTitle,
                          movieYear: widget.movieYear,
                          movieDirector: widget.movieDirector,
                          moviePosterUrl: widget.moviePosterUrl,
                          stars: _stars,
                          text: _ctrl.text.trim(),
                          rewatch: _rewatch,
                        );
                    if (context.mounted) Navigator.pop(context);
                  },
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                gradient: (_stars > 0 && _ctrl.text.trim().isNotEmpty)
                    ? const LinearGradient(
                        colors: [MC.marqueeScore, Color(0xFF3AB8BF)])
                    : null,
                color: (_stars > 0 && _ctrl.text.trim().isNotEmpty)
                    ? null
                    : MC.bg2,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: MC.marqueeScoreInk, strokeWidth: 2))
                  : Text(
                      'Post review',
                      style: TextStyle(
                        color: (_stars > 0 && _ctrl.text.trim().isNotEmpty)
                            ? MC.marqueeScoreInk
                            : MC.dim,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
