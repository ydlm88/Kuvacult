// models.dart — Data domain models for the entire app
import 'package:flutter/material.dart';

enum WatchSection { want, watching, watched }

extension WatchSectionExt on WatchSection {
  String get label {
    switch (this) {
      case WatchSection.want:
        return 'Want to Watch';
      case WatchSection.watching:
        return 'Watching';
      case WatchSection.watched:
        return 'Watched';
    }
  }
}

//Reactions need heavy rework
enum ReactionType { loved, cried, meh, cozy, want }

extension ReactionTypeExt on ReactionType {
  String get label {
    switch (this) {
      case ReactionType.loved:
        return 'Loved it';
      case ReactionType.cried:
        return 'Cried';
      case ReactionType.meh:
        return 'Meh';
      case ReactionType.cozy:
        return 'Cozy';
      case ReactionType.want:
        return 'Want';
    }
  }

  String get mark {
    switch (this) {
      case ReactionType.loved:
        return '♥';
      case ReactionType.cried:
        return '~';
      case ReactionType.meh:
        return '·';
      case ReactionType.cozy:
        return '◐';
      case ReactionType.want:
        return '+';
    }
  }
}

class PosterData {
  final Gradient gradient;
  final Color accent;
  final String style; 
  final String? imageUrl;

  const PosterData({
    required this.gradient,
    required this.accent,
    this.style = 'editorial',
    this.imageUrl,
  });
}

class MovieNote {
  final String by;   // member id
  final String text;
  final DateTime at;

  const MovieNote({required this.by, required this.text, required this.at});
}

class Review {
  final String id;
  final String byId;
  final String byName;
  final String byHandle;
  final Color byAvatarColor;
  final String? byAvatarUrl;
  final String movieId;
  final String movieTitle;
  final int movieYear;
  final String? moviePosterUrl;
  final String movieDirector;
  final double stars; 
  final String text;
  final DateTime at;
  int likes;
  int commentCount;
  final bool rewatch;
  bool likedByMe;

  Review({
    required this.id,
    required this.byId,
    required this.byName,
    required this.byHandle,
    required this.byAvatarColor,
    this.byAvatarUrl,
    required this.movieId,
    required this.movieTitle,
    required this.movieYear,
    this.moviePosterUrl,
    this.movieDirector = '',
    required this.stars,
    required this.text,
    required this.at,
    this.likes = 0,
    this.commentCount = 0,
    this.rewatch = false,
    this.likedByMe = false,
  });
}

class ReviewComment {
  final String id;
  final String reviewId;
  final String byId;
  final String byName;
  final String byHandle;
  final Color byAvatarColor;
  final String? byAvatarUrl;
  final String text;
  int likes;
  bool likedByMe;
  final DateTime at;

  ReviewComment({
    required this.id,
    required this.reviewId,
    required this.byId,
    required this.byName,
    required this.byHandle,
    required this.byAvatarColor,
    this.byAvatarUrl,
    required this.text,
    this.likes = 0,
    this.likedByMe = false,
    required this.at,
  });
}

class Movie {
  final String id;
  final String title;
  final int year;
  final int runtime;
  final double rating;
  final List<String> genres;
  final String director;
  final String streamId;
  final String addedBy;
  WatchSection section;
  final String synopsis;
  final String mediaType;
  Map<String, ReactionType> reactions;
  Map<String, double> stars;
  List<MovieNote> notes;
  List<String> watchedBy;
  final PosterData poster;

  Movie({
    required this.id,
    required this.title,
    required this.year,
    required this.runtime,
    required this.rating,
    required this.genres,
    required this.director,
    required this.streamId,
    required this.addedBy,
    required this.section,
    required this.synopsis,
    this.mediaType = 'movie',
    Map<String, ReactionType>? reactions,
    Map<String, double>? stars,
    List<MovieNote>? notes,
    List<String>? watchedBy,
    required this.poster,
  })  : reactions = reactions ?? {},
        stars = stars ?? {},
        notes = notes ?? [],
        watchedBy = watchedBy ?? [];
}

class StreamingService {
  final String id;
  final String name;
  final String abbr;
  final Color bg;
  final Color fg;

  const StreamingService({
    required this.id,
    required this.name,
    required this.abbr,
    required this.bg,
    required this.fg,
  });
}

class Member {
  final String id;
  final String name;
  final String initial;
  final Color avatarBg;

  const Member({
    required this.id,
    required this.name,
    required this.initial,
    required this.avatarBg,
  });
}

class Watchlist {
  final String id;
  String name;
  final String listKey;
  final List<String> memberIds;
  final List<Movie> movies;
  int likes;
  bool likedByMe;

  Watchlist({
    required this.id,
    required this.name,
    this.listKey = '',
    List<String>? memberIds,
    List<Movie>? movies,
    this.likes = 0,
    this.likedByMe = false,
  })  : memberIds = memberIds ?? [],
        movies = movies ?? [];
}

class UserAccount {
  final String id;
  final String username;
  final String email;
  String displayName;        
  final Color avatarBg;      
  String? avatarUrl;         
  String? roomKey;           
  List<String> friendIds;
  List<String> watchlistIds;

  UserAccount({
    required this.id,
    required this.username,
    required this.email,
    required this.displayName,
    required this.avatarBg,
    this.avatarUrl,
    this.roomKey,
    List<String>? friendIds,
    List<String>? watchlistIds,
  })  : friendIds = friendIds ?? [],
        watchlistIds = watchlistIds ?? [];
}

class FriendRequest {
  final String id;
  final String fromId;
  final String toId;
  final DateTime sentAt;
  bool accepted;
  final String? fromUsername;
  final String? fromDisplayName;
  final String? fromAvatarUrl;

  FriendRequest({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.sentAt,
    this.accepted = false,
    this.fromUsername,
    this.fromDisplayName,
    this.fromAvatarUrl,
  });
}

enum ActivityKind { added, reacted, note, rated, moved, vetoPick, vetoed, watched, postedReview }

class ActivityEvent {
  final String? id;
  final ActivityKind kind;
  final String who;
  final String? movieId;
  final ReactionType? reaction;
  final double? stars;
  final String? to;
  final List<String>? picks;
  final String? text;
  final DateTime at;

  const ActivityEvent({
    required this.kind,
    required this.who,
    this.id,
    this.movieId,
    this.reaction,
    this.stars,
    this.to,
    this.picks,
    this.text,
    required this.at,
  });
}

class WatchlistInvite {
  final String id;
  final String watchlistId;
  final String watchlistName;
  final String inviterId;
  final String inviterName;
  final String? inviterAvatarUrl;

  const WatchlistInvite({
    required this.id,
    required this.watchlistId,
    required this.watchlistName,
    required this.inviterId,
    required this.inviterName,
    this.inviterAvatarUrl,
  });
}

class VetoInvite {
  final String fromId;
  final String fromName;
  final String watchlistId;
  final String watchlistName;

  const VetoInvite({
    required this.fromId,
    required this.fromName,
    required this.watchlistId,
    required this.watchlistName,
  });
}

class BlackjackCard {
  final String suit;  // ♥ ♦ ♣ ♠
  final String rank;  // A 2 3 … 10 J Q K

  const BlackjackCard({required this.suit, required this.rank});

  int get value {
    if (rank == 'A') return 11;
    if (['J', 'Q', 'K'].contains(rank)) return 10;
    return int.parse(rank);
  }
}

class BlackjackPlayer {
  final String playerId;
  final String playerName;
  final String betMovieId;
  final List<BlackjackCard> hand;
  final bool stood;
  final bool bust;

  const BlackjackPlayer({
    required this.playerId,
    required this.playerName,
    required this.betMovieId,
    required this.hand,
    this.stood = false,
    this.bust = false,
  });

  int get handValue {
    int total = hand.fold(0, (s, c) => s + c.value);
    int aces = hand.where((c) => c.rank == 'A').length;
    while (total > 21 && aces > 0) { total -= 10; aces--; }
    return total;
  }

  BlackjackPlayer copyWith({List<BlackjackCard>? hand, bool? stood, bool? bust}) =>
      BlackjackPlayer(
        playerId: playerId,
        playerName: playerName,
        betMovieId: betMovieId,
        hand: hand ?? this.hand,
        stood: stood ?? this.stood,
        bust: bust ?? this.bust,
      );
}

enum NotifType {
  friendRequest,
  watchlistInvite,
  vetoInvite,
  likedReview,
  likedWatchlist,
  followed,
}

class AppNotification {
  final String id;
  final NotifType type;
  final DateTime at;
  bool read;

  final String? fromId;
  final String? fromName;
  final String? fromHandle;
  final String? fromAvatarUrl;

  final String? watchlistId;
  final String? watchlistName;
  final String? reviewId;
  final String? movieTitle;

  AppNotification({
    required this.id,
    required this.type,
    required this.at,
    this.read = false,
    this.fromId,
    this.fromName,
    this.fromHandle,
    this.fromAvatarUrl,
    this.watchlistId,
    this.watchlistName,
    this.reviewId,
    this.movieTitle,
  });
}

class BlackjackState {
  final List<BlackjackPlayer> players;
  final String status; // 'betting' | 'playing' | 'done' | 'redeal'
  final String? winnerId;
  final String? activePlayerId;
  final List<BlackjackCard> house;
  final bool houseRevealed;

  const BlackjackState({
    required this.players,
    required this.status,
    this.winnerId,
    this.activePlayerId,
    this.house = const [],
    this.houseRevealed = false,
  });

  static BlackjackCard _cardFromMap(Map<String, dynamic> m) =>
      BlackjackCard(suit: m['suit'] as String, rank: m['rank'] as String);

  static BlackjackPlayer _playerFromMap(Map<String, dynamic> m) =>
      BlackjackPlayer(
        playerId: m['playerId'] as String,
        playerName: m['playerName'] as String,
        betMovieId: m['betMovieId'] as String? ?? '',
        hand: (m['hand'] as List? ?? [])
            .map((c) => _cardFromMap(c as Map<String, dynamic>))
            .toList(),
        stood: m['stood'] as bool? ?? false,
        bust: m['bust'] as bool? ?? false,
      );

  factory BlackjackState.fromMap(Map<String, dynamic> m) => BlackjackState(
        players: (m['players'] as List? ?? [])
            .map((p) => _playerFromMap(p as Map<String, dynamic>))
            .toList(),
        status: m['status'] as String? ?? 'betting',
        winnerId: m['winnerId'] as String?,
        activePlayerId: m['activePlayerId'] as String?,
        house: (m['house'] as List? ?? [])
            .map((c) => _cardFromMap(c as Map<String, dynamic>))
            .toList(),
        houseRevealed: m['houseRevealed'] as bool? ?? false,
      );

  BlackjackState copyWith({
    List<BlackjackPlayer>? players,
    String? status,
    String? winnerId,
    String? activePlayerId,
    List<BlackjackCard>? house,
    bool? houseRevealed,
  }) =>
      BlackjackState(
        players: players ?? this.players,
        status: status ?? this.status,
        winnerId: winnerId ?? this.winnerId,
        activePlayerId: activePlayerId ?? this.activePlayerId,
        house: house ?? this.house,
        houseRevealed: houseRevealed ?? this.houseRevealed,
      );
}

class WatchedMovie {
  final String id;       // IMDb ID
  final String? posterUrl;
  final String title;
  final int year;

  const WatchedMovie({
    required this.id,
    this.posterUrl,
    this.title = '',
    this.year = 0,
  });
}

enum SortOrder { dateAdded, rating, runtime, title, year }

extension SortOrderExt on SortOrder {
  String get label {
    switch (this) {
      case SortOrder.dateAdded:
        return 'Date Added';
      case SortOrder.rating:
        return 'Rating';
      case SortOrder.runtime:
        return 'Runtime';
      case SortOrder.title:
        return 'Title';
      case SortOrder.year:
        return 'Year';
    }
  }
}
