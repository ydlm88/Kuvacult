// community_reviews.dart — Community hub screen showing trending movies, popular reviews, top watchlists, and top reviewers, with explore drill-downs and an activity/notification drawer.
import 'package:flutter/gestures.dart';
import '../widgets/app_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models.dart';
import '../app_state.dart';
import '../config.dart';
import '../widgets/review_text.dart';
import '../services/api_service.dart';
import 'detail.dart';
import 'user_profile.dart';
import 'activity.dart';
import '../utils/top_toast.dart';

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
  static const _kPageSize = 15;
  String _reviewSearch = '';
  final _reviewSearchCtrl = TextEditingController();
  int _reviewPage = 0;
  final _popularMoviesScroll = ScrollController();
  final _popularReviewsScroll = ScrollController();
  final _topWatchlistsScroll = ScrollController();
  final _topReviewersScroll = ScrollController();

  @override
  void dispose() {
    _reviewSearchCtrl.dispose();
    _popularMoviesScroll.dispose();
    _popularReviewsScroll.dispose();
    _topWatchlistsScroll.dispose();
    _topReviewersScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      state.loadPublicReviews();
      state.loadCommunityTopWatchlists().then((_) {
        if (!mounted) return;
        // Pre-fetch poster URLs for all watchlists so the "see all" grid
        // has them ready before the user navigates there.
        for (final wl in context.read<AppState>().communityTopWatchlists) {
          final id = wl['id'] as String?;
          if (id != null && id.isNotEmpty) _fetchCommunityPosters(id);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final reviews = state.publicReviews;
    final loading = state.reviewsLoading;

    final topMonthReviews = state.popularReviewsThisMonth;

    // Top watchlists from community API (all watchlists, sorted by likes)
    final topTenWatchlists = state.communityTopWatchlists;

    final topReviewers = state.topReviewers();

    final trendingMovies = state.trendingMovies;

    final filteredReviews = _reviewSearch.isEmpty
        ? reviews
        : reviews
            .where((r) => r.movieTitle
                .toLowerCase()
                .contains(_reviewSearch.toLowerCase()))
            .toList();
    final reviewPageCount =
        filteredReviews.isEmpty ? 0 : (filteredReviews.length / _kPageSize).ceil();
    final currentReviewPage =
        reviewPageCount == 0 ? 0 : _reviewPage.clamp(0, reviewPageCount - 1);
    final reviewPageItems = filteredReviews
        .skip(currentReviewPage * _kPageSize)
        .take(_kPageSize)
        .toList();

    return Scaffold(
      backgroundColor: MC.bg0,
      body: RefreshIndicator(
        color: MC.kuvacultScore,
        backgroundColor: MC.bg1,
        onRefresh: () => Future.wait([
          state.loadPublicReviews(force: true),
          state.loadTrending(),
          state.refreshActivity(),
          state.loadCommunityTopWatchlists(),
        ]),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 62, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('KUVACULT COMMUNITY',
                          style: MT.mono(
                              size: 10,
                              letterSpacing: 2,
                              color: MC.kuvacultScore)),
                      const SizedBox(height: 4),
                      Text('Reviews', style: MT.display(size: 34)),
                    ],
                  ),
                  const Spacer(),
                  Builder(builder: (ctx) {
                    final unread = state.notifications
                            .where((n) => !n.read)
                            .length +
                        state.pendingInvites.length;
                    return GestureDetector(
                      onTap: () {
                        context.read<AppState>().markAllNotificationsRead();
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const _ActivityDrawer(),
                        );
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: MC.bg1,
                          border: Border.all(color: MC.line, width: 0.5),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            const Icon(Icons.notifications_outlined,
                                color: MC.mute, size: 20),
                            if (unread > 0)
                              Positioned(
                                top: -4,
                                right: -4,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE05A7A),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    unread > 9 ? '9+' : '$unread',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

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
                                      color: MC.kuvacultScore, strokeWidth: 2))
                              : Text('No movies',
                                  style:
                                      TextStyle(color: MC.dim, fontSize: 12)),
                        )
                      : ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(
                            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
                          ),
                          child: ListView.builder(
                            controller: _popularMoviesScroll,
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
                                            ? AppImage(
                                                imageUrl: m.poster.imageUrl!,
                                                width: 110,
                                                height: 155,
                                                fit: BoxFit.cover,
                                                errorWidget: (_, __, ___) =>
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
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    children: [
                      Text('POPULAR THIS MONTH',
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
                  child: topMonthReviews.isEmpty
                      ? Center(
                          child: Text('No reviews this month',
                              style: TextStyle(color: MC.dim, fontSize: 12)),
                        )
                      : ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(
                            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
                          ),
                          child: ListView.builder(
                            controller: _popularReviewsScroll,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: topMonthReviews.length,
                          itemBuilder: (ctx, i) {
                            final r = topMonthReviews[i];
                            final posterUrl = r.moviePosterUrl != null && r.moviePosterUrl!.isNotEmpty
                                ? (r.moviePosterUrl!.startsWith('/')
                                    ? '${Config.httpBase}${r.moviePosterUrl}'
                                    : r.moviePosterUrl!)
                                : null;
                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DetailScreen(
                                    movie: Movie(
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
                                      poster: PosterData(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF1C1C2E), Color(0xFF2D2D44)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        accent: const Color(0xFFF6C453),
                                        imageUrl: r.moviePosterUrl,
                                      ),
                                    ),
                                    scrollToReviewId: r.id,
                                  ),
                                ),
                              ),
                              child: Container(
                                width: 220,
                                height: 180,
                                margin: const EdgeInsets.only(right: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: MC.bg1,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: MC.line, width: 0.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(5),
                                          child: posterUrl != null
                                              ? AppImage(
                                                  imageUrl: posterUrl,
                                                  width: 40,
                                                  height: 60,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, __, ___) => Container(
                                                    width: 40, height: 60, color: MC.bg2,
                                                    child: const Icon(Icons.movie_outlined, color: MC.dim, size: 14),
                                                  ),
                                                )
                                              : Container(
                                                  width: 40, height: 60, color: MC.bg2,
                                                  child: const Icon(Icons.movie_outlined, color: MC.dim, size: 14),
                                                ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              GestureDetector(
                                                onTap: () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => UserProfileScreen(
                                                      userId: r.byId,
                                                      initialName: r.byName,
                                                    ),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    _AvatarWidget(
                                                      avatarUrl: r.byAvatarUrl,
                                                      avatarColor: r.byAvatarColor,
                                                      name: r.byName,
                                                      size: 22,
                                                      userId: r.byId,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        r.byName,
                                                        style: const TextStyle(
                                                          color: MC.ink,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                r.movieTitle,
                                                style: MT.display(size: 12, letterSpacing: -0.2),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              _StarRow(stars: r.stars),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (r.text.isNotEmpty)
                                      Expanded(
                                        child: ReviewText(
                                          text: r.text,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: MC.mute,
                                            height: 1.4,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )
                                    else
                                      const Spacer(),
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: () => state.likeReview(r.id),
                                      child: Row(
                                        children: [
                                          Icon(
                                            r.likedByMe
                                                ? Icons.favorite_rounded
                                                : Icons.favorite_border_rounded,
                                            size: 11,
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
                                          const SizedBox(width: 10),
                                          const Icon(Icons.mode_comment_outlined,
                                              size: 11, color: MC.dim),
                                          const SizedBox(width: 3),
                                          Text('${r.commentCount}',
                                              style: MT.mono(
                                                  size: 9,
                                                  letterSpacing: 0,
                                                  color: MC.dim)),
                                          if (state.isWatched(r.movieId)) ...[
                                            const SizedBox(width: 8),
                                            const Icon(Icons.remove_red_eye_rounded,
                                                size: 11, color: MC.mute),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        ),
                ),
              ],
            ),
          ),

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
                  height: 172,
                  child: topTenWatchlists.isEmpty
                      ? Center(
                          child: Text('No watchlists',
                              style: TextStyle(color: MC.dim, fontSize: 12)),
                        )
                      : ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(
                            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
                          ),
                          child: ListView.builder(
                            controller: _topWatchlistsScroll,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: topTenWatchlists.length,
                            itemBuilder: (ctx, i) {
                              final wl = topTenWatchlists[i];
                              final watchlistId = wl['id'] as String? ?? '';
                              final name = wl['name'] as String? ?? '';
                              final movieCount = wl['movieCount'] as int? ?? 0;
                              final likes = wl['likes'] as int? ?? 0;
                              final isLiked = watchlistId.isNotEmpty &&
                                  state.isCommunityWatchlistLiked(watchlistId);
                              return _WatchlistFanCard(
                                watchlistId: watchlistId,
                                name: name,
                                movieCount: movieCount,
                                likes: likes,
                                isLiked: isLiked,
                                onTap: watchlistId.isNotEmpty
                                    ? () => _openCommunityWatchlist(context, watchlistId, name, initialLikes: likes)
                                    : () {},
                                onLike: watchlistId.isNotEmpty
                                    ? () => state.likeCommunityWatchlist(watchlistId)
                                    : () {},
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),

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
                      : ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(
                            dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
                          ),
                          child: ListView.builder(
                            controller: _topReviewersScroll,
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
                                      userId: r['userId'] as String?,
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
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                children: [
                  Text('ALL REVIEWS', style: MT.mono(size: 10, letterSpacing: 2)),
                  const Spacer(),
                  GestureDetector(
                    onTap: loading ? null : () => state.loadPublicReviews(force: true),
                    child: loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: MC.mute, strokeWidth: 1.5),
                          )
                        : const Icon(Icons.refresh_rounded,
                            color: MC.mute, size: 18),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _reviewSearchCtrl,
                style: const TextStyle(color: MC.ink, fontSize: 13),
                onChanged: (v) =>
                    setState(() { _reviewSearch = v; _reviewPage = 0; }),
                decoration: InputDecoration(
                  hintText: 'Search by movie title…',
                  hintStyle: const TextStyle(color: MC.dim, fontSize: 13),
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: MC.dim, size: 18),
                  suffixIcon: _reviewSearch.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            setState(() {
                              _reviewSearch = '';
                              _reviewPage = 0;
                            });
                            _reviewSearchCtrl.clear();
                          },
                          child: const Icon(Icons.close_rounded,
                              color: MC.dim, size: 16),
                        )
                      : null,
                  filled: true,
                  fillColor: MC.bg1,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: MC.line, width: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: MC.line, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: MC.kuvacultScore, width: 1),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
          ),

          if (loading && reviews.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: MC.kuvacultScore, strokeWidth: 2),
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
                        color: MC.kuvacultScore.withAlpha(20),
                        border: Border.all(
                            color: MC.kuvacultScore.withAlpha(60), width: 1),
                      ),
                      child: const Icon(Icons.rate_review_outlined,
                          color: MC.kuvacultScore, size: 26),
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
          else if (filteredReviews.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Center(
                  child: Text('No reviews match your search',
                      style: TextStyle(color: MC.dim, fontSize: 13)),
                ),
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _ReviewCard(
                    key: ValueKey(reviewPageItems[i].id),
                    review: reviewPageItems[i],
                    onLike: () => state.likeReview(reviewPageItems[i].id),
                    onUserTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => UserProfileScreen(
                                  userId: reviewPageItems[i].byId,
                                  initialName: reviewPageItems[i].byName,
                                ))),
                    onDelete: state.currentUser?.id == reviewPageItems[i].byId
                        ? () => state.deleteReview(reviewPageItems[i].id)
                        : null,
                  ),
                  childCount: reviewPageItems.length,
                ),
              ),
            ),
            if (reviewPageCount > 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: currentReviewPage > 0
                            ? () => setState(
                                () => _reviewPage = currentReviewPage - 1)
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: currentReviewPage > 0 ? MC.bg1 : MC.bg0,
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: MC.line, width: 0.5),
                          ),
                          child: Text('← Prev',
                              style: TextStyle(
                                  color: currentReviewPage > 0
                                      ? MC.ink
                                      : MC.dim,
                                  fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${currentReviewPage + 1} / $reviewPageCount',
                        style: MT.mono(
                            size: 11,
                            letterSpacing: 0.5,
                            color: MC.mute),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: currentReviewPage < reviewPageCount - 1
                            ? () => setState(
                                () => _reviewPage = currentReviewPage + 1)
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: currentReviewPage < reviewPageCount - 1
                                ? MC.bg1
                                : MC.bg0,
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: MC.line, width: 0.5),
                          ),
                          child: Text('Next →',
                              style: TextStyle(
                                  color: currentReviewPage < reviewPageCount - 1
                                      ? MC.ink
                                      : MC.dim,
                                  fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
        ),
      ),
    );
  }
}


class _ActivityDrawer extends StatelessWidget {
  const _ActivityDrawer();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final activity = state.activity;
    final invites = state.pendingInvites;
    final notifs = state.notifications
        .where((n) =>
            n.type == NotifType.likedReview ||
            n.type == NotifType.likedWatchlist ||
            n.type == NotifType.followed)
        .toList();
    final hasContent =
        activity.isNotEmpty || notifs.isNotEmpty || invites.isNotEmpty;

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
                Text('ACTIVITY',
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
          if (!hasContent)
            Expanded(
              child: Center(
                child: Text('No activity yet',
                    style: TextStyle(color: MC.dim, fontSize: 13)),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  if (invites.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('WATCHLIST INVITES',
                          style: MT.mono(
                              size: 9,
                              letterSpacing: 2,
                              color: MC.dim)),
                    ),
                    ...invites.map((inv) => _DrawerInviteTile(invite: inv)),
                    const SizedBox(height: 12),
                  ],
                  if (notifs.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('NOTIFICATIONS',
                          style: MT.mono(size: 9, letterSpacing: 2, color: MC.dim)),
                    ),
                    ...notifs.map((n) => _DrawerNotifTile(notif: n)),
                    const SizedBox(height: 12),
                  ],
                  if (activity.isNotEmpty) ...[
                    if (notifs.isNotEmpty || invites.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('WATCHLIST ACTIVITY',
                            style: MT.mono(size: 9, letterSpacing: 2, color: MC.dim)),
                      ),
                    ...activity.asMap().entries.map((entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: ActivityItem(
                            event: entry.value,
                            isLast: entry.key == activity.length - 1,
                            onMovieTap: (_) {},
                          ),
                        )),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DrawerNotifTile extends StatelessWidget {
  final AppNotification notif;
  const _DrawerNotifTile({required this.notif});

  @override
  Widget build(BuildContext context) {
    String text;
    IconData icon;
    Color iconColor;

    switch (notif.type) {
      case NotifType.likedReview:
        text =
            '${notif.fromName ?? 'Someone'} liked your review of ${notif.movieTitle ?? 'a movie'}';
        icon = Icons.favorite_rounded;
        iconColor = const Color(0xFFE05A7A);
      case NotifType.likedWatchlist:
        text =
            '${notif.fromName ?? 'Someone'} liked your watchlist${notif.watchlistName != null ? ' "${notif.watchlistName}"' : ''}';
        icon = Icons.favorite_rounded;
        iconColor = const Color(0xFFE05A7A);
      case NotifType.followed:
        text = '${notif.fromName ?? 'Someone'} followed you';
        icon = Icons.person_add_rounded;
        iconColor = MC.accent1;
      default:
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(25),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: MC.ink, fontSize: 12, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _timeAgo(notif.at),
            style: MT.mono(size: 9, letterSpacing: 0, color: MC.mute),
          ),
        ],
      ),
    );
  }
}

class _DrawerInviteTile extends StatelessWidget {
  final WatchlistInvite invite;
  const _DrawerInviteTile({required this.invite});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MC.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MC.line, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: MC.accent1.withAlpha(25),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.playlist_add_rounded,
                  color: MC.accent1, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${invite.inviterName} invited you to "${invite.watchlistName}"',
                    style: const TextStyle(
                        color: MC.ink, fontSize: 12, height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                await state.acceptWatchlistInvite(
                    invite.watchlistId, invite.id);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: MC.accent1,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Join',
                    style: TextStyle(
                        color: MC.accentInk,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => state.declineWatchlistInvite(
                  invite.watchlistId, invite.id),
              child: const Icon(Icons.close_rounded,
                  color: MC.dim, size: 16),
            ),
          ],
        ),
      ),
    );
  }
}


class _ExploreListScreen extends StatefulWidget {
  final String type; // 'movies' | 'reviews' | 'watchlists' | 'reviewers'
  const _ExploreListScreen({required this.type});

  @override
  State<_ExploreListScreen> createState() => _ExploreListScreenState();
}

class _ExploreListScreenState extends State<_ExploreListScreen> {
  String _period = 'This Week';
  int _page = 0;
  static const _kPageSize = 15;
  static const _periods = ['This Week', 'This Month', 'This Year', 'All Time'];

  @override
  void initState() {
    super.initState();
    if (widget.type == 'watchlists') {
      // Pre-fetch posters for whatever is already cached before the grid renders.
      _prefetchPosters(context.read<AppState>().communityTopWatchlists);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AppState>().loadCommunityTopWatchlists().then((_) {
          if (!mounted) return;
          _prefetchPosters(context.read<AppState>().communityTopWatchlists);
        });
      });
    }
  }

  void _prefetchPosters(List<Map<String, dynamic>> watchlists) {
    for (final wl in watchlists) {
      final id = wl['id'] as String?;
      if (id != null && id.isNotEmpty) _fetchCommunityPosters(id);
    }
  }

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

          if (widget.type == 'reviews')
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Row(
                  children: _periods.map((p) {
                    final isActive = _period == p;
                    return GestureDetector(
                      onTap: () =>
                          setState(() { _period = p; _page = 0; }),
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

          if (widget.type == 'movies') ..._buildMoviesList(state),
          if (widget.type == 'reviews') ..._buildReviewsList(state),
          if (widget.type == 'watchlists') ..._buildWatchlistsList(state),
          if (widget.type == 'reviewers') ..._buildReviewersList(state),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _buildPaginationSliver(int page, int pageCount) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: page > 0
                  ? () => setState(() => _page = page - 1)
                  : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            Text(
              '${page + 1} / $pageCount',
              style:
                  MT.mono(size: 11, letterSpacing: 0.5, color: MC.mute),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: page < pageCount - 1
                  ? () => setState(() => _page = page + 1)
                  : null,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    final pageCount = (movies.length / _kPageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final pageMovies =
        movies.skip(page * _kPageSize).take(_kPageSize).toList();
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: (MediaQuery.of(context).size.width / 180).floor().clamp(3, 8),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 110 / 175,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final m = pageMovies[i];
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
                            ? AppImage(
                                imageUrl: m.poster.imageUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorWidget: (_, __, ___) =>
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
            childCount: pageMovies.length,
          ),
        ),
      ),
      if (pageCount > 1) _buildPaginationSliver(page, pageCount),
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
    final pageCount = (reviews.length / _kPageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final pageReviews =
        reviews.skip(page * _kPageSize).take(_kPageSize).toList();
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => _ReviewCard(
              key: ValueKey(pageReviews[i].id),
              review: pageReviews[i],
              onLike: () => state.likeReview(pageReviews[i].id),
              onUserTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => UserProfileScreen(
                          userId: pageReviews[i].byId,
                          initialName: pageReviews[i].byName,
                        )),
              ),
              onDelete: state.currentUser?.id == pageReviews[i].byId
                  ? () => state.deleteReview(pageReviews[i].id)
                  : null,
            ),
            childCount: pageReviews.length,
          ),
        ),
      ),
      if (pageCount > 1) _buildPaginationSliver(page, pageCount),
    ];
  }

  List<Widget> _buildWatchlistsList(AppState state) {
    final watchlists = state.communityTopWatchlists;
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
    final pageCount = (watchlists.length / _kPageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final pageWatchlists =
        watchlists.skip(page * _kPageSize).take(_kPageSize).toList();
    return [
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
              final wl = pageWatchlists[i];
              final watchlistId = wl['id'] as String? ?? '';
              final name = wl['name'] as String? ?? '';
              final movieCount = wl['movieCount'] as int? ?? 0;
              final likes = wl['likes'] as int? ?? 0;
              final isLiked = watchlistId.isNotEmpty &&
                  state.isCommunityWatchlistLiked(watchlistId);
              return _WatchlistGridPosterCard(
                watchlistId: watchlistId,
                name: name,
                movieCount: movieCount,
                likes: likes,
                isLiked: isLiked,
                onTap: watchlistId.isNotEmpty
                    ? () => _openCommunityWatchlist(context, watchlistId, name, initialLikes: likes)
                    : () {},
                onLike: watchlistId.isNotEmpty
                    ? () => state.likeCommunityWatchlist(watchlistId)
                    : () {},
              );
            },
            childCount: pageWatchlists.length,
          ),
        ),
      ),
      if (pageCount > 1) _buildPaginationSliver(page, pageCount),
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
    final pageCount = (reviewers.length / _kPageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final pageReviewers =
        reviewers.skip(page * _kPageSize).take(_kPageSize).toList();
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) {
              final r = pageReviewers[i];
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
                        userId: r['userId'] as String?,
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
                                  color: MC.kuvacultScore,
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
            childCount: pageReviewers.length,
          ),
        ),
      ),
      if (pageCount > 1) _buildPaginationSliver(page, pageCount),
    ];
  }
}


class _ReviewCard extends StatefulWidget {
  final Review review;
  final VoidCallback onLike;
  final VoidCallback onUserTap;
  final VoidCallback? onDelete;

  const _ReviewCard({
    super.key,
    required this.review,
    required this.onLike,
    required this.onUserTap,
    this.onDelete,
  });

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: widget.onUserTap,
                  child: _AvatarWidget(
                    avatarUrl: widget.review.byAvatarUrl,
                    avatarColor: widget.review.byAvatarColor,
                    name: widget.review.byName,
                    size: 34,
                    userId: widget.review.byId,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: widget.onUserTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.review.byName,
                          style: const TextStyle(
                            color: MC.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          '@${widget.review.byHandle}',
                          style: MT.mono(
                              size: 10,
                              letterSpacing: 0.5,
                              color: MC.dim),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(_timeAgo(widget.review.at),
                    style: MT.mono(
                        size: 10, letterSpacing: 0, color: MC.dim)),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetailScreen(
                        movie: _reviewToStubMovie(widget.review),
                        scrollToReviewId: widget.review.id,
                      ),
                    ),
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: widget.review.moviePosterUrl != null
                            ? AppImage(
                                imageUrl: widget.review.moviePosterUrl!,
                                width: 44,
                                height: 66,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => _posterPlaceholder(),
                              )
                            : _posterPlaceholder(),
                      ),
                      if (context.watch<AppState>().isWatched(widget.review.movieId))
                        Positioned(
                          bottom: 3,
                          right: 3,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(160),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.remove_red_eye_rounded,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DetailScreen(
                          movie: _reviewToStubMovie(widget.review),
                          scrollToReviewId: widget.review.id,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.review.movieTitle,
                          style: MT.display(size: 15, letterSpacing: -0.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.review.movieYear}${widget.review.movieDirector.isNotEmpty ? '  ·  ${widget.review.movieDirector}' : ''}',
                          style: MT.mono(
                              size: 10, letterSpacing: 0, color: MC.mute),
                        ),
                        const SizedBox(height: 6),
                        _StarRow(stars: widget.review.stars),
                        if (widget.review.rewatch)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Icon(Icons.replay_rounded,
                                    size: 11,
                                    color: MC.kuvacultScore.withAlpha(200)),
                                const SizedBox(width: 3),
                                Text('Rewatch',
                                    style: MT.mono(
                                        size: 9,
                                        letterSpacing: 0,
                                        color: MC.kuvacultScore)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (widget.review.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: ExpandableReviewText(
                text: widget.review.text,
                style: const TextStyle(fontSize: 13, color: MC.ink, height: 1.5),
                collapsedLines: 4,
              ),
            ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: widget.onLike,
                  child: Row(
                    children: [
                      Icon(
                        widget.review.likedByMe
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 16,
                        color: widget.review.likedByMe
                            ? const Color(0xFFE05A7A)
                            : MC.dim,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.review.likes}',
                        style: MT.mono(
                            size: 10,
                            letterSpacing: 0,
                            color: widget.review.likedByMe
                                ? const Color(0xFFE05A7A)
                                : MC.dim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetailScreen(
                        movie: _reviewToStubMovie(widget.review),
                        scrollToReviewId: widget.review.id,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mode_comment_outlined,
                          size: 14, color: MC.dim),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.review.commentCount}',
                        style:
                            MT.mono(size: 10, letterSpacing: 0, color: MC.dim),
                      ),
                    ],
                  ),
                ),
                if (widget.onDelete != null) ...[
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _confirmDelete(context),
                    child: const Icon(Icons.delete_outline_rounded,
                        size: 16, color: MC.dim),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
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
              widget.onDelete?.call();
            },
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFE05A7A), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Movie _reviewToStubMovie(Review r) => Movie(
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
    poster: PosterData(
      gradient: const LinearGradient(
        colors: [Color(0xFF1C1C2E), Color(0xFF2D2D44)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accent: const Color(0xFFF6C453),
      imageUrl: r.moviePosterUrl,
    ),
  );

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


class _AvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final Color avatarColor;
  final String name;
  final double size;
  final String? userId;

  const _AvatarWidget({
    required this.avatarUrl,
    required this.avatarColor,
    required this.name,
    required this.size,
    this.userId,
  });

  @override
  Widget build(BuildContext context) {
    String? resolvedUrl = avatarUrl;

    if (userId != null) {
      // Use select() for current user so we only rebuild when their avatar changes.
      // For others, use read() since friends/member avatars don't change mid-session.
      final currentUserId = context.select<AppState, String?>((s) => s.currentUser?.id);
      if (userId == currentUserId) {
        resolvedUrl = context.select<AppState, String?>((s) => s.currentUser?.avatarUrl) ?? avatarUrl;
      } else if ((avatarUrl ?? '').isEmpty) {
        final state = context.read<AppState>();
        final friend = state.friends.cast<UserAccount?>().firstWhere(
            (f) => f?.id == userId,
            orElse: () => null);
        if (friend != null) {
          resolvedUrl = friend.avatarUrl;
        } else {
          final member = state.memberProfiles[userId!];
          if (member != null) resolvedUrl = member.avatarUrl;
        }
      }
    }

    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
      final url = resolvedUrl.startsWith('/')
          ? '${Config.httpBase}$resolvedUrl'
          : resolvedUrl;
      return ClipOval(
        child: AppImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _initials(initial),
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
            color: MC.kuvacultScore,
          ),
        );
      }),
    );
  }
}

void _openCommunityWatchlist(BuildContext context, String watchlistId, String name, {int initialLikes = 0}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PublicWatchlistScreen(
        watchlistId: watchlistId,
        name: name,
        initialLikes: initialLikes,
      ),
    ),
  );
}

Widget _avatarFallback(String name) {
  final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
  return Container(
    width: 36, height: 36,
    color: const Color(0xFF3A3A4A),
    child: Center(
      child: Text(initial,
          style: const TextStyle(
              color: MC.ink, fontSize: 14, fontWeight: FontWeight.w600)),
    ),
  );
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

final _communityPosterCache = <String, List<String>>{};
final _communityPosterFetch = <String, Future<List<String>>>{};

Future<List<String>> _fetchCommunityPosters(String watchlistId) {
  if (_communityPosterCache.containsKey(watchlistId)) {
    return Future.value(_communityPosterCache[watchlistId]!);
  }
  return _communityPosterFetch.putIfAbsent(watchlistId, () async {
    try {
      final data = await ApiService.fetchWatchlistById(watchlistId);
      final movies = data['movies'] as List? ?? [];
      final urls = movies
          .map((m) => (m as Map<String, dynamic>)['imageUrl'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .take(4)
          .toList();
      _communityPosterFetch.remove(watchlistId);
      return _communityPosterCache[watchlistId] = urls;
    } catch (_) {
      _communityPosterFetch.remove(watchlistId);
      return _communityPosterCache[watchlistId] = [];
    }
  });
}

class _WatchlistFanCard extends StatefulWidget {
  final String watchlistId;
  final String name;
  final int movieCount;
  final int likes;
  final bool isLiked;
  final VoidCallback onTap;
  final VoidCallback onLike;

  const _WatchlistFanCard({
    required this.watchlistId,
    required this.name,
    required this.movieCount,
    required this.likes,
    required this.isLiked,
    required this.onTap,
    required this.onLike,
  });

  @override
  State<_WatchlistFanCard> createState() => _WatchlistFanCardState();
}

class _WatchlistFanCardState extends State<_WatchlistFanCard> {
  List<String> _posters = [];

  @override
  void initState() {
    super.initState();
    if (widget.watchlistId.isNotEmpty) {
      final cached = _communityPosterCache[widget.watchlistId];
      if (cached != null) {
        _posters = cached;
      } else {
        _fetchCommunityPosters(widget.watchlistId).then((urls) {
          if (mounted) setState(() => _posters = urls);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: MC.bg1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MC.line, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                child: _buildFan(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name,
                      style: const TextStyle(
                          color: MC.ink, fontSize: 12, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text('${widget.movieCount} films',
                          style: MT.mono(size: 9, letterSpacing: 0, color: MC.dim)),
                      const Spacer(),
                      GestureDetector(
                        onTap: widget.onLike,
                        child: Row(children: [
                          Icon(
                            widget.isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 13,
                            color: widget.isLiked
                                ? const Color(0xFFE05A7A)
                                : MC.dim,
                          ),
                          const SizedBox(width: 3),
                          Text('${widget.likes}',
                              style: MT.mono(
                                  size: 9,
                                  letterSpacing: 0,
                                  color: widget.isLiked
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
      ),
    );
  }

  Widget _buildFan() {
    if (_posters.isEmpty) {
      return Container(
        color: MC.bg2,
        child: const Center(child: Icon(Icons.movie_outlined, color: MC.dim, size: 26)),
      );
    }

    final count = _posters.length.clamp(1, 4);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Equal-width strips, edge to edge, no background showing
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < count; i++) ...[
              if (i > 0)
                Container(width: 1, color: Colors.black.withOpacity(0.25)),
              Expanded(
                child: AppImage(
                  imageUrl: _posters[i],
                  fit: BoxFit.cover,
                  cacheByHeight: true,
                  fadeInDuration: const Duration(milliseconds: 200),
                  placeholder: (_, __) => Container(color: MC.bg2),
                  errorWidget: (_, __, ___) => Container(color: MC.bg2),
                ),
              ),
            ],
          ],
        ),
        // Subtle bottom vignette so the card edge reads cleanly
        Positioned(
          left: 0, right: 0, bottom: 0,
          height: 28,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.55)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WatchlistGridPosterCard extends StatefulWidget {
  final String watchlistId;
  final String name;
  final int movieCount;
  final int likes;
  final bool isLiked;
  final VoidCallback onTap;
  final VoidCallback onLike;

  const _WatchlistGridPosterCard({
    required this.watchlistId,
    required this.name,
    required this.movieCount,
    required this.likes,
    required this.isLiked,
    required this.onTap,
    required this.onLike,
  });

  @override
  State<_WatchlistGridPosterCard> createState() => _WatchlistGridPosterCardState();
}

class _WatchlistGridPosterCardState extends State<_WatchlistGridPosterCard> {
  List<String> _posters = [];

  void _loadPosters(String watchlistId) {
    if (watchlistId.isEmpty) return;
    final cached = _communityPosterCache[watchlistId];
    if (cached != null) {
      _posters = cached;
    } else {
      _fetchCommunityPosters(watchlistId).then((urls) {
        if (mounted) setState(() => _posters = urls);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPosters(widget.watchlistId);
  }

  @override
  void didUpdateWidget(covariant _WatchlistGridPosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.watchlistId != oldWidget.watchlistId) {
      _posters = [];
      _loadPosters(widget.watchlistId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
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
                child: _buildMosaic(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.name,
                      style: MT.display(size: 13, letterSpacing: -0.3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${widget.movieCount} ${widget.movieCount == 1 ? 'film' : 'films'}',
                        style: MT.mono(size: 9, letterSpacing: 1, color: MC.mute),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: widget.onLike,
                        child: Row(children: [
                          Icon(
                            widget.isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 13,
                            color: widget.isLiked
                                ? const Color(0xFFE05A7A)
                                : MC.dim,
                          ),
                          const SizedBox(width: 3),
                          Text('${widget.likes}',
                              style: MT.mono(
                                  size: 9,
                                  letterSpacing: 0,
                                  color: widget.isLiked
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
      ),
    );
  }

  Widget _buildMosaic() {
    Widget img(String url) => AppImage(
      imageUrl: url,
      fit: BoxFit.cover,
      cacheByHeight: true,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => Container(color: MC.bg2),
      errorWidget: (_, __, ___) => Container(color: MC.bg2),
    );
    if (_posters.isEmpty) {
      return Container(
        color: MC.bg2,
        child: const Center(child: Icon(Icons.movie_outlined, color: MC.dim, size: 32)),
      );
    }
    if (_posters.length == 1) return img(_posters[0]);
    if (_posters.length < 4) {
      return Row(children: [
        Expanded(child: img(_posters[0])),
        const SizedBox(width: 1),
        Expanded(child: img(_posters[1])),
      ]);
    }
    return Column(children: [
      Expanded(child: Row(children: [
        Expanded(child: img(_posters[0])),
        const SizedBox(width: 1),
        Expanded(child: img(_posters[1])),
      ])),
      const SizedBox(height: 1),
      Expanded(child: Row(children: [
        Expanded(child: img(_posters[2])),
        const SizedBox(width: 1),
        Expanded(child: img(_posters[3])),
      ])),
    ]);
  }
}

class _WatchlistMoviesScreen extends StatefulWidget {
  final Watchlist watchlist;
  const _WatchlistMoviesScreen({required this.watchlist});

  @override
  State<_WatchlistMoviesScreen> createState() => _WatchlistMoviesScreenState();
}

class _WatchlistMoviesScreenState extends State<_WatchlistMoviesScreen> {
  String _search = '';
  int _page = 0;
  static const _kPageSize = 18;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Pull from live state so likes update reactively
    final wl = state.watchlists.cast<Watchlist?>().firstWhere(
          (w) => w?.id == widget.watchlist.id,
          orElse: () => null,
        ) ??
        widget.watchlist;

    final allMovies = wl.movies;
    final filtered = _search.isEmpty
        ? allMovies
        : allMovies
            .where((m) =>
                m.title.toLowerCase().contains(_search.toLowerCase()))
            .toList();
    final pageCount =
        filtered.isEmpty ? 0 : (filtered.length / _kPageSize).ceil();
    final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final pageMovies =
        filtered.skip(page * _kPageSize).take(_kPageSize).toList();

    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 62, 20, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: MC.ink, size: 18),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(wl.name, style: MT.display(size: 26)),
                  ),
                  GestureDetector(
                    onTap: () => state.likeWatchlist(wl.id),
                    child: Row(
                      children: [
                        Icon(
                          wl.likedByMe
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 20,
                          color: wl.likedByMe
                              ? const Color(0xFFE05A7A)
                              : MC.dim,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${wl.likes}',
                          style: MT.mono(
                              size: 12,
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
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '${allMovies.length} movie${allMovies.length == 1 ? '' : 's'}',
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
                onChanged: (v) =>
                    setState(() { _search = v; _page = 0; }),
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
                          child: const Icon(Icons.close_rounded,
                              color: MC.dim, size: 16),
                        )
                      : null,
                  filled: true,
                  fillColor: MC.bg1,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: MC.line, width: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: MC.line, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: MC.kuvacultScore, width: 1),
                  ),
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
                        : 'No movies in this watchlist yet',
                    style: const TextStyle(color: MC.dim, fontSize: 13),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: (MediaQuery.of(context).size.width / 180).floor().clamp(3, 8),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 12,
                  childAspectRatio: 110 / 185,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final m = pageMovies[i];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => DetailScreen(movie: m)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: m.poster.imageUrl != null
                                  ? AppImage(
                                      imageUrl: m.poster.imageUrl!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorWidget: (_, __, ___) =>
                                          _moviePlaceholder(),
                                    )
                                  : _moviePlaceholder(),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            m.title,
                            style: const TextStyle(
                                color: MC.ink, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${m.year}',
                            style: MT.mono(
                                size: 9, letterSpacing: 0, color: MC.dim),
                          ),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: page > 0
                          ? () => setState(() => _page = page - 1)
                          : null,
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
                                color: page > 0 ? MC.ink : MC.dim,
                                fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${page + 1} / $pageCount',
                        style: MT.mono(
                            size: 11, letterSpacing: 0.5, color: MC.mute)),
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
                                color:
                                    page < pageCount - 1 ? MC.ink : MC.dim,
                                fontSize: 12)),
                      ),
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
}


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
    showTopToast(context, 'Sign in to write reviews');
    return;
  }

  // If user already reviewed this movie, open in edit mode
  final userId = state.currentUser?.id ?? '';
  final existing = state.reviewsForUser(userId)
      .where((r) => r.movieId == movieId)
      .firstOrNull;

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
      existingReview: existing,
    ),
  );
}

class _WriteReviewSheet extends StatefulWidget {
  final String movieId;
  final String movieTitle;
  final int movieYear;
  final String movieDirector;
  final String? moviePosterUrl;
  final Review? existingReview;

  const _WriteReviewSheet({
    required this.movieId,
    required this.movieTitle,
    required this.movieYear,
    required this.movieDirector,
    this.moviePosterUrl,
    this.existingReview,
  });

  @override
  State<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<_WriteReviewSheet> {
  late double _stars;
  late bool _rewatch;
  bool _submitting = false;
  late final TextEditingController _ctrl;

  bool get _isEdit => widget.existingReview != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existingReview;
    _stars = e?.stars ?? 0;
    _rewatch = e?.rewatch ?? false;
    _ctrl = TextEditingController(text: e?.text ?? '');
  }

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
                    Text(_isEdit ? 'Edit review' : 'Write a review', style: MT.display(size: 20)),
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
                      color: MC.kuvacultScore,
                    ),
                  ),
                ),
                if (_stars > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${_stars % 1 == 0 ? _stars.toInt() : _stars} / 5',
                    style: MT.mono(
                        size: 14, color: MC.kuvacultScore, letterSpacing: 1),
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
                        color: _rewatch ? MC.kuvacultScore : MC.dim,
                        width: 1.5),
                    color: _rewatch
                        ? MC.kuvacultScore.withAlpha(30)
                        : Colors.transparent,
                  ),
                  child: _rewatch
                      ? const Icon(Icons.check_rounded,
                          size: 12, color: MC.kuvacultScore)
                      : null,
                ),
                const SizedBox(width: 8),
                Text('Rewatch',
                    style: TextStyle(
                        fontSize: 13,
                        color: _rewatch ? MC.kuvacultScore : MC.mute)),
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
                    const BorderSide(color: MC.kuvacultScore, width: 1),
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
                    try {
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
                    } catch (e) {
                      if (context.mounted) {
                        setState(() => _submitting = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to post review: $e',
                                style: const TextStyle(color: MC.ink, fontSize: 13)),
                            backgroundColor: MC.bg1,
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      }
                    }
                  },
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: (_stars > 0 && _ctrl.text.trim().isNotEmpty)
                    ? MC.kuvacultScore
                    : MC.bg2,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: MC.kuvacultScoreInk, strokeWidth: 2))
                  : Text(
                      _isEdit ? 'Update review' : 'Post review',
                      style: TextStyle(
                        color: (_stars > 0 && _ctrl.text.trim().isNotEmpty)
                            ? MC.kuvacultScoreInk
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
