// watchlist.dart — Displays the active watchlist's movies across Want/Watching/Watched sections with sort, genre filter, grid/list toggle, random pick, and inline invite sheet.
import 'dart:math';

import 'package:flutter/material.dart';
import '../widgets/app_image.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models.dart';
import '../app_state.dart';
import '../widgets/avatar.dart';
import '../widgets/poster.dart';
import '../widgets/stream_badge.dart';
import '../widgets/watch_row.dart';
import '../widgets/section_header.dart';
import '../widgets/tag.dart';
import '../widgets/kuvacult_loader.dart';
import 'detail.dart';
import 'watchlists.dart';
import '../utils/top_toast.dart';

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  WatchSection _section = WatchSection.want;
  final ScrollController _scrollCtrl = ScrollController();
  String _movieSearch = '';
  final _movieSearchCtrl = TextEditingController();
  int _page = 0;
  static const int _kPageSize = 15;

  bool _loading = false;
  bool _prevGridView = false;
  WatchSection _prevSection = WatchSection.want;
  String? _draggingMovieId;

  @override
  void initState() {
    super.initState();
    // Show loader on first open so posters never flash in cold.
    _loading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _movieSearchCtrl.dispose();
    super.dispose();
  }

  void _switchSection(WatchSection s) {
    setState(() {
      _section = s;
      _movieSearch = '';
      _page = 0;
    });
    _movieSearchCtrl.clear();
    _scrollCtrl.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final watchlist = state.activeWatchlist;

    // Guard, if no list is active, go back
    if (watchlist == null) {
      return Scaffold(
        backgroundColor: MC.bg0,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No list selected.', style: MT.display(size: 20, color: MC.mute)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.pushReplacement(
                    context, MaterialPageRoute(builder: (_) => const WatchlistsScreen())),
                child: Text('Go to your lists',
                    style: TextStyle(color: MC.accent1, fontSize: 14)),
              ),
            ],
          ),
        ),
      );
    }

    final gridView = state.getGridView(watchlist.id);

    // Trigger loader on grid/list toggle or section switch.
    // Set _loading synchronously so the loader renders on this very frame.
    if (gridView != _prevGridView || _section != _prevSection) {
      _loading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) setState(() => _loading = false);
      });
    }
    _prevGridView = gridView;
    _prevSection = _section;

    final allMovies = state.moviesForSection(_section);
    final movies = _movieSearch.isEmpty
        ? allMovies
        : allMovies
            .where((m) => m.title
                .toLowerCase()
                .contains(_movieSearch.toLowerCase()))
            .toList();
    return Scaffold(
      backgroundColor: MC.bg0,
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context, watchlist, state)),
          SliverToBoxAdapter(child: _buildTabs(state, watchlist)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _movieSearchCtrl,
                style: const TextStyle(color: MC.ink, fontSize: 13),
                onChanged: (v) =>
                    setState(() { _movieSearch = v; _page = 0; }),
                decoration: InputDecoration(
                  hintText: 'Search movies…',
                  hintStyle: const TextStyle(color: MC.dim, fontSize: 13),
                  prefixIcon: const Icon(
                      Icons.search_rounded, color: MC.dim, size: 18),
                  suffixIcon: _movieSearch.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            setState(() { _movieSearch = ''; _page = 0; });
                            _movieSearchCtrl.clear();
                          },
                          child: const Icon(Icons.close_rounded,
                              color: MC.dim, size: 16),
                        )
                      : null,
                  filled: true,
                  fillColor: MC.bg1,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: MC.line, width: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: MC.line, width: 0.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: MC.accent1, width: 1),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topCenter,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              child: _loading
                  ? const SizedBox(
                      key: ValueKey('l'),
                      height: 420,
                      child: Center(child: KuvacultLoader()),
                    )
                  : KeyedSubtree(
                      key: ValueKey('c${_section.index}$gridView'),
                      child: gridView
                          ? _buildGridWidget(context, movies,
                              showTopPickBadge: _section == WatchSection.want)
                          : (_section == WatchSection.want
                              ? _buildWantWidget(context, movies)
                              : _buildListWidget(context, movies)),
                    ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildNoResultsSliver() => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 40, 20, 0),
          child: Center(
            child: Text('No movies match your search',
                style: TextStyle(color: MC.dim, fontSize: 13)),
          ),
        ),
      );

  List<Widget> _buildWantContent(BuildContext context, List<Movie> movies) {
    if (movies.isEmpty) {
      return [_movieSearch.isNotEmpty
          ? _buildNoResultsSliver()
          : SliverToBoxAdapter(child: _buildEmptyState())];
    }

    // When searching, skip the featured card and show a flat paginated list
    if (_movieSearch.isNotEmpty) {
      final pageCount = (movies.length / _kPageSize).ceil();
      final page = _page.clamp(0, pageCount - 1);
      final pageMovies =
          movies.skip(page * _kPageSize).take(_kPageSize).toList();
      return [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => Column(
              children: [
                WatchRow(
                  movie: pageMovies[i],
                  onTap: () => _openDetail(context, pageMovies[i]),
                ),
                if (i < pageMovies.length - 1)
                  Divider(color: MC.line, height: 0.5, thickness: 0.5),
              ],
            ),
            childCount: pageMovies.length,
          ),
        ),
        if (pageCount > 1) _buildPaginationSliver(page, pageCount),
      ];
    }

    // Default: featured hero + paginated rest of queue
    final featured = movies.first;
    final rest = movies.length > 1 ? movies.sublist(1) : <Movie>[];
    final pageCount = rest.isEmpty ? 0 : (rest.length / _kPageSize).ceil();
    final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final pageMovies = rest.skip(page * _kPageSize).take(_kPageSize).toList();
    return [
      SliverToBoxAdapter(child: _buildFeatured(context, featured)),
      if (rest.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 4),
            child: SectionHeader(
              title: 'The rest of the queue',
              count: rest.length,
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => Column(
              children: [
                WatchRow(
                  movie: pageMovies[i],
                  onTap: () => _openDetail(context, pageMovies[i]),
                ),
                if (i < pageMovies.length - 1)
                  Divider(color: MC.line, height: 0.5, thickness: 0.5),
              ],
            ),
            childCount: pageMovies.length,
          ),
        ),
        if (pageCount > 1) _buildPaginationSliver(page, pageCount),
      ],
    ];
  }

  List<Widget> _buildListContent(BuildContext context, List<Movie> movies) {
    if (movies.isEmpty) {
      return [_movieSearch.isNotEmpty
          ? _buildNoResultsSliver()
          : SliverToBoxAdapter(child: _buildEmptyState())];
    }
    final pageCount = (movies.length / _kPageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final pageMovies = movies.skip(page * _kPageSize).take(_kPageSize).toList();
    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => Column(
            children: [
              WatchRow(
                movie: pageMovies[i],
                onTap: () => _openDetail(context, pageMovies[i]),
              ),
              if (i < pageMovies.length - 1)
                Divider(color: MC.line, height: 0.5, thickness: 0.5),
            ],
          ),
          childCount: pageMovies.length,
        ),
      ),
      if (pageCount > 1) _buildPaginationSliver(page, pageCount),
    ];
  }

  Widget _buildWantWidget(BuildContext context, List<Movie> movies) {
    final isOrdered = context.read<AppState>().activeWatchlist?.isOrdered ?? false;
    if (movies.isEmpty) {
      return _movieSearch.isNotEmpty
          ? const Padding(
              padding: EdgeInsets.fromLTRB(20, 40, 20, 0),
              child: Center(child: Text('No movies match your search',
                  style: TextStyle(color: MC.dim, fontSize: 13))),
            )
          : _buildEmptyState();
    }
    if (_movieSearch.isNotEmpty) {
      final pageCount = (movies.length / _kPageSize).ceil();
      final page = _page.clamp(0, pageCount - 1);
      final pageMovies = movies.skip(page * _kPageSize).take(_kPageSize).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...List.generate(pageMovies.length, (i) => Column(children: [
            WatchRow(
              movie: pageMovies[i],
              onTap: () => _openDetail(context, pageMovies[i]),
              position: isOrdered ? page * _kPageSize + i + 1 : null,
            ),
            if (i < pageMovies.length - 1) Divider(color: MC.line, height: 0.5, thickness: 0.5),
          ])),
          if (pageCount > 1) _buildPaginationWidget(page, pageCount),
        ],
      );
    }
    final featured = movies.first;
    final rest = movies.length > 1 ? movies.sublist(1) : <Movie>[];
    final pageCount = rest.isEmpty ? 0 : (rest.length / _kPageSize).ceil();
    final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final pageMovies = rest.skip(page * _kPageSize).take(_kPageSize).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFeatured(context, featured, position: isOrdered ? 1 : null),
        if (rest.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 4),
            child: SectionHeader(title: 'The rest of the queue', count: rest.length),
          ),
          ...List.generate(pageMovies.length, (i) => Column(children: [
            WatchRow(
              movie: pageMovies[i],
              onTap: () => _openDetail(context, pageMovies[i]),
              position: isOrdered ? page * _kPageSize + i + 2 : null,
            ),
            if (i < pageMovies.length - 1) Divider(color: MC.line, height: 0.5, thickness: 0.5),
          ])),
          if (pageCount > 1) _buildPaginationWidget(page, pageCount),
        ],
      ],
    );
  }

  Widget _buildListWidget(BuildContext context, List<Movie> movies) {
    final isOrdered = context.read<AppState>().activeWatchlist?.isOrdered ?? false;
    if (movies.isEmpty) {
      return _movieSearch.isNotEmpty
          ? const Padding(
              padding: EdgeInsets.fromLTRB(20, 40, 20, 0),
              child: Center(child: Text('No movies match your search',
                  style: TextStyle(color: MC.dim, fontSize: 13))),
            )
          : _buildEmptyState();
    }
    final pageCount = (movies.length / _kPageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final pageMovies = movies.skip(page * _kPageSize).take(_kPageSize).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(pageMovies.length, (i) => Column(children: [
          WatchRow(
            movie: pageMovies[i],
            onTap: () => _openDetail(context, pageMovies[i]),
            position: isOrdered ? page * _kPageSize + i + 1 : null,
          ),
          if (i < pageMovies.length - 1) Divider(color: MC.line, height: 0.5, thickness: 0.5),
        ])),
        if (pageCount > 1) _buildPaginationWidget(page, pageCount),
      ],
    );
  }

  List<Widget> _buildGridContent(BuildContext context, List<Movie> movies, {bool showTopPickBadge = false}) {
    if (movies.isEmpty) {
      return [_movieSearch.isNotEmpty
          ? _buildNoResultsSliver()
          : SliverToBoxAdapter(child: _buildEmptyState())];
    }
    final pageCount = (movies.length / _kPageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final pageMovies =
        movies.skip(page * _kPageSize).take(_kPageSize).toList();
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: (MediaQuery.of(context).size.width / 160).floor().clamp(2, 8),
            crossAxisSpacing: 8,
            mainAxisSpacing: 12,
            childAspectRatio: MediaQuery.of(context).size.width < 480 ? 0.65 : 0.62,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, i) => RepaintBoundary(
              child: _PosterGridCell(
                movie: pageMovies[i],
                onTap: () => _openDetail(context, pageMovies[i]),
                isTopPick: showTopPickBadge && i == 0 && page == 0,
              ),
            ),
            childCount: pageMovies.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false,
          ),
        ),
      ),
      if (pageCount > 1) _buildPaginationSliver(page, pageCount),
    ];
  }

  Widget _buildGridWidget(BuildContext context, List<Movie> movies, {bool showTopPickBadge = false}) {
    final state = context.read<AppState>();
    final watchlist = state.activeWatchlist;
    final isOrdered = watchlist?.isOrdered ?? false;
    final canReorder = isOrdered && state.sortOrder == SortOrder.listOrder;

    if (movies.isEmpty) {
      return _movieSearch.isNotEmpty
          ? const Padding(
              padding: EdgeInsets.fromLTRB(20, 40, 20, 0),
              child: Center(
                child: Text('No movies match your search',
                    style: TextStyle(color: MC.dim, fontSize: 13)),
              ),
            )
          : _buildEmptyState();
    }
    final pageCount = (movies.length / _kPageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final pageMovies = movies.skip(page * _kPageSize).take(_kPageSize).toList();

    return LayoutBuilder(
      builder: (ctx, box) {
        const hPad = 16.0;
        const gap = 8.0;
        const textH = _PosterGridCell._textAreaHeight;
        final gridW = box.maxWidth - hPad * 2;
        final cols = (gridW / 140).round().clamp(2, 8);
        final cellW = (gridW - gap * (cols - 1)) / cols;
        final cellH = cellW * 1.5 + textH;

        Widget buildCell(int i) {
          final movie = pageMovies[i];
          final isSrc = _draggingMovieId == movie.id;
          final positionBadge = isOrdered ? (page * _kPageSize + i + 1) : null;
          final cell = _PosterGridCell(
            movie: movie,
            onTap: () => _openDetail(context, movie),
            isTopPick: showTopPickBadge && i == 0 && page == 0,
            position: positionBadge,
          );

          if (!canReorder) return cell;

          return DragTarget<String>(
            onWillAcceptWithDetails: (d) => d.data != movie.id,
            onAccept: (fromId) {
              if (fromId == movie.id || watchlist == null) return;
              _reorderWithinSection(fromId, movie.id, movies, state, watchlist);
            },
            builder: (ctx2, candidates, rejects) {
              final isHovered = candidates.isNotEmpty && !isSrc;
              return LongPressDraggable<String>(
                data: movie.id,
                feedback: SizedBox(
                  width: cellW,
                  height: cellH,
                  child: Opacity(
                    opacity: 0.9,
                    child: _PosterGridCell(
                      movie: movie,
                      onTap: () {},
                      isTopPick: false,
                      position: positionBadge,
                    ),
                  ),
                ),
                childWhenDragging: Opacity(
                  opacity: 0.4,
                  child: _PosterGridCell(
                    movie: movie,
                    onTap: () {},
                    isTopPick: false,
                    position: positionBadge,
                  ),
                ),
                onDragStarted: () => setState(() => _draggingMovieId = movie.id),
                onDragEnd: (_) => setState(() => _draggingMovieId = null),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: isHovered
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: MC.accent1.withAlpha(180), width: 2),
                        )
                      : null,
                  child: cell,
                ),
              );
            },
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
          child: Column(
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  childAspectRatio: cellW / cellH,
                ),
                itemCount: pageMovies.length,
                itemBuilder: (ctx, i) => RepaintBoundary(child: buildCell(i)),
              ),
              if (pageCount > 1) _buildPaginationWidget(page, pageCount),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaginationWidget(int page, int pageCount) {
    return Padding(
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
    );
  }

  Widget _buildPaginationSliver(int page, int pageCount) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
              style: MT.mono(size: 11, letterSpacing: 0.5, color: MC.mute),
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

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
      child: Column(
        children: [
          const Icon(Icons.movie_creation_outlined, color: MC.accent1, size: 32),
          const SizedBox(height: 12),
          Text(
            _section == WatchSection.watching
                ? 'Nothing in progress'
                : 'Nothing watched yet',
            style: MT.display(size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            _section == WatchSection.watching
                ? 'Tap the play icon on a movie to mark it as currently watching.'
                : 'Mark movies as watched from their detail page.',
            style: const TextStyle(color: MC.mute, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Watchlist watchlist, AppState state) {
    final isOwner = state.currentUser != null &&
        watchlist.memberIds.isNotEmpty &&
        watchlist.memberIds[0] == state.currentUser!.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 58, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: MC.bg1,
                    shape: BoxShape.circle,
                    border: Border.all(color: MC.line, width: 0.5),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: MC.mute, size: 14),
                ),
              ),
              const Spacer(),
              Row(
                children: watchlist.memberIds.asMap().entries.map((e) {
                  return Transform.translate(
                    offset: Offset(e.key * -8.0, 0),
                    child: AvatarWidget(
                        memberId: e.value, size: 28, ring: MC.bg0),
                  );
                }).toList(),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _showInviteSheet(context, watchlist),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    border: Border.all(color: MC.line, width: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_add_outlined,
                          color: MC.mute, size: 14),
                      const SizedBox(width: 5),
                      Text('Invite',
                          style: MT.mono(
                              size: 10, letterSpacing: 1, color: MC.mute)),
                    ],
                  ),
                ),
              ),
              if (!isOwner) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _confirmLeave(context, watchlist, state),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.redAccent.withAlpha(80), width: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Leave',
                        style: MT.mono(size: 10, letterSpacing: 1, color: Colors.redAccent)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                watchlist.listKey.isNotEmpty
                    ? '${watchlist.name}  ·  ${watchlist.listKey}'
                    : watchlist.name,
                style: MT.mono(size: 10, letterSpacing: 2),
              ),
              if (watchlist.isOrdered) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF5A4620), width: 1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('ORDERED',
                      style: MT.mono(
                          size: 11, letterSpacing: 2, color: MC.accent1)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text('The Queue', style: MT.display(size: 34)),
        ],
      ),
    );
  }

  void _showInviteSheet(BuildContext context, Watchlist watchlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.bg1,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) =>
          _InviteSheetInline(watchlistId: watchlist.id, parentContext: context),
    );
  }

  void _confirmLeave(BuildContext context, Watchlist watchlist, AppState state) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.bg1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Leave "${watchlist.name}"?',
            style: const TextStyle(color: MC.ink)),
        content: const Text(
          'You will be removed from this list. The list stays for other members.',
          style: TextStyle(color: MC.mute, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: MC.mute)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context); // pop the watchlist detail screen
              state.leaveWatchlist(watchlist.id);
            },
            child: const Text('Leave', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(AppState state, Watchlist watchlist) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _showFilterSheet(context, state),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: MC.line, width: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tune_rounded, color: MC.mute, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        state.genreFilter ?? 'Filter',
                        style: const TextStyle(color: MC.mute, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showSortSheet(context, state),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: MC.line, width: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort_rounded, color: MC.mute, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        state.sortOrder.label,
                        style: const TextStyle(color: MC.mute, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (watchlist.isOrdered) ...[
                GestureDetector(
                  onTap: () => _showReorderSheet(context, state, watchlist),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      border: Border.all(color: MC.line, width: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.format_list_numbered_rounded, color: MC.mute, size: 14),
                        const SizedBox(width: 4),
                        const Text('Reorder', style: TextStyle(color: MC.mute, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Randomizer — picks a random Want movie and promotes it to top pick
              GestureDetector(
                onTap: () => _randomizePick(context, state),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: MC.accent1.withAlpha(120), width: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.casino_rounded, color: MC.accent1, size: 14),
                      const SizedBox(width: 4),
                      Text('Random Pick', style: const TextStyle(color: MC.accent1, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  context.read<AppState>().setGridView(watchlist.id, !state.getGridView(watchlist.id));
                  setState(() { _page = 0; });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: MC.line, width: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    state.getGridView(watchlist.id) ? Icons.view_list_rounded : Icons.grid_view_rounded,
                    color: MC.mute, size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: MC.line, width: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              children: WatchSection.values.map((s) {
                final count = watchlist.movies.where((m) => m.section == s).length;
                final isActive = _section == s;
                return GestureDetector(
                  onTap: () => _switchSection(s),
                  child: Container(
                    margin: const EdgeInsets.only(right: 20),
                    padding: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isActive ? MC.accent1 : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                            color: isActive ? MC.ink : MC.dim,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$count',
                          style: MT.mono(size: 10, letterSpacing: 0),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatured(BuildContext context, Movie featured, {int? position}) {
    return GestureDetector(
      onTap: () => _openDetail(context, featured),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: featured.poster.gradient,
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Background poster image (when available)
            if (featured.poster.imageUrl != null)
              Positioned.fill(
                child: AppImage(
                  imageUrl: featured.poster.imageUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            // Poster overlay gradient — stronger over image so text stays readable
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 1.0],
                    colors: [
                      Colors.black.withAlpha(featured.poster.imageUrl != null ? 80 : 0),
                      MC.bg0.withAlpha(238),
                    ],
                  ),
                ),
              ),
            ),
            // Position badge for ordered lists
            if (position != null)
              Positioned(
                top: 10, left: 10,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  decoration: BoxDecoration(
                    color: const Color(0xD90B0A09),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF3A332C), width: 1),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                  child: Text(
                    '$position',
                    style: MT.mono(size: 13, weight: FontWeight.w500, color: MC.ink, letterSpacing: 0),
                  ),
                ),
              ),
            // Top row: badge + avatar
            Positioned(
              top: 14,
              left: position != null ? 52 : 14,
              right: 14,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: MC.accent1,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'TOP PICK',
                      style: MT.mono(
                          size: 9, color: MC.accentInk, letterSpacing: 1.2),
                    ),
                  ),
                  const Spacer(),
                  AvatarWidget(memberId: featured.addedBy, size: 22),
                ],
              ),
            ),
            // Bottom: title + meta
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${featured.director.toUpperCase()}  ·  ${featured.year}',
                    style: MT.mono(
                        size: 10,
                        color: Colors.white.withAlpha(178),
                        letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    featured.title,
                    style: MT.display(size: 30, italic: true, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      StreamBadgeWidget(streamId: featured.streamId),
                      const SizedBox(width: 6),
                      ...featured.genres
                          .take(2)
                          .map((g) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: TagWidget(label: g),
                              ))
                          .toList(),
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

  void _randomizePick(BuildContext context, AppState state) {
    final wantMovies = (state.activeWatchlist?.movies ?? [])
        .where((m) => m.section == WatchSection.want)
        .toList();
    if (wantMovies.isEmpty) {
      showTopToast(context, 'No movies in Want to Watch');
      return;
    }
    final movie = wantMovies[Random().nextInt(wantMovies.length)];
    state.promoteToTopPickAndSync(movie.id);
    if (_section != WatchSection.want) _switchSection(WatchSection.want);
  }

  // Reorders `fromId` to the position of `toId` within `sectionMovies`,
  // preserving the global positions of movies in all other sections.
  void _reorderWithinSection(String fromId, String toId, List<Movie> sectionMovies, AppState state, Watchlist wl) {
    final fromIdx = sectionMovies.indexWhere((m) => m.id == fromId);
    final toIdx = sectionMovies.indexWhere((m) => m.id == toId);
    if (fromIdx == -1 || toIdx == -1 || fromIdx == toIdx) return;
    final reorderedSection = List<Movie>.from(sectionMovies);
    final item = reorderedSection.removeAt(fromIdx);
    reorderedSection.insert(toIdx, item);
    // Slot the reordered section IDs back into the full global order.
    final currentOrder = wl.movieOrder ?? wl.movies.map((m) => m.id).toList();
    final sectionIds = sectionMovies.map((m) => m.id).toSet();
    final newSectionIds = reorderedSection.map((m) => m.id).toList();
    var si = 0;
    final newOrder = currentOrder.map((id) => sectionIds.contains(id) ? newSectionIds[si++] : id).toList();
    state.reorderMovies(wl.id, newOrder);
  }

  void _showReorderSheet(BuildContext context, AppState state, Watchlist watchlist) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: MC.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReorderSheet(watchlist: watchlist, state: state),
    );
  }

  void _openDetail(BuildContext context, Movie movie) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailScreen(movie: movie)),
    );
  }

  // TODO(algorithm): Sorting is currently done client-side on mock data.
  // When connected to API, delegate sort to server: GET /watchlists/:id/movies?sort=rating&dir=desc
  void _showSortSheet(BuildContext context, AppState state) {
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
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: MC.dim,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Sort by', style: MT.display(size: 20)),
          ),
          const SizedBox(height: 12),
          ...(() {
                final wl = state.activeWatchlist;
                final options = wl?.isOrdered == true
                    ? SortOrder.values
                    : SortOrder.values.where((o) => o != SortOrder.listOrder).toList();
                return options.map((o) => ListTile(
                  title: Text(o.label, style: const TextStyle(color: MC.ink)),
                  trailing: state.sortOrder == o
                      ? const Icon(Icons.check_rounded, color: MC.accent1)
                      : null,
                  onTap: () {
                    state.setSortOrder(o);
                    Navigator.pop(context);
                  },
                ));
              })(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // TODO(algorithm): Genre filtering is client-side. For large lists, push filters to API.
  // GET /watchlists/:id/movies?genre=Drama&section=want
  void _showFilterSheet(BuildContext context, AppState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MC.bg1,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.65;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: MC.dim, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Filter by genre', style: MT.display(size: 20)),
                ),
                const SizedBox(height: 12),
                ...state.allGenres.map((g) => ListTile(
                      title: Text(g, style: const TextStyle(color: MC.ink)),
                      trailing: (state.genreFilter == g ||
                              (g == 'All' && state.genreFilter == null))
                          ? const Icon(Icons.check_rounded, color: MC.accent1)
                          : null,
                      onTap: () {
                        state.setGenreFilter(g == 'All' ? null : g);
                        Navigator.pop(context);
                      },
                    )),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Reused by WatchlistScreen's invite button — same sheet as the hub.
class _InviteSheetInline extends StatefulWidget {
  final String watchlistId;
  final BuildContext parentContext;

  const _InviteSheetInline(
      {required this.watchlistId, required this.parentContext});

  @override
  State<_InviteSheetInline> createState() => _InviteSheetInlineState();
}

class _InviteSheetInlineState extends State<_InviteSheetInline> {
  bool _regenerating = false;
  final _searchCtrl = TextEditingController();
  List<UserAccount> _searchResults = [];
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _regenerate(AppState state) async {
    setState(() => _regenerating = true);
    try {
      await state.regenerateListKey(widget.watchlistId);
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _searchUsers(AppState state, String query) async {
    if (query.trim().isEmpty) {
      setState(() { _searchResults = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await state.searchUsers(query.trim());
      if (mounted) setState(() => _searchResults = results);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addMember(AppState state, UserAccount user) async {
    await state.addMemberToWatchlist(widget.watchlistId, user.id);
    if (!mounted) return;
    setState(() {
      _searchResults.removeWhere((u) => u.id == user.id);
      _searchCtrl.clear();
    });
    showTopToast(widget.parentContext, 'Invite sent to ${user.displayName}');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final watchlist = state.watchlists.firstWhere(
      (w) => w.id == widget.watchlistId,
      orElse: () => state.watchlist,
    );
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
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
          Text('Invite to ${watchlist.name}', style: MT.display(size: 22)),
          const SizedBox(height: 4),
          const Text('They\'ll receive an invite to accept or decline',
              style: TextStyle(color: MC.mute, fontSize: 13)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: watchlist.listKey));
              showTopToast(widget.parentContext, 'Code copied');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: MC.bg2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MC.accent1.withAlpha(100), width: 0.5),
              ),
              child: Row(
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(watchlist.listKey,
                          style: MT.mono(size: 22, letterSpacing: 6, color: MC.accent1)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.copy_rounded, color: MC.mute, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _regenerating ? null : () => _regenerate(state),
            child: Row(
              children: [
                _regenerating
                    ? const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(color: MC.mute, strokeWidth: 1.5))
                    : const Icon(Icons.refresh_rounded, color: MC.mute, size: 14),
                const SizedBox(width: 6),
                Text('Regenerate code',
                    style: MT.mono(size: 10, color: MC.mute, letterSpacing: 1)),
              ],
            ),
          ),
          if (watchlist.memberIds.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('MEMBERS', style: MT.mono(size: 10, letterSpacing: 2)),
            const SizedBox(height: 10),
            Row(
              children: watchlist.memberIds
                  .map((id) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AvatarWidget(memberId: id, size: 32),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 20),
          Text('ADD BY USERNAME', style: MT.mono(size: 10, letterSpacing: 2)),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged: (q) => _searchUsers(state, q),
            style: const TextStyle(color: MC.ink, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Find by username',
              hintStyle: const TextStyle(color: MC.dim, fontSize: 14),
              prefixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: MC.mute, strokeWidth: 1.5)))
                  : const Icon(Icons.person_search_outlined, color: MC.mute, size: 18),
              filled: true,
              fillColor: MC.bg2,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._searchResults.map((user) {
              final alreadyMember = watchlist.memberIds.contains(user.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    AvatarWidget(memberId: user.id, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.displayName,
                              style: const TextStyle(color: MC.ink, fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          Text('@${user.username}',
                              style: const TextStyle(color: MC.mute, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (alreadyMember)
                      Text('In list', style: MT.mono(size: 10, color: MC.mute, letterSpacing: 1))
                    else
                      GestureDetector(
                        onTap: () => _addMember(state, user),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: MC.accent1,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Invite',
                              style: TextStyle(color: MC.accentInk, fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _PosterGridCell extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;
  final bool isTopPick;
  final int? position;

  const _PosterGridCell({
    required this.movie,
    required this.onTap,
    this.isTopPick = false,
    this.position,
  });

  static const double _textAreaHeight = 20.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final cellW = constraints.maxWidth;
          final cellH = constraints.maxHeight;
          final posterH = (cellH - _textAreaHeight).clamp(0.0, double.infinity);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: PosterWidget(
                      movie: movie,
                      width: cellW,
                      height: posterH,
                    ),
                  ),
                  if (position != null)
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        decoration: BoxDecoration(
                          color: const Color(0xD90B0A09),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF3A332C), width: 1),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                        child: Text(
                          '$position',
                          style: MT.mono(
                              size: 13,
                              weight: FontWeight.w500,
                              color: MC.ink,
                              letterSpacing: 0),
                        ),
                      ),
                    ),
                  if (isTopPick)
                    Positioned(
                      bottom: 5, left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: MC.accent1,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'NEXT',
                          style: TextStyle(
                            fontSize: 8,
                            color: MC.accentInk,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: MC.ink,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Reorder sheet ────────────────────────────────────────────────────────────

class _ReorderSheet extends StatefulWidget {
  final Watchlist watchlist;
  final AppState state;

  const _ReorderSheet({required this.watchlist, required this.state});

  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late List<Movie> _movies;

  @override
  void initState() {
    super.initState();
    final wl = widget.watchlist;
    _movies = List<Movie>.from(wl.movies);
    final order = wl.movieOrder;
    if (order != null && order.isNotEmpty) {
      _movies.sort((a, b) {
        final ai = order.indexOf(a.id);
        final bi = order.indexOf(b.id);
        return (ai == -1 ? 999999 : ai).compareTo(bi == -1 ? 999999 : bi);
      });
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final item = _movies.removeAt(oldIndex);
      _movies.insert(newIndex, item);
    });
    widget.state.reorderMovies(widget.watchlist.id, _movies.map((m) => m.id).toList());
  }

  void _moveTo(int fromIndex, int toOneBased) {
    final toIndex = toOneBased - 1;
    if (toIndex < 0 || toIndex >= _movies.length || toIndex == fromIndex) return;
    setState(() {
      final item = _movies.removeAt(fromIndex);
      _movies.insert(toIndex, item);
    });
    widget.state.reorderMovies(widget.watchlist.id, _movies.map((m) => m.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: MC.dim, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Text('Reorder', style: MT.display(size: 22)),
              const Spacer(),
              Text(
                '${_movies.length} films',
                style: MT.mono(size: 10, letterSpacing: 1, color: MC.mute),
              ),
            ],
          ),
        ),
        Divider(color: MC.line, height: 0.5, thickness: 0.5),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _movies.length,
            onReorder: _onReorder,
            itemBuilder: (ctx, i) => _ReorderRow(
              key: ValueKey(_movies[i].id),
              movie: _movies[i],
              position: i + 1,
              totalCount: _movies.length,
              dragIndex: i,
              onMoveTo: (newPos) => _moveTo(i, newPos),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReorderRow extends StatelessWidget {
  final Movie movie;
  final int position;
  final int totalCount;
  final int dragIndex;
  final void Function(int newPos) onMoveTo;

  const _ReorderRow({
    super.key,
    required this.movie,
    required this.position,
    required this.totalCount,
    required this.dragIndex,
    required this.onMoveTo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MC.bg1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: dragIndex,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.drag_handle_rounded, color: MC.dim, size: 20),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showMoveDialog(context),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                    decoration: BoxDecoration(
                      color: const Color(0xD90B0A09),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: MC.accent1.withAlpha(120), width: 1),
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      '$position',
                      style: MT.mono(size: 11, weight: FontWeight.w500, color: MC.accent1, letterSpacing: 0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: PosterWidget(movie: movie, width: 36, height: 54),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        movie.title,
                        style: const TextStyle(
                            color: MC.ink, fontSize: 14, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text('${movie.year}', style: MT.mono(size: 9, letterSpacing: 1)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _SectionBadge(section: movie.section),
              ],
            ),
          ),
          Divider(color: MC.line, height: 0.5, thickness: 0.5, indent: 16, endIndent: 16),
        ],
      ),
    );
  }

  void _showMoveDialog(BuildContext context) {
    final ctrl = TextEditingController(text: '$position');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MC.bg1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Move to position', style: MT.display(size: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('1 – $totalCount', style: const TextStyle(color: MC.mute, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: MT.mono(size: 22, color: MC.ink, letterSpacing: 2),
              decoration: InputDecoration(
                filled: true,
                fillColor: MC.bg2,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: MC.accent1, width: 1)),
              ),
              onSubmitted: (_) => _doMove(ctx, ctrl.text),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: MC.mute)),
          ),
          GestureDetector(
            onTap: () => _doMove(ctx, ctrl.text),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: MC.accent1, borderRadius: BorderRadius.circular(10)),
              child: const Text('Move',
                  style: TextStyle(
                      color: MC.accentInk, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _doMove(BuildContext ctx, String raw) {
    final newPos = int.tryParse(raw.trim());
    if (newPos != null && newPos >= 1 && newPos <= totalCount) onMoveTo(newPos);
    Navigator.pop(ctx);
  }
}

class _SectionBadge extends StatelessWidget {
  final WatchSection section;
  const _SectionBadge({required this.section});

  @override
  Widget build(BuildContext context) {
    final label = switch (section) {
      WatchSection.want => 'WANT',
      WatchSection.watching => 'NOW',
      WatchSection.watched => 'SEEN',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: MC.bg2, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: MT.mono(size: 9, letterSpacing: 1)),
    );
  }
}
