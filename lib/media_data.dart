import 'dart:io';
import 'package:flutter/material.dart';
import 'models.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MediaData {
  static final String _base = Platform.isAndroid
      ? 'http://10.0.2.2:3000'
      : 'http://localhost:3000';

  static const _timeout = Duration(seconds: 14);

  Future<(List<Movie>, String?)> searchTitles(String query,
      {String? pageToken}) async {
    var url = '$_base/movies/search?q=${Uri.encodeComponent(query)}';
    if (pageToken != null) url += '&pageToken=${Uri.encodeComponent(pageToken)}';
    final res = await http.get(Uri.parse(url)).timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Search failed: ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final titles = (data['titles'] as List<dynamic>?) ?? [];
    final nextToken = data['nextPageToken'] as String?;
    return (titles.map(_titleToMovie).toList(), nextToken);
  }

  Future<Movie> fetchTitle(String imdbId) async {
    final res = await http
        .get(Uri.parse('$_base/movies/$imdbId'))
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Fetch failed: ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return _titleToMovie(data);
  }

  Future<(List<Movie>, String?)> fetchByGenre(String genre,
      {String? pageToken}) async {
    var url = '$_base/movies/genre?g=${Uri.encodeComponent(genre)}';
    if (pageToken != null) url += '&pageToken=${Uri.encodeComponent(pageToken)}';
    final res = await http.get(Uri.parse(url)).timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Genre search failed: ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final titles = (data['titles'] as List<dynamic>?) ?? [];
    final nextToken = data['nextPageToken'] as String?;
    return (titles.map(_titleToMovie).toList(), nextToken);
  }

  Future<List<Movie>> fetchTrending() async {
    final res = await http
        .get(Uri.parse('$_base/movies/trending'))
        .timeout(_timeout);
    if (res.statusCode != 200) throw Exception('Trending failed: ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final titles = (data['titles'] as List<dynamic>?) ?? [];
    return titles.take(20).map(_titleToMovie).toList();
  }

  Movie _titleToMovie(dynamic json) {
    final j = json as Map<String, dynamic>;
    final rating = j['rating'] as Map<String, dynamic>?;
    final runtimeSecs = (j['runtimeSeconds'] as num?)?.toInt() ?? 0;

    return Movie(
      id: j['id'] as String? ?? '',
      title: (j['primaryTitle'] ?? j['title'] ?? j['originalTitle'] ?? '') as String,
      year: (j['startYear'] as num?)?.toInt() ?? 0,
      runtime: (runtimeSecs / 60).round(),
      rating: (rating?['aggregateRating'] as num?)?.toDouble() ?? 0.0,
      genres: List<String>.from(j['genres'] as List? ?? []),
      director: _extractDirector(j),
      streamId: 'none',
      addedBy: 'search',
      section: WatchSection.want,
      synopsis: j['plot'] as String? ?? '',
      poster: _buildPoster(j),
    );
  }

  String _extractDirector(Map<String, dynamic> j) {
    final directors = j['directors'] as List?;
    if (directors == null || directors.isEmpty) return '';
    final first = directors.first as Map<String, dynamic>;
    return first['primaryName'] as String? ?? '';
  }

  PosterData _buildPoster(Map<String, dynamic> j) {
    final image = j['primaryImage'] as Map<String, dynamic>?;
    final imageUrl = image?['url'] as String?;
    return PosterData(
      gradient: const LinearGradient(
        colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accent: const Color(0xFFF4ECDE),
      style: 'editorial',
      imageUrl: imageUrl,
    );
  }
}
