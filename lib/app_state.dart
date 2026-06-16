import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart';
import 'media_data.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/wl_service.dart';
import 'services/user_notification_service.dart';

class AppState extends ChangeNotifier {
  // ─── Auth state ────────────────────────────────────────────────────────────────
  // _authService handles all Auth0 token operations.
  // TODO(backend): After Auth0 login, exchange the id_token for a backend JWT at
  // POST /auth/verify — your server validates the Auth0 token and returns a session.
  final _authService = AuthService();
  bool _isLoggedIn = false;
  bool _isGuest = false;
  UserAccount? _currentUser;

  bool get isLoggedIn => _isLoggedIn;
  bool get isGuest => _isGuest;
  UserAccount? get currentUser => _currentUser;

  // ─── Watchlist state ───────────────────────────────────────────────────────────
  // TODO(backend): On init load watchlists from your API:
  // GET /watchlists — returns all watchlists the current user belongs to
  // Subscribe to a WebSocket channel per watchlist for live collaborative updates.
  final _wlService = WatchlistService();
  StreamSubscription? _wlSub;

  final _notifService = UserNotificationService();
  StreamSubscription<Map<String, dynamic>>? _notifSub;

  final _imdb = MediaData();

  final List<Watchlist> _watchlists = [];
  String? _activeWatchlistId;
  SortOrder _sortOrder = SortOrder.dateAdded;
  String? _genreFilter;

  List<Watchlist> get watchlists => List.unmodifiable(_watchlists);

  Watchlist? get activeWatchlist => _watchlists.isEmpty
      ? null
      : _watchlists.firstWhere(
          (w) => w.id == _activeWatchlistId,
          orElse: () => _watchlists.first,
        );

  // Convenience getters kept for screens that read state.watchlist / state.allMovies
  Watchlist get watchlist =>
      activeWatchlist ?? Watchlist(id: '', name: '', listKey: '');
  List<Movie> get allMovies => activeWatchlist?.movies ?? const [];

  SortOrder get sortOrder => _sortOrder;
  String? get genreFilter => _genreFilter;

  // ─── Search state ──────────────────────────────────────────────────────────────
  // TODO(backend): Replace direct IMDb API calls with your own search endpoint:
  // GET /search/movies?q=<query>&pageToken=<token> — proxies IMDb and caches results
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  // Raw results from the current API fetch — may contain more than 15 items.
  List<Movie> _searchRawResults = [];
  bool _searchLoading = false;
  bool get searchLoading => _searchLoading;
  // Incremented on every new fetch; stale responses check against this and bail.
  int _searchGeneration = 0;

  // Session-scoped cache for first-page search results.
  // Keyed by query string; avoids re-hitting the API when the user retypes a
  // query they already searched (e.g. type "RRR" → delete → retype "RRR").
  // Bounded to _kSearchCacheMax entries; oldest evicted first.
  static const int _kSearchCacheMax = 40;
  final Map<String, (List<Movie>, String?)> _searchCache = {};

  // Which 15-item slice of _searchRawResults to display.
  int _localPage = 0;
  // User-visible page counter (increments across both local and API pages).
  int _displayPage = 1;

  static const int _pageSize = 15;

  // Returns at most 15 results from the current API fetch.
  List<Movie> get searchResults =>
      _searchRawResults.skip(_localPage * _pageSize).take(_pageSize).toList();

  // Page history stack: each entry is the pageToken used to fetch that page.
  // Null = first page (no token needed). Popping lets us go back a page.
  final List<String?> _searchPageHistory = [null];
  String? _searchNextPageToken;

  bool get searchHasNextPage =>
      (_localPage + 1) * _pageSize < _searchRawResults.length ||
      _searchNextPageToken != null;
  bool get searchHasPrevPage =>
      _localPage > 0 || _searchPageHistory.length > 1;
  int get searchPageNumber => _displayPage;

  // ─── Trending state ────────────────────────────────────────────────────────────
  // TODO(backend): Replace with GET /movies/trending — server-curated list
  List<Movie> _trendingMovies = [];
  bool _trendingLoaded = false;
  bool _trendingLoading = false;
  List<Movie> get trendingMovies => _trendingMovies;
  bool get trendingLoaded => _trendingLoaded;
  bool get trendingLoading => _trendingLoading;

  // ─── Genre search state ────────────────────────────────────────────────────────
  String? _selectedGenre;
  List<Movie> _genreResults = [];
  bool _genreLoading = false;
  String? get selectedGenre => _selectedGenre;
  List<Movie> get genreResults => List.unmodifiable(_genreResults);
  bool get genreLoading => _genreLoading;

  // ─── Activity feed ─────────────────────────────────────────────────────────────
  // TODO(backend): Fetch activity from your API:
  // GET /watchlists/:id/activity?page=1 — paginated activity log
  // Push new events via WebSocket so all members see updates in real time.
  final List<ActivityEvent> _activity = [];
  List<ActivityEvent> get activity => List.unmodifiable(_activity);

  // ─── Social graph ──────────────────────────────────────────────────────────────
  final Set<String> _followingIds = {};
  int _myFollowerCount = 0;
  Set<String> get followingIds => Set.unmodifiable(_followingIds);
  bool isFollowing(String userId) => _followingIds.contains(userId);
  int get myFollowerCount => _myFollowerCount;
  int get myFollowingCount => _followingIds.length;

  // ─── Public reviews ────────────────────────────────────────────────────────────
  // TODO(backend): Load from GET /reviews and cache locally.
  final List<Review> _reviews = [];
  bool _reviewsLoading = false;
  List<Review> get publicReviews => List.unmodifiable(_reviews);
  bool get reviewsLoading => _reviewsLoading;

  List<Review> reviewsForMovie(String movieId) =>
      _reviews.where((r) => r.movieId == movieId).toList();

  List<Review> reviewsForUser(String userId) =>
      _reviews.where((r) => r.byId == userId).toList();

  double marqueeScore(String movieId) {
    final rs = reviewsForMovie(movieId);
    if (rs.isEmpty) return 0.0;
    return rs.map((r) => r.stars).reduce((a, b) => a + b) / rs.length;
  }

  Future<void> loadPublicReviews() async {
    if (_reviewsLoading) return;
    _reviewsLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.fetchPublicReviews();
      final fresh = data.map(_reviewFromJson).toList();
      _reviews.clear();
      _reviews.addAll(fresh);
    } catch (_) {
      // non-critical; keep existing cached reviews
    } finally {
      _reviewsLoading = false;
      notifyListeners();
    }
  }

  Future<List<Review>> loadUserReviews(String userId) async {
    try {
      final data = await ApiService.fetchUserReviews(userId);
      return data.map(_reviewFromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Review>> loadMovieReviews(String movieId) async {
    try {
      final data = await ApiService.fetchMovieReviews(movieId);
      return data.map(_reviewFromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Review?> submitReview({
    required String movieId,
    required String movieTitle,
    required int movieYear,
    String movieDirector = '',
    String? moviePosterUrl,
    required double stars,
    required String text,
    bool rewatch = false,
  }) async {
    if (_currentUser == null) return null;
    try {
      final data = await ApiService.submitReview(
        byId: _currentUser!.id,
        movieId: movieId,
        movieTitle: movieTitle,
        movieYear: movieYear,
        movieDirector: movieDirector,
        moviePosterUrl: moviePosterUrl,
        stars: stars,
        text: text,
        rewatch: rewatch,
      );
      final review = _reviewFromJson(data);
      _reviews.insert(0, review);
      notifyListeners();
      return review;
    } catch (_) {
      // Optimistic local insert so UI feels responsive even when backend is down
      final review = Review(
        id: 'local_${DateTime.now().millisecondsSinceEpoch}',
        byId: _currentUser!.id,
        byName: _currentUser!.displayName,
        byHandle: _currentUser!.username,
        byAvatarColor: _currentUser!.avatarBg,
        byAvatarUrl: _currentUser!.avatarUrl,
        movieId: movieId,
        movieTitle: movieTitle,
        movieYear: movieYear,
        moviePosterUrl: moviePosterUrl,
        movieDirector: movieDirector,
        stars: stars,
        text: text,
        at: DateTime.now(),
        rewatch: rewatch,
      );
      _reviews.insert(0, review);
      notifyListeners();
      return review;
    }
  }

  void likeReview(String reviewId) async {
    final idx = _reviews.indexWhere((r) => r.id == reviewId);
    if (idx == -1) return;
    final review = _reviews[idx];
    review.likedByMe = !review.likedByMe;
    review.likes += review.likedByMe ? 1 : -1;
    notifyListeners();
    try {
      await ApiService.likeReview(reviewId);
    } catch (_) {
      // revert on failure
      review.likedByMe = !review.likedByMe;
      review.likes += review.likedByMe ? 1 : -1;
      notifyListeners();
    }
  }

  Review _reviewFromJson(Map<String, dynamic> d) => Review(
        id: d['id'] as String? ?? '',
        byId: d['byId'] as String? ?? '',
        byName: d['byName'] as String? ?? '',
        byHandle: d['byHandle'] as String? ?? d['username'] as String? ?? '',
        byAvatarColor: _avatarColor(d['byId'] as String? ?? ''),
        byAvatarUrl: d['byAvatarUrl'] as String?,
        movieId: d['movieId'] as String? ?? '',
        movieTitle: d['movieTitle'] as String? ?? '',
        movieYear: (d['movieYear'] as num?)?.toInt() ?? 0,
        moviePosterUrl: d['moviePosterUrl'] as String?,
        movieDirector: d['movieDirector'] as String? ?? '',
        stars: (d['stars'] as num?)?.toDouble() ?? 0.0,
        text: d['text'] as String? ?? '',
        at: DateTime.tryParse(d['at'] as String? ?? '') ?? DateTime.now(),
        likes: (d['likes'] as num?)?.toInt() ?? 0,
        commentCount: (d['commentCount'] as num?)?.toInt() ?? 0,
        rewatch: d['rewatch'] as bool? ?? false,
        likedByMe: d['likedByMe'] as bool? ?? false,
      );

  // ─── Veto invite ───────────────────────────────────────────────────────────────
  VetoInvite? _pendingVetoInvite;
  VetoInvite? get pendingVetoInvite => _pendingVetoInvite;

  void dismissVetoInvite() {
    _pendingVetoInvite = null;
    notifyListeners();
  }

  // ─── Friends state ─────────────────────────────────────────────────────────────
  // TODO(backend): Endpoints for friends:
  // GET /users/:id/friends, POST /friends/request, PATCH /friends/:id/accept
  final List<FriendRequest> _friendRequests = [];
  List<FriendRequest> get friendRequests => List.unmodifiable(_friendRequests);

  // Resolved friend profiles (display name, username, avatar) — loaded after login
  final List<UserAccount> _friends = [];
  List<UserAccount> get friends => List.unmodifiable(_friends);

  // Profiles for watchlist members who may not be friends (for names/avatars in activity/avatar widgets)
  final Map<String, UserAccount> _memberProfiles = {};
  Map<String, UserAccount> get memberProfiles => Map.unmodifiable(_memberProfiles);

  AppState() {
    // Pre-load trending titles for the onboarding and search screens
    loadTrending();
  }

  // ─── Filtered + sorted movie list ─────────────────────────────────────────────
  // TODO(backend): Replace with server-side sorting/filtering:
  // POST /watchlists/:id/movies/filter — body: { section, genre, sortBy, sortDir }
  List<Movie> moviesForSection(WatchSection section) {
    var list = (activeWatchlist?.movies ?? [])
        .where((m) => m.section == section)
        .toList();
    if (_genreFilter != null) {
      list = list.where((m) => m.genres.contains(_genreFilter)).toList();
    }
    // TODO(algorithm): Implement weighted sort (rating × recency) or delegate to server
    switch (_sortOrder) {
      case SortOrder.rating:
        list.sort((a, b) => b.rating.compareTo(a.rating));
      case SortOrder.runtime:
        list.sort((a, b) => a.runtime.compareTo(b.runtime));
      case SortOrder.title:
        list.sort((a, b) => a.title.compareTo(b.title));
      case SortOrder.year:
        list.sort((a, b) => b.year.compareTo(a.year));
      case SortOrder.dateAdded:
        break; // insertion order = date added order
    }
    return list;
  }

  // ─── Search ────────────────────────────────────────────────────────────────────
  Future<void> searchByGenre(String genre) async {
    if (_selectedGenre == genre) {
      _selectedGenre = null;
      _genreResults = [];
      notifyListeners();
      return;
    }
    _selectedGenre = genre;
    _genreLoading = true;
    notifyListeners();
    try {
      final (movies, _) = await _imdb.fetchByGenre(genre);
      _genreResults = movies;
    } catch (_) {
      _genreResults = [];
    } finally {
      _genreLoading = false;
      notifyListeners();
    }
  }

  void clearGenreSearch() {
    _selectedGenre = null;
    _genreResults = [];
    notifyListeners();
  }

  // Starts a new search, resetting pagination to page 1.
  // Debounced 500ms in the UI layer before this is called.
  // TODO(backend): Swap _imdb.searchTitles for your own endpoint to add auth and caching.
  Future<void> setSearchQuery(String q) async {
    if (q.isNotEmpty && _selectedGenre != null) {
      _selectedGenre = null;
      _genreResults = [];
    }
    if (q != _searchQuery) {
      _searchPageHistory..clear()..add(null);
      _localPage = 0;
      _displayPage = 1;
    }
    _searchQuery = q;
    if (q.isEmpty) {
      _searchRawResults = [];
      _searchNextPageToken = null;
      _searchPageHistory..clear()..add(null);
      _localPage = 0;
      _displayPage = 1;
      notifyListeners();
      return;
    }
    await _fetchSearchPage(_searchPageHistory.last);
  }

  // Fetches search results for the current query using the given page token.
  // Each call stamps a generation number; if a newer call has started by the
  // time this one resolves, the response is silently dropped so stale data
  // never overwrites fresher results (fixes race when typing/deleting quickly).
  Future<void> _fetchSearchPage(String? pageToken) async {
    final myGen = ++_searchGeneration;

    // Serve from cache for first-page queries — avoids duplicate API calls when
    // the user retypes a query they already searched, and sidesteps rate limiting.
    if (pageToken == null) {
      final hit = _searchCache[_searchQuery];
      if (hit != null) {
        _searchRawResults = hit.$1;
        _searchNextPageToken = hit.$2;
        _searchLoading = false;
        notifyListeners();
        return;
      }
    }

    _searchLoading = true;
    notifyListeners();
    try {
      final (movies, nextToken) =
          await _imdb.searchTitles(_searchQuery, pageToken: pageToken);
      if (myGen != _searchGeneration) return; // superseded by a newer query
      _searchRawResults = movies;
      _searchNextPageToken = nextToken;
      // Cache first-page results for this query so retypes are instant.
      if (pageToken == null) {
        _searchCache[_searchQuery] = (movies, nextToken);
        if (_searchCache.length > _kSearchCacheMax) {
          _searchCache.remove(_searchCache.keys.first);
        }
      }
    } catch (e) {
      if (myGen != _searchGeneration) return;
      _searchRawResults = [];
      _searchNextPageToken = null;
    } finally {
      if (myGen == _searchGeneration) {
        _searchLoading = false;
        notifyListeners();
      }
    }
  }

  // Advances to the next page — within the current API batch first, then fetches more.
  Future<void> nextSearchPage() async {
    if (_searchQuery.isEmpty) return;
    if ((_localPage + 1) * _pageSize < _searchRawResults.length) {
      // Still have local items left in this API batch
      _localPage++;
      _displayPage++;
      notifyListeners();
    } else if (_searchNextPageToken != null) {
      // Need a new API fetch
      _localPage = 0;
      _displayPage++;
      _searchPageHistory.add(_searchNextPageToken);
      await _fetchSearchPage(_searchNextPageToken);
    }
  }

  // Returns to the previous page of search results.
  Future<void> prevSearchPage() async {
    if (_searchQuery.isEmpty) return;
    if (_localPage > 0) {
      _localPage--;
      _displayPage--;
      notifyListeners();
    } else if (_searchPageHistory.length > 1) {
      _searchPageHistory.removeLast();
      _localPage = 0;
      _displayPage--;
      await _fetchSearchPage(_searchPageHistory.last);
    }
  }

  // Loads the 10 most popular titles from the IMDb API for the onboarding collage
  // and search screen trending rail.
  Future<void> loadTrending() async {
    if (_trendingLoading) return; // prevent concurrent fetches
    _trendingLoading = true;
    _trendingLoaded = false;
    notifyListeners();
    try {
      _trendingMovies = await _imdb.fetchTrending();
    } catch (_) {
      _trendingMovies = [];
    } finally {
      _trendingLoading = false;
      _trendingLoaded = true;
      notifyListeners();
    }
  }

  // ─── Watchlist CRUD ────────────────────────────────────────────────────────────
  
  Future<Watchlist> createWatchlist(String name) async {
    final result = await ApiService.createWatchlist(
      name: name,
      listKey: _generateRoomCode(),
      memberIds: [_currentUser?.id ?? 'guest'],
    );
    final wl = Watchlist(
      id: result['id'],
      name: name,
      listKey: result['listKey'] ?? '',
    );
    _watchlists.add(wl);
    _activeWatchlistId ??= wl.id;
    notifyListeners();
    return wl;
  }

  //Update websocket
  void connectToWatchlist(String watchlistId) {
    _wlSub?.cancel();
    _wlService.connect(watchlistId);
    _wlSub = _wlService.events.listen(_onWatchlistEvent);
  }

  void setActiveWatchlist(String id) {
    _activeWatchlistId = id;
    connectToWatchlist(id);
    notifyListeners();
  }

  void renameWatchlist(String id, String newName) async {
    final wl = _watchlists.firstWhere((w) => w.id == id, orElse: () => throw Exception());
    wl.name = newName;
    notifyListeners();
    await ApiService.renameWatchlist(watchlistId: id, name: newName);
  }

  void deleteWatchlist(String id) async {
    _watchlists.removeWhere((w) => w.id == id);
    if (_activeWatchlistId == id) {
      _activeWatchlistId = _watchlists.isNotEmpty ? _watchlists.first.id : null;
    }
    notifyListeners();
    await ApiService.deleteWatchlist(id);
  }

  Future<void> regenerateListKey(String watchlistId) async {
    final newKey = _generateRoomCode();
    final wl = _watchlists.firstWhere((w) => w.id == watchlistId, orElse: () => throw Exception());
    final result = await ApiService.regenerateListKey(watchlistId: watchlistId, listKey: newKey);
    final idx = _watchlists.indexOf(wl);
    _watchlists[idx] = Watchlist(
      id: wl.id,
      name: wl.name,
      listKey: result['listKey'] as String? ?? newKey,
      memberIds: wl.memberIds,
      movies: wl.movies,
    );
    notifyListeners();
  }

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ123456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<void> addMemberToWatchlist(String watchlistId, String auth0Sub) async {
    await ApiService.addMemberToWatchlist(watchlistId: watchlistId, auth0Sub: auth0Sub);
    final idx = _watchlists.indexWhere((w) => w.id == watchlistId);
    if (idx != -1 && !_watchlists[idx].memberIds.contains(auth0Sub)) {
      _watchlists[idx].memberIds.add(auth0Sub);
      notifyListeners();
    }
  }

  // ─── Watchlist mutations ───────────────────────────────────────────────────────
  // TODO(backend): Each mutation should also POST/PATCH your API and broadcast
  // the change over the room's WebSocket channel so all members see it live.

  // Adds a movie to a specific watchlist (by id) or to the active one if omitted.
  void addMovieToWatchlist(Movie movie, {String? watchlistId}) async {
    final target = watchlistId != null
        ? _watchlists.firstWhere((w) => w.id == watchlistId,
            orElse: () => throw Exception('Watchlist not found'))
        : activeWatchlist;
    if (target == null) return;
    if (!target.movies.any((m) => m.id == movie.id)) {
      target.movies.add(Movie(
        id: movie.id, title: movie.title, year: movie.year,
        runtime: movie.runtime, rating: movie.rating, genres: movie.genres,
        director: movie.director, streamId: movie.streamId,
        addedBy: _currentUser?.id ?? 'guest',
        section: WatchSection.want, synopsis: movie.synopsis,
        poster: movie.poster,
      ));
      _addActivity(ActivityEvent(
        id: 'a${_activity.length + 1}',
        kind: ActivityKind.added,
        who: _currentUser?.id ?? 'guest',
        movieId: movie.id,
        at: DateTime.now(),
      ));
      notifyListeners();
      await ApiService.addMovie(
        watchlistId: target.id,
        movieId: movie.id,
        title: movie.title,
        year: movie.year,
        addedBy: _currentUser?.id ?? 'guest',
        runtime: movie.runtime,
        rating: movie.rating,
        genres: movie.genres,
        director: movie.director,
        streamId: movie.streamId,
        synopsis: movie.synopsis,
        imageUrl: movie.poster.imageUrl,
      );
    }
  }

  void moveMovie(String movieId, WatchSection newSection) async {
    final movies = activeWatchlist?.movies;
    if (movies == null) return;
    final idx = movies.indexWhere((m) => m.id == movieId);
    if (idx != -1) {
      final wlId = activeWatchlist!.id;
      movies[idx].section = newSection;
      _addActivity(ActivityEvent(
        id: 'a${_activity.length + 1}',
        kind: ActivityKind.moved,
        who: _currentUser?.id ?? 'guest',
        movieId: movieId,
        to: newSection.label,
        at: DateTime.now(),
      ));
      notifyListeners();
      await ApiService.patchMovie(
        watchlistId: wlId,
        movieId: movieId,
        section: newSection.name,
        memberId: _currentUser?.id,
      );
    }
  }

  // Moves the veto winner to the front of the Want to Watch section.
  // TODO(backend): PATCH /watchlists/:id/movies/:movieId/promote — sets section=want and sortOrder=0
  void promoteToTopPick(String movieId) {
    final movies = activeWatchlist?.movies;
    if (movies == null) return;
    final idx = movies.indexWhere((m) => m.id == movieId);
    if (idx == -1) return;
    final movie = movies.removeAt(idx);
    movie.section = WatchSection.want;
    movies.insert(0, movie);
    notifyListeners();
  }

  void removeMovie(String movieId) async {
    final wlId = activeWatchlist?.id;
    if (wlId == null) return;
    activeWatchlist?.movies.removeWhere((m) => m.id == movieId);
    notifyListeners();
    await ApiService.removeMovie(watchlistId: wlId, movieId: movieId);
  }

  // If watchlists exist but none is active (e.g. after a logout/login edge case),
  // silently activate the first one so mutations don't no-op.
  void ensureActiveWatchlist() {
    if (_activeWatchlistId == null && _watchlists.isNotEmpty) {
      _activeWatchlistId = _watchlists.first.id;
      notifyListeners();
    }
  }

  // ─── Star rating ───────────────────────────────────────────────────────────────
  void rateMovie(String movieId, String memberId, double stars) async {
    final movies = activeWatchlist?.movies;
    if (movies == null) return;
    final idx = movies.indexWhere((m) => m.id == movieId);
    if (idx == -1) return;
    final wlId = activeWatchlist!.id;
    movies[idx].stars[memberId] = stars;
    _addActivity(ActivityEvent(
      id: 'a${_activity.length + 1}',
      kind: ActivityKind.rated,
      who: memberId,
      movieId: movieId,
      stars: stars,
      at: DateTime.now(),
    ));
    notifyListeners();
    await ApiService.patchMovie(
      watchlistId: wlId,
      movieId: movieId,
      memberId: memberId,
      stars: stars.round(),
    );
  }

  // ─── Reactions ─────────────────────────────────────────────────────────────────
  void reactToMovie(String movieId, String memberId, ReactionType reaction) async {
    final movies = activeWatchlist?.movies;
    if (movies == null) return;
    final idx = movies.indexWhere((m) => m.id == movieId);
    if (idx == -1) return;
    final wlId = activeWatchlist!.id;
    movies[idx].reactions[memberId] = reaction;
    _addActivity(ActivityEvent(
      id: 'a${_activity.length + 1}',
      kind: ActivityKind.reacted,
      who: memberId,
      movieId: movieId,
      reaction: reaction,
      at: DateTime.now(),
    ));
    notifyListeners();
    await ApiService.patchMovie(
      watchlistId: wlId,
      movieId: movieId,
      memberId: memberId,
      reaction: reaction.name,
    );
  }

  // ─── Notes ─────────────────────────────────────────────────────────────────────
  void addNote(String movieId, String memberId, String text) async {
    final movies = activeWatchlist?.movies;
    if (movies == null) return;
    final idx = movies.indexWhere((m) => m.id == movieId);
    if (idx == -1) return;
    final wlId = activeWatchlist!.id;
    movies[idx].notes.add(MovieNote(by: memberId, text: text, at: DateTime.now()));
    _addActivity(ActivityEvent(
      id: 'a${_activity.length + 1}',
      kind: ActivityKind.note,
      who: memberId,
      movieId: movieId,
      text: text,
      at: DateTime.now(),
    ));
    notifyListeners();
    await ApiService.addNote(
      watchlistId: wlId,
      movieId: movieId,
      by: memberId,
      text: text,
    );
  }

  // ─── Sort & filter ─────────────────────────────────────────────────────────────
  void setSortOrder(SortOrder order) {
    _sortOrder = order;
    notifyListeners();
  }

  void setGenreFilter(String? genre) {
    _genreFilter = genre;
    notifyListeners();
  }

  // ─── Auth — Auth0 Universal Login ──────────────────────────────────────────────
  
  //After login, send the Auth0 access_token to your backend at
  // POST /auth/verify to get a session token, then load the user's watchlist data.
  Future<void> login() async {
    // Only _authService.login() propagates — a down backend never shows "Sign in failed"
    // when Auth0 actually succeeded.
    final result = await _authService.login();
    _isLoggedIn = true;
    _isGuest = false;
    _currentUser = _userFromAuthResult(result);
    notifyListeners();
    try {
      final userData = await ApiService.upsertUser(
        auth0Sub: _currentUser!.id,
        username: _currentUser!.username,
        email: _currentUser!.email,
        displayName: _currentUser!.displayName,
      );
      // Sync server-stored fields back so friendIds/roomKey/displayName/avatarUrl are correct
      _currentUser!.friendIds = (userData['friendIds'] as List? ?? []).cast<String>();
      if (userData['roomKey'] != null) _currentUser!.roomKey = userData['roomKey'] as String;
      if (userData['displayName'] != null) _currentUser!.displayName = userData['displayName'] as String;
      if (userData['avatarUrl'] != null) _currentUser!.avatarUrl = userData['avatarUrl'] as String;
      notifyListeners();
      await _loadWatchlists();
      await _loadFriendRequests();
      await _loadFriends();
      await loadFollowing();
      _connectNotifications();
    } catch (_) {
      // Backend unavailable — user is still logged in; data reloads on next open
    }
  }

  // Clears the Auth0 browser session and resets all local state.
  // TODO(backend): Also call POST /auth/logout on your backend to invalidate
  // the session token stored server-side.
  Future<void> logout() async {
    await _authService.logout();
    await _authService.clearStoredCredentials();
    _notifSub?.cancel();
    _notifService.disconnect();
    _isLoggedIn = false;
    _isGuest = false;
    _currentUser = null;
    _watchlists.clear();
    _activeWatchlistId = null;
    _activity.clear();
    _friends.clear();
    _friendRequests.clear();
    _memberProfiles.clear();
    notifyListeners();
  }

  // Sets a local guest profile with no watchlists.
  // Guest sessions are ephemeral — nothing is persisted to the backend.
  void loginAsGuest() {
    _isLoggedIn = false; // guest is NOT an authenticated user
    _isGuest = true;
    _currentUser = UserAccount(
      id: 'guest',
      username: 'guest',
      email: '',
      displayName: 'Guest',
      avatarBg: const Color(0xFF5A5A5A),
    );
    _watchlists.clear();
    _activeWatchlistId = null;
    _activity.clear();
    notifyListeners();
  }

  // Checks for a valid existing Auth0 session on app start — avoids forcing
  // the user to log in again if their refresh token is still valid.
  // TODO(backend): On success also refresh the backend session token.
  Future<void> tryRestoreSession() async {
    final result = await _authService.getStoredCredentials();
    if (result != null) {
      _isLoggedIn = true;
      _isGuest = false;
      _currentUser = _userFromAuthResult(result);
      notifyListeners();
      try {
        // Sync server-stored data (friendIds, displayName, roomKey, avatarUrl) not in stored credentials
        final userData = await ApiService.fetchUser(
          _currentUser!.id,
          requesterId: _currentUser!.id,
        );
        _currentUser!.friendIds = (userData['friendIds'] as List? ?? []).cast<String>();
        if (userData['displayName'] != null) _currentUser!.displayName = userData['displayName'] as String;
        if (userData['roomKey'] != null) _currentUser!.roomKey = userData['roomKey'] as String;
        if (userData['avatarUrl'] != null) _currentUser!.avatarUrl = userData['avatarUrl'] as String;
        notifyListeners();
      } catch (_) {}
      await _loadWatchlists();
      await _loadFriendRequests();
      await _loadFriends();
      await loadFollowing();
      _connectNotifications();
    }
  }

  // Builds a UserAccount from the platform-agnostic AuthResult.
  UserAccount _userFromAuthResult(AuthResult result) {
    return UserAccount(
      id: result.sub,
      username: result.nickname ?? result.name,
      email: result.email ?? '',
      displayName: result.name,
      avatarBg: _avatarColor(result.sub),
    );
  }

  // Deterministically picks one of the brand palette colours based on the user ID.
  Color _avatarColor(String id) {
    const palette = [
      Color(0xFFF6C453), Color(0xFF7AB9F2), Color(0xFFE98AA8),
      Color(0xFF85C9A8), Color(0xFFB39DDB),
    ];
    return palette[id.hashCode.abs() % palette.length];
  }

  // ─── Profile edits ────────────────────────────────────────────────────────────
  Future<void> updateProfile({String? displayName, String? avatarFilePath}) async {
    if (_currentUser == null) return;
    final trimmed = displayName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      _currentUser!.displayName = trimmed;
    }
    String? cloudAvatarUrl;
    if (avatarFilePath != null) {
      cloudAvatarUrl = await ApiService.uploadAvatar(
        auth0Sub: _currentUser!.id,
        filePath: avatarFilePath,
      );
      _currentUser!.avatarUrl = cloudAvatarUrl;
    }
    notifyListeners();
    await ApiService.updateProfile(
      auth0Sub: _currentUser!.id,
      displayName: trimmed?.isNotEmpty == true ? trimmed : null,
      avatarUrl: cloudAvatarUrl,
    );
  }

  // ─── Room key ─────────────────────────────────────────────────────────────────
  // POST /users/:id/room-key — returns guaranteed-unique 6-char key.
  Future<void> generateRoomKey() async {
    if (_currentUser == null) return;
    String key;
    do {
      key = _generateRoomCode();
    } while (await ApiService.checkRoomKey(key));

    await ApiService.saveRoomKey(auth0Sub: _currentUser!.id, roomKey: key);
    _currentUser!.roomKey = key;
    notifyListeners();
  }

  Future<void> joinRoomByKey(String key) async {
    final k = key.trim().toUpperCase();
    if (k.length != 6) return;
    // Guests get a read-only view of the room without being added to memberIds
    final data = _isGuest
        ? await ApiService.findRoom(listKey: k)
        : await ApiService.joinRoom(
            listKey: k,
            auth0Sub: _currentUser?.id ?? 'guest',
          );
    if (!_watchlists.any((w) => w.id == data['id'])) {
      final movies = (data['movies'] as List? ?? []).map((m) => _movieFromJson(m as Map<String, dynamic>)).toList();
      _watchlists.add(Watchlist(
        id: data['id'] as String,
        name: data['name'] as String? ?? '',
        listKey: data['listKey'] as String? ?? '',
        memberIds: (data['memberIds'] as List? ?? []).cast<String>(),
        movies: movies,
      ));
      _activeWatchlistId ??= data['id'] as String;
      connectToWatchlist(data['id'] as String);
      notifyListeners();
    }
  }

  // ─── Watchlist rooms ───────────────────────────────────────────────────────────
  Future<void> joinRoom(String code) async {
    await joinRoomByKey(code);
  }

  // ─── Friends ───────────────────────────────────────────────────────────────────
  Future<void> sendFriendRequest(String toUserId) async {
    if (_currentUser == null) return;
    final result = await ApiService.sendFriendRequest(
      fromId: _currentUser!.id,
      toId: toUserId,
    );
    _friendRequests.add(FriendRequest(
      id: result['id'] as String? ?? DateTime.now().toIso8601String(),
      fromId: _currentUser!.id,
      toId: toUserId,
      sentAt: DateTime.now(),
    ));
    notifyListeners();
  }

  Future<void> acceptFriendRequest(String requestId) async {
    await ApiService.acceptFriendRequest(requestId);
    final req = _friendRequests.firstWhere((r) => r.id == requestId);
    _currentUser?.friendIds.add(req.fromId);
    _friendRequests.removeWhere((r) => r.id == requestId);
    notifyListeners();
    // Reload full friend profiles so the new friend's display name is available
    _loadFriends();
  }

  Future<void> declineFriendRequest(String requestId) async {
    await ApiService.declineFriendRequest(requestId);
    _friendRequests.removeWhere((r) => r.id == requestId);
    notifyListeners();
  }

  Future<List<UserAccount>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final data = await ApiService.searchUsers(query.trim());
    return data.map((u) => UserAccount(
      id: u['id'] as String,
      username: u['username'] as String? ?? '',
      email: u['email'] as String? ?? '',
      displayName: u['displayName'] as String? ?? '',
      avatarBg: _avatarColor(u['id'] as String),
      avatarUrl: u['avatarUrl'] as String?,
    )).toList();
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────────

  Future<void> _loadWatchlists() async {
    if (_currentUser == null) return;
    try {
      final data = await ApiService.fetchUserWatchlists(_currentUser!.id);
      _watchlists.clear();
      for (final wl in data) {
        final movies = (wl['movies'] as List? ?? []).map((m) => _movieFromJson(m as Map<String, dynamic>)).toList();
        _watchlists.add(Watchlist(
          id: wl['id'] as String,
          name: wl['name'] as String? ?? '',
          listKey: wl['listKey'] as String? ?? '',
          memberIds: (wl['memberIds'] as List? ?? []).cast<String>(),
          movies: movies,
        ));
        // Cache member profiles so activity/avatar widgets have names+photos for non-friends
        for (final m in (wl['members'] as List? ?? [])) {
          final mp = m as Map<String, dynamic>;
          final memberId = mp['id'] as String?;
          if (memberId != null && memberId != _currentUser?.id) {
            _memberProfiles[memberId] = UserAccount(
              id: memberId,
              username: mp['username'] as String? ?? '',
              email: '',
              displayName: mp['displayName'] as String? ?? '',
              avatarBg: _avatarColor(memberId),
              avatarUrl: mp['avatarUrl'] as String?,
            );
          }
        }
      }
      _activeWatchlistId ??= _watchlists.isNotEmpty ? _watchlists.first.id : null;
      //Check before websocket connection
      if(_activeWatchlistId != null) connectToWatchlist(_activeWatchlistId!);
      notifyListeners();
      _backfillMissingPosters(); // fire-and-forget; updates UI when done
    } catch (_) {
      // Non-critical on session restore — watchlists stay empty if fetch fails
    }
  }

  void _onWatchlistEvent(WatchlistEvent event) {
    final wl = _watchlists.cast<Watchlist?>().firstWhere(
      (w) => w!.id == _activeWatchlistId, orElse: () => null);

    if (wl == null) return;
    switch(event.type){
      case 'movie_added':
        final addedBy = event.data['movie']['addedBy'] as String?;
        if(addedBy == _currentUser?.id) break; //already added elsewhere by current user
        wl.movies.add(_movieFromJson(event.data['movie']));
      case 'movie_updated':
        final updated = _movieFromJson(event.data['movie']);
        final idx = wl.movies.indexWhere((m) => m.id == updated.id);
        if(idx != -1) wl.movies[idx] = updated;
      case 'movie_removed':
        wl.movies.removeWhere((m) => m.id == event.data['movieId']);
      case 'activity_added':
        final e = event.data['event'] as Map<String, dynamic>;
        final whoId = e['who'] as String? ?? '';
        if (whoId == _currentUser?.id) break; // already added locally
        ReactionType? parsedReaction;
        try {
          if (e['reaction'] != null) parsedReaction = ReactionType.values.byName(e['reaction'] as String);
        } catch (_) {}
        _activity.insert(0, ActivityEvent(
          kind: ActivityKind.values.byName(e['kind'] as String),
          who: whoId,
          movieId: e['movieId'] as String?,
          text: e['text'] as String?,
          to: e['to'] as String?,
          reaction: parsedReaction,
          stars: (e['stars'] as num?)?.toDouble(),
          at: DateTime.tryParse(e['at'] as String? ?? '') ?? DateTime.now(),
        ));
    }
    notifyListeners();
  }

  Movie _movieFromJson(Map<String, dynamic> m){
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
            addedBy: m['addedBy'] ?? 'guest',
            section: _parseSection(m['section'] as String?),
            synopsis: m['synopsis'] ?? '',
            poster: imageUrl != null && imageUrl.isNotEmpty
                ? PosterData(
                    gradient: _fallbackPoster.gradient,
                    accent: _fallbackPoster.accent,
                    imageUrl: imageUrl,
                  )
                : _fallbackPoster,
          );
  }

  Future<void> _loadFriends() async {
    if (_currentUser == null) return;
    try {
      final data = await ApiService.fetchFriends(_currentUser!.id);
      _friends
        ..clear()
        ..addAll(data.map((u) => UserAccount(
          id: u['id'] as String,
          username: u['username'] as String? ?? '',
          email: u['email'] as String? ?? '',
          displayName: u['displayName'] as String? ?? '',
          avatarBg: _avatarColor(u['id'] as String),
          avatarUrl: u['avatarUrl'] as String?,
        )));
      // Keep friendIds in sync with server-authoritative list
      _currentUser!.friendIds = _friends.map((f) => f.id).toList();
      notifyListeners();
    } catch (_) {
      // Non-critical — friend display names degrade to IDs if fetch fails
    }
  }

  Future<void> _loadFriendRequests() async {
    if (_currentUser == null) return;
    try {
      final data = await ApiService.fetchFriendRequests(_currentUser!.id);
      _friendRequests.clear();
      for (final r in data) {
        _friendRequests.add(FriendRequest(
          id: r['id'] as String,
          fromId: r['fromId'] as String,
          toId: r['toId'] as String,
          sentAt: DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now(),
        ));
      }
      notifyListeners();
    } catch (_) {
      // Non-critical — friend requests stay empty if fetch fails
    }
  }

  WatchSection _parseSection(String? s) {
    switch (s) {
      case 'watching': return WatchSection.watching;
      case 'watched':  return WatchSection.watched;
      default:         return WatchSection.want;
    }
  }

  static const _fallbackPoster = PosterData(
    gradient: LinearGradient(
      colors: [Color(0xFF1C1C2E), Color(0xFF2D2D44)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    accent: Color(0xFFF6C453),
  );

  // Best-effort background fetch — fills in imageUrl for movies that predate
  // the Firestore imageUrl field. Fires and forgets; notifies once done.
  Future<void> _backfillMissingPosters() async {
    bool changed = false;
    for (final wl in _watchlists) {
      for (int i = 0; i < wl.movies.length; i++) {
        final m = wl.movies[i];
        if (m.poster.imageUrl != null || m.id.isEmpty) continue;
        try {
          final fetched = await _imdb.fetchTitle(m.id);
          if (fetched.poster.imageUrl != null) {
            wl.movies[i] = Movie(
              id: m.id, title: m.title, year: m.year,
              runtime: m.runtime, rating: m.rating, genres: m.genres,
              director: m.director, streamId: m.streamId, addedBy: m.addedBy,
              section: m.section, synopsis: m.synopsis,
              reactions: Map.from(m.reactions),
              stars: Map.from(m.stars),
              notes: List.from(m.notes),
              poster: fetched.poster,
            );
            changed = true;
          }
        } catch (_) {}
      }
    }
    if (changed) notifyListeners();
  }

  void _connectNotifications() {
    if (_currentUser == null) return;
    _notifSub?.cancel();
    _notifService.connect(_currentUser!.id);
    _notifSub = _notifService.events.listen(_onNotification);
  }

  void _onNotification(Map<String, dynamic> msg) {
    if (msg['type'] == 'veto_invite') {
      if (msg['fromId'] != _currentUser?.id) {
        _pendingVetoInvite = VetoInvite(
          fromId: msg['fromId'] as String? ?? '',
          fromName: msg['fromName'] as String? ?? 'Someone',
          watchlistId: msg['watchlistId'] as String? ?? '',
          watchlistName: msg['watchlistName'] as String? ?? 'Watchlist',
        );
        notifyListeners();
      }
    }
  }

  void _addActivity(ActivityEvent event) {
    _activity.insert(0, event);
  }

  Movie? findMovie(String id) {
    try {
      return activeWatchlist?.movies.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  List<String> get allGenres {
    final genres = <String>{};
    for (final m in activeWatchlist?.movies ?? []) {
      genres.addAll(m.genres);
    }
    return ['All', ...genres.toList()..sort()];
  }

  Future<void> loadFollowing() async {
    if (_currentUser == null) return;
    try {
      final ids = await ApiService.fetchFollowingIds(_currentUser!.id);
      _followingIds
        ..clear()
        ..addAll(ids);
      final stats = await ApiService.fetchUserSocialStats(_currentUser!.id);
      _myFollowerCount = (stats['followerCount'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> followUser(String targetId) async {
    if (_currentUser == null) return;
    _followingIds.add(targetId);
    notifyListeners();
    try {
      await ApiService.followUser(targetId, _currentUser!.id);
    } catch (_) {
      _followingIds.remove(targetId);
      notifyListeners();
    }
  }

  Future<void> unfollowUser(String targetId) async {
    if (_currentUser == null) return;
    _followingIds.remove(targetId);
    notifyListeners();
    try {
      await ApiService.unfollowUser(targetId, _currentUser!.id);
    } catch (_) {
      _followingIds.add(targetId);
      notifyListeners();
    }
  }

  void likeWatchlist(String watchlistId) async {
    final idx = _watchlists.indexWhere((w) => w.id == watchlistId);
    if (idx == -1) return;
    final wl = _watchlists[idx];
    wl.likedByMe = !wl.likedByMe;
    wl.likes += wl.likedByMe ? 1 : -1;
    notifyListeners();
    try {
      if (wl.likedByMe) {
        await ApiService.likeWatchlist(watchlistId, _currentUser?.id ?? 'guest');
      } else {
        await ApiService.unlikeWatchlist(watchlistId, _currentUser?.id ?? 'guest');
      }
    } catch (_) {
      wl.likedByMe = !wl.likedByMe;
      wl.likes += wl.likedByMe ? 1 : -1;
      notifyListeners();
    }
  }

  List<Review> reviewsForPeriod(String period) {
    if (period == 'This Week') {
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      return _reviews.where((r) => r.at.isAfter(cutoff)).toList();
    }
    if (period == 'This Month') {
      final cutoff = DateTime.now().subtract(const Duration(days: 30));
      return _reviews.where((r) => r.at.isAfter(cutoff)).toList();
    }
    if (period == 'This Year') {
      final cutoff = DateTime.now().subtract(const Duration(days: 365));
      return _reviews.where((r) => r.at.isAfter(cutoff)).toList();
    }
    return List.from(_reviews); // All Time
  }

  List<Review> get reviewsThisWeek {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _reviews.where((r) => r.at.isAfter(cutoff)).toList();
  }

  List<Map<String, dynamic>> topReviewers({int limit = 20}) {
    final byUser = <String, List<Review>>{};
    for (final r in _reviews) {
      byUser.putIfAbsent(r.byId, () => []).add(r);
    }
    final entries = byUser.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    return entries.take(limit).map((e) {
      final first = e.value.first;
      return <String, dynamic>{
        'userId': e.key,
        'name': first.byName,
        'handle': first.byHandle,
        'avatarColor': first.byAvatarColor,
        'avatarUrl': first.byAvatarUrl,
        'reviewCount': e.value.length,
        'totalLikes': e.value.fold<int>(0, (s, r) => s + r.likes),
      };
    }).toList();
  }
}
