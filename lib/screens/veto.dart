import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme.dart';
import '../models.dart';
import '../app_state.dart';
import '../services/api_service.dart';
import '../services/veto_service.dart';
import '../widgets/poster.dart';
import '../widgets/stream_badge.dart';
import 'detail.dart';

class VetoScreen extends StatefulWidget {
  const VetoScreen({super.key});

  @override
  State<VetoScreen> createState() => _VetoScreenState();
}

class _VetoScreenState extends State<VetoScreen> {
  List<String> _pickedIds = [];
  Set<String> _vetoedIds = {};
  Set<String> _myPickIds = {};
  Set<String> _myVetoIds = {};
  int _serverMaxVetos = 2;

  BlackjackState? _blackjack;

  VetoService? _veto;
  StreamSubscription<VetoEvent>? _sub;
  String? _watchlistId;
  bool _sendInvite = true;

  bool _canVeto(String movieId) =>
      !_vetoedIds.contains(movieId) &&
      !_myVetoIds.contains(movieId) &&
      _myVetoIds.length < _serverMaxVetos;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final wls = context.read<AppState>().watchlists;
      if (wls.length == 1) _connect(wls.first.id);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _veto?.dispose();
    super.dispose();
  }

  Future<void> _connect(String wlId) async {
    _sub?.cancel();
    _veto?.dispose();
    _watchlistId = wlId;
    _veto = VetoService()..connect(wlId);
    _sub = _veto!.events.listen(_handleEvent);
    if (mounted) {
      setState(() {
        _pickedIds = [];
        _vetoedIds = {};
        _myPickIds = {};
        _myVetoIds = {};
        _blackjack = null;
      });
    }
    final session = await ApiService.fetchVetoSession(wlId);
    if (session != null && mounted) {
      setState(() {
        _pickedIds = (session['pickedIds'] as List?)?.cast<String>() ?? [];
        _vetoedIds = Set<String>.from(
            (session['vetoedIds'] as List?)?.cast<String>() ?? []);
        _serverMaxVetos = (session['maxVetosPerPlayer'] as num?)?.toInt() ?? 2;
        final bjData = session['blackjack'] as Map<String, dynamic>?;
        _blackjack = bjData != null ? BlackjackState.fromMap(bjData) : null;
      });
    }
  }

  void _clearVeto() {
    setState(() {
      _pickedIds = [];
      _vetoedIds = {};
      _myPickIds = {};
      _myVetoIds = {};
      _blackjack = null;
      _serverMaxVetos = 2;
    });
    _veto?.resetGame();
  }

  void _handleEvent(VetoEvent e) {
    switch (e.type) {
      case 'veto_state':
      case 'veto_started':
        setState(() {
          _pickedIds = (e.data['pickedIds'] as List).cast<String>();
          _vetoedIds = Set<String>.from(
              (e.data['vetoedIds'] as List?)?.cast<String>() ?? []);
          _serverMaxVetos = (e.data['maxVetosPerPlayer'] as num?)?.toInt() ?? 2;
          _myPickIds = {};
          _myVetoIds = {};
          final bjData = e.data['blackjack'] as Map<String, dynamic>?;
          _blackjack = bjData != null ? BlackjackState.fromMap(bjData) : null;
        });
        if (e.data['status'] == 'blackjack_betting' && _blackjack == null) {
          setState(() => _blackjack = const BlackjackState(players: [], status: 'betting'));
        }
      case 'veto_reset':
        setState(() {
          _pickedIds = [];
          _vetoedIds = {};
          _myPickIds = {};
          _myVetoIds = {};
          _blackjack = null;
          _serverMaxVetos = 2;
        });
      case 'picks_added':
        setState(() {
          _pickedIds = (e.data['pickedIds'] as List).cast<String>();
          _serverMaxVetos = (e.data['maxVetosPerPlayer'] as num?)?.toInt() ?? _serverMaxVetos;
        });
      case 'veto_actioned':
        setState(() => _vetoedIds.add(e.data['vetoedId'] as String));
      case 'blackjack_start':
        setState(() => _blackjack = const BlackjackState(players: [], status: 'betting'));
      case 'blackjack_update':
        final bjData = e.data['blackjack'] as Map<String, dynamic>?;
        if (bjData != null) setState(() => _blackjack = BlackjackState.fromMap(bjData));
      case 'veto_winner':
        context.read<AppState>().promoteToTopPick(e.data['winnerId'] as String);
        if (_blackjack != null) {
          setState(() => _blackjack = _blackjack!.copyWith(
            status: 'done',
            winnerId: e.data['winnerId'] as String?,
            houseRevealed: true,
          ));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final watchlists = state.watchlists;

    if (watchlists.length == 1 && _watchlistId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _watchlistId == null) _connect(watchlists.first.id);
      });
    }

    final selectedWl = _watchlistId != null
        ? watchlists.cast<Watchlist?>().firstWhere(
            (w) => w?.id == _watchlistId, orElse: () => null)
        : null;

    final allWatchlistMovies = selectedWl?.movies ?? [];

    final picks = _pickedIds
        .map((id) => allWatchlistMovies.cast<Movie?>()
            .firstWhere((m) => m?.id == id, orElse: () => null))
        .whereType<Movie>()
        .toList();

    final remaining = picks.where((p) => !_vetoedIds.contains(p.id)).toList();
    final winnerMovie = remaining.length == 1 ? remaining.first : null;
    final myVetosLeft = _serverMaxVetos - _myVetoIds.length;

    final bool poolEmpty = _pickedIds.isEmpty;
    final bool hasWinner = remaining.length == 1 && _pickedIds.isNotEmpty;
    final bool userHasPicked = _myPickIds.isNotEmpty;
    final bool inBlackjack = _blackjack != null;

    final String buttonLabel = poolEmpty
        ? 'Start a veto game'
        : (hasWinner || userHasPicked)
            ? 'Start new round'
            : 'Add my picks';

    return Scaffold(
      backgroundColor: MC.bg0,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 62, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Tonight's Ritual",
                          style: MT.mono(size: 10, letterSpacing: 2)),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          style: MT.display(size: 34),
                          children: [
                            const TextSpan(text: 'Pick'),
                            TextSpan(
                                text: ' · ',
                                style: MT.display(
                                    size: 34, italic: true, color: MC.accent1)),
                            const TextSpan(text: 'Veto All'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _buildDescription(winnerMovie, picks.length, remaining.length, myVetosLeft),
                        style: const TextStyle(fontSize: 13, color: MC.mute, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),

              if (watchlists.length > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: _WatchlistSelector(
                      watchlists: watchlists,
                      selectedId: _watchlistId,
                      onSelect: (wl) {
                        if (wl.id != _watchlistId) _connect(wl.id);
                      },
                    ),
                  ),
                ),

              if (_pickedIds.isEmpty && _watchlistId != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: allWatchlistMovies.isEmpty
                        ? const _EmptyState(
                            icon: Icons.search_rounded,
                            headline: 'Your queue is empty',
                            body: 'Search for movies and add them to your watchlist, then come back to start a veto.',
                          )
                        : const _EmptyState(
                            icon: Icons.how_to_vote_outlined,
                            headline: 'Ready for tonight\'s film?',
                            body: 'Each person picks 1–3 films. Last one standing wins.',
                          ),
                  ),
                ),

              if (_pickedIds.isEmpty && _watchlistId == null)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _EmptyState(
                      icon: Icons.how_to_vote_outlined,
                      headline: 'Choose a watchlist',
                      body: 'Select which list to run the veto game for.',
                    ),
                  ),
                ),

              if (_pickedIds.isNotEmpty)
                SliverToBoxAdapter(child: _buildStatusBar(myVetosLeft)),

              if (_pickedIds.isNotEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: _TicketStub(
                        movie: picks[i],
                        index: i,
                        isVetoed: _vetoedIds.contains(picks[i].id),
                        isWinner: winnerMovie?.id == picks[i].id,
                        canVeto: _canVeto(picks[i].id) && !inBlackjack,
                        onVeto: () {
                          final s = context.read<AppState>();
                          setState(() {
                            _myVetoIds.add(picks[i].id);
                            _vetoedIds.add(picks[i].id);
                          });
                          _veto?.vetoMovie(
                            vetoedId: picks[i].id,
                            vetoerId: s.currentUser?.id ?? 'guest',
                            vetoerName: s.currentUser?.displayName ?? 'Guest',
                          );
                        },
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DetailScreen(movie: picks[i])),
                        ),
                      ),
                    ),
                    childCount: picks.length,
                  ),
                ),

              if (winnerMovie != null && !inBlackjack)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: _WinnerCard(movie: winnerMovie),
                  ),
                ),

              if (_watchlistId != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: GestureDetector(
                      onTap: allWatchlistMovies.isEmpty
                          ? null
                          : () {
                              if (buttonLabel == 'Start new round') _clearVeto();
                              _showPickerSheet(context, state, selectedWl!);
                            },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: allWatchlistMovies.isEmpty ? MC.bg2 : MC.bg1,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: MC.line, width: 0.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          buttonLabel,
                          style: TextStyle(
                            color: allWatchlistMovies.isEmpty ? MC.dim : MC.mute,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),

          // Blackjack full-screen overlay
          if (inBlackjack)
            _BlackjackOverlay(
              bj: _blackjack!,
              remaining: remaining,
              currentUserId: state.currentUser?.id ?? 'guest',
              currentUserName: state.currentUser?.displayName ?? 'Guest',
              onBet: (movieId) => _veto?.blackjackBet(
                playerId: state.currentUser?.id ?? 'guest',
                playerName: state.currentUser?.displayName ?? 'Guest',
                betMovieId: movieId,
              ),
              onHit: () => _veto?.blackjackHit(playerId: state.currentUser?.id ?? 'guest'),
              onStand: () => _veto?.blackjackStand(playerId: state.currentUser?.id ?? 'guest'),
              onDealAgain: () => _veto?.blackjackDealAgain(),
              onClear: _clearVeto,
            ),
        ],
      ),
    );
  }

  String _buildDescription(Movie? winner, int pickCount, int remaining, int vetosLeft) {
    if (winner != null) return '${winner.title} survived the veto. Tonight\'s film is decided.';
    if (pickCount == 0) return 'Everyone picks 1–3 films. Last one standing is tonight\'s film.';
    return '$pickCount picks in the pool · $remaining still standing · $vetosLeft of your vetos left';
  }

  Widget _buildStatusBar(int myVetosLeft) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${_pickedIds.length} PICKS  ·  ${_pickedIds.length - _vetoedIds.length} REMAINING',
                style: MT.mono(size: 9, letterSpacing: 1.5),
              ),
              const Spacer(),
              Text('YOUR VETOS: $myVetosLeft LEFT',
                  style: MT.mono(size: 9, color: MC.accent1, letterSpacing: 1.5)),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _clearVeto,
                child: Text('CLEAR', style: MT.mono(size: 9, color: MC.dim, letterSpacing: 1.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _serverMaxVetos > 0 ? _myVetoIds.length / _serverMaxVetos : 0,
              minHeight: 3,
              color: MC.accent1,
              backgroundColor: MC.bg2,
            ),
          ),
        ],
      ),
    );
  }

  void _showPickerSheet(BuildContext context, AppState state, Watchlist watchlist) {
    final isNewRound = _pickedIds.isEmpty;
    final currentUserId = state.currentUser?.id ?? 'guest';

    if (!isNewRound &&
        watchlist.movies.where((m) => !_pickedIds.contains(m.id)).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('All watchlist films are already in the pool.'),
        backgroundColor: MC.bg1,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    final Set<String> selected = {};
    String pickerSearch = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MC.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final liveState = Provider.of<AppState>(ctx, listen: true);
          final liveWl = liveState.watchlists.cast<Watchlist?>()
              .firstWhere((w) => w?.id == _watchlistId, orElse: () => null);
          final allMovies = liveWl?.movies ?? watchlist.movies;
          final available = allMovies.where((m) => !_pickedIds.contains(m.id)).toList();
          final sourceList = isNewRound ? allMovies : available;
          final query = pickerSearch.toLowerCase().trim();
          final filtered = query.isEmpty
              ? sourceList
              : sourceList.where((m) => m.title.toLowerCase().contains(query)).toList();

          const maxPicks = 3;
          final canConfirm = selected.isNotEmpty;

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scroll) => Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: MC.dim, borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Text(isNewRound ? 'Pick 1–3 films' : 'Add your picks',
                          style: MT.display(size: 20)),
                      const Spacer(),
                      Text('${selected.length}/$maxPicks',
                          style: MT.mono(size: 12, color: MC.accent1, letterSpacing: 0)),
                    ],
                  ),
                ),
                if (!isNewRound)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      '${_pickedIds.length} picks in pool — choose 1–3 different films',
                      style: const TextStyle(color: MC.dim, fontSize: 12),
                    ),
                  ),
                if (isNewRound)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
                    child: GestureDetector(
                      onTap: () => setS(() => _sendInvite = !_sendInvite),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _sendInvite,
                            onChanged: (v) => setS(() => _sendInvite = v ?? true),
                            activeColor: MC.accent1,
                            checkColor: MC.accentInk,
                            side: const BorderSide(color: MC.dim),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 4),
                          const Text('Notify members to join',
                              style: TextStyle(color: MC.mute, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: MC.bg2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MC.line, width: 0.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, color: MC.dim, size: 15),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setS(() => pickerSearch = v),
                            style: const TextStyle(color: MC.ink, fontSize: 14),
                            decoration: const InputDecoration(
                              hintText: 'Search your watchlist…',
                              hintStyle: TextStyle(color: MC.dim),
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              border: InputBorder.none,
                            ),
                            cursorColor: MC.accent1,
                          ),
                        ),
                        if (pickerSearch.isNotEmpty)
                          GestureDetector(
                            onTap: () => setS(() => pickerSearch = ''),
                            child: const Icon(Icons.close_rounded, color: MC.dim, size: 14),
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            query.isEmpty ? 'No films available' : 'No results for "$pickerSearch"',
                            style: const TextStyle(color: MC.dim, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          controller: scroll,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final m = filtered[i];
                            final isSel = selected.contains(m.id);
                            final alreadyPicked = !isNewRound && _pickedIds.contains(m.id);
                            return ListTile(
                              leading: PosterWidget(movie: m, width: 36, height: 54),
                              title: Text(m.title,
                                  style: TextStyle(color: alreadyPicked ? MC.dim : MC.ink)),
                              subtitle: Text(
                                alreadyPicked
                                    ? 'Already in pool'
                                    : '${m.director.isNotEmpty ? m.director : m.year.toString()}  ·  ${m.section.label}',
                                style: TextStyle(
                                    color: alreadyPicked ? MC.dim : MC.mute,
                                    fontSize: 12),
                              ),
                              trailing: alreadyPicked
                                  ? const Icon(Icons.lock_outline_rounded, color: MC.dim, size: 16)
                                  : isSel
                                      ? const Icon(Icons.check_circle_rounded, color: MC.accent1)
                                      : const Icon(Icons.circle_outlined, color: MC.dim),
                              onTap: alreadyPicked
                                  ? null
                                  : () {
                                      setS(() {
                                        if (isSel) {
                                          selected.remove(m.id);
                                        } else if (selected.length < maxPicks) {
                                          selected.add(m.id);
                                        }
                                      });
                                    },
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: GestureDetector(
                    onTap: canConfirm
                        ? () {
                            final ids = selected.toList();
                            final pc = ids.length;
                            final maxV = (pc - 1).clamp(0, 2);
                            if (isNewRound) {
                              _veto?.startGame(
                                pickedIds: ids,
                                pickerId: currentUserId,
                                pickerName: state.currentUser?.displayName ?? 'You',
                                pickCount: pc,
                                sendInvite: _sendInvite,
                              );
                              setState(() {
                                _pickedIds = ids;
                                _vetoedIds = {};
                                _myPickIds = Set.from(ids);
                                _myVetoIds = {};
                                _serverMaxVetos = maxV;
                                if (pc == 1) {
                                  _blackjack = const BlackjackState(players: [], status: 'betting');
                                }
                              });
                            } else {
                              _veto?.addPicks(
                                additionalPickIds: ids,
                                pickerId: currentUserId,
                                pickerName: state.currentUser?.displayName ?? 'You',
                                pickCount: pc,
                              );
                              setState(() {
                                _pickedIds = [..._pickedIds, ...ids];
                                _myPickIds = Set.from(ids);
                              });
                            }
                            Navigator.pop(ctx);
                          }
                        : null,
                    child: Container(
                      width: double.infinity,
                      height: 48,
                      decoration: BoxDecoration(
                        color: canConfirm ? MC.accent1 : MC.bg2,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        selected.isEmpty
                            ? 'Pick at least 1 film'
                            : 'Confirm ${selected.length} pick${selected.length == 1 ? "" : "s"}',
                        style: TextStyle(
                          color: canConfirm ? MC.accentInk : MC.dim,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Blackjack overlay ─────────────────────────────────────────────────────────
class _BlackjackOverlay extends StatefulWidget {
  final BlackjackState bj;
  final List<Movie> remaining;
  final String currentUserId;
  final String currentUserName;
  final ValueChanged<String> onBet;
  final VoidCallback onHit;
  final VoidCallback onStand;
  final VoidCallback onDealAgain;
  final VoidCallback onClear;

  const _BlackjackOverlay({
    required this.bj,
    required this.remaining,
    required this.currentUserId,
    required this.currentUserName,
    required this.onBet,
    required this.onHit,
    required this.onStand,
    required this.onDealAgain,
    required this.onClear,
  });

  @override
  State<_BlackjackOverlay> createState() => _BlackjackOverlayState();
}

class _BlackjackOverlayState extends State<_BlackjackOverlay> {
  String? _mySelectedMovieId;
  bool _betSent = false;

  @override
  Widget build(BuildContext context) {
    final bj = widget.bj;

    final myPlayer = bj.players.cast<BlackjackPlayer?>()
        .firstWhere((p) => p?.playerId == widget.currentUserId, orElse: () => null);
    final hasBet = myPlayer != null;

    final isBetting = bj.status == 'betting';
    final isPlaying = bj.status == 'playing';
    final isDone = bj.status == 'done';
    final isRedeal = bj.status == 'redeal';
    final isMyTurn = bj.activePlayerId == widget.currentUserId;

    // Build status line text
    final String statusText;
    if (isDone) {
      final winner = bj.players.cast<BlackjackPlayer?>()
          .firstWhere((p) => p?.betMovieId == bj.winnerId, orElse: () => null);
      final name = winner == null
          ? ''
          : (winner.playerId == widget.currentUserId ? 'You' : winner.playerName);
      final movieTitle = widget.remaining.cast<Movie?>()
          .firstWhere((m) => m?.id == bj.winnerId, orElse: () => null)?.title ?? '';
      statusText = name.isEmpty
          ? 'Game over'
          : '${name == 'You' ? 'You win' : '$name wins'} · $movieTitle breaks the veto';
    } else if (isRedeal) {
      statusText = 'House wins · deal again';
    } else if (isPlaying && isMyTurn) {
      statusText = 'Your turn — hit or stand';
    } else if (isPlaying) {
      final activeP = bj.players.cast<BlackjackPlayer?>()
          .firstWhere((p) => p?.playerId == bj.activePlayerId, orElse: () => null);
      statusText = activeP != null ? '${activeP.playerName}\'s turn…' : 'Waiting…';
    } else if (isBetting && (hasBet || _betSent)) {
      statusText = 'Waiting for other player to bet…';
    } else {
      statusText = 'Bet on the film you want to win';
    }

    return Container(
      color: const Color(0xD0070504),
      child: SafeArea(
        bottom: false, // bottom clearance handled manually to stay above app tab bar
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                children: [
                  Text('BLACKJACK TIEBREAKER',
                      style: MT.mono(size: 11, color: MC.accent1, letterSpacing: 3)),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onClear,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: MC.line),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('CLEAR',
                          style: MT.mono(size: 9, color: MC.mute, letterSpacing: 2)),
                    ),
                  ),
                ],
              ),
            ),

            // ── Betting phase ────────────────────────────────────────────────────
            if (isBetting) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Text(statusText,
                    style: const TextStyle(color: MC.mute, fontSize: 14),
                    textAlign: TextAlign.center),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: widget.remaining.map((m) {
                      final serverBet = bj.players.cast<BlackjackPlayer?>()
                          .firstWhere((p) => p?.betMovieId == m.id, orElse: () => null);
                      final isMyBet = serverBet?.playerId == widget.currentUserId ||
                          (_mySelectedMovieId == m.id);
                      final isOtherBet = serverBet != null &&
                          serverBet.playerId != widget.currentUserId;
                      final otherName = isOtherBet ? serverBet.playerName : null;
                      final canSelect = !(hasBet || _betSent);

                      return GestureDetector(
                        onTap: canSelect
                            ? () => setState(() => _mySelectedMovieId = m.id)
                            : null,
                        child: _BetCard(
                          movie: m,
                          isMyBet: isMyBet,
                          isOtherBet: isOtherBet,
                          otherPlayerName: otherName,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              // Confirm button — 100dp from screen bottom clears the app tab bar (top at 92dp)
              if (_mySelectedMovieId != null && !_betSent && !hasBet)
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 100 + MediaQuery.of(context).viewInsets.bottom),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _betSent = true);
                      widget.onBet(_mySelectedMovieId!);
                    },
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [MC.accent1, MC.accent2],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                              color: MC.accent1.withAlpha(56),
                              blurRadius: 18,
                              offset: const Offset(0, 6)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: () {
                        final selTitle = widget.remaining.cast<Movie?>()
                            .firstWhere((mo) => mo?.id == _mySelectedMovieId,
                                orElse: () => null)
                            ?.title ?? '';
                        return Text('Bet on $selTitle',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: MC.accentInk,
                            ));
                      }(),
                    ),
                  ),
                )
              else
                const SizedBox(height: 100),
            ],

            // ── Playing / result phase ───────────────────────────────────────────
            if (!isBetting) ...[
              // House strip
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                child: _HouseRow(
                  house: bj.house,
                  reveal: bj.houseRevealed || isDone || isRedeal,
                ),
              ),

              // Player rows
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  children: [
                    ...bj.players.map((p) {
                      final betMovie = widget.remaining.cast<Movie?>()
                          .firstWhere((m) => m?.id == p.betMovieId, orElse: () => null);
                      final isActive = bj.activePlayerId == p.playerId;
                      final isWinner = isDone && bj.winnerId == p.betMovieId;
                      final isDimmed = isPlaying && !isActive && (p.stood || p.bust);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PlayerRowBJ(
                          player: p,
                          betMovieTitle: betMovie?.title,
                          isActive: isActive,
                          isWinner: isWinner,
                          isDimmed: isDimmed,
                          isMe: p.playerId == widget.currentUserId,
                        ),
                      );
                    }),

                    // Status line
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        statusText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDone ? MC.accent1 : MC.mute,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Action bar — 100dp from screen bottom clears the app tab bar (top at 92dp)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16, 0, 16,
                  100 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: 64,
                  child: () {
                    if (isMyTurn && isPlaying) {
                      return Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: widget.onHit,
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [MC.accent1, MC.accent2],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(13),
                                  boxShadow: [
                                    BoxShadow(
                                        color: MC.accent1.withAlpha(56),
                                        blurRadius: 18,
                                        offset: const Offset(0, 6)),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: Text('Hit',
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: MC.accentInk,
                                    )),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: widget.onStand,
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: MC.accent1.withAlpha(102), width: 1),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                alignment: Alignment.center,
                                child: Text('Stand',
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: MC.ink,
                                    )),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    if (isRedeal) {
                      return GestureDetector(
                        onTap: widget.onDealAgain,
                        child: Container(
                          width: double.infinity,
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [MC.accent1, MC.accent2],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: [
                              BoxShadow(
                                  color: MC.accent1.withAlpha(56),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6)),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text('Deal Again',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: MC.accentInk,
                              )),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Bet card (film poster with highlight during betting) ──────────────────────
class _BetCard extends StatelessWidget {
  final Movie movie;
  final bool isMyBet;
  final bool isOtherBet;
  final String? otherPlayerName;

  const _BetCard({
    required this.movie,
    required this.isMyBet,
    required this.isOtherBet,
    this.otherPlayerName,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMyBet
              ? MC.accent1
              : isOtherBet
                  ? MC.mute.withAlpha(80)
                  : MC.line,
          width: isMyBet ? 2.5 : 1.0,
        ),
        boxShadow: isMyBet
            ? [
                BoxShadow(
                    color: MC.accent1.withAlpha(50), blurRadius: 0, spreadRadius: 3),
                BoxShadow(
                    color: MC.accent1.withAlpha(30),
                    blurRadius: 20,
                    offset: const Offset(0, 4)),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PosterWidget(movie: movie, width: 140, height: 196),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: isMyBet ? MC.accent1.withAlpha(20) : MC.bg1,
              ),
              child: Column(
                children: [
                  Text(
                    movie.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMyBet ? MC.ink : MC.mute,
                      fontSize: 12,
                      fontWeight: isMyBet ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (isMyBet) ...[
                    const SizedBox(height: 4),
                    Text('YOUR BET',
                        style: MT.mono(size: 8, color: MC.accent1, letterSpacing: 2)),
                  ],
                  if (isOtherBet && !isMyBet && otherPlayerName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${otherPlayerName!.toUpperCase()}\'S BET',
                      style: MT.mono(size: 8, color: MC.mute, letterSpacing: 1.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── House (dealer) strip ─────────────────────────────────────────────────────
class _HouseRow extends StatelessWidget {
  final List<BlackjackCard> house;
  final bool reveal;

  const _HouseRow({required this.house, required this.reveal});

  int _val(List<BlackjackCard> cards) {
    int total = cards.fold(0, (s, c) => s + c.value);
    int aces = cards.where((c) => c.rank == 'A').length;
    while (total > 21 && aces > 0) { total -= 10; aces--; }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final total = _val(house);
    final upcard = house.isNotEmpty ? house[0].value : 0;
    final bust = reveal && total > 21;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: MC.bg2.withAlpha(235),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MC.accent1.withAlpha(56), width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(100), blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          // House identity
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('House',
                      style: MT.display(size: 16, color: MC.accent1)),
                  const SizedBox(width: 5),
                  const Text('♠',
                      style: TextStyle(color: Color(0xFFC79A4B), fontSize: 14)),
                ]),
                const SizedBox(height: 2),
                Text('DEALER', style: MT.mono(size: 8, letterSpacing: 2, color: MC.dim)),
              ],
            ),
          ),
          // Cards
          _HandFan(cards: house, holeAt: reveal ? -1 : 1, cardWidth: 38),
          const SizedBox(width: 12),
          // Score
          SizedBox(
            width: 36,
            child: Text(
              bust
                  ? '✗'
                  : reveal
                      ? '$total'
                      : house.isEmpty
                          ? '—'
                          : '$upcard+',
              textAlign: TextAlign.right,
              style: GoogleFonts.playfairDisplay(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: bust ? const Color(0xFFB91C1C) : MC.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Player row ───────────────────────────────────────────────────────────────
class _PlayerRowBJ extends StatelessWidget {
  final BlackjackPlayer player;
  final String? betMovieTitle;
  final bool isActive;
  final bool isWinner;
  final bool isDimmed;
  final bool isMe;

  const _PlayerRowBJ({
    required this.player,
    required this.betMovieTitle,
    required this.isActive,
    required this.isWinner,
    required this.isDimmed,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final val = player.handValue;
    final bust = player.bust || val > 21;
    final isHot = isActive || isWinner;

    return AnimatedOpacity(
      opacity: isDimmed ? 0.55 : 1.0,
      duration: const Duration(milliseconds: 250),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: MC.bg1.withAlpha(240),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isHot ? MC.accent1 : MC.line,
            width: isHot ? 1.5 : 1.0,
          ),
          boxShadow: isHot
              ? [
                  BoxShadow(
                      color: MC.accent1.withAlpha(20),
                      blurRadius: 0,
                      spreadRadius: 4),
                  BoxShadow(
                      color: Colors.black.withAlpha(115),
                      blurRadius: 24,
                      offset: const Offset(0, 8)),
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withAlpha(76),
                      blurRadius: 16,
                      offset: const Offset(0, 5)),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        isMe ? 'You' : player.playerName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: MC.ink),
                      ),
                      const SizedBox(width: 6),
                      const Text('→',
                          style: TextStyle(color: MC.dim, fontSize: 13)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          betMovieTitle ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: MC.mute, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                _HandFan(cards: player.hand, cardWidth: 34),
                const SizedBox(width: 10),
                SizedBox(
                  width: 32,
                  child: Text(
                    bust
                        ? '✗'
                        : player.hand.isEmpty
                            ? '—'
                            : '$val',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: bust
                          ? const Color(0xFFB91C1C)
                          : isHot
                              ? MC.accent1
                              : MC.mute,
                    ),
                  ),
                ),
              ],
            ),
            if (isWinner) ...[
              const SizedBox(height: 4),
              Text('★ Breaks the veto',
                  style: MT.mono(size: 8, color: MC.accent1, letterSpacing: 2)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Overlapping card fan ─────────────────────────────────────────────────────
class _HandFan extends StatelessWidget {
  final List<BlackjackCard> cards;
  final int holeAt; // index of face-down hole card; -1 = none
  final double cardWidth;

  const _HandFan({
    required this.cards,
    this.holeAt = -1,
    this.cardWidth = 34,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final peek = math.min(17.0, cardWidth - 6);
    final totalW = cardWidth + (cards.length - 1) * peek;
    final totalH = cardWidth * 1.4;
    return SizedBox(
      width: totalW,
      height: totalH,
      child: Stack(
        children: [
          for (int i = 0; i < cards.length; i++)
            Positioned(
              left: i * peek,
              child: _MiniCard(
                card: cards[i],
                faceDown: i == holeAt,
                width: cardWidth,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Mini playing card tile ───────────────────────────────────────────────────
class _MiniCard extends StatelessWidget {
  final BlackjackCard? card;
  final bool faceDown;
  final double width;

  const _MiniCard({this.card, this.faceDown = false, this.width = 34});

  @override
  Widget build(BuildContext context) {
    final h = (width * 1.4);

    if (faceDown || card == null) {
      return Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6E2230), Color(0xFF491722)],
          ),
          border: Border.all(color: const Color(0xFFC79A4B), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(100),
                blurRadius: 7,
                offset: const Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4.5),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: CustomPaint(painter: _CardBackPainter()),
          ),
        ),
      );
    }

    final isRed = card!.suit == '♥' || card!.suit == '♦';
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: isRed ? const Color(0xFFEFE6D2) : MC.bg2,
        border: Border.all(
          color: isRed
              ? Colors.black.withAlpha(38)
              : MC.line,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(100),
              blurRadius: 7,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 2, left: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              card!.rank,
              style: GoogleFonts.playfairDisplay(
                fontSize: width * 0.42,
                fontWeight: FontWeight.w700,
                color: isRed ? const Color(0xFFB91C1C) : MC.ink,
                height: 0.95,
              ),
            ),
            Text(
              card!.suit,
              style: TextStyle(
                fontSize: width * 0.36,
                color: isRed ? const Color(0xFFB91C1C) : MC.ink,
                height: 0.95,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Card back diagonal lattice ───────────────────────────────────────────────
class _CardBackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x2EC79A4B)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const step = 8.0;
    for (double i = -size.height; i < size.width + size.height; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Watchlist selector ────────────────────────────────────────────────────────
class _WatchlistSelector extends StatefulWidget {
  final List<Watchlist> watchlists;
  final String? selectedId;
  final ValueChanged<Watchlist> onSelect;

  const _WatchlistSelector({
    required this.watchlists,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  State<_WatchlistSelector> createState() => _WatchlistSelectorState();
}

class _WatchlistSelectorState extends State<_WatchlistSelector> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _query = '';
  bool _atTop = true;
  bool _atBottom = false;

  // Each row: vertical padding 24dp + text ~17dp + bottom margin 3dp ≈ 44dp.
  // Cap at 4 rows so the block stays compact; scrollable beyond that.
  static const double _rowHeight = 44.0;
  static const int _visibleRows = 4;
  static const double _maxHeight = _rowHeight * _visibleRows;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final atTop = _scrollCtrl.offset <= 0;
    final atBottom =
        _scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent - 0.5;
    if (atTop != _atTop || atBottom != _atBottom) {
      setState(() {
        _atTop = atTop;
        _atBottom = atBottom;
      });
    }
  }

  void _resetScroll() {
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    _atTop = true;
    _atBottom = false;
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.watchlists
        : widget.watchlists
            .where((wl) =>
                wl.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    final showSearch = widget.watchlists.length > _visibleRows;
    final isScrollable = filtered.length > _visibleRows;

    // ── List ──────────────────────────────────────────────────────────────────
    Widget listWidget = filtered.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('No lists match "$_query"',
                style: const TextStyle(color: MC.dim, fontSize: 13)),
          )
        : ListView.builder(
            controller: isScrollable ? _scrollCtrl : null,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final wl = filtered[i];
              final isSelected = wl.id == widget.selectedId;
              // Drop the bottom margin on the last item when the list is
              // scrollable so it sits flush against the fade overlay instead
              // of leaving a gap at the edge.
              final isLast = i == filtered.length - 1;
              return GestureDetector(
                onTap: () => widget.onSelect(wl),
                child: Container(
                  margin: EdgeInsets.only(
                      bottom: (isLast && isScrollable) ? 0 : 3),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? MC.accent1.withAlpha(20) : MC.bg1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? MC.accent1 : MC.line,
                      width: isSelected ? 1.0 : 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected ? MC.accent1 : MC.dim,
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(wl.name,
                            style: TextStyle(
                                color: isSelected ? MC.ink : MC.mute,
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                      ),
                      Text('${wl.movies.length} films',
                          style:
                              MT.mono(size: 9, letterSpacing: 0, color: MC.dim)),
                    ],
                  ),
                ),
              );
            },
          );

    // When scrollable, wrap in edge fades that react to scroll position so
    // the list surface dissolves into the page rather than hard-clipping.
    if (isScrollable) {
      listWidget = Stack(
        children: [
          listWidget,
          // Top fade — only shown after user has scrolled down from the top
          if (!_atTop)
            Positioned(
              top: 0, left: 0, right: 0, height: 18,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [MC.bg0, MC.bg0.withAlpha(0)],
                    ),
                  ),
                ),
              ),
            ),
          // Bottom fade — hidden only once the user reaches the last item
          if (!_atBottom)
            Positioned(
              bottom: 0, left: 0, right: 0, height: 18,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [MC.bg0, MC.bg0.withAlpha(0)],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CHOOSE A LIST',
            style: MT.mono(size: 9, letterSpacing: 2, color: MC.dim)),
        const SizedBox(height: 8),

        // Search bar — only shown when list exceeds the visible row cap
        if (showSearch)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: MC.bg1,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: MC.line, width: 0.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: MC.dim, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (q) {
                      setState(() {
                        _query = q;
                        _atTop = true;
                        _atBottom = false;
                      });
                      _resetScroll();
                    },
                    style: const TextStyle(color: MC.ink, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Search lists…',
                      hintStyle: TextStyle(color: MC.dim, fontSize: 13),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                    cursorColor: MC.accent1,
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() {
                        _query = '';
                        _atTop = true;
                        _atBottom = false;
                      });
                      _resetScroll();
                    },
                    child: const Icon(Icons.close_rounded,
                        color: MC.dim, size: 14),
                  ),
              ],
            ),
          ),

        // Constrain to _maxHeight only when scrollable; otherwise shrinks to content
        if (isScrollable)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxHeight),
            child: listWidget,
          )
        else
          listWidget,
      ],
    );
  }
}

// ─── Empty state card ─────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String body;

  const _EmptyState({
    required this.icon,
    required this.headline,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MC.line, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(icon, color: MC.accent1, size: 36),
          const SizedBox(height: 16),
          Text(headline, style: MT.display(size: 20), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(body,
              style: const TextStyle(color: MC.mute, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ─── Ticket stub ─────────────────────────────────────────────────────────────
class _TicketStub extends StatelessWidget {
  final Movie movie;
  final int index;
  final bool isVetoed;
  final bool isWinner;
  final bool canVeto;
  final VoidCallback onVeto;
  final VoidCallback onTap;

  const _TicketStub({
    required this.movie,
    required this.index,
    required this.isVetoed,
    required this.isWinner,
    required this.canVeto,
    required this.onVeto,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isWinner ? MC.accent1.withAlpha(15) : MC.bg1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isWinner ? MC.accent1 : MC.line,
            width: isWinner ? 1.0 : 0.5,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(13)),
                  child: PosterWidget(movie: movie, width: 56, height: 84),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movie.title,
                        style: TextStyle(
                          color: isVetoed ? MC.dim : MC.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          decoration:
                              isVetoed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text('${movie.director}  ·  ${movie.year}',
                          style: const TextStyle(color: MC.mute, fontSize: 12)),
                      if (movie.rating > 0) ...[
                        const SizedBox(height: 3),
                        Text('★ ${movie.rating.toStringAsFixed(1)}',
                            style: const TextStyle(color: MC.mute, fontSize: 11)),
                      ],
                      const SizedBox(height: 5),
                      StreamBadgeWidget(streamId: movie.streamId),
                    ],
                  ),
                ),
                if (isWinner)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: MC.accent1,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('WINNER',
                          style: MT.mono(
                              size: 9,
                              color: MC.accentInk,
                              letterSpacing: 1)),
                    ),
                  )
                else if (!isVetoed)
                  GestureDetector(
                    onTap: canVeto ? onVeto : null,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: canVeto ? MC.bg2 : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: canVeto ? MC.line : Colors.transparent,
                            width: 0.5,
                          ),
                        ),
                        child: Text('VETO',
                            style: MT.mono(
                                size: 9,
                                color: canVeto ? MC.mute : MC.dim,
                                letterSpacing: 1)),
                      ),
                    ),
                  ),
              ],
            ),

            // VETOED stamp
            if (isVetoed)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withAlpha(100),
                    alignment: Alignment.center,
                    child: Transform.rotate(
                      angle: -0.3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: const Color(0xFFB91C1C), width: 2.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'VETOED',
                          style: TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Winner card ──────────────────────────────────────────────────────────────
class _WinnerCard extends StatelessWidget {
  final Movie movie;
  const _WinnerCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MC.accent1.withAlpha(12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MC.accent1.withAlpha(80), width: 0.5),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: PosterWidget(movie: movie, width: 48, height: 72),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Tonight's film",
                    style: MT.mono(size: 9, color: MC.accent1, letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(movie.title, style: MT.display(size: 18, italic: true)),
                const SizedBox(height: 2),
                Text('${movie.year}  ·  ${movie.director}',
                    style: const TextStyle(color: MC.mute, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
