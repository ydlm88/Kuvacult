import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models.dart';
import '../mock_data.dart';
import '../app_state.dart';
import '../widgets/poster.dart';
import '../widgets/avatar.dart';
import '../widgets/stream_badge.dart';
import '../widgets/star_rating.dart';
import '../widgets/tag.dart';
import '../widgets/watchlist_picker.dart';
import '../widgets/sign_in_sheet.dart';
import 'community_reviews.dart';

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
  const DetailScreen({super.key, required this.movie});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _noteCtrl = TextEditingController();
  bool _showNoteInput = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Use the live watchlist copy if available; fall back to the passed-in movie
    final movie = state.findMovie(widget.movie.id) ?? widget.movie;
    // The current user's ID drives all mutations — never hardcode a member name
    final userId = state.currentUser?.id ?? 'guest';

    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHero(context, movie)),
          SliverToBoxAdapter(child: _buildTitleBlock(context, movie, state, userId)),
          SliverToBoxAdapter(child: _buildRatings(context, movie, userId, state)),
          SliverToBoxAdapter(child: _buildNotes(context, movie, userId, state)),
          SliverToBoxAdapter(child: _buildCommunityReviews(context, movie, state)),
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
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Share not yet implemented',
                          style: TextStyle(color: MC.ink, fontSize: 13)),
                      backgroundColor: MC.bg1,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ));
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
                    (s) => s.marqueeScore(movie.id));
                if (score == 0.0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '◆ ${score.toStringAsFixed(1)}',
                    style: MT.mono(
                        size: 12, color: MC.marqueeScore, letterSpacing: 0),
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

          // ── Action buttons ──────────────────────────────────────────────────
          Row(
            children: [
              // Mark as watched — adds to watchlist first if needed
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    if (await _requireWatchlist(context, state)) {
                      _markWatched(context, movie, state);
                    }
                  },
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [MC.accent1, MC.accent2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      inWatchlist && movie.section == WatchSection.watched
                          ? 'Watched ✓'
                          : 'Mark as watched',
                      style: const TextStyle(
                        color: MC.accentInk,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Add to a watchlist — always shows picker so user chooses which list
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

              // Mark as watching
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

              // React button
              GestureDetector(
                onTap: () async {
                  if (await _requireWatchlist(context, state)) {
                    _showReactionSheet(context, movie, userId, state);
                  }
                },
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: MC.bg1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.favorite_border_rounded,
                      color: MC.accent1, size: 18),
                ),
              ),
              const SizedBox(width: 10),

              // Write review button
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
                    color: MC.marqueeScore.withAlpha(20),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MC.marqueeScore.withAlpha(80), width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.rate_review_outlined,
                      color: MC.marqueeScore, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildRatings(BuildContext context, Movie movie, String userId, AppState state) {
    // Shows only the current user's rating row.
    // TODO(backend): When room members are loaded, iterate state.watchlist.memberIds
    // and show a rating row for each member.
    final reaction = movie.reactions[userId];
    final double? stars = movie.stars[userId];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: MC.line, thickness: 0.5),
          const SizedBox(height: 16),
          Text('YOUR RATING', style: MT.mono(size: 10, letterSpacing: 2)),
          const SizedBox(height: 14),
          Row(
            children: [
              AvatarWidget(memberId: userId, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.currentUser?.displayName ?? 'Guest',
                      style: const TextStyle(
                          fontSize: 13, color: MC.ink, fontWeight: FontWeight.w500),
                    ),
                    if (reaction != null)
                      Text(reaction.label,
                          style: MT.mono(size: 10, letterSpacing: 1, color: MC.dim)),
                  ],
                ),
              ),
              // Tap existing stars to re-rate; tap "Rate" to open rating sheet
              GestureDetector(
                onTap: () async {
                  if (await _requireWatchlist(context, state)) {
                    _showRatingSheet(context, movie, userId, state);
                  }
                },
                child: stars != null
                    ? StarDisplay(value: stars, size: 12, color: MC.accent1)
                    : Text('Rate',
                        style: MT.mono(size: 11, color: MC.accent1, letterSpacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: MC.line, thickness: 0.5),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildNotes(BuildContext context, Movie movie, String userId, AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NOTES', style: MT.mono(size: 10, letterSpacing: 2)),
          const SizedBox(height: 14),

          if (movie.notes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No notes yet. Start the conversation.',
                style: TextStyle(
                    fontSize: 12, color: MC.dim, fontStyle: FontStyle.italic),
              ),
            ),

          ...movie.notes.map((note) {
            final member = kMembers[note.by] ??
                (state.currentUser?.id == note.by
                    ? Member(
                        id: note.by,
                        name: state.currentUser!.displayName,
                        initial: state.currentUser!.displayName.isNotEmpty
                            ? state.currentUser!.displayName[0].toUpperCase()
                            : '?',
                        avatarBg: state.currentUser!.avatarBg,
                      )
                    : null);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AvatarWidget(memberId: note.by, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MC.bg1,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: MC.line, width: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                member?.name ?? note.by,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: MC.ink,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 8),
                              Text(_timeAgo(note.at),
                                  style: MT.mono(size: 10, letterSpacing: 0)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(note.text,
                              style: const TextStyle(
                                  fontSize: 13, color: MC.ink, height: 1.45)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),

          // Note input
          if (_showNoteInput) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              autofocus: true,
              maxLines: 3,
              style: const TextStyle(color: MC.ink, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Add a note…',
                hintStyle: const TextStyle(color: MC.dim),
                filled: true,
                fillColor: MC.bg1,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: MC.accent1, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: MC.accent1, width: 1),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _showNoteInput = false),
                  child: const Text('Cancel', style: TextStyle(color: MC.mute)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MC.accent1,
                    foregroundColor: MC.accentInk,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    if (_noteCtrl.text.trim().isNotEmpty) {
                      // Ensure movie is in watchlist before adding a note
                      _ensureInWatchlist(movie, state);
                      state.addNote(movie.id, userId, _noteCtrl.text.trim());
                      _noteCtrl.clear();
                      setState(() => _showNoteInput = false);
                    }
                  },
                  child: const Text('Post'),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                if (await _requireWatchlist(context, state)) {
                  setState(() => _showNoteInput = true);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: MC.bg1,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MC.line, width: 0.5),
                ),
                child: Row(
                  children: [
                    AvatarWidget(memberId: userId, size: 22),
                    const SizedBox(width: 10),
                    const Text('Add a note…',
                        style: TextStyle(fontSize: 13, color: MC.dim)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCommunityReviews(
      BuildContext context, Movie movie, AppState state) {
    final reviews = state.reviewsForMovie(movie.id);
    if (reviews.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: MC.line, thickness: 0.5),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('MARQUEE REVIEWS',
                  style: MT.mono(size: 10, letterSpacing: 2,
                      color: MC.marqueeScore)),
              const Spacer(),
              Text('${reviews.length}',
                  style: MT.mono(size: 10, letterSpacing: 0,
                      color: MC.marqueeScore)),
            ],
          ),
          const SizedBox(height: 14),
          ...reviews.take(3).map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MC.bg1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _reviewAvatar(r),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.byName,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: MC.ink,
                                      fontWeight: FontWeight.w600)),
                              _MiniStars(stars: r.stars),
                            ],
                          ),
                        ),
                        Text(_timeAgo(r.at),
                            style: MT.mono(size: 9, letterSpacing: 0,
                                color: MC.dim)),
                      ]),
                      if (r.text.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(r.text,
                            style: const TextStyle(
                                fontSize: 12, color: MC.ink, height: 1.45),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _reviewAvatar(Review r) {
    final initial = r.byName.isNotEmpty ? r.byName[0].toUpperCase() : '?';
    if (r.byAvatarUrl != null && r.byAvatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(r.byAvatarUrl!, width: 26, height: 26,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _avatarCircle(initial, r.byAvatarColor)),
      );
    }
    return _avatarCircle(initial, r.byAvatarColor);
  }

  Widget _avatarCircle(String initial, Color color) => Container(
        width: 26, height: 26,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        alignment: Alignment.center,
        child: Text(initial,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: MC.accentInk)),
      );

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
    // If movie isn't in the watchlist yet, add it directly as 'watched'
    if (state.findMovie(movie.id) == null) {
      state.addMovieToWatchlist(movie);
      state.moveMovie(movie.id, WatchSection.watched);
      return;
    }
    final newSection = movie.section == WatchSection.watched
        ? WatchSection.want
        : WatchSection.watched;
    state.moveMovie(movie.id, newSection);
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
              // Numeric display — syncs with star selection
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

  void _showReactionSheet(BuildContext context, Movie movie, String userId, AppState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('React', style: MT.display(size: 22)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: ReactionType.values.map((r) {
                return GestureDetector(
                  onTap: () {
                    // Add to watchlist first so the mutation doesn't throw
                    _ensureInWatchlist(movie, state);
                    state.reactToMovie(movie.id, userId, r);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: MC.bg2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: movie.reactions[userId] == r
                            ? MC.accent1
                            : MC.line,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      '${r.mark}  ${r.label}',
                      style: TextStyle(
                        color: movie.reactions[userId] == r
                            ? MC.accent1
                            : MC.ink,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],
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
                state.addMovieToWatchlist(movie);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
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
          color: MC.marqueeScore,
        );
      }),
    );
  }
}
