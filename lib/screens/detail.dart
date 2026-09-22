// detail.dart — Full movie detail screen with enriched metadata, mark-watched/watchlist/rating actions, a watcher list, and a paginated community reviews section with comments.

import 'package:flutter/material.dart';
import '../widgets/app_image.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models.dart';
import '../app_state.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../media_data.dart';
import '../widgets/poster.dart';
import '../widgets/avatar.dart';
import '../widgets/stream_badge.dart';
import '../widgets/review_text.dart';
import '../widgets/star_rating.dart';
import '../widgets/tag.dart';
import '../utils/top_toast.dart';
import '../widgets/watchlist_picker.dart';
import '../widgets/sign_in_sheet.dart';
import 'community_reviews.dart';
import 'user_profile.dart';

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}

class DetailScreen extends StatefulWidget {
  final Movie movie;
  final String? scrollToReviewId;
  const DetailScreen({super.key, required this.movie, this.scrollToReviewId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Movie? _enrichedMovie;
  List<Map<String, dynamic>> _watchers = [];
  bool _watchersLoaded = false;

  @override
  void initState() {
    super.initState();
    _maybeEnrich();
    _loadWatchers();
  }

  // If the movie came from an OMDB search stub it will have no rating,
  // runtime, or synopsis. Fetch full details by IMDb ID in the background.
  Future<void> _maybeEnrich() async {
    final m = widget.movie;
    if (m.rating > 0 || m.runtime > 0 || m.synopsis.isNotEmpty) return;
    try {
      final full = await MediaData().fetchTitle(m.id);
      if (mounted) setState(() => _enrichedMovie = full);
    } catch (_) {}
  }

  Future<void> _loadWatchers() async {
    try {
      final list = await ApiService.fetchMovieWatchers(widget.movie.id);
      if (mounted) setState(() { _watchers = list; _watchersLoaded = true; });
    } catch (_) {
      if (mounted) setState(() => _watchersLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Prefer: live watchlist copy > freshly fetched > original (possibly stub)
    final movie = state.findMovie(widget.movie.id) ?? _enrichedMovie ?? widget.movie;
    // The current user's ID drives all mutations — never hardcode a member name
    final userId = state.currentUser?.id ?? 'guest';

    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHero(context, movie)),
          SliverToBoxAdapter(child: _buildTitleBlock(context, movie, state, userId)),

          SliverToBoxAdapter(child: _buildWatchers(context)),
          SliverToBoxAdapter(
            child: _ReviewsSection(
              movieId: movie.id,
              scrollToReviewId: widget.scrollToReviewId,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context, Movie movie) {
    return SizedBox(
      height: 380,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(gradient: movie.poster.gradient),
              foregroundDecoration: const BoxDecoration(color: Color(0x99000000)),
            ),
          ),
          Positioned(
            left: 0, right: 0, top: 90,
            child: Center(
              child: PosterWidget(movie: movie, width: 180, height: 270),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.25, 0.6, 1.0],
                  colors: [
                    MC.bg0.withAlpha(128), Colors.transparent,
                    Colors.transparent, MC.bg0,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 58, left: 16,
            child: _glassButton(
              onTap: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: MC.ink, size: 14),
            ),
          ),
          Positioned(
            top: 58, right: 16,
            child: Row(
              children: [
                _glassButton(
                  onTap: () {
                    // TODO(backend): Share deep-link — POST /movies/:id/share
                    showTopToast(context, 'Share not yet implemented');
                  },
                  child: const Icon(Icons.share_outlined, color: MC.ink, size: 14),
                ),
                const SizedBox(width: 8),
                _glassButton(
                  onTap: () => _showMovieOptions(context),
                  child: const Icon(Icons.more_horiz, color: MC.ink, size: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassButton({required Widget child, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0x9914100C),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _buildTitleBlock(BuildContext context, Movie movie, AppState state, String userId) {
    // Whether this movie is already in the user's watchlist
    final inWatchlist = state.findMovie(movie.id) != null;
    final isGloballyWatched = state.isWatched(movie.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(movie.director.toUpperCase(), style: MT.mono(size: 10, letterSpacing: 2)),
          const SizedBox(height: 6),
          Text(movie.title, style: MT.display(size: 34, italic: true)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${movie.year}  ·  ${movie.runtime}m',
                style: MT.mono(size: 12, color: MC.mute, letterSpacing: 0),
              ),
              const SizedBox(width: 8),
              Text(
                '★ ${movie.rating}',
                style: MT.mono(size: 12, color: MC.accent1, letterSpacing: 0),
              ),
              Builder(builder: (ctx) {
                final score = ctx.select<AppState, double>(
                    (s) => s.kuvacultScore(movie.id));
                if (score == 0.0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '◆ ${score.toStringAsFixed(1)}',
                    style: MT.mono(
                        size: 12, color: MC.kuvacultScore, letterSpacing: 0),
                  ),
                );
              }),
              const Spacer(),
              StreamBadgeWidget(streamId: movie.streamId, badgeSize: BadgeSize.md),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            children: movie.genres.map((g) => TagWidget(label: g)).toList(),
          ),
          const SizedBox(height: 18),
          Text(
            movie.synopsis,
            style: const TextStyle(fontSize: 14, color: MC.ink, height: 1.55),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (state.isGuest) { showSignInSheet(context); return; }
                    if (isGloballyWatched) {
                      state.unmarkMovieWatched(movie.id);
                    } else {
                      state.markMovieWatched(movie);
                    }
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: isGloballyWatched
                          ? null
                          : const LinearGradient(
                              colors: [MC.accent1, MC.accent2],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: isGloballyWatched
                          ? MC.accent1.withAlpha(30)
                          : null,
                      border: isGloballyWatched
                          ? Border.all(color: MC.accent1, width: 1)
                          : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      isGloballyWatched ? 'Watched ✓' : 'Mark as watched',
                      style: TextStyle(
                        color: isGloballyWatched ? MC.accent1 : MC.accentInk,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              GestureDetector(
                onTap: () => showWatchlistPicker(context, movie),
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: inWatchlist
                        ? MC.bg2
                        : MC.accent1.withAlpha(21),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: inWatchlist ? MC.line : MC.accent1,
                      width: 0.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    inWatchlist
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_add_outlined,
                    color: inWatchlist ? MC.mute : MC.accent1,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              GestureDetector(
                onTap: () async {
                  if (await _requireWatchlist(context, state)) {
                    _markWatching(context, movie, state);
                  }
                },
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: inWatchlist && movie.section == WatchSection.watching
                        ? MC.accent1.withAlpha(30)
                        : MC.bg1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: inWatchlist && movie.section == WatchSection.watching
                          ? MC.accent1
                          : MC.line,
                      width: 0.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.play_circle_outline_rounded,
                    color: inWatchlist && movie.section == WatchSection.watching
                        ? MC.accent1
                        : MC.mute,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              GestureDetector(
                onTap: () => showWriteReviewSheet(
                  context,
                  movieId: movie.id,
                  movieTitle: movie.title,
                  movieYear: movie.year,
                  movieDirector: movie.director,
                  moviePosterUrl: movie.poster.imageUrl,
                ),
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: MC.kuvacultScore.withAlpha(20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MC.kuvacultScore.withAlpha(80), width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.rate_review_outlined,
                      color: MC.kuvacultScore, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildWatchers(BuildContext context) {
    final visible = _watchers.take(12).toList();
    final overflow = _watchers.length > 12 ? _watchers.length - 12 : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          Row(
            children: [
              Text('WATCHED BY', style: MT.mono(size: 10, letterSpacing: 2)),
              const SizedBox(width: 8),
              if (_watchersLoaded)
                Text(
                  _watchers.isEmpty ? '0' : '${_watchers.length}',
                  style: MT.mono(size: 11, letterSpacing: 0, color: MC.mute),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!_watchersLoaded)
            const SizedBox(
              height: 56,
              child: Center(child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: MC.mute))),
            )
          else if (_watchers.isEmpty)
            const Text('No one has watched this yet.',
                style: TextStyle(color: MC.mute, fontSize: 13))
          else
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: visible.length + (overflow > 0 ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  if (i == visible.length) {
                    return _watcherChip(
                      context,
                      label: '+$overflow',
                      avatarUrl: null,
                      initial: '+',
                      onTap: null,
                    );
                  }
                  final w = visible[i];
                  final name = (w['displayName'] as String? ?? '').trim();
                  final handle = w['username'] as String? ?? '';
                  final avatarUrl = w['avatarUrl'] as String?;
                  final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                  return _watcherChip(
                    context,
                    label: name.isNotEmpty ? name : handle,
                    avatarUrl: avatarUrl != null && avatarUrl.isNotEmpty
                        ? (avatarUrl.startsWith('/')
                            ? '${Config.httpBase}$avatarUrl'
                            : avatarUrl)
                        : null,
                    initial: initial,
                    onTap: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => UserProfileScreen(userId: w['id'] as String),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _watcherChip(BuildContext context, {
    required String label,
    required String? avatarUrl,
    required String initial,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 52,
        child: Column(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MC.bg2,
                border: Border.all(color: MC.line, width: 0.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatarUrl != null
                  ? AppImage(
                      imageUrl: avatarUrl, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Center(
                        child: Text(initial,
                            style: const TextStyle(color: MC.ink, fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ))
                  : Center(
                      child: Text(initial,
                          style: const TextStyle(color: MC.ink, fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: MC.dim, fontSize: 9, height: 1.2),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }


  // Ensures there is an active watchlist before proceeding.
  // Guests are prompted to sign in; logged-in users create a list if none exists.
  Future<bool> _requireWatchlist(BuildContext context, AppState state) async {
    if (state.isGuest) {
      showSignInSheet(context);
      return false;
    }
    if (state.activeWatchlist != null) return true;
    if (state.watchlists.isNotEmpty) {
      state.ensureActiveWatchlist();
      return true;
    }
    return _showCreateWatchlistPrompt(context, state);
  }

  Future<bool> _showCreateWatchlistPrompt(
      BuildContext context, AppState state) async {
    final ctrl = TextEditingController(text: 'My Watchlist');
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MC.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
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
              Text('Create a watchlist first', style: MT.display(size: 22)),
              const SizedBox(height: 4),
              const Text(
                'You need a watchlist to track, rate, and react to movies.',
                style: TextStyle(color: MC.mute, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(color: MC.ink),
                onChanged: (_) => setS(() {}),
                decoration: InputDecoration(
                  hintText: 'Watchlist name',
                  hintStyle: const TextStyle(color: MC.dim),
                  filled: true,
                  fillColor: MC.bg2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: MC.accent1, width: 1),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  final name = ctrl.text.trim();
                  if (name.isEmpty) return;
                  state.createWatchlist(name);
                  Navigator.pop(sheetCtx, true);
                },
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: ctrl.text.trim().isEmpty
                        ? null
                        : const LinearGradient(colors: [MC.accent1, MC.accent2]),
                    color: ctrl.text.trim().isEmpty ? MC.bg2 : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Create & continue',
                    style: TextStyle(
                      color: ctrl.text.trim().isEmpty ? MC.dim : MC.accentInk,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();
    return result == true;
  }

  // Adds the movie to the watchlist if it isn't already there.
  // Called before any mutation that requires the movie to exist in _movies.
  void _ensureInWatchlist(Movie movie, AppState state) {
    if (state.findMovie(movie.id) == null) {
      state.addMovieToWatchlist(movie);
    }
  }

  void _markWatching(BuildContext context, Movie movie, AppState state) {
    if (state.findMovie(movie.id) == null) {
      state.addMovieToWatchlist(movie);
      state.moveMovie(movie.id, WatchSection.watching);
      return;
    }
    final newSection = movie.section == WatchSection.watching
        ? WatchSection.want
        : WatchSection.watching;
    state.moveMovie(movie.id, newSection);
  }

  void _markWatched(BuildContext context, Movie movie, AppState state) {
    if (movie.section == WatchSection.watched) {
      // Toggling off — move back to want and clear from personal history
      state.unmarkMovieWatched(movie.id);
    } else {
      // Toggling on — add to watchlist first if needed, then use the
      // server-authoritative path (no optimistic section update here;
      // the WS broadcast moves the section once ALL members have watched)
      if (state.findMovie(movie.id) == null) state.addMovieToWatchlist(movie);
      state.markMovieWatched(movie);
    }
  }

  void _showRatingSheet(BuildContext context, Movie movie, String userId, AppState state) {
    double tempStars = movie.stars[userId] ?? 0.0;
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Your rating', style: MT.display(size: 22)),
              const SizedBox(height: 20),
              StarRatingInput(
                initialValue: tempStars,
                size: 36,
                onChanged: (v) => setSheetState(() => tempStars = v),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    tempStars == 0
                        ? '—'
                        : tempStars % 1 == 0
                            ? '${tempStars.toInt()} / 5'
                            : '$tempStars / 5',
                    style: MT.mono(size: 18, color: MC.accent1, letterSpacing: 1),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: tempStars == 0
                    ? null
                    : () {
                        _ensureInWatchlist(movie, state);
                        state.rateMovie(movie.id, userId, tempStars);
                        Navigator.pop(context);
                      },
                child: Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: tempStars == 0
                        ? null
                        : const LinearGradient(colors: [MC.accent1, MC.accent2]),
                    color: tempStars == 0 ? MC.bg2 : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Save rating',
                    style: TextStyle(
                      color: tempStars == 0 ? MC.dim : MC.accentInk,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showMovieOptions(BuildContext context) {
    final state = context.read<AppState>();
    final movie = state.findMovie(widget.movie.id) ?? widget.movie;
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: MC.dim, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          // Only show move options if movie is in the watchlist
          if (state.findMovie(movie.id) != null)
            ...WatchSection.values
                .where((s) => s != movie.section)
                .map((s) => ListTile(
                      leading: const Icon(Icons.move_to_inbox_outlined,
                          color: MC.mute),
                      title: Text('Move to ${s.label}',
                          style: const TextStyle(color: MC.ink)),
                      onTap: () {
                        state.moveMovie(movie.id, s);
                        Navigator.pop(context);
                      },
                    )),
          if (state.findMovie(movie.id) != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: const Text('Remove from watchlist',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                state.removeMovie(movie.id);
                Navigator.pop(context);
                Navigator.pop(context);
              },
            )
          else
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined,
                  color: MC.accent1),
              title: const Text('Add to watchlist',
                  style: TextStyle(color: MC.ink)),
              onTap: () {
                Navigator.pop(context);
                showWatchlistPicker(context, movie);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ReviewsSection extends StatefulWidget {
  final String movieId;
  final String? scrollToReviewId;

  const _ReviewsSection({required this.movieId, this.scrollToReviewId});

  @override
  State<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<_ReviewsSection> {
  int _page = 0;
  String _search = '';
  String? _expandedId;
  final Map<String, List<ReviewComment>> _comments = {};
  final Map<String, bool> _commentsLoading = {};
  final Map<String, int> _commentsVisible = {};
  final Map<String, TextEditingController> _replyCtrl = {};
  final Map<String, GlobalKey> _reviewKeys = {};
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadReviews());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final c in _replyCtrl.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    final state = context.read<AppState>();
    await state.loadMovieReviews(widget.movieId);
    if (!mounted) return;
    final targetId = widget.scrollToReviewId;
    if (targetId == null) return;
    final reviews = state.reviewsForMovie(widget.movieId);
    final targetIdx = reviews.indexWhere((r) => r.id == targetId);
    if (targetIdx == -1) return;
    setState(() {
      _page = targetIdx ~/ 5;
      _expandedId = targetId;
    });
    _loadComments(targetId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _scrollTo(targetId);
      });
    });
  }

  void _scrollTo(String reviewId) {
    final ctx = _reviewKeys[reviewId]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  Future<void> _loadComments(String reviewId) async {
    if (_commentsLoading[reviewId] == true) return;
    if (mounted) setState(() => _commentsLoading[reviewId] = true);
    try {
      final data = await ApiService.fetchReviewComments(reviewId);
      final userId = context.read<AppState>().currentUser?.id;
      final comments = data.map((d) => _commentFromJson(d, userId)).toList();
      if (mounted) setState(() {
        _comments[reviewId] = comments;
        _commentsLoading[reviewId] = false;
      });
    } catch (_) {
      if (mounted) setState(() => _commentsLoading[reviewId] = false);
    }
  }

  ReviewComment _commentFromJson(Map<String, dynamic> d, String? myId) =>
      ReviewComment(
        id: d['id'] as String,
        reviewId: d['reviewId'] as String? ?? widget.movieId,
        byId: d['byId'] as String? ?? '',
        byName: d['byName'] as String? ?? '',
        byHandle: d['byHandle'] as String? ?? '',
        byAvatarColor: Colors.grey,
        byAvatarUrl: d['byAvatarUrl'] as String?,
        text: d['text'] as String? ?? '',
        likes: (d['likes'] as num?)?.toInt() ?? 0,
        likedByMe: d['likedBy'] is List
            ? (d['likedBy'] as List).contains(myId)
            : false,
        at: DateTime.tryParse(d['at'] as String? ?? '') ?? DateTime.now(),
      );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final userId = state.currentUser?.id;
    final allReviews = state.reviewsForMovie(widget.movieId);

    final filtered = _search.isEmpty
        ? allReviews
        : allReviews
            .where((r) =>
                r.byName.toLowerCase().contains(_search.toLowerCase()) ||
                r.text.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    const kPerPage = 5;
    final pageCount = filtered.isEmpty ? 1 : (filtered.length / kPerPage).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final visible = filtered.skip(page * kPerPage).take(kPerPage).toList();

    for (final r in visible) {
      _reviewKeys.putIfAbsent(r.id, () => GlobalKey());
      _replyCtrl.putIfAbsent(r.id, () => TextEditingController());
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: MC.line, thickness: 0.5),
          const SizedBox(height: 16),
          Row(children: [
            Text('KUVACULT REVIEWS',
                style: MT.mono(size: 10, letterSpacing: 2, color: MC.kuvacultScore)),
            const Spacer(),
            Text('${allReviews.length}',
                style: MT.mono(size: 10, letterSpacing: 0, color: MC.kuvacultScore)),
          ]),
          if (allReviews.length > 3) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() { _search = v; _page = 0; }),
              style: const TextStyle(color: MC.ink, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search reviews…',
                hintStyle: const TextStyle(color: MC.dim, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: MC.dim, size: 16),
                filled: true,
                fillColor: MC.bg1,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: MC.line, width: 0.5)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: MC.line, width: 0.5)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: MC.kuvacultScore, width: 1)),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _search.isEmpty ? 'No reviews yet.' : 'No reviews match your search.',
                style: const TextStyle(color: MC.dim, fontSize: 13),
              ),
            )
          else
            ...visible.map((r) => _buildReviewCard(context, r, userId, state)),
          if (pageCount > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _pageBtn(
                  icon: Icons.chevron_left_rounded,
                  enabled: page > 0,
                  onTap: () => setState(() => _page = page - 1),
                ),
                const SizedBox(width: 12),
                Text('${page + 1} / $pageCount',
                    style: MT.mono(size: 11, letterSpacing: 0)),
                const SizedBox(width: 12),
                _pageBtn(
                  icon: Icons.chevron_right_rounded,
                  enabled: page < pageCount - 1,
                  onTap: () => setState(() => _page = page + 1),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _pageBtn({required IconData icon, required bool enabled, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? MC.bg1 : MC.bg2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: MC.line, width: 0.5),
          ),
          child: Icon(icon, color: enabled ? MC.ink : MC.dim, size: 16),
        ),
      );

  Widget _buildReviewCard(BuildContext context, Review r, String? userId, AppState state) {
    final isExpanded = _expandedId == r.id;
    _reviewKeys.putIfAbsent(r.id, () => GlobalKey());

    return KeyedSubtree(
      key: _reviewKeys[r.id],
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GestureDetector(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedId = null;
              } else {
                _expandedId = r.id;
                _commentsVisible.remove(r.id); // reset to 3 on each expand
                if (_comments[r.id] == null) _loadComments(r.id);
              }
            });
            if (!isExpanded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Future.delayed(const Duration(milliseconds: 150), () {
                  if (mounted) _scrollTo(r.id);
                });
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isExpanded ? MC.bg2 : MC.bg1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isExpanded ? MC.kuvacultScore.withAlpha(80) : MC.line,
                width: isExpanded ? 1 : 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => UserProfileScreen(
                            userId: r.byId, initialName: r.byName))),
                    child: Row(children: [
                      _reviewAvatar(r),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.byName,
                              style: const TextStyle(fontSize: 12, color: MC.ink,
                                  fontWeight: FontWeight.w600)),
                          _MiniStars(stars: r.stars),
                        ],
                      ),
                    ]),
                  ),
                  const Spacer(),
                  Text(_timeAgo(r.at),
                      style: MT.mono(size: 9, letterSpacing: 0, color: MC.dim)),
                  if (userId == r.byId) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final ok = await _confirmDelete(context, 'Delete review?');
                        if (ok && mounted) state.deleteReview(r.id);
                      },
                      child: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent, size: 14),
                    ),
                  ],
                ]),
                if (r.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ExpandableReviewText(
                    text: r.text,
                    style: const TextStyle(fontSize: 12, color: MC.ink, height: 1.45),
                    collapsedLines: isExpanded ? 15 : 3,
                  ),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  GestureDetector(
                    onTap: userId != null ? () => state.likeReview(r.id) : null,
                    child: Row(children: [
                      Icon(
                        r.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: r.likedByMe ? MC.accent1 : MC.dim, size: 14),
                      const SizedBox(width: 4),
                      Text('${r.likes}',
                          style: MT.mono(size: 10, letterSpacing: 0,
                              color: r.likedByMe ? MC.accent1 : MC.dim)),
                    ]),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.mode_comment_outlined, color: MC.dim, size: 13),
                  const SizedBox(width: 4),
                  Text('${r.commentCount}',
                      style: MT.mono(size: 10, letterSpacing: 0, color: MC.dim)),
                  const Spacer(),
                  if (!isExpanded)
                    Text('tap to expand',
                        style: MT.mono(size: 9, letterSpacing: 0, color: MC.dim)),
                ]),
                if (isExpanded) ...[
                  const SizedBox(height: 12),
                  Divider(color: MC.line, thickness: 0.5),
                  const SizedBox(height: 8),
                  _buildCommentSection(context, r, userId, state),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommentSection(BuildContext context, Review r, String? userId, AppState state) {
    final loading = _commentsLoading[r.id] == true;
    final comments = _comments[r.id] ?? [];
    final ctrl = _replyCtrl[r.id]!;
    final visible = _commentsVisible[r.id] ?? 3;
    final shown = comments.take(visible).toList();
    final remaining = comments.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: MC.mute)),
            ),
          )
        else if (comments.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('No replies yet.',
                style: const TextStyle(color: MC.dim, fontSize: 12,
                    fontStyle: FontStyle.italic)),
          )
        else ...[
          ...shown.map((c) => _buildComment(context, r.id, c, userId, state)),
          if (remaining > 0)
            GestureDetector(
              onTap: () => setState(() =>
                  _commentsVisible[r.id] = visible + 3),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'View ${remaining > 3 ? 3 : remaining} more repl${remaining == 1 ? "y" : "ies"}',
                  style: MT.mono(size: 11, letterSpacing: 0, color: MC.accent1),
                ),
              ),
            ),
        ],
        if (userId != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AvatarWidget(memberId: userId, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: ctrl,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(color: MC.ink, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Add a reply…',
                    hintStyle: const TextStyle(color: MC.dim, fontSize: 12),
                    filled: true,
                    fillColor: MC.bg1,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: MC.line, width: 0.5)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: MC.line, width: 0.5)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: MC.kuvacultScore, width: 1)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final text = ctrl.text.trim();
                  if (text.isEmpty) return;
                  ctrl.clear();
                  try {
                    final data = await ApiService.postReviewComment(
                        reviewId: r.id, byId: userId, text: text);
                    final myId = context.read<AppState>().currentUser?.id;
                    final comment = _commentFromJson(
                        {...data, 'likedBy': <dynamic>[]}, myId);
                    if (mounted) {
                      setState(() {
                        _comments[r.id] = [...(_comments[r.id] ?? []), comment];
                        // Ensure the new reply is within the visible window
                        final total = _comments[r.id]!.length;
                        final cur = _commentsVisible[r.id] ?? 3;
                        if (total > cur) _commentsVisible[r.id] = total;
                      });
                      context.read<AppState>().incrementReviewCommentCount(r.id);
                    }
                  } catch (_) {}
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: MC.kuvacultScore.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: MC.kuvacultScore, size: 14),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildComment(BuildContext context, String reviewId, ReviewComment c,
      String? userId, AppState state) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _commentAvatar(c),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(c.byName,
                      style: const TextStyle(
                          fontSize: 11, color: MC.ink,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Text(_timeAgo(c.at),
                      style: MT.mono(size: 9, letterSpacing: 0, color: MC.dim)),
                  const Spacer(),
                  GestureDetector(
                    onTap: userId != null
                        ? () => _likeComment(reviewId, c, userId)
                        : null,
                    child: Row(children: [
                      Icon(
                        c.likedByMe
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: c.likedByMe ? MC.accent1 : MC.dim,
                        size: 12,
                      ),
                      const SizedBox(width: 3),
                      Text('${c.likes}',
                          style: MT.mono(size: 9, letterSpacing: 0,
                              color: c.likedByMe ? MC.accent1 : MC.dim)),
                    ]),
                  ),
                  if (userId == c.byId) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final ok = await _confirmDelete(context, 'Delete reply?');
                        if (ok && mounted) _deleteComment(reviewId, c);
                      },
                      child: const Icon(Icons.delete_outline_rounded,
                          color: Colors.redAccent, size: 12),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                ExpandableReviewText(
                  text: c.text,
                  style: const TextStyle(
                      fontSize: 12, color: MC.mute, height: 1.4),
                  collapsedLines: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _likeComment(String reviewId, ReviewComment c, String userId) async {
    final comments = _comments[reviewId];
    if (comments == null) return;
    final idx = comments.indexWhere((x) => x.id == c.id);
    if (idx == -1) return;
    final wasLiked = comments[idx].likedByMe;
    setState(() {
      comments[idx].likedByMe = !wasLiked;
      comments[idx].likes += wasLiked ? -1 : 1;
    });
    try {
      final data = await ApiService.likeReviewComment(reviewId, c.id, userId);
      if (mounted) setState(() {
        final newLikes = (data['likes'] as num?)?.toInt();
        if (newLikes != null) comments[idx].likes = newLikes;
        if (data['likedBy'] is List) {
          comments[idx].likedByMe =
              (data['likedBy'] as List).contains(userId);
        }
      });
    } catch (_) {
      if (mounted) setState(() {
        comments[idx].likedByMe = wasLiked;
        comments[idx].likes += wasLiked ? 1 : -1;
      });
    }
  }

  void _deleteComment(String reviewId, ReviewComment c) async {
    final comments = _comments[reviewId];
    if (comments == null) return;
    final idx = comments.indexWhere((x) => x.id == c.id);
    if (idx == -1) return;
    setState(() => comments.removeAt(idx));
    try {
      await ApiService.deleteReviewComment(reviewId, c.id);
      context.read<AppState>().decrementReviewCommentCount(reviewId);
    } catch (_) {
      if (mounted) setState(() => comments.insert(idx, c));
    }
  }

  Future<bool> _confirmDelete(BuildContext context, String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: MC.bg1,
          title: Text(title,
              style: const TextStyle(color: MC.ink, fontSize: 16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(color: MC.mute)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ) ??
      false;

  Widget _reviewAvatar(Review r) {
    final initial = r.byName.isNotEmpty ? r.byName[0].toUpperCase() : '?';
    // Fall back to the live member profile cache when the review's stored URL is
    // stale (e.g. user uploaded an avatar after writing the review).
    final profileUrl = context.read<AppState>().memberProfiles[r.byId]?.avatarUrl;
    final rawUrl = (r.byAvatarUrl?.isNotEmpty == true) ? r.byAvatarUrl : profileUrl;
    if (rawUrl != null && rawUrl.isNotEmpty) {
      final url = rawUrl.startsWith('/') ? '${Config.httpBase}$rawUrl' : rawUrl;
      return ClipOval(
        child: AppImage(
            imageUrl: url,
            width: 26,
            height: 26,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) =>
                _avatarCircle(initial, r.byAvatarColor)),
      );
    }
    return _avatarCircle(initial, r.byAvatarColor);
  }

  Widget _commentAvatar(ReviewComment c) {
    final initial = c.byName.isNotEmpty ? c.byName[0].toUpperCase() : '?';
    if (c.byAvatarUrl != null && c.byAvatarUrl!.isNotEmpty) {
      final url = c.byAvatarUrl!.startsWith('/')
          ? '${Config.httpBase}${c.byAvatarUrl}'
          : c.byAvatarUrl!;
      return ClipOval(
        child: AppImage(
            imageUrl: url,
            width: 22,
            height: 22,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) =>
                _avatarCircle(initial, c.byAvatarColor, size: 22)),
      );
    }
    return _avatarCircle(initial, c.byAvatarColor, size: 22);
  }

  Widget _avatarCircle(String initial, Color color, {double size = 26}) =>
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        alignment: Alignment.center,
        child: Text(initial,
            style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w700,
                color: MC.accentInk)),
      );
}

class _MiniStars extends StatelessWidget {
  final double stars;
  const _MiniStars({required this.stars});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = (i + 1) <= stars;
        final half = !filled && (i + 0.5) <= stars;
        return Icon(
          half ? Icons.star_half_rounded
              : filled ? Icons.star_rounded
              : Icons.star_border_rounded,
          size: 11,
          color: MC.kuvacultScore,
        );
      }),
    );
  }
}
