import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiService {
  // Android emulator routes localhost through 10.0.2.2; every other platform uses localhost directly
  static final String _base = Platform.isAndroid
      ? 'http://10.0.2.2:3000'
      : 'http://localhost:3000';
  static const _timeout = Duration(seconds: 10);

  static Map<String, dynamic> _decode(http.Response res) {
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, body['error'] ?? 'Unknown error');
    }
    return body;
  }

  //Upsert method
  static Future<Map<String, dynamic>> upsertUser({
    required String auth0Sub,
    required String username,
    required String email,
    required String displayName,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'auth0Sub' : auth0Sub,
        'username' : username,
        'email' : email,
        'displayName' : displayName,
      }),
    ).timeout(_timeout);
    return _decode(res);
  }

  //Roomkey methods
  static Future<bool> checkRoomKey(String key) async {
    final res = await http.get(
      Uri.parse('$_base/users?roomKey=$key'),
    ).timeout(_timeout);
    final body = _decode(res);
    return body['exists'] as bool;
  }

  static Future<void> saveRoomKey({
    required String auth0Sub,
    required String roomKey,
  }) async {
    final res = await http.patch(
      Uri.parse('$_base/users/$auth0Sub'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'roomKey': roomKey}),
    ).timeout(_timeout);
    _decode(res);
  }

  static Future<Map<String, dynamic>> joinRoom({
    required String listKey,
    required String auth0Sub,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/watchlists/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'listKey': listKey, 'auth0Sub': auth0Sub}),
    ).timeout(_timeout);
    return _decode(res);
  }

  // Read-only room lookup — used by guests to view a room without joining as a member
  static Future<Map<String, dynamic>> findRoom({required String listKey}) async {
    final res = await http.get(
      Uri.parse('$_base/watchlists/find?code=${Uri.encodeQueryComponent(listKey)}'),
    ).timeout(_timeout);
    return _decode(res);
  }

  //CRUD methods
  static Future<Map<String, dynamic>> createWatchlist({
    required String name,
    required String listKey,
    required List<String> memberIds,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/watchlists'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'listKey': listKey, 'memberIds': memberIds}),
    ).timeout(_timeout);
    return _decode(res);
  }

  static Future<Map<String, dynamic>> regenerateListKey({
    required String watchlistId,
    required String listKey,
  }) async {
    final res = await http.patch(
      Uri.parse('$_base/watchlists/$watchlistId/regenerate-key'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'listKey': listKey}),
    ).timeout(_timeout);
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
    final res = await http.post(
      Uri.parse('$_base/watchlists/$watchlistId/movies'),
      headers: {'Content-Type': 'application/json'},
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
    ).timeout(_timeout);
    return _decode(res);
  }

  static Future<Map<String, dynamic>> addMemberToWatchlist({
    required String watchlistId,
    required String auth0Sub,
  }) async {
    final res = await http.patch(
      Uri.parse('$_base/watchlists/$watchlistId/members'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'auth0Sub': auth0Sub}),
    ).timeout(_timeout);
    return _decode(res);
  }

  static Future<Map<String, dynamic>> renameWatchlist({
    required String watchlistId,
    required String name,
  }) async {
    final res = await http.patch(
      Uri.parse('$_base/watchlists/$watchlistId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    ).timeout(_timeout);
    return _decode(res);
  }

  static Future<void> deleteWatchlist(String watchlistId) async {
    final res = await http.delete(
      Uri.parse('$_base/watchlists/$watchlistId'),
    ).timeout(_timeout);
    _decode(res);
  }

  static Future<Map<String, dynamic>> patchMovie({
    required String watchlistId,
    required String movieId,
    String? section,
    String? memberId,
    int? stars,
    String? reaction,
  }) async {
    final body = <String, dynamic>{};
    if (section != null) body['section'] = section;
    if (memberId != null) body['memberId'] = memberId;
    if (stars != null) body['stars'] = stars;
    if (reaction != null) body['reaction'] = reaction;
    final res = await http.patch(
      Uri.parse('$_base/watchlists/$watchlistId/movies/$movieId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(_timeout);
    return _decode(res);
  }

  static Future<void> removeMovie({
    required String watchlistId,
    required String movieId,
  }) async {
    final res = await http.delete(
      Uri.parse('$_base/watchlists/$watchlistId/movies/$movieId'),
    ).timeout(_timeout);
    _decode(res);
  }

  static Future<Map<String, dynamic>> addNote({
    required String watchlistId,
    required String movieId,
    required String by,
    required String text,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/watchlists/$watchlistId/movies/$movieId/notes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'by': by, 'text': text}),
    ).timeout(_timeout);
    return _decode(res);
  }

  static Future<Map<String, dynamic>> updateProfile({
    required String auth0Sub,
    String? displayName,
    String? avatarUrl,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['displayName'] = displayName;
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    final res = await http.patch(
      Uri.parse('$_base/users/$auth0Sub'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(_timeout);
    return _decode(res);
  }

  // Uploads a local image file to Firebase Storage via the backend.
  // Returns the public download URL. Throws on failure.
  static Future<String> uploadAvatar({
    required String auth0Sub,
    required String filePath,
  }) async {
    final Uint8List bytes = await File(filePath).readAsBytes();
    final String imageBase64 = base64Encode(bytes);
    final ext = filePath.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    final res = await http.post(
      Uri.parse('$_base/users/$auth0Sub/avatar'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'imageBase64': imageBase64, 'mimeType': ext}),
    ).timeout(const Duration(seconds: 30));
    final body = _decode(res);
    return body['avatarUrl'] as String;
  }

  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final res = await http.get(
      Uri.parse('$_base/users?q=${Uri.encodeQueryComponent(query)}'),
    ).timeout(_timeout);
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        (jsonDecode(res.body) as Map<String, dynamic>)['error'] ?? 'Unknown error',
      );
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchUserWatchlists(String auth0Sub) async {
    final res = await http.get(
      Uri.parse('$_base/users/$auth0Sub/watchlists'),
    ).timeout(_timeout);
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        (jsonDecode(res.body) as Map<String, dynamic>)['error'] ?? 'Unknown error',
      );
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  //Friend request methods
  static Future<Map<String, dynamic>> sendFriendRequest({
    required String fromId,
    required String toId,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/friend-requests'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fromId': fromId, 'toId': toId}),
      ).timeout(_timeout);
      return _decode(res);
  }

  static Future<List<Map<String, dynamic>>> fetchFriendRequests(String auth0Sub) async{
    final res = await http.get(
      Uri.parse('$_base/users/$auth0Sub/friend-requests'),
    ).timeout(_timeout);

    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        (jsonDecode(res.body) as Map<String, dynamic>)['error'] ?? 'Unkown error',
      );
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> acceptFriendRequest(String requestId) async {
    final res = await http.patch(
      Uri.parse('$_base/friend-requests/$requestId/accept'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(_timeout);
    _decode(res);
  }

  static Future<void> declineFriendRequest(String requestId) async{
    final res = await http.delete(
      Uri.parse('$_base/friend-requests/$requestId'),
    ).timeout(_timeout);
    _decode(res);
  }

  static Future<List<Map<String, dynamic>>> fetchFriends(String auth0Sub) async {
    final res = await http.get(
      Uri.parse('$_base/users/$auth0Sub/friends'),
    ).timeout(_timeout);
    if (res.statusCode >= 400){
      throw ApiException(
        res.statusCode,
        (jsonDecode(res.body) as Map<String, dynamic>)['error'] ?? 'Unkown error',
      );
    }

    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> fetchUser(String auth0Sub, {String? requesterId}) async {
    var url = '$_base/users/$auth0Sub';
    if (requesterId != null) url += '?requesterId=${Uri.encodeQueryComponent(requesterId)}';
    final res = await http.get(Uri.parse(url)).timeout(_timeout);
    return _decode(res);
  }

  // ─── Reviews ───────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchPublicReviews({int page = 1}) async {
    final res = await http.get(
      Uri.parse('$_base/reviews?page=$page'),
    ).timeout(_timeout);
    if (res.statusCode >= 400) return [];
    final body = jsonDecode(res.body);
    if (body is List) return body.cast<Map<String, dynamic>>();
    return (body['reviews'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchUserReviews(String userId) async {
    final res = await http.get(
      Uri.parse('$_base/users/$userId/reviews'),
    ).timeout(_timeout);
    if (res.statusCode >= 400) return [];
    final body = jsonDecode(res.body);
    if (body is List) return body.cast<Map<String, dynamic>>();
    return (body['reviews'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchMovieReviews(String movieId) async {
    final res = await http.get(
      Uri.parse('$_base/movies/$movieId/reviews'),
    ).timeout(_timeout);
    if (res.statusCode >= 400) return [];
    final body = jsonDecode(res.body);
    if (body is List) return body.cast<Map<String, dynamic>>();
    return (body['reviews'] as List? ?? []).cast<Map<String, dynamic>>();
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
    final res = await http.post(
      Uri.parse('$_base/reviews'),
      headers: {'Content-Type': 'application/json'},
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
    ).timeout(_timeout);
    return _decode(res);
  }

  static Future<Map<String, dynamic>> likeReview(String reviewId) async {
    final res = await http.patch(
      Uri.parse('$_base/reviews/$reviewId/like'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(_timeout);
    return _decode(res);
  }

  static Future<Map<String, dynamic>?> fetchVetoSession(String watchlistId) async {
    try {
      final res = await http.get(
        Uri.parse('$_base/watchlists/$watchlistId/veto'),
      ).timeout(_timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body is Map<String, dynamic> ? body : null;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> followUser(String targetId, String myId) async {
    try {
      await http.post(Uri.parse('$_base/users/$targetId/follow'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'followerId': myId}),
      ).timeout(_timeout);
    } catch (_) {}
  }

  static Future<void> unfollowUser(String targetId, String myId) async {
    try {
      await http.delete(
        Uri.parse('$_base/users/$targetId/follow?followerId=${Uri.encodeQueryComponent(myId)}'),
      ).timeout(_timeout);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> fetchUserSocialStats(String userId) async {
    try {
      final res = await http.get(Uri.parse('$_base/users/$userId/social')).timeout(_timeout);
      if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    return {'followerCount': 0, 'followingCount': 0};
  }

  static Future<List<String>> fetchFollowingIds(String myId) async {
    try {
      final res = await http.get(Uri.parse('$_base/users/$myId/following')).timeout(_timeout);
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
      await http.post(Uri.parse('$_base/watchlists/$watchlistId/like'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId}),
      ).timeout(_timeout);
    } catch (_) {}
  }

  static Future<void> unlikeWatchlist(String watchlistId, String userId) async {
    try {
      await http.delete(
        Uri.parse('$_base/watchlists/$watchlistId/like?userId=${Uri.encodeQueryComponent(userId)}'),
      ).timeout(_timeout);
    } catch (_) {}
  }
}



class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}