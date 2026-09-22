// api_service.dart — Thin HTTP client wrapping the Kuvacult REST API; all methods are static and throw ApiException on non-2xx responses.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config.dart';

class ApiService {
  static String get _base => Config.httpBase;
  static const _timeout = Duration(seconds: 10);

  static String? _token;
  static void setToken(String? t) => _token = t;

  static Map<String, String> _json() => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  // Headers for GET / DELETE requests that need auth but carry no body
  static Map<String, String>? _auth() =>
      _token != null ? {'Authorization': 'Bearer $_token'} : null;

  static Map<String, dynamic> _decode(http.Response res) {
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, body['error'] ?? 'Unknown error');
    }
    return body;
  }

  static void Function()? onServerDown;

  static Future<http.Response> _get(Uri uri, {
    Map<String, String>? headers,
    Duration timeout = _timeout,
  }) async {
    try {
      return await http.get(uri, headers: headers).timeout(timeout);
    } on SocketException {
      onServerDown?.call();
      rethrow;
    } on http.ClientException {
      onServerDown?.call();
      rethrow;
    } on TimeoutException {
      onServerDown?.call();
      rethrow;
    }
  }

  static Future<http.Response> _post(Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = _timeout,
  }) async {
    try {
      return await http.post(uri, headers: headers, body: body).timeout(timeout);
    } on SocketException {
      onServerDown?.call();
      rethrow;
    } on http.ClientException {
      onServerDown?.call();
      rethrow;
    } on TimeoutException {
      onServerDown?.call();
      rethrow;
    }
  }

  static Future<http.Response> _patch(Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = _timeout,
  }) async {
    try {
      return await http.patch(uri, headers: headers, body: body).timeout(timeout);
    } on SocketException {
      onServerDown?.call();
      rethrow;
    } on http.ClientException {
      onServerDown?.call();
      rethrow;
    } on TimeoutException {
      onServerDown?.call();
      rethrow;
    }
  }

  static Future<http.Response> _delete(Uri uri, {
    Map<String, String>? headers,
    Duration timeout = _timeout,
  }) async {
    try {
      final res = await http.delete(uri, headers: headers).timeout(timeout);
      return res;
    } on SocketException {
      onServerDown?.call();
      rethrow;
    } on http.ClientException {
      onServerDown?.call();
      rethrow;
    } on TimeoutException {
      onServerDown?.call();
      rethrow;
    }
  }

  static Future<bool> isServerUp() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> checkRoomKey(String key) async {
    final res = await _get(
      Uri.parse('$_base/users?roomKey=$key'),
      headers: _auth(),
    );
    final body = _decode(res);
    return body['exists'] as bool;
  }

  static Future<void> saveRoomKey({
    required String userId,
    required String roomKey,
  }) async {
    final res = await _patch(
      Uri.parse('$_base/users/$userId'),
      headers: _json(),
      body: jsonEncode({'roomKey': roomKey}),
    );
    _decode(res);
  }


  static Future<Map<String, dynamic>> joinRoom({
    required String listKey,
    required String userId,
  }) async {
    final res = await _post(
      Uri.parse('$_base/watchlists/join'),
      headers: _json(),
      body: jsonEncode({'listKey': listKey, 'userId': userId}),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> findRoom({required String listKey}) async {
    final res = await _get(
      Uri.parse('$_base/watchlists/find?code=${Uri.encodeQueryComponent(listKey)}'),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> fetchWatchlistById(String watchlistId) async {
    final res = await _get(
      Uri.parse('$_base/watchlists/$watchlistId'),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> createWatchlist({
    required String name,
    required String listKey,
    required List<String> memberIds,
  }) async {
    final res = await _post(
      Uri.parse('$_base/watchlists'),
      headers: _json(),
      body: jsonEncode({'name': name, 'listKey': listKey, 'memberIds': memberIds}),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> regenerateListKey({
    required String watchlistId,
    required String listKey,
  }) async {
    final res = await _patch(
      Uri.parse('$_base/watchlists/$watchlistId/regenerate-key'),
      headers: _json(),
      body: jsonEncode({'listKey': listKey}),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> addMovie({
    required String watchlistId,
    required String movieId,
    required String title,
    required int year,
    required String addedBy,
    int runtime = 0,
    double rating = 0.0,
    List<String> genres = const [],
    String director = '',
    String streamId = '',
    String synopsis = '',
    String? imageUrl,
  }) async {
    final res = await _post(
      Uri.parse('$_base/watchlists/$watchlistId/movies'),
      headers: _json(),
      body: jsonEncode({
        'movieId': movieId,
        'title': title,
        'year': year,
        'addedBy': addedBy,
        'runtime': runtime,
        'rating': rating,
        'genres': genres,
        'director': director,
        'streamId': streamId,
        'synopsis': synopsis,
        if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      }),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> addMemberToWatchlist({
    required String watchlistId,
    required String userId,
  }) async {
    final res = await _patch(
      Uri.parse('$_base/watchlists/$watchlistId/members'),
      headers: _json(),
      body: jsonEncode({'userId': userId}),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> acceptWatchlistInvite({
    required String watchlistId,
    required String inviteId,
  }) async {
    final res = await _post(
      Uri.parse('$_base/watchlists/$watchlistId/invites/$inviteId/accept'),
      headers: _json(),
      body: jsonEncode({}),
    );
    return _decode(res);
  }

  static Future<void> declineWatchlistInvite({
    required String watchlistId,
    required String inviteId,
  }) async {
    final res = await _delete(
      Uri.parse('$_base/watchlists/$watchlistId/invites/$inviteId'),
      headers: _auth(),
    );
    _decode(res);
  }

  static Future<void> leaveWatchlist(String watchlistId) async {
    final res = await _delete(
      Uri.parse('$_base/watchlists/$watchlistId/members'),
      headers: _auth(),
    );
    _decode(res);
  }

  static Future<List<Map<String, dynamic>>> fetchPendingInvites(String userId) async {
    final res = await _get(
      Uri.parse('$_base/users/$userId/invites'),
      headers: _auth(),
    );
    if (res.statusCode >= 400) return [];
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchSentInvites(String userId) async {
    try {
      final res = await _get(
        Uri.parse('$_base/users/$userId/sent-invites'),
        headers: _auth(),
      );
      if (res.statusCode >= 400) return [];
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    } catch (_) { return []; }
  }

  static Future<Map<String, dynamic>> renameWatchlist({
    required String watchlistId,
    required String name,
  }) async {
    final res = await _patch(
      Uri.parse('$_base/watchlists/$watchlistId'),
      headers: _json(),
      body: jsonEncode({'name': name}),
    );
    return _decode(res);
  }

  static Future<void> deleteWatchlist(String watchlistId) async {
    final res = await _delete(
      Uri.parse('$_base/watchlists/$watchlistId'),
      headers: _auth(),
    );
    _decode(res);
  }

  static Future<Map<String, dynamic>> patchMovie({
    required String watchlistId,
    required String movieId,
    String? section,
    String? memberId,
    int? stars,
  }) async {
    final body = <String, dynamic>{};
    if (section   != null) body['section']   = section;
    if (memberId  != null) body['memberId']  = memberId;
    if (stars     != null) body['stars']     = stars;
    final res = await _patch(
      Uri.parse('$_base/watchlists/$watchlistId/movies/$movieId'),
      headers: _json(),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  static Future<void> promoteMovie({
    required String watchlistId,
    required String movieId,
    String? promotedBy,
  }) async {
    await _post(
      Uri.parse('$_base/watchlists/$watchlistId/movies/$movieId/promote'),
      headers: _json(),
      body: jsonEncode({'promotedBy': promotedBy}),
    );
  }

  static Future<void> removeMovie({
    required String watchlistId,
    required String movieId,
  }) async {
    final res = await _delete(
      Uri.parse('$_base/watchlists/$watchlistId/movies/$movieId'),
      headers: _auth(),
    );
    _decode(res);
  }

  static Future<Map<String, dynamic>> addNote({
    required String watchlistId,
    required String movieId,
    required String by,
    required String text,
  }) async {
    final res = await _post(
      Uri.parse('$_base/watchlists/$watchlistId/movies/$movieId/notes'),
      headers: _json(),
      body: jsonEncode({'by': by, 'text': text}),
    );
    return _decode(res);
  }


  static Future<Map<String, dynamic>> updateProfile({
    required String userId,
    String? displayName,
    String? avatarUrl,
    List<String>? bannerUrls,
  }) async {
    final body = <String, dynamic>{};
    if (displayName  != null) body['displayName']  = displayName;
    if (avatarUrl    != null) body['avatarUrl']     = avatarUrl;
    if (bannerUrls   != null) body['bannerUrls']    = bannerUrls;
    final res = await _patch(
      Uri.parse('$_base/users/$userId'),
      headers: _json(),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  static Future<String> uploadAvatar({
    required String userId,
    required String filePath,
  }) async {
    final Uint8List bytes = await File(filePath).readAsBytes();
    final ext = filePath.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    final res = await _post(
      Uri.parse('$_base/users/$userId/avatar'),
      headers: _json(),
      body: jsonEncode({'imageBase64': base64Encode(bytes), 'mimeType': ext}),
      timeout: const Duration(seconds: 30),
    );
    final body = _decode(res);
    return body['avatarUrl'] as String;
  }

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final res = await _get(
      Uri.parse('$_base/users?q=${Uri.encodeQueryComponent(query)}'),
      headers: _auth(),
    );
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        (jsonDecode(res.body) as Map<String, dynamic>)['error'] ?? 'Unknown error',
      );
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchUserWatchlists(String userId) async {
    final res = await _get(
      Uri.parse('$_base/users/$userId/watchlists'),
      headers: _auth(),
    );
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        (jsonDecode(res.body) as Map<String, dynamic>)['error'] ?? 'Unknown error',
      );
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> fetchUser(String userId, {String? requesterId}) async {
    var url = '$_base/users/$userId';
    if (requesterId != null) url += '?requesterId=${Uri.encodeQueryComponent(requesterId)}';
    final res = await _get(Uri.parse(url), headers: _auth());
    return _decode(res);
  }


  static Future<Map<String, dynamic>> sendFriendRequest({
    required String fromId,
    required String toId,
  }) async {
    final res = await _post(
      Uri.parse('$_base/friend-requests'),
      headers: _json(),
      body: jsonEncode({'fromId': fromId, 'toId': toId}),
    );
    return _decode(res);
  }

  static Future<List<Map<String, dynamic>>> fetchFriendRequests(String userId) async {
    final res = await _get(
      Uri.parse('$_base/users/$userId/friend-requests'),
      headers: _auth(),
    );
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        (jsonDecode(res.body) as Map<String, dynamic>)['error'] ?? 'Unknown error',
      );
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> acceptFriendRequest(String requestId) async {
    final res = await _patch(
      Uri.parse('$_base/friend-requests/$requestId/accept'),
      headers: _json(),
      body: jsonEncode({}),
    );
    _decode(res);
  }

  static Future<void> declineFriendRequest(String requestId) async {
    final res = await _delete(
      Uri.parse('$_base/friend-requests/$requestId'),
      headers: _auth(),
    );
    _decode(res);
  }

  static Future<List<Map<String, dynamic>>> fetchFriends(String userId) async {
    final res = await _get(
      Uri.parse('$_base/users/$userId/friends'),
      headers: _auth(),
    );
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        (jsonDecode(res.body) as Map<String, dynamic>)['error'] ?? 'Unknown error',
      );
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }


  static Future<List<Map<String, dynamic>>> fetchPublicReviews({int limit = 500}) async {
    final res = await _get(
      Uri.parse('$_base/reviews?limit=$limit'),
    );
    if (res.statusCode >= 400) return [];
    final body = jsonDecode(res.body);
    if (body is List) return body.cast<Map<String, dynamic>>();
    return (body['reviews'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchUserReviews(String userId) async {
    final res = await _get(
      Uri.parse('$_base/users/$userId/reviews'),
    );
    if (res.statusCode >= 400) return [];
    final body = jsonDecode(res.body);
    if (body is List) return body.cast<Map<String, dynamic>>();
    return (body['reviews'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchMovieReviews(String movieId) async {
    final res = await _get(
      Uri.parse('$_base/movies/$movieId/reviews'),
    );
    if (res.statusCode >= 400) return [];
    final body = jsonDecode(res.body);
    if (body is List) return body.cast<Map<String, dynamic>>();
    return (body['reviews'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchMovieWatchers(String movieId) async {
    final res = await _get(
      Uri.parse('$_base/movies/${Uri.encodeComponent(movieId)}/watchers'),
      headers: _auth(),
    );
    if (res.statusCode >= 400) return [];
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }


  static Future<Map<String, dynamic>> importLetterboxd(String filePath) async {
    final uri     = Uri.parse('$_base/import/letterboxd');
    final request = http.MultipartRequest('POST', uri);
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    try {
      final streamed  = await request.send().timeout(const Duration(seconds: 180));
      final response  = await http.Response.fromStream(streamed);
      if (response.statusCode >= 500) onServerDown?.call();
      return _decode(response);
    } on SocketException {
      onServerDown?.call();
      rethrow;
    } on http.ClientException {
      onServerDown?.call();
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> submitReview({
    required String byId,
    required String movieId,
    required String movieTitle,
    required int movieYear,
    String movieDirector = '',
    String? moviePosterUrl,
    required double stars,
    required String text,
    bool rewatch = false,
  }) async {
    final res = await _post(
      Uri.parse('$_base/reviews'),
      headers: _json(),
      timeout: const Duration(seconds: 30),
      body: jsonEncode({
        'byId': byId,
        'movieId': movieId,
        'movieTitle': movieTitle,
        'movieYear': movieYear,
        'movieDirector': movieDirector,
        if (moviePosterUrl != null) 'moviePosterUrl': moviePosterUrl,
        'stars': stars,
        'text': text,
        'rewatch': rewatch,
      }),
    );
    return _decode(res);
  }

  static Future<void> deleteReview(String reviewId) async {
    final res = await _delete(
      Uri.parse('$_base/reviews/$reviewId'),
      headers: _auth(),
    );
    _decode(res);
  }

  static Future<Map<String, dynamic>> likeReview(String reviewId, String userId) async {
    final res = await _patch(
      Uri.parse('$_base/reviews/$reviewId/like'),
      headers: _json(),
      body: jsonEncode({'userId': userId}),
    );
    return _decode(res);
  }


  static Future<List<Map<String, dynamic>>> fetchReviewComments(String reviewId) async {
    final res = await _get(
      Uri.parse('$_base/reviews/$reviewId/comments'),
    );
    if (res.statusCode >= 400) return [];
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> postReviewComment({
    required String reviewId,
    required String byId,
    required String text,
  }) async {
    final res = await _post(
      Uri.parse('$_base/reviews/$reviewId/comments'),
      headers: _json(),
      body: jsonEncode({'byId': byId, 'text': text}),
    );
    return _decode(res);
  }

  static Future<void> deleteReviewComment(String reviewId, String commentId) async {
    final res = await _delete(
      Uri.parse('$_base/reviews/$reviewId/comments/$commentId'),
      headers: _auth(),
    );
    _decode(res);
  }

  static Future<Map<String, dynamic>> likeReviewComment(
      String reviewId, String commentId, String userId) async {
    final res = await _patch(
      Uri.parse('$_base/reviews/$reviewId/comments/$commentId/like'),
      headers: _json(),
      body: jsonEncode({'userId': userId}),
    );
    return _decode(res);
  }


  static Future<Map<String, dynamic>?> fetchVetoSession(String watchlistId) async {
    try {
      final res = await _get(
        Uri.parse('$_base/watchlists/$watchlistId/veto'),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body is Map<String, dynamic> ? body : null;
      }
    } catch (_) {}
    return null;
  }


  static Future<void> followUser(String targetId, String myId) async {
    try {
      await _post(
        Uri.parse('$_base/users/$targetId/follow'),
        headers: _json(),
        body: jsonEncode({'followerId': myId}),
      );
    } catch (_) {}
  }

  static Future<void> unfollowUser(String targetId, String myId) async {
    try {
      await _delete(
        Uri.parse('$_base/users/$targetId/follow?followerId=${Uri.encodeQueryComponent(myId)}'),
        headers: _auth(),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> fetchUserSocialStats(String userId) async {
    try {
      final res = await _get(
        Uri.parse('$_base/users/$userId/social'),
        headers: _auth(),
      );
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return {'followerCount': 0, 'followingCount': 0};
  }

  static Future<List<String>> fetchFollowingIds(String myId) async {
    try {
      final res = await _get(
        Uri.parse('$_base/users/$myId/following'),
        headers: _auth(),
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is List) return body.cast<String>();
        return (body['ids'] as List? ?? []).cast<String>();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> likeWatchlist(String watchlistId, String userId) async {
    try {
      await _post(
        Uri.parse('$_base/watchlists/$watchlistId/like'),
        headers: _json(),
        body: jsonEncode({'userId': userId}),
      );
    } catch (_) {}
  }

  static Future<void> unlikeWatchlist(String watchlistId, String userId) async {
    try {
      await _delete(
        Uri.parse('$_base/watchlists/$watchlistId/like?userId=${Uri.encodeQueryComponent(userId)}'),
        headers: _auth(),
      );
    } catch (_) {}
  }


  static Future<List<Map<String, dynamic>>> fetchTopWatchlists({int limit = 20}) async {
    try {
      final res = await _get(
        Uri.parse('$_base/watchlists/top?limit=$limit'),
      );
      if (res.statusCode >= 400) return [];
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> fetchWatchedMovies(String userId) async {
    try {
      final res = await _get(
        Uri.parse('$_base/users/$userId/watched'),
        headers: _auth(),
      );
      if (res.statusCode >= 400) return [];
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> markMovieWatched(
    String userId, {
    required String movieId,
    String? posterUrl,
    String title = '',
    int year = 0,
  }) async {
    try {
      await _post(
        Uri.parse('$_base/users/$userId/watched'),
        headers: _json(),
        body: jsonEncode({
          'movieId': movieId,
          if (posterUrl != null) 'posterUrl': posterUrl,
          'title': title,
          'year': year,
        }),
      );
    } catch (_) {}
  }

  static Future<void> unmarkMovieWatched(String userId, String movieId) async {
    try {
      await _delete(
        Uri.parse('$_base/users/$userId/watched/${Uri.encodeComponent(movieId)}'),
        headers: _auth(),
      );
    } catch (_) {}
  }


  static Future<List<Map<String, dynamic>>> fetchWatchlistActivity(
      String watchlistId, {int limit = 50}) async {
    try {
      final res = await _get(
        Uri.parse('$_base/watchlists/$watchlistId/activity?limit=$limit'),
        headers: _auth(),
      );
      if (res.statusCode >= 400) return [];
      return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }


  static Future<Map<String, dynamic>> fetchCatalogStats() async {
    final res = await _get(
      Uri.parse('$_base/movies/catalog/stats'),
      headers: _auth(),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> bulkPullMovies() async {
    final res = await _post(
      Uri.parse('$_base/movies/bulk-pull'),
      headers: _json(),
      body: jsonEncode({}),
      timeout: const Duration(seconds: 120),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> fetchCatalog({
    int limit = 20,
    int offset = 0,
    String? q,
  }) async {
    var url = '$_base/movies/catalog?limit=$limit&offset=$offset';
    if (q != null && q.isNotEmpty) url += '&q=${Uri.encodeQueryComponent(q)}';
    final res = await _get(Uri.parse(url), headers: _auth());
    return _decode(res);
  }

  static Future<void> deleteCatalogEntry(String id) async {
    final res = await _delete(
      Uri.parse('$_base/movies/catalog/${Uri.encodeComponent(id)}'),
      headers: _auth(),
    );
    _decode(res);
  }


  static Future<void> submitBugReport({required String text, String? userId}) async {
    final res = await _post(
      Uri.parse('$_base/admin/bug-report'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'userId': userId}),
    );
    _decode(res);
  }

  // ── Séance ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> startSeance(String watchlistId) async {
    final res = await _post(
      Uri.parse('$_base/seance/start'),
      headers: _json(),
      body: jsonEncode({'watchlistId': watchlistId}),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> joinSeance(String watchlistId) async {
    final res = await _post(
      Uri.parse('$_base/seance/join'),
      headers: _json(),
      body: jsonEncode({'watchlistId': watchlistId}),
    );
    return _decode(res);
  }

  static Future<void> endSeance(String watchlistId) async {
    final res = await _delete(
      Uri.parse('$_base/seance/${Uri.encodeComponent(watchlistId)}'),
      headers: _auth(),
    );
    _decode(res);
  }

  static Future<Map<String, dynamic>> fetchSeanceSession(String watchlistId) async {
    final res = await _get(
      Uri.parse('$_base/seance/${Uri.encodeComponent(watchlistId)}'),
      headers: _auth(),
    );
    return _decode(res);
  }

  static Future<List<Map<String, dynamic>>> fetchActiveSeances() async {
    final res = await _get(
      Uri.parse('$_base/seance/active'),
      headers: _auth(),
    );
    final body = _decode(res);
    return (body['sessions'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchActiveVetoLobbies() async {
    final res = await _get(
      Uri.parse('$_base/watchlists/veto-lobbies'),
      headers: _auth(),
    );
    final body = _decode(res);
    return (body['lobbies'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> fetchHostToken(String watchlistId) async {
    final res = await _get(
      Uri.parse('$_base/seance/${Uri.encodeComponent(watchlistId)}/host-token'),
      headers: _auth(),
    );
    return _decode(res);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
