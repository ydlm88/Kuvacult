import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models.dart';
import '../app_state.dart';
import '../widgets/poster.dart';
import '../widgets/stream_badge.dart';
import '../widgets/section_header.dart';
import '../widgets/watchlist_picker.dart';
import 'detail.dart';
import 'dart:async';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

// Predefined genre list 
const _kGenres = [
  'Action', 'Adventure', 'Animation', 'Comedy', 'Crime',
  'Documentary', 'Drama', 'Fantasy', 'Horror', 'Mystery',
  'Romance', 'Sci-Fi', 'Thriller', 'Western',
];

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _trendingScroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onCtrlChanged);
    // Retry if trending failed on startup
    final state = context.read<AppState>();
    if (state.trendingMovies.isEmpty) {
      state.loadTrending();
    }
  }

  void _onCtrlChanged() => setState(() {});

  void _onSearchChanged(String q, AppState state) {
    _debounce?.cancel();
    if (q.isEmpty) {
      state.setSearchQuery('');
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      state.setSearchQuery(q);
    });
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChanged);
    _debounce?.cancel();
    _ctrl.dispose();
    _trendingScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only watch the specific fields we need — avoids rebuilding on unrelated changes
    final searchLoading = context.select<AppState, bool>((s) => s.searchLoading);
    final searchQuery = context.select<AppState, String>((s) => s.searchQuery);
    final searchResults = context.select<AppState, List<Movie>>((s) => s.searchResults);
    final trendingMovies = context.select<AppState, List<Movie>>((s) => s.trendingMovies);
    final trendingLoading = context.select<AppState, bool>((s) => s.trendingLoading);
    final hasNext = context.select<AppState, bool>((s) => s.searchHasNextPage);
    final hasPrev = context.select<AppState, bool>((s) => s.searchHasPrevPage);
    final pageNum = context.select<AppState, int>((s) => s.searchPageNumber);
    final selectedGenre = context.select<AppState, String?>((s) => s.selectedGenre);
    final genreLoading = context.select<AppState, bool>((s) => s.genreLoading);
    final genreResults = context.select<AppState, List<Movie>>((s) => s.genreResults);
    final state = context.read<AppState>();

    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        // Cache more of the list off-screen to reduce build stutters during scroll
        cacheExtent: 400,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 62, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add to The Queue',
                      style: MT.mono(size: 10, letterSpacing: 2)),
                  const SizedBox(height: 4),
                  Text('Search', style: MT.display(size: 34)),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                        controller: _ctrl,
                        onChanged: (q) => _onSearchChanged(q, state),
                        style: const TextStyle(
                            color: MC.ink,
                            fontSize: 15,
                            letterSpacing: -0.2),
                        decoration: const InputDecoration(
                          hintText: 'Title or director…',
                          hintStyle: TextStyle(color: MC.dim),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                        cursorColor: MC.accent1,
                      ),
                    ),
                    if (_ctrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _debounce?.cancel();
                          _ctrl.clear();
                          state.setSearchQuery('');
                        },
                        child: const Icon(Icons.close_rounded,
                            color: MC.dim, size: 16),
                      ),
                    const SizedBox(width: 4),
                    Text('IMDb', style: MT.mono(size: 10, letterSpacing: 1)),
                  ],
                ),
              ),
            ),
          ),

          // (debounce pending) AND during the actual API fetch.
          if (searchLoading || (_ctrl.text.isNotEmpty && _ctrl.text != searchQuery))
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                  child: CircularProgressIndicator(
                      color: MC.accent1, strokeWidth: 2),
                ),
              ),
            )

          //state.searchResults populates after debounce
          else if (_ctrl.text.isNotEmpty) ...[
            if (searchResults.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    'No results. Try a different title.',
                    style: TextStyle(color: MC.dim, fontSize: 13),
                  ),
                ),
              )
            else ...[
              // Results header + page indicator
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Row(
                    children: [
                      Text('RESULTS',
                          style: MT.mono(size: 10, letterSpacing: 2)),
                      const Spacer(),
                      if (hasPrev || hasNext)
                        Text('PAGE $pageNum',
                            style: MT.mono(
                                size: 10,
                                letterSpacing: 1,
                                color: MC.dim)),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => RepaintBoundary(
                    child: _SearchResultRow(
                      movie: searchResults[i],
                      onAdd: () =>
                          _addMovie(context, searchResults[i]),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                DetailScreen(movie: searchResults[i])),
                      ),
                    ),
                  ),
                  childCount: searchResults.length,
                  addRepaintBoundaries: false, // we add them manually above
                ),
              ),

              if (hasPrev || hasNext)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        // Previous page
                        Expanded(
                          child: GestureDetector(
                            onTap: hasPrev ? state.prevSearchPage : null,
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: hasPrev ? MC.bg1 : MC.bg2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: MC.line, width: 0.5),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.chevron_left_rounded,
                                      color: MC.mute, size: 18),
                                  Text('Prev',
                                      style: TextStyle(
                                          color: hasPrev
                                              ? MC.ink
                                              : MC.dim,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Next page
                        Expanded(
                          child: GestureDetector(
                            onTap: hasNext ? state.nextSearchPage : null,
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: hasNext ? MC.bg1 : MC.bg2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: MC.line, width: 0.5),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Text('Next',
                                      style: TextStyle(
                                          color: hasNext
                                              ? MC.ink
                                              : MC.dim,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500)),
                                  const Icon(Icons.chevron_right_rounded,
                                      color: MC.mute, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ]

          else if (selectedGenre != null) ...[
            // Active genre filter header with clear button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: MC.accent1,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(selectedGenre,
                              style: MT.mono(size: 11, color: MC.accentInk, letterSpacing: 1)),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => state.clearGenreSearch(),
                            child: const Icon(Icons.close_rounded, color: MC.accentInk, size: 14),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text('GENRE', style: MT.mono(size: 10, letterSpacing: 2)),
                  ],
                ),
              ),
            ),

            if (genreLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(color: MC.accent1, strokeWidth: 2),
                  ),
                ),
              )
            else if (genreResults.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Text(
                    'No results for this genre.',
                    style: TextStyle(color: MC.dim, fontSize: 13),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => RepaintBoundary(
                    child: _SearchResultRow(
                      movie: genreResults[i],
                      onAdd: () => _addMovie(context, genreResults[i]),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => DetailScreen(movie: genreResults[i])),
                      ),
                    ),
                  ),
                  childCount: genreResults.length,
                  addRepaintBoundaries: false,
                ),
              ),
          ]

          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 24, 0, 10),
                child: SectionHeader(title: 'Trending'),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 250,
                child: trendingLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: MC.accent1, strokeWidth: 2),
                      )
                    : trendingMovies.isEmpty
                    ? Center(
                        child: GestureDetector(
                          onTap: () => context.read<AppState>().loadTrending(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.refresh_rounded, color: MC.dim, size: 20),
                              const SizedBox(height: 6),
                              const Text(
                                'Couldn\'t load · tap to retry',
                                style: TextStyle(color: MC.dim, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    // ScrollConfiguration lets the mouse button drag the list.
                    // Listener translates mouse-wheel vertical delta -> horizontal scroll.
                    : ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                    },
                  ),
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent &&
                          _trendingScroll.hasClients) {
                        _trendingScroll.jumpTo(
                          (_trendingScroll.offset + event.scrollDelta.dy)
                              .clamp(0.0, _trendingScroll.position.maxScrollExtent),
                        );
                      }
                    },
                    child: ListView.separated(
                      controller: _trendingScroll,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemCount: trendingMovies.length,
                      itemBuilder: (ctx, i) {
                        final m = trendingMovies[i];
                        return GestureDetector(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => DetailScreen(movie: m))),
                          child: RepaintBoundary(
                            child: SizedBox(
                              width: 120,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  PosterWidget(movie: m, width: 120, height: 180),
                                  const SizedBox(height: 8),
                                  Text(m.title,
                                      style: const TextStyle(
                                          color: MC.ink,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.2),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  Text('${m.year}',
                                      style: MT.mono(size: 10, letterSpacing: 0)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            // Genre 
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 28, 0, 8),
                child: SectionHeader(title: 'Browse by genre'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _GenreChip(
                    genre: _kGenres[i],
                    isSelected: selectedGenre == _kGenres[i],
                    onTap: () => state.searchByGenre(_kGenres[i]),
                  ),
                  childCount: _kGenres.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.5,
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  void _addMovie(BuildContext context, Movie movie) {
    showWatchlistPicker(context, movie);
  }
}

class _SearchResultRow extends StatelessWidget {
  final Movie movie;
  final VoidCallback onAdd;
  final VoidCallback onTap;

  const _SearchResultRow({
    required this.movie,
    required this.onAdd,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Check membership across all watchlists so removed movies re-enable the button.
    final inQueue = context.select<AppState, bool>(
        (s) => s.isInAnyQueue(movie.id));

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            PosterWidget(movie: movie, width: 44, height: 66),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    style: MT.display(
                        size: 16, letterSpacing: -0.3, height: 1.1),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    movie.director.isNotEmpty
                        ? '${movie.director}  ·  ${movie.year}'
                        : '${movie.year}',
                    style: const TextStyle(fontSize: 11, color: MC.mute),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      StreamBadgeWidget(streamId: movie.streamId),
                      const SizedBox(width: 6),
                      Text(
                        movie.rating > 0 ? '★ ${movie.rating}' : '★ —',
                        style: MT.mono(
                            size: 10, color: MC.accent1, letterSpacing: 0),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: inQueue ? null : onAdd,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: inQueue ? MC.bg2 : MC.accent1.withAlpha(21),
                  border: Border.all(
                    color: inQueue ? MC.line : MC.accent1,
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  inQueue ? Icons.check_rounded : Icons.add_rounded,
                  color: inQueue ? MC.dim : MC.accent1,
                  size: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  final String genre;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenreChip({
    required this.genre,
    required this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? MC.accent1 : MC.bg1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected ? MC.accent1 : MC.line, width: 0.5),
        ),
        alignment: Alignment.center,
        child: Text(
          genre,
          style: TextStyle(
            color: isSelected ? MC.accentInk : MC.mute,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
