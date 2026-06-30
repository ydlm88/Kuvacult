// app_state.dart — Central ChangeNotifier that owns all runtime state for the app, including the user session, watchlists, movies, reviews, friends, notifications, and community data.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart';
import 'media_data.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/wl_service.dart';
import 'services/user_notification_service.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final _authService = AuthService();
  bool _isLoggedIn = false;
  bool _isGuest = false;
  UserAccount? _currentUser;

  bool get isLoggedIn => _isLoggedIn;
  bool get isGuest => _isGuest;
  UserAccount? get currentUser => _currentUser;

  final _wlService = WatchlistService();
  StreamSubscription? _wlSub;

  Timer? _tokenRefreshTimer;

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

  // Convenience getters kept for screens that read state.watchlist/state.allMovies
  Watchlist get watchlist =>
      activeWatchlist ?? Watchlist(id: '', name: '', listKey: '');
  List<Movie> get allMovies => activeWatchlist?.movies ?? const [];

  //Checker
  bool isInAnyQueue(String movieId) =>
      _watchlists.any((wl) => wl.movies.any((m) => m.id == movieId));

  SortOrder get sortOrder => _sortOrder;
  String? get genreFilter => _genreFilter;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  List<Movie> _searchRawResults = [];
  bool _searchLoading = false;
  bool get searchLoading => _searchLoading;
  // Incremented on every new fetch; stale responses check against this
  int _searchGeneration = 0;

  // Session-scoped cache for first-page search results.
  // Keyed by query string; avoids re-hitting the API when the user retypes a
  // query they already searched (e.g. type "RRR" → delete → retype "RRR").
  // Bounded to _kSearchCacheMax entries; oldest evicted first.
  static const int _kSearchCacheMax = 40;
  final Map<String, (List<Movie>, String?)> _searchCache = {};

  // Which 15-item slice of _searchRawResults to display.
  int _localPage = 0;
  // User-visible page counter 
  int _displayPage = 1;

  static const int _pageSize = 15;

  // Returns at most 15 results from the current API fetch
  List<Movie> get searchResults =>
      _searchRawResults.skip(_localPage * _pageSize).take(_pageSize).toList();

  // Page history stack: each entry is the pageToken used to fetch that page.
  final List<String?> _searchPageHistory = [null];
  String? _searchNextPageToken;

  bool get searchHasNextPage =>
      (_localPage + 1) * _pageSize < _searchRawResults.length ||
      _searchNextPageToken != null;
  bool get searchHasPrevPage =>
      _localPage > 0 || _searchPageHistory.length > 1;
  int get searchPageNumber => _displayPage;

  List<Movie> _trendingMovies = [];
  bool _trendingLoaded = false;
  bool _trendingLoading = false;
  DateTime? _trendingLoadedAt;
  static const _kTrendingTtl = Duration(hours: 4);
  List<Movie> get trendingMovies => _trendingMovies;
  bool get trendingLoaded => _trendingLoaded;
  bool get trendingLoading => _trendingLoading;

  String? _selectedGenre;
  List<Movie> _genreResults = [];
  bool _genreLoading = false;
  String? get selectedGenre => _selectedGenre;
  List<Movie> get genreResults => List.unmodifiable(_genreResults);
  bool get genreLoading => _genreLoading;

  final List<ActivityEvent> _activity = [];
  List<ActivityEvent> get activity => List.unmodifiable(_activity);

  final Set<String> _followingIds = {};
  int _myFollowerCount = 0;
  Set<String> get followingIds => Set.unmodifiable(_followingIds);
  bool isFollowing(String userId) => _followingIds.contains(userId);
  int get myFollowerCount => _myFollowerCount;
  int get myFollowingCount => _followingIds.length;

  final List<Review> _reviews = [];
  bool _reviewsLoading = false;
  DateTime? _publicReviewsLoadedAt;
  final Map<String, DateTime> _userReviewsLoadedAt = {};
  final Map<String, DateTime> _userWatchedLoadedAt = {};
  static const _kCacheTtl = Duration(minutes: 5);
  List<Review> get publicReviews => List.unmodifiable(_reviews);
  bool get reviewsLoading => _reviewsLoading;

  List<Review> reviewsForMovie(String movieId) =>
      _reviews.where((r) => r.movieId == movieId).toList();

  List<Review> reviewsForUser(String userId) =>
      _reviews.where((r) => r.byId == userId).toList();

  double kuvacultScore(String movieId) {
    final rs = reviewsForMovie(movieId);
    if (rs.isEmpty) return 0.0;
    return (rs.map((r) => r.stars).reduce((a, b) => a + b) / rs.length) * 2;
  }

  Future<void> loadPublicReviews({bool force = false}) async {
    if (_reviewsLoading) return;
    if (!force &&
        _publicReviewsLoadedAt != null &&
        DateTime.now().difference(_publicReviewsLoadedAt!) < _kCacheTtl &&
        _reviews.isNotEmpty) return;
    _reviewsLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.fetchPublicReviews();
      final fresh = data.map(_reviewFromJson).toList();
      _publicReviewsLoadedAt = DateTime.now();
      // Upsert
      for (final r in fresh) {
        final idx = _reviews.indexWhere((e) => e.id == r.id);
        if (idx != -1) {
          _reviews[idx] = r;
        } else {
          _reviews.add(r);
        }
      }
      _prefetchMissingAvatars(fresh);
    } catch (_) {
      // keep existing cached reviews
    } finally {
      _reviewsLoading = false;
      notifyListeners();
    }
  }

  void _prefetchMissingAvatars(List<Review> reviews) {
    final ids = reviews
        .where((r) =>
            (r.byAvatarUrl ?? '').isEmpty &&
            r.byId != (_currentUser?.id ?? '') &&
            !_memberProfiles.containsKey(r.byId))
        .map((r) => r.byId)
        .toSet();
    for (final id in ids) {
      ApiService.fetchUser(id).then((data) {
        final url = data['avatarUrl'] as String?;
        if (url != null && url.isNotEmpty) {
          cacheMemberProfile(
            id,
            data['displayName'] as String? ?? '',
            data['username'] as String? ?? '',
            url,
          );
        }
      }).catchError((_) {});
    }
  }

  Future<List<Review>> loadUserReviews(String userId) async {
    final lastLoad = _userReviewsLoadedAt[userId];
    if (lastLoad != null &&
        DateTime.now().difference(lastLoad) < _kCacheTtl) {
      return reviewsForUser(userId);
    }
    try {
      final data = await ApiService.fetchUserReviews(userId);
      final fetched = data.map(_reviewFromJson).toList();
      // Upsert
      for (final r in fetched) {
        final idx = _reviews.indexWhere((e) => e.id == r.id);
        if (idx != -1) {
          _reviews[idx] = r;
        } else {
          _reviews.add(r);
        }
      }
      _userReviewsLoadedAt[userId] = DateTime.now();
      notifyListeners();
      return fetched;
    } catch (_) {
      return reviewsForUser(userId);
    }
  }

  Future<List<Review>> loadMovieReviews(String movieId) async {
    try {
      final data = await ApiService.fetchMovieReviews(movieId);
      final fetched = data.map(_reviewFromJson).toList();
      for (final r in fetched) {
        final idx = _reviews.indexWhere((e) => e.id == r.id);
        if (idx != -1) {
          _reviews[idx] = r;
        } else {
          _reviews.add(r);
        }
      }
      notifyListeners();
      return fetched;
    } catch (_) {
      return reviewsForMovie(movieId);
    }
  }

  void incrementReviewCommentCount(String reviewId) {
    final idx = _reviews.indexWhere((r) => r.id == reviewId);
    if (idx != -1) {
      _reviews[idx].commentCount++;
      notifyListeners();
    }
  }

  void decrementReviewCommentCount(String reviewId) {
    final idx = _reviews.indexWhere((r) => r.id == reviewId);
    if (idx != -1) {
      _reviews[idx].commentCount = (_reviews[idx].commentCount - 1).clamp(0, 9999);
      notifyListeners();
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
  }

  Future<void> deleteReview(String reviewId) async {
    final idx = _reviews.indexWhere((r) => r.id == reviewId);
    Review? removed;
    if (idx != -1) {
      removed = _reviews.removeAt(idx);
      notifyListeners();
    }
    try {
      await ApiService.deleteReview(reviewId);
    } catch (_) {
      if (removed != null) {
        _reviews.insert(idx, removed);
        notifyListeners();
      }
    }
  }

  void likeReview(String reviewId) async {
    if (_currentUser == null) return;
    final idx = _reviews.indexWhere((r) => r.id == reviewId);
    if (idx == -1) return;
    final review = _reviews[idx];
    final wasLiked = review.likedByMe;
    review.likedByMe = !wasLiked;
    review.likes += review.likedByMe ? 1 : -1;
    notifyListeners();
    try {
      final data = await ApiService.likeReview(reviewId, _currentUser!.id);
      final serverLikes = (data['likes'] as num?)?.toInt();
      if (serverLikes != null) review.likes = serverLikes;
      final likedBy = data['likedBy'];
      if (likedBy is List) review.likedByMe = likedBy.contains(_currentUser?.id);
      notifyListeners();
    } catch (_) {
      review.likedByMe = wasLiked;
      review.likes += wasLiked ? 1 : -1;
      notifyListeners();
    }
  }

  Future<void> markMovieWatched(Movie movie) async {
    if (_currentUser == null) return;
    // Update global watch history optimistically
    if (!_myWatchedMovies.any((m) => m.id == movie.id)) {
      _myWatchedMovies.add(WatchedMovie(
        id: movie.id,
        posterUrl: movie.poster.imageUrl,
        title: movie.title,
        year: movie.year,
      ));
      notifyListeners();
    }
    ApiService.markMovieWatched(
      _currentUser!.id,
      movieId: movie.id,
      posterUrl: movie.poster.imageUrl,
      title: movie.title,
      year: movie.year,
    );
    // Tell the watchlist backend this member watched 
    final wlId = activeWatchlist?.id;
    if (wlId != null && findMovie(movie.id) != null) {
      await ApiService.patchMovie(
        watchlistId: wlId,
        movieId: movie.id,
        section: 'watched',
        memberId: _currentUser!.id,
      );
    }
  }

  Future<void> unmarkMovieWatched(String movieId) async {
    if (_currentUser == null) return;
    _myWatchedMovies.removeWhere((m) => m.id == movieId);
    notifyListeners();
    ApiService.unmarkMovieWatched(_currentUser!.id, movieId);
    final live = findMovie(movieId);
    final wlId = activeWatchlist?.id;
    if (live != null && wlId != null) {
      final targetSection = live.section == WatchSection.watched
          ? WatchSection.want
          : live.section;
      if (live.section == WatchSection.watched) {
        live.section = WatchSection.want;
        live.watchedBy.remove(_currentUser!.id);
        notifyListeners();
      }
      // Tell backend to clear this member's watched_by entry
      await ApiService.patchMovie(
        watchlistId: wlId,
        movieId: movieId,
        section: targetSection.name,
        memberId: _currentUser!.id,
      );
    }
  }

  Future<List<WatchedMovie>> loadUserWatchedMovies(String userId) async {
    final lastLoad = _userWatchedLoadedAt[userId];
    if (lastLoad != null &&
        DateTime.now().difference(lastLoad) < _kCacheTtl) {
      return userId == _currentUser?.id
          ? List.unmodifiable(_myWatchedMovies)
          : (_profileWatchedCache[userId] ?? []);
    }
    try {
      final data = await ApiService.fetchWatchedMovies(userId);
      final items = data
          .map((d) => WatchedMovie(
                id: d['movieId'] as String? ?? '',
                posterUrl: d['posterUrl'] as String?,
                title: d['title'] as String? ?? '',
                year: (d['year'] as num?)?.toInt() ?? 0,
              ))
          .where((m) => m.id.isNotEmpty)
          .toList()
          .reversed
          .toList();
      if (userId == _currentUser?.id) {
        _myWatchedMovies
          ..clear()
          ..addAll(items);
      } else {
        _profileWatchedCache[userId] = items;
      }
      _userWatchedLoadedAt[userId] = DateTime.now();
      notifyListeners();
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadMyWatchedMovies() async {
    if (_currentUser == null) return;
    await loadUserWatchedMovies(_currentUser!.id);
    _syncWatchedSections();
  }

  // Tells the backend which movies this member has watched so watched_by is
  // current. The server promotes the movie to 'watched' section only once ALL
  // members have watched it and broadcasts movie_updated; local sections stay
  // as fetched from the DB via _loadWatchlists() to avoid transient wrong state.
  void _syncWatchedSections() {
    final userId = _currentUser?.id;
    if (userId == null) return;
    for (final wl in _watchlists) {
      for (final movie in wl.movies) {
        // Only sync if the backend doesn't already have this user in watchedBy —
        // avoids creating spurious 'moved to watched' activity events on every startup.
        if (movie.section != WatchSection.watched &&
            isWatched(movie.id) &&
            !movie.watchedBy.contains(userId)) {
          ApiService.patchMovie(
            watchlistId: wl.id,
            movieId: movie.id,
            section: 'watched',
            memberId: userId,
          ).catchError((_) {});
        }
      }
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
        likedByMe: (d['likedBy'] is List
                       ? (d['likedBy'] as List).contains(_currentUser?.id)
                       : false)
                   || (d['likedByMe'] as bool? ?? false),
      );

  VetoInvite? _pendingVetoInvite;
  VetoInvite? get pendingVetoInvite => _pendingVetoInvite;

  // Set when user taps "Join" on the banner — VetoScreen reads this to
  // auto-connect and send veto_join for the right watchlist.
  String? _pendingVetoJoin;
  String? get pendingVetoJoin => _pendingVetoJoin;

  void acceptVetoInvite() {
    _pendingVetoJoin = _pendingVetoInvite?.watchlistId;
    _pendingVetoInvite = null;
    notifyListeners();
  }

  void clearPendingVetoJoin() {
    _pendingVetoJoin = null;
    // No notifyListeners — VetoScreen clears this internally to avoid a rebuild loop.
  }

  void dismissVetoInvite() {
    _pendingVetoInvite = null;
    notifyListeners();
  }

  final List<WatchlistInvite> _pendingInvites = [];
  List<WatchlistInvite> get pendingInvites => List.unmodifiable(_pendingInvites);

  final List<AppNotification> _notifications = [];
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadNotifCount {
    final rtUnread = _notifications.where((n) => !n.read).length;
    final myId = _currentUser?.id ?? '';
    final pendingFriendReqs = _friendRequests.where((r) => r.toId == myId && !r.accepted).length;
    return rtUnread + pendingFriendReqs + _pendingInvites.length + (_pendingVetoInvite != null ? 1 : 0);
  }

  void markAllNotificationsRead() {
    for (final n in _notifications) {
      n.read = true;
    }
    notifyListeners();
  }

  final List<FriendRequest> _friendRequests = [];
  List<FriendRequest> get friendRequests => List.unmodifiable(_friendRequests);

  // Resolved friend profiles 
  final List<UserAccount> _friends = [];
  List<UserAccount> get friends => List.unmodifiable(_friends);

  // Profiles for watchlist members who may not be friends (for names/avatars in activity/avatar widgets)
  final Map<String, UserAccount> _memberProfiles = {};
  Map<String, UserAccount> get memberProfiles => Map.unmodifiable(_memberProfiles);

  // Caches a visited user's profile so avatar widgets can resolve their photo
  // without needing to re-fetch. Called from UserProfileScreen after load.
  void cacheMemberProfile(String userId, String displayName, String username, String? avatarUrl) {
    if (userId == _currentUser?.id) return;
    _memberProfiles[userId] = UserAccount(
      id: userId,
      username: username,
      email: '',
      displayName: displayName,
      avatarBg: _avatarColor(userId),
      avatarUrl: avatarUrl,
    );
  }

  final List<WatchedMovie> _myWatchedMovies = [];
  final Map<String, List<WatchedMovie>> _profileWatchedCache = {};
  List<WatchedMovie> get myWatchedMovies => List.unmodifiable(_myWatchedMovies);
  bool isWatched(String movieId) => _myWatchedMovies.any((m) => m.id == movieId);

  final List<Map<String, dynamic>> _communityTopWatchlists = [];
  final Set<String> _likedCommunityWatchlistIds = {};
  List<Map<String, dynamic>> get communityTopWatchlists =>
      List.unmodifiable(_communityTopWatchlists);

  bool isCommunityWatchlistLiked(String watchlistId) {
    final matches = _watchlists.where((w) => w.id == watchlistId);
    if (matches.isNotEmpty) return matches.first.likedByMe;
    return _likedCommunityWatchlistIds.contains(watchlistId);
  }

  Future<void> loadCommunityTopWatchlists() async {
    final data = await ApiService.fetchTopWatchlists(limit: 20);
    _communityTopWatchlists
      ..clear()
      ..addAll(data);
    notifyListeners();
  }

  Future<void> likeCommunityWatchlist(String watchlistId) async {
    if (_watchlists.any((w) => w.id == watchlistId)) {
      likeWatchlist(watchlistId);
      return;
    }
    final isLiked = _likedCommunityWatchlistIds.contains(watchlistId);
    if (isLiked) {
      _likedCommunityWatchlistIds.remove(watchlistId);
    } else {
      _likedCommunityWatchlistIds.add(watchlistId);
    }
    final idx = _communityTopWatchlists.indexWhere((w) => w['id'] == watchlistId);
    if (idx >= 0) {
      final updated = Map<String, dynamic>.from(_communityTopWatchlists[idx]);
      updated['likes'] = ((updated['likes'] as int?) ?? 0) + (isLiked ? -1 : 1);
      _communityTopWatchlists[idx] = updated;
    }
    notifyListeners();
    try {
      if (!isLiked) {
        await ApiService.likeWatchlist(watchlistId, _currentUser?.id ?? 'guest');
      } else {
        await ApiService.unlikeWatchlist(watchlistId, _currentUser?.id ?? 'guest');
      }
    } catch (_) {
      if (isLiked) {
        _likedCommunityWatchlistIds.add(watchlistId);
      } else {
        _likedCommunityWatchlistIds.remove(watchlistId);
      }
      if (idx >= 0) {
        final updated = Map<String, dynamic>.from(_communityTopWatchlists[idx]);
        updated['likes'] = ((updated['likes'] as int?) ?? 0) + (isLiked ? 1 : -1);
        _communityTopWatchlists[idx] = updated;
      }
      notifyListeners();
    }
  }

  List<WatchedMovie> watchedMoviesForUser(String userId) {
    if (userId == _currentUser?.id) return List.unmodifiable(_myWatchedMovies);
    return List.unmodifiable(_profileWatchedCache[userId] ?? []);
  }

  AppState() {
    WidgetsBinding.instance.addObserver(this);
    // Pre-load trending titles for the onboarding and search screens
    loadTrending();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wlService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      loadTrending();
      // Re-establish WS and pull fresh movie sections in case we missed events while backgrounded.
      if (_activeWatchlistId != null) {
        connectToWatchlist(_activeWatchlistId!);
        _refreshActiveWatchlist();
      }
    }
  }

  // Silently re-fetches the active watchlist's movies from the backend and
  // updates in-place. Called on app resume to catch up on missed WS events.
  Future<void> _refreshActiveWatchlist() async {
    final wlId = _activeWatchlistId;
    if (wlId == null) return;
    final idx = _watchlists.indexWhere((w) => w.id == wlId);
    if (idx == -1) return;
    try {
      final data = await ApiService.fetchWatchlistById(wlId);
      final movies = (data['movies'] as List? ?? [])
          .map((m) => _movieFromJson(m as Map<String, dynamic>))
          .toList();
      _watchlists[idx].movies
        ..clear()
        ..addAll(movies);
      notifyListeners();
    } catch (_) {}
  }

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

  // Searches all watchlist movies and personal watch history by title/director.
  // Returns Movie objects whose IDs aren't in excludeIds (dedup against API results).
  List<Movie> _searchPersonalDb(String query, Set<String> excludeIds) {
    final q = query.toLowerCase();
    final seen = <String>{...excludeIds};
    final results = <Movie>[];

    for (final wl in _watchlists) {
      for (final m in wl.movies) {
        if (seen.contains(m.id)) continue;
        if (m.title.toLowerCase().contains(q) ||
            m.director.toLowerCase().contains(q)) {
          seen.add(m.id);
          results.add(m);
        }
      }
    }

    for (final wm in _myWatchedMovies) {
      if (seen.contains(wm.id)) continue;
      if (wm.title.toLowerCase().contains(q)) {
        seen.add(wm.id);
        results.add(Movie(
          id: wm.id,
          title: wm.title,
          year: wm.year,
          runtime: 0,
          rating: 0,
          genres: [],
          director: '',
          streamId: '',
          addedBy: '',
          section: WatchSection.want,
          synopsis: '',
          poster: (wm.posterUrl?.isNotEmpty ?? false)
              ? PosterData(
                  gradient: _fallbackPoster.gradient,
                  accent: _fallbackPoster.accent,
                  imageUrl: wm.posterUrl,
                )
              : _fallbackPoster,
        ));
      }
    }

    return results;
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
        final apiIds = hit.$1.map((m) => m.id).toSet();
        final personal = _searchPersonalDb(_searchQuery, apiIds);
        _searchRawResults = personal.isEmpty ? hit.$1 : [...hit.$1, ...personal];
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
      _searchNextPageToken = nextToken;
      // Cache only the API portion so personal DB is always re-computed live.
      if (pageToken == null) {
        _searchCache[_searchQuery] = (movies, nextToken);
        if (_searchCache.length > _kSearchCacheMax) {
          _searchCache.remove(_searchCache.keys.first);
        }
        // Append personal DB matches on the first page only (deduped by ID).
        final apiIds = movies.map((m) => m.id).toSet();
        final personal = _searchPersonalDb(_searchQuery, apiIds);
        _searchRawResults = personal.isEmpty ? movies : [...movies, ...personal];
      } else {
        _searchRawResults = movies;
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

  // Loads popular titles from the IMDb API for the onboarding collage and search/review
  // trending rails. TTL-gated so warm starts and app-resume don't hammer the API.
  // Falls back to cached data on failure so the UI never goes blank.
  Future<void> loadTrending() async {
    if (_trendingLoading) return;
    final hasData = _trendingMovies.isNotEmpty;
    final isFresh = _trendingLoadedAt != null &&
        DateTime.now().difference(_trendingLoadedAt!) < _kTrendingTtl;
    if (hasData && isFresh) return;
    _trendingLoading = true;
    if (!hasData) _trendingLoaded = false;
    notifyListeners();
    try {
      final movies = await _imdb.fetchTrending();
      if (movies.isNotEmpty) {
        _trendingMovies = movies;
        _trendingLoadedAt = DateTime.now();
      }
    } catch (_) {} // keep existing data on failure
    finally {
      _trendingLoading = false;
      _trendingLoaded = true;
      notifyListeners();
    }
  }

  
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
      memberIds: [_currentUser?.id ?? 'guest'],
    );
    _watchlists.add(wl);
    _activeWatchlistId ??= wl.id;
    notifyListeners();
    return wl;
  }

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

  Future<void> addMemberToWatchlist(String watchlistId, String userId) async {
    await ApiService.addMemberToWatchlist(watchlistId: watchlistId, userId: userId);
    // Invite sent — recipient must accept; don't add to memberIds yet
  }

  Future<void> leaveWatchlist(String watchlistId) async {
    _watchlists.removeWhere((w) => w.id == watchlistId);
    if (_activeWatchlistId == watchlistId) {
      _activeWatchlistId = _watchlists.isNotEmpty ? _watchlists.first.id : null;
    }
    notifyListeners();
    await ApiService.leaveWatchlist(watchlistId);
  }

  Future<void> acceptWatchlistInvite(String watchlistId, String inviteId) async {
    final data = await ApiService.acceptWatchlistInvite(
      watchlistId: watchlistId,
      inviteId: inviteId,
    );
    _pendingInvites.removeWhere((inv) => inv.id == inviteId);
    if (!_watchlists.any((w) => w.id == watchlistId)) {
      final movies = (data['movies'] as List? ?? [])
          .map((m) => _movieFromJson(m as Map<String, dynamic>))
          .toList();
      final newWlId = data['id'] as String;
      // Auto-move any films the user already watched to the watched section
      for (final movie in movies) {
        if (movie.section != WatchSection.watched && isWatched(movie.id)) {
          movie.section = WatchSection.watched;
          ApiService.patchMovie(
            watchlistId: newWlId,
            movieId: movie.id,
            section: 'watched',
            memberId: _currentUser?.id,
          ).catchError((_) {});
        }
      }
      _watchlists.add(Watchlist(
        id: newWlId,
        name: data['name'] as String? ?? '',
        listKey: data['listKey'] as String? ?? '',
        memberIds: (data['memberIds'] as List? ?? []).cast<String>(),
        movies: movies,
      ));
      setActiveWatchlist(newWlId);
    }
    notifyListeners();
  }

  Future<void> declineWatchlistInvite(String watchlistId, String inviteId) async {
    _pendingInvites.removeWhere((inv) => inv.id == inviteId);
    notifyListeners();
    await ApiService.declineWatchlistInvite(watchlistId: watchlistId, inviteId: inviteId);
  }

  // Adds a movie to a specific watchlist (by id) or to the active one if omitted.
  // If the movie is a search stub (no rating/runtime/synopsis), it is added
  // immediately for instant UI feedback and then enriched in the background
  // before the backend save so the stored record has full metadata.
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

      Movie toSave = movie;
      if (movie.rating == 0 && movie.runtime == 0 && movie.synopsis.isEmpty) {
        try {
          final enriched = await _imdb.fetchTitle(movie.id);
          toSave = enriched;
          final idx = target.movies.indexWhere((m) => m.id == movie.id);
          if (idx != -1) {
            target.movies[idx] = Movie(
              id: enriched.id, title: enriched.title, year: enriched.year,
              runtime: enriched.runtime, rating: enriched.rating,
              genres: enriched.genres, director: enriched.director,
              streamId: enriched.streamId, addedBy: _currentUser?.id ?? 'guest',
              section: WatchSection.want, synopsis: enriched.synopsis,
              poster: enriched.poster,
            );
            notifyListeners();
          }
        } catch (_) {}
      }

      await ApiService.addMovie(
        watchlistId: target.id,
        movieId: toSave.id,
        title: toSave.title,
        year: toSave.year,
        addedBy: _currentUser?.id ?? 'guest',
        runtime: toSave.runtime,
        rating: toSave.rating,
        genres: toSave.genres,
        director: toSave.director,
        streamId: toSave.streamId,
        synopsis: toSave.synopsis,
        imageUrl: toSave.poster.imageUrl,
      );
    }
  }

  void moveMovie(String movieId, WatchSection newSection) async {
    // 'watched' section moves are handled exclusively by markMovieWatched so
    // the server can enforce the "all members watched" rule before promoting.
    // Any call here with WatchSection.watched is a mistake — ignore it.
    if (newSection == WatchSection.watched) return;
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

  // Promotes a movie and broadcasts the change to all watchlist members via WS.
  Future<void> promoteToTopPickAndSync(String movieId) async {
    promoteToTopPick(movieId);
    final wlId = activeWatchlist?.id;
    if (wlId != null) {
      ApiService.promoteMovie(
        watchlistId: wlId,
        movieId: movieId,
        promotedBy: _currentUser?.id,
      ).catchError((_) {});
    }
  }

  void removeMovie(String movieId) async {
    final wlId = activeWatchlist?.id;
    if (wlId == null) return;
    activeWatchlist?.movies.removeWhere((m) => m.id == movieId);
    notifyListeners();
    await ApiService.removeMovie(watchlistId: wlId, movieId: movieId);
  }

  // If watchlists exist but none is active,
  // silently activate the first one so mutations don't no-op.
  void ensureActiveWatchlist() {
    if (_activeWatchlistId == null && _watchlists.isNotEmpty) {
      _activeWatchlistId = _watchlists.first.id;
      notifyListeners();
    }
  }

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

  void setSortOrder(SortOrder order) {
    _sortOrder = order;
    notifyListeners();
  }

  void setGenreFilter(String? genre) {
    _genreFilter = genre;
    notifyListeners();
  }


  Future<void> login(String email, String password, {bool rememberMe = true}) async {
    final (:result, :accessToken, :refreshToken) = await _authService.login(
      email: email,
      password: password,
    );
    ApiService.setToken(accessToken);
    if (rememberMe) {
      await _authService.storeSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        userId: result.userId,
      );
    }
    _isLoggedIn = true;
    _isGuest = false;
    _currentUser = _userFromAuthResult(result);
    notifyListeners();
    _scheduleTokenRefresh(refreshToken);
    try {
      await _loadWatchlists();
      await _loadFriendRequests();
      await _loadFriends();
      await loadFollowing();
      await _loadInvites();
      _connectNotifications();
      _userWatchedLoadedAt.remove(_currentUser!.id);
      await _loadMyWatchedMovies();
    } catch (_) {}
  }

  Future<void> register(
    String username,
    String email,
    String password,
    String displayName,
  ) async {
    final message = await _authService.register(
      username: username,
      email: email,
      password: password,
      displayName: displayName,
    );
    // Registration succeeded but user must verify email before logging in.
    // Throw so the auth screen can show a check-email prompt.
    throw RegistrationPendingException(message);
  }

  Future<void> resendVerification(String email) async {
    await _authService.resendVerification(email);
  }

  Future<void> forgotPassword(String email) async {
    await _authService.forgotPassword(email);
  }

  Future<void> logout() async {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
    final stored = await _authService.getStoredSession();
    if (stored != null) await _authService.logout(stored.refreshToken);
    await _authService.clearSession();
    ApiService.setToken(null);
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
    _pendingInvites.clear();
    _notifications.clear();
    _myWatchedMovies.clear();
    _profileWatchedCache.clear();
    _publicReviewsLoadedAt = null;
    _userReviewsLoadedAt.clear();
    _userWatchedLoadedAt.clear();
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

  Future<void> tryRestoreSession() async {
    final stored = await _authService.getStoredSession();
    if (stored == null) return;

    // Refresh the access token — 15min TTL means it's often expired on cold start.
    final newToken = await _authService.refreshAccessToken(stored.refreshToken);
    if (newToken == null) {
      await _authService.clearSession();
      return;
    }
    ApiService.setToken(newToken);
    await _authService.storeSession(
      accessToken: newToken,
      refreshToken: stored.refreshToken,
      userId: stored.userId,
    );

    _isLoggedIn = true;
    _isGuest = false;
    try {
      final userData = await ApiService.fetchUser(stored.userId, requesterId: stored.userId);
      _currentUser = UserAccount(
        id: stored.userId,
        username: userData['username'] as String? ?? '',
        email: '',
        displayName: userData['displayName'] as String? ?? '',
        avatarBg: _avatarColor(stored.userId),
        avatarUrl: userData['avatarUrl'] as String?,
        roomKey: userData['roomKey'] as String?,
      );
      _currentUser!.friendIds = (userData['friendIds'] as List? ?? []).cast<String>();
    } catch (_) {
      _currentUser = UserAccount(
        id: stored.userId,
        username: '',
        email: '',
        displayName: '',
        avatarBg: _avatarColor(stored.userId),
      );
    }
    _scheduleTokenRefresh(stored.refreshToken);
    notifyListeners();
    await _loadWatchlists();
    await _loadFriendRequests();
    await _loadFriends();
    await loadFollowing();
    await _loadInvites();
    _connectNotifications();
    _userWatchedLoadedAt.remove(_currentUser!.id);
    await _loadMyWatchedMovies();
  }

  void _scheduleTokenRefresh(String refreshToken) {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 14), (_) async {
      final newToken = await _authService.refreshAccessToken(refreshToken);
      if (newToken != null) {
        ApiService.setToken(newToken);
        final stored = await _authService.getStoredSession();
        if (stored != null) {
          await _authService.storeSession(
            accessToken: newToken,
            refreshToken: stored.refreshToken,
            userId: stored.userId,
          );
        }
      }
    });
  }

  UserAccount _userFromAuthResult(AuthResult result) {
    final account = UserAccount(
      id: result.userId,
      username: result.username,
      email: result.email,
      displayName: result.displayName,
      avatarBg: _avatarColor(result.userId),
      avatarUrl: result.avatarUrl,
      roomKey: result.roomKey,
    );
    account.friendIds = result.friendIds.toList();
    return account;
  }

  // Deterministically picks one of the brand palette colours based on the user ID.
  Color _avatarColor(String id) {
    const palette = [
      Color(0xFFF6C453), Color(0xFF7AB9F2), Color(0xFFE98AA8),
      Color(0xFF85C9A8), Color(0xFFB39DDB),
    ];
    return palette[id.hashCode.abs() % palette.length];
  }

  Future<void> updateProfile({String? displayName, String? avatarFilePath}) async {
    if (_currentUser == null) return;
    final trimmed = displayName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      _currentUser!.displayName = trimmed;
    }
    String? cloudAvatarUrl;
    if (avatarFilePath != null) {
      cloudAvatarUrl = await ApiService.uploadAvatar(
        userId: _currentUser!.id,
        filePath: avatarFilePath,
      );
      _currentUser!.avatarUrl = cloudAvatarUrl;
    }
    notifyListeners();
    await ApiService.updateProfile(
      userId: _currentUser!.id,
      displayName: trimmed?.isNotEmpty == true ? trimmed : null,
      avatarUrl: cloudAvatarUrl,
    );
  }

  // POST /users/:id/room-key — returns guaranteed-unique 6-char key.
  Future<void> generateRoomKey() async {
    if (_currentUser == null) return;
    String key;
    do {
      key = _generateRoomCode();
    } while (await ApiService.checkRoomKey(key));

    await ApiService.saveRoomKey(userId: _currentUser!.id, roomKey: key);
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
            userId: _currentUser?.id ?? 'guest',
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
      setActiveWatchlist(data['id'] as String);
      notifyListeners();
    }
  }

  Future<void> joinRoom(String code) async {
    await joinRoomByKey(code);
  }

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


  Future<void> _loadWatchlists() async {
    if (_currentUser == null) return;
    try {
      final data = await ApiService.fetchUserWatchlists(_currentUser!.id);
      _watchlists.clear();
      for (final wl in data) {
        final movies = (wl['movies'] as List? ?? []).map((m) => _movieFromJson(m as Map<String, dynamic>)).toList();
        final likedBy = (wl['likedBy'] as List? ?? []).cast<String>();
        _watchlists.add(Watchlist(
          id: wl['id'] as String,
          name: wl['name'] as String? ?? '',
          listKey: wl['listKey'] as String? ?? '',
          memberIds: (wl['memberIds'] as List? ?? []).cast<String>(),
          movies: movies,
          likes: (wl['likes'] as num?)?.toInt() ?? 0,
          likedByMe: likedBy.contains(_currentUser?.id),
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
      if(_activeWatchlistId != null) connectToWatchlist(_activeWatchlistId!);
      notifyListeners();
      _backfillMissingPosters(); // fire-and-forget; updates UI when done
      _loadActivity(); // fire-and-forget; populates activity feed from backend
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
      case 'movie_promoted':
        final promotedId = event.data['movieId'] as String?;
        final promotedBy = event.data['promotedBy'] as String?;
        if (promotedId != null && promotedBy != _currentUser?.id) {
          final idx = wl.movies.indexWhere((m) => m.id == promotedId);
          if (idx != -1) {
            final movie = wl.movies.removeAt(idx);
            movie.section = WatchSection.want;
            wl.movies.insert(0, movie);
          }
        }
      case 'member_joined':
        final joinedId = event.data['userId'] as String?;
        if (joinedId != null && !wl.memberIds.contains(joinedId)) {
          wl.memberIds.add(joinedId);
        }
      case 'member_left':
        final leftId = event.data['userId'] as String?;
        if (leftId != null) wl.memberIds.remove(leftId);
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

  Future<void> refreshActivity() async {
    await Future.wait([_loadActivity(), _loadInvites()]);
  }

  Future<void> _loadActivity() async {
    if (_watchlists.isEmpty) return;
    try {
      final all = <ActivityEvent>[];
      for (final wl in _watchlists) {
        final data = await ApiService.fetchWatchlistActivity(wl.id);
        for (final e in data) {
          ReactionType? reaction;
          try {
            if (e['reaction'] != null) {
              reaction = ReactionType.values.byName(e['reaction'] as String);
            }
          } catch (_) {}
          ActivityKind kind;
          try {
            kind = ActivityKind.values.byName(
                (e['kind'] as String? ?? 'added').toLowerCase());
          } catch (_) {
            kind = ActivityKind.added;
          }
          all.add(ActivityEvent(
            id: e['id'] as String?,
            kind: kind,
            who: e['who'] as String? ?? '',
            movieId: e['movieId'] as String?,
            text: e['text'] as String?,
            to: e['to'] as String?,
            reaction: reaction,
            stars: (e['stars'] as num?)?.toDouble(),
            at: DateTime.tryParse(e['at']?.toString() ?? '') ?? DateTime.now(),
          ));
        }
      }
      // Dedup by id (server events have UUIDs), keep most recent 200
      final seen = <String>{};
      final deduped = <ActivityEvent>[];
      for (final e in all) {
        final key = e.id ?? '${e.who}|${e.kind.name}|${e.at.millisecondsSinceEpoch}';
        if (seen.add(key)) deduped.add(e);
      }
      deduped.sort((a, b) => b.at.compareTo(a.at));
      _activity
        ..clear()
        ..addAll(deduped.take(200));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadInvites() async {
    if (_currentUser == null) return;
    try {
      final data = await ApiService.fetchPendingInvites(_currentUser!.id);
      _pendingInvites.clear();
      for (final inv in data) {
        _pendingInvites.add(WatchlistInvite(
          id: inv['id'] as String,
          watchlistId: inv['watchlistId'] as String,
          watchlistName: inv['watchlistName'] as String? ?? '',
          inviterId: inv['inviterId'] as String,
          inviterName: inv['inviterName'] as String? ?? '',
          inviterAvatarUrl: inv['inviterAvatarUrl'] as String?,
        ));
      }
      notifyListeners();
    } catch (_) {}
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
            watchedBy: (m['watchedBy'] as List? ?? []).cast<String>(),
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
      // Keep friendIds in sync 
      _currentUser!.friendIds = _friends.map((f) => f.id).toList();
      notifyListeners();
    } catch (_) {
      //friend display names degrade to IDs if fetch fails
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
          fromUsername:    r['fromUsername']    as String?,
          fromDisplayName: r['fromDisplayName'] as String?,
          fromAvatarUrl:   r['fromAvatarUrl']   as String?,
        ));
      }
      notifyListeners();
    } catch (_) {
      // friend requests stay empty if fetch fails
    }
  }

  Future<void> refreshProfile() async {
    if (_currentUser == null) return;
    _userWatchedLoadedAt.remove(_currentUser!.id); 
    await Future.wait([
      _loadWatchlists(),
      _loadFriendRequests(),
      _loadFriends(),
      loadFollowing(),
      loadUserWatchedMovies(_currentUser!.id),
    ]);
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

  // Best-effort background fetch
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
    final type = msg['type'] as String?;
    if (type == 'veto_invite') {
      if (msg['fromId'] != _currentUser?.id) {
        _pendingVetoInvite = VetoInvite(
          fromId: msg['fromId'] as String? ?? '',
          fromName: msg['fromName'] as String? ?? 'Someone',
          watchlistId: msg['watchlistId'] as String? ?? '',
          watchlistName: msg['watchlistName'] as String? ?? 'Watchlist',
        );
        notifyListeners();
      }
    } else if (type == 'watchlist_invite') {
      final inviteId = msg['inviteId'] as String?;
      final watchlistId = msg['watchlistId'] as String?;
      if (inviteId != null && watchlistId != null &&
          !_pendingInvites.any((inv) => inv.id == inviteId)) {
        _pendingInvites.add(WatchlistInvite(
          id: inviteId,
          watchlistId: watchlistId,
          watchlistName: msg['watchlistName'] as String? ?? '',
          inviterId: msg['inviterId'] as String? ?? '',
          inviterName: msg['inviterName'] as String? ?? '',
          inviterAvatarUrl: msg['inviterAvatarUrl'] as String?,
        ));
        notifyListeners();
      }
    } else if (type == 'like_review') {
      _notifications.insert(0, AppNotification(
        id: 'notif_${DateTime.now().millisecondsSinceEpoch}',
        type: NotifType.likedReview,
        at: DateTime.now(),
        fromId: msg['fromId'] as String?,
        fromName: msg['fromName'] as String?,
        fromHandle: msg['fromHandle'] as String?,
        fromAvatarUrl: msg['fromAvatarUrl'] as String?,
        reviewId: msg['reviewId'] as String?,
        movieTitle: msg['movieTitle'] as String?,
      ));
      notifyListeners();
    } else if (type == 'like_watchlist') {
      _notifications.insert(0, AppNotification(
        id: 'notif_${DateTime.now().millisecondsSinceEpoch}',
        type: NotifType.likedWatchlist,
        at: DateTime.now(),
        fromId: msg['fromId'] as String?,
        fromName: msg['fromName'] as String?,
        fromHandle: msg['fromHandle'] as String?,
        fromAvatarUrl: msg['fromAvatarUrl'] as String?,
        watchlistId: msg['watchlistId'] as String?,
        watchlistName: msg['watchlistName'] as String?,
      ));
      notifyListeners();
    } else if (type == 'follow') {
      _notifications.insert(0, AppNotification(
        id: 'notif_${DateTime.now().millisecondsSinceEpoch}',
        type: NotifType.followed,
        at: DateTime.now(),
        fromId: msg['fromId'] as String?,
        fromName: msg['fromName'] as String?,
        fromHandle: msg['fromHandle'] as String?,
        fromAvatarUrl: msg['fromAvatarUrl'] as String?,
      ));
      notifyListeners();
    } else if (type == 'friend_review') {
      _activity.insert(0, ActivityEvent(
        kind: ActivityKind.postedReview,
        who: msg['fromId'] as String? ?? '',
        movieId: msg['movieId'] as String?,
        text: msg['movieTitle'] as String?,
        stars: (msg['stars'] as num?)?.toDouble(),
        at: DateTime.tryParse(msg['at'] as String? ?? '') ?? DateTime.now(),
      ));
      notifyListeners();
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

  List<Review> get reviewsThisMonth {
    final cutoff = DateTime.now().subtract(const Duration(days: 31));
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
