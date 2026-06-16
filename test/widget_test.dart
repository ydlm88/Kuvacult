import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:marquee/main.dart';
import 'package:marquee/app_state.dart';
import 'package:marquee/models.dart';
import 'package:marquee/theme.dart';
import 'package:marquee/screens/onboarding.dart';

void main() {
  testWidgets('App renders onboarding screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MarqueeApp());
    await tester.pump();
    // The MARQUEE wordmark is always visible on the onboarding screen
    expect(find.text('MARQUEE'), findsOneWidget);
  });

  testWidgets('Onboarding has start and join buttons', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: MaterialApp(
          theme: MT.theme,
          home: const OnboardingScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Start a new room'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
  });

  // Mock data has been removed — AppState starts with an empty movie list
  testWidgets('AppState initialises with empty movie list', (WidgetTester tester) async {
    final state = AppState();
    expect(state.allMovies.isEmpty, true);
  });

  // Guest login sets the guest flag and clears movies/activity
  testWidgets('loginAsGuest sets isGuest and empty state', (WidgetTester tester) async {
    final state = AppState();
    state.loginAsGuest();
    expect(state.isGuest, true);
    expect(state.isLoggedIn, false);
    expect(state.currentUser?.id, 'guest');
    expect(state.allMovies.isEmpty, true);
    expect(state.activity.isEmpty, true);
  });

  // Adding a movie populates the watchlist
  testWidgets('AppState rateMovie updates star count', (WidgetTester tester) async {
    final state = AppState();
    // Add a minimal movie first so there is something to rate
    state.addMovieToWatchlist(_testMovie());
    final movieId = state.allMovies.first.id;
    state.rateMovie(movieId, 'guest', 4);
    expect(state.allMovies.first.stars['guest'], 4);
  });

  testWidgets('AppState addNote appends note to movie', (WidgetTester tester) async {
    final state = AppState();
    state.addMovieToWatchlist(_testMovie());
    final movie = state.allMovies.first;
    final initialCount = movie.notes.length;
    state.addNote(movie.id, 'guest', 'Great pick!');
    expect(state.findMovie(movie.id)!.notes.length, initialCount + 1);
  });

  testWidgets('AppState moveMovie changes section', (WidgetTester tester) async {
    final state = AppState();
    state.addMovieToWatchlist(_testMovie());
    final movie = state.allMovies.first;
    state.moveMovie(movie.id, WatchSection.watched);
    expect(state.findMovie(movie.id)!.section, WatchSection.watched);
  });

  testWidgets('Search sets loading true while fetching', (WidgetTester tester) async {
    final state = AppState();
    // Don't await — check loading flag immediately after kick-off
    final future = state.setSearchQuery('dune');
    expect(state.searchLoading, true);
    // Let it finish (network will fail in test env — results stay empty, that's fine)
    await future.catchError((_) {});
    expect(state.searchLoading, false);
  });

  testWidgets('Search clears results on empty query', (WidgetTester tester) async {
    final state = AppState();
    await state.setSearchQuery('').catchError((_) {});
    expect(state.searchResults.isEmpty, true);
    expect(state.searchLoading, false);
  });
}

// Minimal Movie fixture used by tests that need a movie in the watchlist
Movie _testMovie() {
  return Movie(
    id: 'test-movie',
    title: 'Test Film',
    year: 2024,
    runtime: 90,
    rating: 7.0,
    genres: ['Drama'],
    director: 'Test Director',
    streamId: 'none',
    addedBy: 'guest',
    section: WatchSection.want,
    synopsis: 'A film for testing.',
    poster: PosterData(
      gradient: const LinearGradient(
        colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      accent: const Color(0xFFF4ECDE),
    ),
  );
}
