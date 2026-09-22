// veto.dart — Screen and supporting widgets for the real-time Veto Sacrifice game, where players pick and veto movies from a shared watchlist, with a blackjack tiebreaker round.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme.dart';
import '../models.dart';
import '../app_state.dart';
import '../services/api_service.dart';
import '../services/veto_service.dart';
import '../services/seance_service.dart';
import '../widgets/poster.dart';
import '../widgets/stream_badge.dart';
import '../widgets/candle_widget.dart';
import '../utils/top_toast.dart';
import 'detail.dart';
import 'seance_screen.dart';

class VetoScreen extends StatefulWidget {
  const VetoScreen({super.key});

  @override
  State<VetoScreen> createState() => _VetoScreenState();
}

class _VetoScreenState extends State<VetoScreen> {
  String _gameStatus = '';

  List<Map<String, dynamic>> _lobbyPlayers = [];
  int _pickCount = 2;
  bool _isHost = false;
  bool _amInLobby = false;

  bool _myPicksSubmitted = false;
  int _submittedCount = 0;
  int _totalCount = 0;
  Set<String> _takenIds = {}; // movies already picked by other players

  List<String> _pickedIds = [];
  Set<String> _vetoedIds = {};
  Set<String> _myVetoIds = {};
  Map<String, int> _maxVetosByPlayer = {};

  BlackjackState? _blackjack;
  bool _pickerSheetOpen = false;

  VetoService? _veto;
  StreamSubscription<VetoEvent>? _sub;
  String? _watchlistId;

  SeanceSession? _activeSeance;
  final _seanceCardKey = GlobalKey<_SeanceCardState>();

  int _myMaxVetos(String userId) => _maxVetosByPlayer[userId] ?? 0;
  int _myVetosLeft(String userId) => _myMaxVetos(userId) - _myVetoIds.length;

  bool _canVeto(String movieId, String userId) =>
      !_vetoedIds.contains(movieId) &&
      !_myVetoIds.contains(movieId) &&
      _myVetoIds.length < _myMaxVetos(userId);

  List<Map<String, dynamic>> _parseLobby(dynamic raw) {
    if (raw == null) return [];
    return (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appState = context.read<AppState>();
      final wls = appState.watchlists;
      if (wls.isNotEmpty) _connect(wls.first.id);
      appState.refreshAvailableSeances();
      appState.refreshVetoInvites();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _veto?.dispose();
    super.dispose();
  }

  Future<void> _connect(String wlId, {bool autoJoin = false}) async {
    _sub?.cancel();
    _veto?.dispose();
    _watchlistId = wlId;
    _veto = VetoService()..connect(wlId);
    _sub = _veto!.events.listen(_handleEvent);
    if (mounted) _resetState();

    // Sync séance state for late arrivals (read-only GET, no broadcasts).
    ApiService.fetchSeanceSession(wlId).then((data) {
      if (!mounted) return;
      if (data['active'] == true) {
        final session = SeanceSession.fromJson(data);
        setState(() => _activeSeance = session);
        // Ensure the radar is aware of this session even if the WS event was missed.
        context.read<AppState>().addAvailableSeanceIfNotPresent(session);
      } else {
        setState(() => _activeSeance = null);
      }
    }).catchError((_) {});

    final session = await ApiService.fetchVetoSession(wlId);
    if (session != null && mounted) {
      final appState = context.read<AppState>();
      final userId   = appState.currentUser?.id ?? 'guest';
      _restoreFromSession(session, userId);
      // If game moved past lobby without the user, clear any pending invite for this watchlist.
      if (_gameStatus != '' && _gameStatus != 'lobby' && !_amInLobby) {
        appState.dismissVetoInviteFor(wlId);
      }
      if (autoJoin && _gameStatus == 'lobby' && !_amInLobby) {
        _veto?.joinLobby(
          playerId:   userId,
          playerName: appState.currentUser?.displayName ?? 'Guest',
        );
      }
    }
  }

  void _restoreFromSession(Map<String, dynamic> data, String userId) {
    final status = data['status'] as String? ?? '';
    final lobby  = _parseLobby(data['lobbyPlayers']);
    final raw    = data['maxVetosByPlayer'] as Map<String, dynamic>? ?? {};
    final submitted = data['picksSubmitted'] as Map<String, dynamic>? ?? {};
    final takenByOthers = <String>{};
    for (final entry in submitted.entries) {
      if (entry.key != userId) {
        takenByOthers.addAll((entry.value as List).cast<String>());
      }
    }
    setState(() {
      _gameStatus       = status;
      _lobbyPlayers     = lobby;
      _pickCount        = (data['pickCount'] as num?)?.toInt() ?? 2;
      _isHost           = data['pickerId'] == userId;
      _amInLobby        = lobby.any((p) => p['id'] == userId);
      _pickedIds        = (data['pickedIds'] as List?)?.cast<String>() ?? [];
      _vetoedIds        = Set<String>.from((data['vetoedIds'] as List?)?.cast<String>() ?? []);
      _maxVetosByPlayer = raw.map((k, v) => MapEntry(k, (v as num).toInt()));
      _totalCount       = lobby.length;
      _submittedCount   = submitted.length;
      _myPicksSubmitted = submitted.containsKey(userId);
      _takenIds         = takenByOthers;
      final bjData      = data['blackjack'] as Map<String, dynamic>?;
      _blackjack        = bjData != null ? BlackjackState.fromMap(bjData) : null;
    });
  }

  void _resetState() {
    setState(() {
      _gameStatus       = '';
      _lobbyPlayers     = [];
      _pickedIds        = [];
      _vetoedIds        = {};
      _myVetoIds        = {};
      _maxVetosByPlayer = {};
      _isHost           = false;
      _amInLobby        = false;
      _myPicksSubmitted = false;
      _submittedCount   = 0;
      _totalCount       = 0;
      _takenIds         = {};
      _blackjack        = null;
      // Note: _activeSeance is intentionally NOT reset here —
      // a séance can be live while the veto game is not running.
    });
  }

  void _clearVeto() {
    _resetState();
    _veto?.resetGame();
  }

  void _handleEvent(VetoEvent e) {
    if (!mounted) return;
    final userId = context.read<AppState>().currentUser?.id ?? 'guest';

    switch (e.type) {

      case 'veto_lobby_created':
        final lobby = _parseLobby(e.data['lobbyPlayers']);
        setState(() {
          _gameStatus       = 'lobby';
          _lobbyPlayers     = lobby;
          _pickCount        = (e.data['pickCount'] as num?)?.toInt() ?? 2;
          _isHost           = e.data['pickerId'] == userId;
          _amInLobby        = lobby.any((p) => p['id'] == userId);
          _pickedIds        = [];
          _vetoedIds        = {};
          _myVetoIds        = {};
          _myPicksSubmitted = false;
          _submittedCount   = 0;
          _blackjack        = null;
        });

      case 'veto_player_joined':
        final lobby = _parseLobby(e.data['lobbyPlayers']);
        setState(() {
          _lobbyPlayers = lobby;
          _totalCount   = lobby.length;
          _amInLobby    = lobby.any((p) => p['id'] == userId);
        });

      case 'veto_picking_started':
        if (!_amInLobby && _watchlistId != null) {
          context.read<AppState>().dismissVetoInviteFor(_watchlistId!);
        }
        final lobby = _parseLobby(e.data['lobbyPlayers']);
        setState(() {
          _gameStatus       = 'picking';
          _pickCount        = (e.data['pickCount'] as num?)?.toInt() ?? _pickCount;
          _lobbyPlayers     = lobby;
          _totalCount       = lobby.length;
          _submittedCount   = 0;
          _myPicksSubmitted = false;
          _takenIds         = {};
        });

      case 'picks_submitted':
        final taken = (e.data['takenIds'] as List?)?.cast<String>().toSet() ?? <String>{};
        setState(() {
          _submittedCount = (e.data['submittedCount'] as num?)?.toInt() ?? _submittedCount;
          _takenIds       = taken;
        });

      case 'picks_conflict':
        if (e.data['playerId'] == userId) {
          final taken = (e.data['takenIds'] as List?)?.cast<String>().toSet() ?? <String>{};
          setState(() {
            _myPicksSubmitted = false;
            _takenIds         = taken;
            // Undo the optimistic submittedCount increment
            if (_submittedCount > 0) _submittedCount--;
          });
          // Close the picker sheet if it's still open so the user sees fresh taken IDs
          if (_pickerSheetOpen && Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        }

      case 'veto_phase_started':
        final raw = e.data['maxVetosByPlayer'] as Map<String, dynamic>? ?? {};
        setState(() {
          _gameStatus       = 'vetoing';
          _pickedIds        = (e.data['pickedIds'] as List?)?.cast<String>() ?? [];
          _maxVetosByPlayer = raw.map((k, v) => MapEntry(k, (v as num).toInt()));
          _vetoedIds        = {};
          _myVetoIds        = {};
        });

      case 'veto_state':
        _restoreFromSession(e.data, userId);

      case 'veto_cancelled':
        _resetState();

      case 'veto_reset':
        _resetState();

      case 'veto_actioned':
        setState(() => _vetoedIds.add(e.data['vetoedId'] as String));

      case 'veto_stalemate':
        showTopToast(context, 'Stalemate! Going straight to blackjack…');

      case 'blackjack_start':
        setState(() {
          _gameStatus = 'blackjack_betting';
          _blackjack  = const BlackjackState(players: [], status: 'betting');
          final ids = (e.data['pickedIds'] as List?)?.cast<String>();
          if (ids != null && ids.isNotEmpty) _pickedIds = ids;
        });

      case 'blackjack_update':
        final bjData = e.data['blackjack'] as Map<String, dynamic>?;
        if (bjData != null) {
          final bj = BlackjackState.fromMap(bjData);
          setState(() {
            _blackjack = bj;
            if (bj.status == 'playing') { _gameStatus = 'blackjack_playing'; }
            else if (bj.status == 'redeal') { _gameStatus = 'blackjack_redeal'; }
            else if (bj.status == 'done') { _gameStatus = 'done'; }
          });
        }

      case 'seance_started':
        setState(() => _activeSeance = SeanceSession(
              watchlistId: _watchlistId ?? '',
              hostId: e.data['hostId'] as String? ?? '',
              hostName: e.data['hostName'] as String? ?? '',
              hostAvatarUrl: e.data['hostAvatarUrl'] as String?,
              livekitRoom: '',
            ));

      case 'seance_ended':
        setState(() => _activeSeance = null);
        _seanceCardKey.currentState?.signalRemoteEnd();

      case 'veto_winner':
        context.read<AppState>().promoteToTopPickAndSync(e.data['winnerId'] as String);
        setState(() {
          _gameStatus = 'done';
          if (_blackjack != null) {
            _blackjack = _blackjack!.copyWith(
              status: 'done',
              winnerId: e.data['winnerId'] as String?,
              houseRevealed: true,
            );
          }
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state      = context.watch<AppState>();
    final watchlists = state.watchlists;
    final userId     = state.currentUser?.id ?? 'guest';
    final userName   = state.currentUser?.displayName ?? 'Guest';

    final pendingJoin = state.pendingVetoJoin;
    if (pendingJoin != null) {
      state.clearPendingVetoJoin();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_watchlistId != pendingJoin) {
          _connect(pendingJoin, autoJoin: true);
        } else if (_gameStatus == 'lobby' && !_amInLobby) {
          _veto?.joinLobby(playerId: userId, playerName: userName);
        }
      });
    }

    final pendingSeanceAccept = state.pendingSeanceAccept;
    if (pendingSeanceAccept != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        state.clearPendingSeanceAccept();
        setState(() => _activeSeance = pendingSeanceAccept);
        if (_watchlistId != pendingSeanceAccept.watchlistId) {
          _connect(pendingSeanceAccept.watchlistId);
          await Future.delayed(const Duration(milliseconds: 400));
        }
        if (mounted) _seanceCardKey.currentState?.autoJoin();
      });
    }

    if (watchlists.isNotEmpty && _watchlistId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _watchlistId == null) _connect(watchlists.first.id);
      });
    }

    final selectedWl = _watchlistId != null
        ? watchlists.cast<Watchlist?>().firstWhere((w) => w?.id == _watchlistId, orElse: () => null)
        : null;

    final allMovies = selectedWl?.movies ?? [];

    // Resolve movie objects from IDs for the veto/blackjack phase.
    final picks = _pickedIds
        .map((id) => allMovies.cast<Movie?>().firstWhere((m) => m?.id == id, orElse: () => null))
        .whereType<Movie>()
        .toList();

    final remaining   = picks.where((p) => !_vetoedIds.contains(p.id)).toList();
    final winnerMovie = (remaining.length == 1 && _pickedIds.isNotEmpty) ? remaining.first : null;
    final vetosLeft   = _myVetosLeft(userId);
    // Keep the overlay up through the 'done' phase so the winner is visible
    // until the user explicitly taps CLEAR.
    final inBlackjack = _blackjack != null &&
        (_gameStatus.startsWith('blackjack') ||
         (_gameStatus == 'done' && _blackjack!.status == 'done'));

    return Scaffold(
      backgroundColor: MC.bg0,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── Séance section (own header + compact card) ───────────────
              if (watchlists.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 62, 20, 10),
                    child: Text('SÉANCE', style: MT.mono(size: 10, letterSpacing: 2)),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _SeanceCard(
                      key: _seanceCardKey,
                      activeSeance: _activeSeance,
                      watchlists: watchlists,
                      currentUserId: userId,
                      currentUserName: state.currentUser?.displayName,
                      currentUserAvatarUrl: state.currentUser?.avatarUrl,
                      onStarted: (session) => setState(() => _activeSeance = session),
                      onEnded: () => setState(() => _activeSeance = null),
                    ),
                  ),
                ),
              ],

              // ── Veto Sacrifice header ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, watchlists.isEmpty ? 62 : 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Tonight's Ritual", style: MT.mono(size: 10, letterSpacing: 2)),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          style: MT.display(size: 34),
                          children: [
                            const TextSpan(text: 'Veto Sacrifice'),
                            TextSpan(text: ' · ', style: MT.display(size: 34, italic: true, color: MC.accent1)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _buildDescription(winnerMovie, picks.length, remaining.length, vetosLeft),
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
                      onSelect: (wl) { if (wl.id != _watchlistId) _connect(wl.id); },
                    ),
                  ),
                ),

              if (_gameStatus == '' && _watchlistId != null &&
                  (selectedWl?.memberIds.length ?? 0) < 2)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _EmptyState(
                      icon: Icons.group_outlined,
                      headline: 'Needs more cultists',
                      body: 'The veto ritual requires at least 2 members. Invite someone to this watchlist first.',
                    ),
                  ),
                ),

              if (_gameStatus == '' && _watchlistId != null &&
                  (selectedWl?.memberIds.length ?? 0) >= 2)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: allMovies.isEmpty
                        ? const _EmptyState(
                            icon: Icons.search_rounded,
                            headline: 'Your queue is empty',
                            body: 'Add movies to your watchlist, then come back to start a veto.',
                          )
                        : const _EmptyState(
                            icon: Icons.how_to_vote_outlined,
                            headline: 'Let the ritual begin',
                            body: 'Create a lobby, choose picks per player, invite members, then veto.',
                          ),
                  ),
                ),

              if (_gameStatus == '' && _watchlistId == null)
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

              if (_gameStatus == 'lobby')
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _VetoLobbyCard(
                      lobbyPlayers: _lobbyPlayers,
                      pickCount: _pickCount,
                      isHost: _isHost,
                      amInLobby: _amInLobby,
                    ),
                  ),
                ),

              if (_gameStatus == 'picking')
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: _VetoPickingCard(
                      submittedCount: _submittedCount,
                      totalCount: _totalCount,
                      myPicksSubmitted: _myPicksSubmitted,
                      pickCount: _pickCount,
                    ),
                  ),
                ),

              if (_gameStatus == 'vetoing' || _gameStatus == 'done')
                SliverToBoxAdapter(child: _buildStatusBar(vetosLeft, userId)),

              if (_gameStatus == 'vetoing' || _gameStatus == 'done')
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: _TicketStub(
                        movie: picks[i],
                        index: i,
                        isVetoed: _vetoedIds.contains(picks[i].id),
                        isWinner: winnerMovie?.id == picks[i].id,
                        canVeto: _canVeto(picks[i].id, userId) && !inBlackjack,
                        onVeto: () {
                          setState(() {
                            _myVetoIds.add(picks[i].id);
                            _vetoedIds.add(picks[i].id);
                          });
                          _veto?.vetoMovie(
                            vetoedId: picks[i].id,
                            vetoerId: userId,
                            vetoerName: userName,
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
                    child: _buildActionButton(context, state, selectedWl, userId, userName, allMovies),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),

          if (inBlackjack)
            _BlackjackOverlay(
              bj: _blackjack!,
              remaining: remaining,
              currentUserId: userId,
              currentUserName: userName,
              onBet: (movieId) => _veto?.blackjackBet(
                playerId: userId, playerName: userName, betMovieId: movieId,
              ),
              onHit:      () => _veto?.blackjackHit(playerId: userId),
              onStand:    () => _veto?.blackjackStand(playerId: userId),
              onDealAgain: () => _veto?.blackjackDealAgain(),
              onClear: _clearVeto,
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    AppState state,
    Watchlist? selectedWl,
    String userId,
    String userName,
    List<Movie> allMovies,
  ) {
    switch (_gameStatus) {
      case '':
        return GestureDetector(
          onTap: allMovies.isEmpty ? null : () => _showLobbySetupSheet(context, state),
          child: _ActionBtn(label: 'Start a veto game', enabled: allMovies.isNotEmpty),
        );

      case 'lobby':
        if (_isHost) {
          final ready = _lobbyPlayers.length >= 2;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: ready ? () => _veto?.hostStartGame(hostId: userId) : null,
                child: _ActionBtn(
                  label: ready
                      ? 'Start Game  (${_lobbyPlayers.length} players)'
                      : 'Waiting for at least 1 more player…',
                  enabled: ready,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _veto?.cancelLobby(hostId: userId),
                child: const _ActionBtn(label: 'Cancel Lobby', enabled: true, muted: true),
              ),
            ],
          );
        }
        if (!_amInLobby) {
          return GestureDetector(
            onTap: () => _veto?.joinLobby(playerId: userId, playerName: userName),
            child: const _ActionBtn(label: 'Join Game', enabled: true),
          );
        }
        return const _ActionBtn(label: 'Waiting for host to start…', enabled: false);

      case 'picking':
        final pickBtn = _myPicksSubmitted
            ? const _ActionBtn(label: 'Waiting for others to pick…', enabled: false)
            : GestureDetector(
                onTap: selectedWl != null ? () => _showPickerSheet(context, state, selectedWl) : null,
                child: _ActionBtn(label: 'Choose wisely..', enabled: selectedWl != null),
              );
        if (_isHost) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              pickBtn,
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _veto?.cancelLobby(hostId: userId),
                child: const _ActionBtn(label: 'Cancel Game', enabled: true, muted: true),
              ),
            ],
          );
        }
        return pickBtn;

      case 'vetoing':
      case 'done':
        return GestureDetector(
          onTap: _clearVeto,
          child: const _ActionBtn(label: 'Start new round', enabled: true, muted: true),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  String _buildDescription(Movie? winner, int pickCount, int remaining, int vetosLeft) {
    switch (_gameStatus) {
      case '':
        return 'Create a lobby, set pick count, then veto movies out one by one.';
      case 'lobby':
        final n = _lobbyPlayers.length;
        return '$n player${n == 1 ? "" : "s"} in lobby · $_pickCount ${_pickCount == 1 ? "pick" : "picks"} each · ${_pickCount == 1 ? "goes straight to blackjack" : "${_pickCount - 1} veto${_pickCount - 1 == 1 ? "" : "s"} each"}';
      case 'picking':
        return '$_submittedCount of $_totalCount players have submitted their picks';
      case 'vetoing':
        if (winner != null) return '${winner.title} survived the veto.';
        return '$pickCount picks in pool · $remaining still standing · $vetosLeft of your vetos left';
      case 'done':
        return winner != null
            ? '${winner.title} survived. Tonight\'s film is decided.'
            : 'Game over.';
      default:
        return '';
    }
  }

  Widget _buildStatusBar(int vetosLeft, String userId) {
    final maxV = _myMaxVetos(userId);
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
              Text('YOUR VETOS: $vetosLeft LEFT',
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
              value: maxV > 0 ? _myVetoIds.length / maxV : 0,
              minHeight: 3,
              color: MC.accent1,
              backgroundColor: MC.bg2,
            ),
          ),
        ],
      ),
    );
  }

  void _showLobbySetupSheet(BuildContext context, AppState state) {
    int pickCount  = 2;
    bool notifyAll = true;
    final userId   = state.currentUser?.id ?? 'guest';
    final userName = state.currentUser?.displayName ?? 'Guest';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MC.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: MC.dim, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text('New Veto Game', style: MT.display(size: 22)),
              const SizedBox(height: 4),
              const Text(
                'Decide the rules before anyone picks movies.',
                style: TextStyle(color: MC.dim, fontSize: 13),
              ),
              const SizedBox(height: 24),

              // Pick count selector
              Text('PICKS PER PLAYER', style: MT.mono(size: 9, letterSpacing: 2, color: MC.dim)),
              const SizedBox(height: 10),
              Row(
                children: [1, 2, 3].map((n) {
                  final sel = pickCount == n;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => setS(() => pickCount = n),
                      child: Container(
                        width: 72, height: 56,
                        decoration: BoxDecoration(
                          color: sel ? MC.accent1.withAlpha(20) : MC.bg2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel ? MC.accent1 : MC.line,
                            width: sel ? 1.5 : 0.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(n == 1 ? '1v1' : '$n',
                                style: MT.display(size: n == 1 ? 18 : 22, color: sel ? MC.accent1 : MC.ink)),
                            Text(n == 1 ? 'quick' : 'picks',
                                style: TextStyle(fontSize: 10, color: sel ? MC.accent1 : MC.dim)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                pickCount == 1
                    ? '1 pick each · no veto · goes straight to blackjack'
                    : pickCount == 2
                    ? '2 picks · 1 veto each · 2 movies survive → blackjack decides'
                    : '3 picks · 2 vetos each · 3 movies survive → blackjack decides',
                style: const TextStyle(color: MC.dim, fontSize: 12),
              ),
              const SizedBox(height: 20),

              // Notify toggle
              GestureDetector(
                onTap: () => setS(() => notifyAll = !notifyAll),
                child: Row(
                  children: [
                    Checkbox(
                      value: notifyAll,
                      onChanged: (v) => setS(() => notifyAll = v ?? true),
                      activeColor: MC.accent1,
                      checkColor: MC.accentInk,
                      side: const BorderSide(color: MC.dim),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    const Text('Notify all members to join',
                        style: TextStyle(color: MC.mute, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              GestureDetector(
                onTap: () {
                  _veto?.createLobby(
                    pickerId:  userId,
                    pickerName: userName,
                    pickCount: pickCount,
                    notifyAll: notifyAll,
                  );
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: double.infinity, height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [MC.accent1, MC.accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [BoxShadow(color: MC.accent1.withAlpha(56), blurRadius: 18, offset: const Offset(0, 6))],
                  ),
                  alignment: Alignment.center,
                  child: Text('Create Lobby',
                      style: GoogleFonts.newsreader(
                          fontSize: 17, fontWeight: FontWeight.w700, color: MC.accentInk)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPickerSheet(BuildContext context, AppState state, Watchlist watchlist) {
    final userId = state.currentUser?.id ?? 'guest';
    final Set<String> selected = {};
    String search = '';

    _pickerSheetOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: MC.bg1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          final liveWl = context.read<AppState>().watchlists.cast<Watchlist?>()
              .firstWhere((w) => w?.id == _watchlistId, orElse: () => null);
          final movies  = liveWl?.movies ?? watchlist.movies;
          final query   = search.toLowerCase();
          final filtered = query.isEmpty
              ? movies
              : movies.where((m) => m.title.toLowerCase().contains(query)).toList();

          final canConfirm = selected.length == _pickCount;

          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scroll) => ClipRect(
              child: Column(
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
                      Text('Pick exactly $_pickCount ${_pickCount == 1 ? "film" : "films"}', style: MT.display(size: 20)),
                      const Spacer(),
                      Text('${selected.length}/$_pickCount',
                          style: MT.mono(size: 12, color: MC.accent1, letterSpacing: 0)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text(
                    _pickCount == 1
                        ? 'Goes straight to blackjack — no veto phase.'
                        : 'You\'ll get ${_pickCount - 1} veto${_pickCount - 1 == 1 ? "" : "s"} once everyone has picked.',
                    style: const TextStyle(color: MC.dim, fontSize: 12),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
                            onChanged: (v) => setS(() => search = v),
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
                        if (search.isNotEmpty)
                          GestureDetector(
                            onTap: () => setS(() => search = ''),
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
                            query.isEmpty ? 'No films available' : 'No results',
                            style: const TextStyle(color: MC.dim, fontSize: 13),
                          ),
                        )
                      : ListView.builder(
                          controller: scroll,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final m       = filtered[i];
                            final isSel   = selected.contains(m.id);
                            final isTaken = _takenIds.contains(m.id);
                            return Opacity(
                              opacity: isTaken ? 0.35 : 1.0,
                              child: ListTile(
                                leading: PosterWidget(movie: m, width: 36, height: 54),
                                title: Text(m.title,
                                    style: TextStyle(
                                      color: MC.ink,
                                      decoration: isTaken ? TextDecoration.lineThrough : null,
                                    )),
                                subtitle: Text(
                                  isTaken
                                      ? 'Already picked'
                                      : '${m.director.isNotEmpty ? m.director : m.year.toString()}  ·  ${m.section.label}',
                                  style: const TextStyle(color: MC.mute, fontSize: 12),
                                ),
                                trailing: isTaken
                                    ? const Icon(Icons.block_rounded, color: MC.dim, size: 18)
                                    : isSel
                                        ? const Icon(Icons.check_circle_rounded, color: MC.accent1)
                                        : const Icon(Icons.circle_outlined, color: MC.dim),
                                onTap: isTaken ? null : () {
                                  setS(() {
                                    if (isSel) {
                                      selected.remove(m.id);
                                    } else if (selected.length < _pickCount) {
                                      selected.add(m.id);
                                    }
                                  });
                                },
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: GestureDetector(
                    onTap: canConfirm
                        ? () {
                            _veto?.submitPicks(
                              playerId: userId,
                              pickedIds: selected.toList(),
                            );
                            setState(() {
                              _myPicksSubmitted = true;
                              _submittedCount   = math.min(_submittedCount + 1, _totalCount);
                            });
                            Navigator.pop(ctx);
                          }
                        : null,
                    child: Container(
                      width: double.infinity, height: 48,
                      decoration: BoxDecoration(
                        color: canConfirm ? MC.accent1 : MC.bg2,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        selected.length < _pickCount
                            ? 'Pick ${_pickCount - selected.length} more'
                            : 'Confirm $_pickCount ${_pickCount == 1 ? "pick" : "picks"}',
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
          ),
          );
        },
      ),
    ).whenComplete(() => _pickerSheetOpen = false);
  }
}

class _VetoLobbyCard extends StatelessWidget {
  final List<Map<String, dynamic>> lobbyPlayers;
  final int pickCount;
  final bool isHost;
  final bool amInLobby;

  const _VetoLobbyCard({
    required this.lobbyPlayers,
    required this.pickCount,
    required this.isHost,
    required this.amInLobby,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MC.line, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('LOBBY', style: MT.mono(size: 9, letterSpacing: 2, color: MC.accent1)),
              const Spacer(),
              Text(
                pickCount == 1
                    ? '1 pick · goes straight to blackjack'
                    : '$pickCount picks · ${pickCount - 1} veto${pickCount - 1 == 1 ? "" : "s"} each',
                style: MT.mono(size: 9, letterSpacing: 1, color: MC.dim),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...lobbyPlayers.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: MC.accent1, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Text(p['name'] as String? ?? '',
                    style: const TextStyle(color: MC.ink, fontSize: 14, fontWeight: FontWeight.w500)),
                if (lobbyPlayers.indexOf(p) == 0) ...[
                  const SizedBox(width: 6),
                  Text('HOST', style: MT.mono(size: 8, color: MC.dim, letterSpacing: 1.5)),
                ],
              ],
            ),
          )),
          if (!amInLobby) ...[
            const Divider(color: MC.line, height: 20),
            const Text(
              'You\'ve been invited to this game.',
              style: TextStyle(color: MC.mute, fontSize: 13),
            ),
          ] else if (lobbyPlayers.length < 2)
            Text(
              isHost
                  ? 'Waiting for at least 1 more player to join…'
                  : 'Waiting for the host to start the game…',
              style: const TextStyle(color: MC.dim, fontSize: 12, fontStyle: FontStyle.italic),
            ),
        ],
      ),
    );
  }
}

class _VetoPickingCard extends StatelessWidget {
  final int submittedCount;
  final int totalCount;
  final bool myPicksSubmitted;
  final int pickCount;

  const _VetoPickingCard({
    required this.submittedCount,
    required this.totalCount,
    required this.myPicksSubmitted,
    required this.pickCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MC.bg1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MC.line, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PICKING PHASE', style: MT.mono(size: 9, letterSpacing: 2, color: MC.accent1)),
          const SizedBox(height: 8),
          Text(
            myPicksSubmitted
                ? 'Your picks are in. Waiting for others…'
                : 'Pick exactly $pickCount ${pickCount == 1 ? "film" : "films"} to add to the pool.',
            style: const TextStyle(color: MC.mute, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: totalCount > 0 ? submittedCount / totalCount : 0,
              minHeight: 3,
              color: MC.accent1,
              backgroundColor: MC.bg2,
            ),
          ),
          const SizedBox(height: 6),
          Text('$submittedCount of $totalCount players have picked',
              style: MT.mono(size: 9, letterSpacing: 1, color: MC.dim)),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool muted;

  const _ActionBtn({required this.label, required this.enabled, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: enabled && !muted ? MC.bg1 : MC.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MC.line, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: enabled ? (muted ? MC.dim : MC.mute) : MC.dim,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

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
    final isDone    = bj.status == 'done';
    final isRedeal  = bj.status == 'redeal';
    final isMyTurn  = bj.activePlayerId == widget.currentUserId;

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
          : '${name == 'You' ? 'You are the chosen one' : '$name is the chosen one'} · $movieTitle wins';
    } else if (isRedeal) {
      statusText = 'House wins · deal again';
    } else if (isPlaying && isMyTurn) {
      statusText = 'Your turn — hit or stand';
    } else if (isPlaying) {
      final activeP = bj.players.cast<BlackjackPlayer?>()
          .firstWhere((p) => p?.playerId == bj.activePlayerId, orElse: () => null);
      statusText = activeP != null ? '${activeP.playerName}\'s turn…' : 'Waiting…';
    } else if (isBetting && (hasBet || _betSent)) {
      statusText = 'Waiting for other players to bet…';
    } else {
      statusText = 'Bet on the film you want to win';
    }

    return Container(
      color: const Color(0xD0070504),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
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
                      child: Text('CLEAR', style: MT.mono(size: 9, color: MC.mute, letterSpacing: 2)),
                    ),
                  ),
                ],
              ),
            ),

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
                      final canSelect = !(hasBet || _betSent);

                      return GestureDetector(
                        onTap: canSelect ? () => setState(() => _mySelectedMovieId = m.id) : null,
                        child: _BetCard(
                          movie: m,
                          isMyBet: isMyBet,
                          isOtherBet: isOtherBet,
                          otherPlayerName: isOtherBet ? serverBet.playerName : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (_mySelectedMovieId != null && !_betSent && !hasBet)
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 100 + MediaQuery.of(context).viewInsets.bottom),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _betSent = true);
                      widget.onBet(_mySelectedMovieId!);
                    },
                    child: Container(
                      width: double.infinity, height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [MC.accent1, MC.accent2],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [BoxShadow(color: MC.accent1.withAlpha(56), blurRadius: 18, offset: const Offset(0, 6))],
                      ),
                      alignment: Alignment.center,
                      child: () {
                        final selTitle = widget.remaining.cast<Movie?>()
                            .firstWhere((mo) => mo?.id == _mySelectedMovieId, orElse: () => null)
                            ?.title ?? '';
                        return Text('Bet on $selTitle',
                            style: GoogleFonts.newsreader(
                                fontSize: 17, fontWeight: FontWeight.w700, color: MC.accentInk));
                      }(),
                    ),
                  ),
                )
              else
                const SizedBox(height: 100),
            ],

            if (!isBetting) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                child: _HouseRow(house: bj.house, reveal: bj.houseRevealed || isDone || isRedeal),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  children: [
                    ...bj.players.map((p) {
                      final betMovie = widget.remaining.cast<Movie?>()
                          .firstWhere((m) => m?.id == p.betMovieId, orElse: () => null);
                      final isActive  = bj.activePlayerId == p.playerId;
                      final isWinner  = isDone && bj.winnerId == p.betMovieId;
                      final isDimmed  = isPlaying && !isActive && (p.stood || p.bust);
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
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(statusText,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: isDone ? MC.accent1 : MC.mute)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 100 + MediaQuery.of(context).viewInsets.bottom),
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
                                  gradient: const LinearGradient(colors: [MC.accent1, MC.accent2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                  borderRadius: BorderRadius.circular(13),
                                  boxShadow: [BoxShadow(color: MC.accent1.withAlpha(56), blurRadius: 18, offset: const Offset(0, 6))],
                                ),
                                alignment: Alignment.center,
                                child: Text('Hit', style: GoogleFonts.newsreader(fontSize: 17, fontWeight: FontWeight.w400, color: MC.accentInk)),
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
                                  border: Border.all(color: MC.accent1.withAlpha(102), width: 1),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                alignment: Alignment.center,
                                child: Text('Stand', style: GoogleFonts.newsreader(fontSize: 16, fontWeight: FontWeight.w400, color: MC.ink)),
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
                          width: double.infinity, height: 50,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [MC.accent1, MC.accent2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: [BoxShadow(color: MC.accent1.withAlpha(56), blurRadius: 18, offset: const Offset(0, 6))],
                          ),
                          alignment: Alignment.center,
                          child: Text('Deal Again', style: GoogleFonts.newsreader(fontSize: 17, fontWeight: FontWeight.w400, color: MC.accentInk)),
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

class _BetCard extends StatelessWidget {
  final Movie movie;
  final bool isMyBet;
  final bool isOtherBet;
  final String? otherPlayerName;

  const _BetCard({required this.movie, required this.isMyBet, required this.isOtherBet, this.otherPlayerName});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMyBet ? MC.accent1 : isOtherBet ? MC.mute.withAlpha(80) : MC.line,
          width: isMyBet ? 2.5 : 1.0,
        ),
        boxShadow: isMyBet
            ? [
                BoxShadow(color: MC.accent1.withAlpha(50), blurRadius: 0, spreadRadius: 3),
                BoxShadow(color: MC.accent1.withAlpha(30), blurRadius: 20, offset: const Offset(0, 4)),
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
              decoration: BoxDecoration(color: isMyBet ? MC.accent1.withAlpha(20) : MC.bg1),
              child: Column(
                children: [
                  Text(movie.title,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isMyBet ? MC.ink : MC.mute,
                          fontSize: 12,
                          fontWeight: isMyBet ? FontWeight.w600 : FontWeight.w400)),
                  if (isMyBet) ...[
                    const SizedBox(height: 4),
                    Text('YOUR BET', style: MT.mono(size: 8, color: MC.accent1, letterSpacing: 2)),
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

class _HouseRow extends StatelessWidget {
  final List<BlackjackCard> house;
  final bool reveal;
  const _HouseRow({required this.house, required this.reveal});

  int _val(List<BlackjackCard> cards) {
    int total = cards.fold(0, (s, c) => s + c.value);
    int aces  = cards.where((c) => c.rank == 'A').length;
    while (total > 21 && aces > 0) { total -= 10; aces--; }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final total  = _val(house);
    final upcard = house.isNotEmpty ? house[0].value : 0;
    final bust   = reveal && total > 21;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: MC.bg2.withAlpha(235),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MC.accent1.withAlpha(56), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('House', style: MT.display(size: 16, color: MC.accent1)),
                  const SizedBox(width: 5),
                  const Text('♠', style: TextStyle(color: Color(0xFFC79A4B), fontSize: 14)),
                ]),
                const SizedBox(height: 2),
                Text('DEALER', style: MT.mono(size: 8, letterSpacing: 2, color: MC.dim)),
              ],
            ),
          ),
          _HandFan(cards: house, holeAt: reveal ? -1 : 1, cardWidth: 38),
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            child: Text(
              bust ? '✗' : reveal ? '$total' : house.isEmpty ? '—' : '$upcard+',
              textAlign: TextAlign.right,
              style: GoogleFonts.newsreader(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: bust ? const Color(0xFFB91C1C) : MC.ink),
            ),
          ),
        ],
      ),
    );
  }
}

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
    final val  = player.handValue;
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
          border: Border.all(color: isHot ? MC.accent1 : MC.line, width: isHot ? 1.5 : 1.0),
          boxShadow: isHot
              ? [
                  BoxShadow(color: MC.accent1.withAlpha(20), blurRadius: 0, spreadRadius: 4),
                  BoxShadow(color: Colors.black.withAlpha(115), blurRadius: 24, offset: const Offset(0, 8)),
                ]
              : [BoxShadow(color: Colors.black.withAlpha(76), blurRadius: 16, offset: const Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(isMe ? 'You' : player.playerName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: MC.ink)),
                      const SizedBox(width: 6),
                      const Text('→', style: TextStyle(color: MC.dim, fontSize: 13)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(betMovieTitle ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: MC.mute, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                _HandFan(cards: player.hand, cardWidth: 34),
                const SizedBox(width: 10),
                SizedBox(
                  width: 32,
                  child: Text(
                    bust ? '✗' : player.hand.isEmpty ? '—' : '$val',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.newsreader(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: bust ? const Color(0xFFB91C1C) : isHot ? MC.accent1 : MC.mute),
                  ),
                ),
              ],
            ),
            if (isWinner) ...[
              const SizedBox(height: 4),
              Text('★ Breaks the veto', style: MT.mono(size: 8, color: MC.accent1, letterSpacing: 2)),
            ],
          ],
        ),
      ),
    );
  }
}

class _HandFan extends StatelessWidget {
  final List<BlackjackCard> cards;
  final int holeAt;
  final double cardWidth;

  const _HandFan({required this.cards, this.holeAt = -1, this.cardWidth = 34});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final peek   = math.min(17.0, cardWidth - 6);
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
              child: _MiniCard(card: cards[i], faceDown: i == holeAt, width: cardWidth),
            ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final BlackjackCard? card;
  final bool faceDown;
  final double width;

  const _MiniCard({this.card, this.faceDown = false, this.width = 34});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    if (faceDown || card == null) {
      return Container(
        width: width, height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFF6E2230), Color(0xFF491722)],
          ),
          border: Border.all(color: const Color(0xFFC79A4B), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 7, offset: const Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4.5),
          child: Padding(padding: const EdgeInsets.all(3), child: CustomPaint(painter: _CardBackPainter())),
        ),
      );
    }
    final isRed = card!.suit == '♥' || card!.suit == '♦';
    return Container(
      width: width, height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: isRed ? const Color(0xFFEFE6D2) : MC.bg2,
        border: Border.all(color: isRed ? Colors.black.withAlpha(38) : MC.line, width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 7, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 2, left: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(card!.rank,
                style: GoogleFonts.newsreader(
                    fontSize: width * 0.42, fontWeight: FontWeight.w700,
                    color: isRed ? const Color(0xFFB91C1C) : MC.ink, height: 0.95)),
            Text(card!.suit,
                style: TextStyle(fontSize: width * 0.36,
                    color: isRed ? const Color(0xFFB91C1C) : MC.ink, height: 0.95)),
          ],
        ),
      ),
    );
  }
}

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

class _WatchlistSelector extends StatefulWidget {
  final List<Watchlist> watchlists;
  final String? selectedId;
  final ValueChanged<Watchlist> onSelect;

  const _WatchlistSelector({required this.watchlists, required this.selectedId, required this.onSelect});

  @override
  State<_WatchlistSelector> createState() => _WatchlistSelectorState();
}

class _WatchlistSelectorState extends State<_WatchlistSelector> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _query = '';
  bool _atTop = true;
  bool _atBottom = false;

  static const double _rowHeight   = 44.0;
  static const int    _visibleRows = 4;
  static const double _maxHeight   = _rowHeight * _visibleRows;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final atTop    = _scrollCtrl.offset <= 0;
    final atBottom = _scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent - 0.5;
    if (atTop != _atTop || atBottom != _atBottom) {
      setState(() { _atTop = atTop; _atBottom = atBottom; });
    }
  }

  void _resetScroll() {
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    _atTop = true; _atBottom = false;
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
        : widget.watchlists.where((wl) => wl.name.toLowerCase().contains(_query.toLowerCase())).toList();

    final showSearch  = widget.watchlists.length > _visibleRows;
    final isScrollable = filtered.length > _visibleRows;

    Widget listWidget = filtered.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('No lists match "$_query"', style: const TextStyle(color: MC.dim, fontSize: 13)),
          )
        : ListView.builder(
            controller: isScrollable ? _scrollCtrl : null,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final wl       = filtered[i];
              final isSelected = wl.id == widget.selectedId;
              final isLast   = i == filtered.length - 1;
              return GestureDetector(
                onTap: () => widget.onSelect(wl),
                child: Container(
                  margin: EdgeInsets.only(bottom: (isLast && isScrollable) ? 0 : 3),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? MC.accent1.withAlpha(20) : MC.bg1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isSelected ? MC.accent1 : MC.line,
                        width: isSelected ? 1.0 : 0.5),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                        color: isSelected ? MC.accent1 : MC.dim, size: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(wl.name,
                            style: TextStyle(
                                color: isSelected ? MC.ink : MC.mute,
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
                      ),
                      Text('${wl.movies.length} films',
                          style: MT.mono(size: 9, letterSpacing: 0, color: MC.dim)),
                    ],
                  ),
                ),
              );
            },
          );

    if (isScrollable) {
      listWidget = Stack(
        children: [
          listWidget,
          if (!_atTop)
            Positioned(
              top: 0, left: 0, right: 0, height: 18,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [MC.bg0, MC.bg0.withAlpha(0)],
                    ),
                  ),
                ),
              ),
            ),
          if (!_atBottom)
            Positioned(
              bottom: 0, left: 0, right: 0, height: 18,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
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
        Text('CHOOSE A LIST', style: MT.mono(size: 9, letterSpacing: 2, color: MC.dim)),
        const SizedBox(height: 8),
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
                      setState(() { _query = q; _atTop = true; _atBottom = false; });
                      _resetScroll();
                    },
                    style: const TextStyle(color: MC.ink, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Search lists…',
                      hintStyle: TextStyle(color: MC.dim, fontSize: 13),
                      isDense: true, contentPadding: EdgeInsets.zero, border: InputBorder.none,
                    ),
                    cursorColor: MC.accent1,
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() { _query = ''; _atTop = true; _atBottom = false; });
                      _resetScroll();
                    },
                    child: const Icon(Icons.close_rounded, color: MC.dim, size: 14),
                  ),
              ],
            ),
          ),
        if (isScrollable)
          ConstrainedBox(constraints: const BoxConstraints(maxHeight: _maxHeight), child: listWidget)
        else
          listWidget,
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String body;

  const _EmptyState({required this.icon, required this.headline, required this.body});

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
          border: Border.all(color: isWinner ? MC.accent1 : MC.line, width: isWinner ? 1.0 : 0.5),
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
                      Text(movie.title,
                          style: TextStyle(
                              color: isVetoed ? MC.dim : MC.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              decoration: isVetoed ? TextDecoration.lineThrough : null)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: MC.accent1, borderRadius: BorderRadius.circular(20)),
                      child: Text('WINNER', style: MT.mono(size: 9, color: MC.accentInk, letterSpacing: 1)),
                    ),
                  )
                else if (!isVetoed)
                  GestureDetector(
                    onTap: canVeto ? onVeto : () {},
                    child: Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: canVeto ? MC.bg2 : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: canVeto ? MC.line : Colors.transparent, width: 0.5),
                        ),
                        child: Text('VETO',
                            style: MT.mono(size: 9, color: canVeto ? MC.mute : MC.dim, letterSpacing: 1)),
                      ),
                    ),
                  ),
              ],
            ),
            if (isVetoed)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withAlpha(100),
                    alignment: Alignment.center,
                    child: Transform.rotate(
                      angle: -0.3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFB91C1C), width: 2.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('SACRIFICED',
                            style: TextStyle(
                                color: Color(0xFFB91C1C),
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                letterSpacing: 3)),
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
                Text("Tonight's film", style: MT.mono(size: 9, color: MC.accent1, letterSpacing: 1.5)),
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

// ── Séance card ───────────────────────────────────────────────────────────────
class _SeanceCard extends StatefulWidget {
  final SeanceSession? activeSeance;
  final List<Watchlist> watchlists;
  final String currentUserId;
  final String? currentUserName;
  final String? currentUserAvatarUrl;
  final ValueChanged<SeanceSession> onStarted;
  final VoidCallback onEnded;

  const _SeanceCard({
    super.key,
    required this.activeSeance,
    required this.watchlists,
    required this.currentUserId,
    this.currentUserName,
    this.currentUserAvatarUrl,
    required this.onStarted,
    required this.onEnded,
  });

  @override
  State<_SeanceCard> createState() => _SeanceCardState();
}

class _SeanceCardState extends State<_SeanceCard> {
  bool _lit = false;
  bool _loading = false;
  // Set true when a non-host dismisses an active invite so they can start their own.
  bool _declined = false;
  SeanceService? _activeSvc;
  // Set while the pop-out pill is visible; calling it removes the overlay.
  VoidCallback? _removePopOutOverlay;

  @override
  void initState() {
    super.initState();
    _lit = widget.activeSeance != null;
  }

  @override
  void didUpdateWidget(_SeanceCard old) {
    super.didUpdateWidget(old);
    final nowActive = widget.activeSeance != null;
    if (!nowActive) _declined = false;
    // Don't clobber optimistic _lit=true while an operation is in progress —
    // otherwise any mid-call widget rebuild will extinguish the candle.
    if (!_loading) {
      if (_lit != nowActive && !_declined) setState(() => _lit = nowActive);
      if (!nowActive && _lit) setState(() => _lit = false);
    }
  }

  bool get _isHost => widget.activeSeance?.hostId == widget.currentUserId;

  // True when another user is hosting and this user hasn't declined the invite.
  bool get _canJoin =>
      widget.activeSeance != null && !_isHost && !_declined;

  Future<void> _toggle() async {
    if (_loading) return;
    if (!_lit) {
      setState(() { _lit = true; _declined = false; });
    } else if (_isHost && widget.activeSeance != null) {
      await _endSeance();
    } else if (_canJoin) {
      await _joinSeance();
    } else {
      setState(() => _lit = false);
    }
  }

  void _declineSeance() {
    setState(() {
      _declined = true;
      _lit = false;
    });
  }

  void autoJoin() {
    if (!mounted) return;
    _joinSeance();
  }

  void signalRemoteEnd() => _activeSvc?.signalRemoteEnd();

  Future<void> _returnToSeance() async {
    if (!mounted || widget.activeSeance == null || _activeSvc != null) return;
    setState(() => _loading = true);
    try {
      final data = await ApiService.fetchHostToken(widget.activeSeance!.watchlistId);
      if (!mounted) return;
      final session = widget.activeSeance!;
      await _openSeanceScreen(
        token: data['token'] as String,
        livekitHost: data['livekitHost'] as String? ?? '',
        session: session,
        isHost: true,
      );
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _pickWatchlist() async {
    if (widget.watchlists.length == 1) return widget.watchlists.first.id;
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.6;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1612),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x1FF4ECDE)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Text('Invite which cult?',
                    style: GoogleFonts.newsreader(
                        fontSize: 22, color: const Color(0xFFF4ECDE))),
              ),
              const Divider(height: 1, color: Color(0x14F4ECDE)),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.watchlists.length,
                  itemBuilder: (_, i) {
                    final wl = widget.watchlists[i];
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, wl.id),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                        decoration: const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: Color(0x0FF4ECDE)))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(wl.name,
                                style: const TextStyle(
                                    color: Color(0xFFF4ECDE),
                                    fontSize: 15,
                                    height: 1.2)),
                            const SizedBox(height: 3),
                            Text(
                              '${wl.memberIds.length} member${wl.memberIds.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                  fontFamily: GoogleFonts.martianMono().fontFamily,
                                  fontSize: 10,
                                  letterSpacing: 1.4,
                                  color: const Color(0x66F4ECDE)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _beginSeance() async {
    // Set loading BEFORE the first await so didUpdateWidget can't clobber the
    // optimistic _lit=true while the watchlist picker or permission dialog is open.
    setState(() => _loading = true);
    final wlId = await _pickWatchlist();
    if (!mounted || wlId == null) {
      if (mounted) setState(() { _loading = false; _lit = false; });
      return;
    }

    final micStatus = await Permission.microphone.request();
    if (!mounted) return;
    if (!micStatus.isGranted) {
      if (mounted) setState(() { _loading = false; _lit = false; });
      _showPermissionSnack('Séance requires mic access. Enable it in Settings.');
      return;
    }
    try {
      final data = await ApiService.startSeance(wlId);
      if (!mounted) return;
      final session = SeanceSession(
        watchlistId: wlId,
        hostId: data['hostId'] as String? ?? '',
        hostName: data['hostName'] as String? ?? '',
        hostAvatarUrl: data['hostAvatarUrl'] as String?,
        livekitRoom: data['livekitRoom'] as String? ?? '',
      );
      setState(() => _lit = true);
      widget.onStarted(session);
      await _openSeanceScreen(
        token: data['token'] as String,
        livekitHost: data['livekitHost'] as String? ?? '',
        session: session,
        isHost: true,
      );
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinSeance() async {
    final activeSeance = widget.activeSeance;
    if (activeSeance == null || !mounted) return;
    final activeWlId = activeSeance.watchlistId;
    setState(() => _loading = true);
    try {
      final data = await ApiService.joinSeance(activeWlId);
      if (!mounted) return;
      final session = SeanceSession(
        watchlistId: activeWlId,
        hostId: data['hostId'] as String? ?? '',
        hostName: data['hostName'] as String? ?? '',
        hostAvatarUrl: data['hostAvatarUrl'] as String?,
        livekitRoom: data['livekitRoom'] as String? ?? '',
      );
      await _openSeanceScreen(
        token: data['token'] as String,
        livekitHost: data['livekitHost'] as String? ?? '',
        session: session,
        isHost: false,
      );
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message);
    } catch (e) {
      if (mounted) _showSnack('Could not join séance');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _endSeance() async {
    final active = widget.activeSeance;
    if (active == null) return;
    final activeWlId = active.watchlistId;
    setState(() { _lit = false; _loading = true; });
    // If popped out: close the floating pill and kill the stream before the API call.
    final poppedOutSvc = _activeSvc;
    if (poppedOutSvc != null) {
      _removePopOutOverlay?.call();
      _activeSvc = null;
      await poppedOutSvc.dispose();
    }
    try {
      await ApiService.endSeance(activeWlId);
      if (mounted) widget.onEnded();
    } on ApiException catch (e) {
      if (mounted) { setState(() => _lit = true); _showSnack(e.message); }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSeanceScreen({
    required String token,
    required String livekitHost,
    required SeanceSession session,
    required bool isHost,
  }) async {
    final svc = SeanceService();
    try {
      if (isHost) {
        await svc.startAsHost(livekitHost, token);
      } else {
        await svc.joinAsViewer(livekitHost, token, hostIdentity: session.hostId);
      }
    } catch (e) {
      await svc.dispose();
      if (mounted) _showSnack('Could not connect: ${e.toString()}');
      return;
    }
    if (!mounted) { await svc.dispose(); return; }
    _activeSvc = svc;

    final activeWlId = session.watchlistId;
    final nav = Navigator.of(context);
    bool poppedOut = false;
    OverlayEntry? floatingOverlay;

    bool onEndedFired = false;

    void removeOverlay() {
      floatingOverlay?.remove();
      floatingOverlay = null;
      _removePopOutOverlay = null;
    }

    // Shared end-séance handler — guarded so button tap + WS event can't both fire.
    Future<void> onSeanceEnded() async {
      if (onEndedFired) return;
      onEndedFired = true;
      if (isHost) {
        try { await ApiService.endSeance(activeWlId); } catch (_) {}
      }
      removeOverlay();
      _activeSvc = null;
      if (mounted) nav.pop();
      await svc.dispose();
      if (mounted) widget.onEnded();
    }

    // Forward-declared so showPill and returnToSeance can mutually reference.
    late final Future<void> Function() returnToSeance;
    late final void Function() showPill;

    returnToSeance = () async {
      poppedOut = false;
      removeOverlay();
      if (!mounted) return;
      // Re-push with the SAME service — preserves screen share and audio.
      await nav.push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => SeanceScreen(
            service: svc,
            isHost: isHost,
            hostName: session.hostName,
            hostId: session.hostId,
            hostAvatarUrl: session.hostAvatarUrl,
            currentUserId: widget.currentUserId,
            currentUserName: widget.currentUserName,
            currentUserAvatarUrl: widget.currentUserAvatarUrl,
            onEnded: onSeanceEnded,
            onPopOut: () {
              poppedOut = true;
              nav.pop();
            },
          ),
        ),
      );
      if (poppedOut && mounted) {
        poppedOut = false;
        showPill();
      }
    };

    showPill = () {
      final pillCollapsed = ValueNotifier<bool>(false);
      final overlayState = Overlay.of(context);
      floatingOverlay = OverlayEntry(
        builder: (ctx) => ValueListenableBuilder<bool>(
          valueListenable: pillCollapsed,
          builder: (_, collapsed, __) {
            final bottom = MediaQuery.of(ctx).padding.bottom + 90;
            if (collapsed) {
              return Positioned(
                bottom: bottom,
                right: 16,
                child: Material(
                  color: Colors.transparent,
                  child: GestureDetector(
                    onTap: () => pillCollapsed.value = false,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1210),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE8A13C).withAlpha(120)),
                        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 14)],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(Icons.sensors, size: 22, color: Color(0xFFE8A13C)),
                          Positioned(
                            top: 9, right: 9,
                            child: Container(
                              width: 8, height: 8,
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle, color: Color(0xFF4ADE80)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            return Positioned(
              bottom: bottom,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1210),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8A13C).withAlpha(120)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x88000000), blurRadius: 20, offset: Offset(0, 6)),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sensors, size: 16, color: Color(0xFFE8A13C)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Séance active — ${session.hostName}',
                          style: TextStyle(
                            fontFamily: GoogleFonts.martianMono().fontFamily,
                            fontSize: 11,
                            color: const Color(0xFFF3E4CF),
                            letterSpacing: 0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedBuilder(
                        animation: svc,
                        builder: (_, __) => GestureDetector(
                          onTap: () => svc.toggleMic(),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: svc.micMuted
                                  ? const Color(0x29E8A13C)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              svc.micMuted
                                  ? Icons.mic_off_outlined
                                  : Icons.mic_none_outlined,
                              size: 16,
                              color: const Color(0xBFF3E4CF),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => returnToSeance(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8A13C),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'RETURN',
                            style: TextStyle(
                              fontFamily: GoogleFonts.martianMono().fontFamily,
                              fontSize: 10,
                              color: const Color(0xFF1B1210),
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => pillCollapsed.value = true,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.remove_rounded, color: Color(0xCCF3E4CF), size: 16),
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          setState(() { _lit = false; });
                          removeOverlay();
                          if (isHost) {
                            try { await ApiService.endSeance(activeWlId); } catch (_) {}
                          }
                          _activeSvc = null;
                          await svc.dispose();
                          if (mounted) widget.onEnded();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded, color: Color(0xCCF3E4CF), size: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      overlayState.insert(floatingOverlay!);
      _removePopOutOverlay = removeOverlay;
    };

    await nav.push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SeanceScreen(
          service: svc,
          isHost: isHost,
          hostName: session.hostName,
          hostId: session.hostId,
          hostAvatarUrl: session.hostAvatarUrl,
          currentUserId: widget.currentUserId,
          currentUserName: widget.currentUserName,
          currentUserAvatarUrl: widget.currentUserAvatarUrl,
          onEnded: onSeanceEnded,
          onPopOut: () {
            poppedOut = true;
            nav.pop();
          },
        ),
      ),
    );

    if (poppedOut && mounted) {
      // Service stays alive while the pill is visible — do NOT dispose here.
      showPill();
      return;
    }

    _activeSvc = null;
    if (!onEndedFired) await svc.dispose();
  }

  void _showSnack(String msg) => showTopToast(context, msg);

  void _showPermissionSnack(String msg) {
    showTopToast(context, '$msg — open Settings to allow');
    // Open settings after a brief delay so the toast is readable
    Future.delayed(const Duration(milliseconds: 400), openAppSettings);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.activeSeance;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF121010),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _lit ? const Color(0x8CE8A13C) : const Color(0x47E8A13C),
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x8C000000), blurRadius: 60, offset: Offset(0, 24)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // warm spill anchored on the candle (left), not the card centre
          Positioned(
            left: -88,
            top: -120,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 800),
                opacity: _lit ? 1 : 0,
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x33FFA647),
                        Color(0x12FF8C2B),
                        Color(0x00000000),
                      ],
                      stops: [0.0, 0.42, 0.72],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CandleWidget(lit: _lit, onTap: _toggle, width: 86, height: 118),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Séance',
                            style: GoogleFonts.newsreader(
                              fontSize: 26,
                              height: 1.1,
                              color: const Color(0xFFF3E4CF),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_lit) ...[
                          const SizedBox(width: 10),
                          _LiveBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _lit
                          ? (_canJoin
                              ? '${active?.hostName ?? ''} is hosting'
                              : 'The cult is gathering — the candle is lit.')
                          : 'Light the candle, Share what you see.',
                      style: TextStyle(
                        fontFamily: GoogleFonts.martianMono().fontFamily,
                        fontSize: 11,
                        height: 1.6,
                        color: const Color(0x8CF3E4CF),
                      ),
                    ),
                  ],
                ),
              ),
              if (_lit && !_declined) ...[
                const SizedBox(width: 18),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (_isHost && widget.activeSeance != null) {
                          _returnToSeance();
                        } else if (_canJoin) {
                          _joinSeance();
                        } else {
                          _beginSeance();
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0x1FE8A13C),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0x66E8A13C)),
                        ),
                        child: Text(
                          _loading
                              ? '…'
                              : (_isHost && widget.activeSeance != null
                                  ? 'ENTER SÉANCE'
                                  : _canJoin
                                      ? 'JOIN SÉANCE'
                                      : 'BEGIN SÉANCE'),
                          style: TextStyle(
                            fontFamily: GoogleFonts.martianMono().fontFamily,
                            fontSize: 11,
                            letterSpacing: 1.98,
                            color: const Color(0xFFF3E4CF),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    if (_canJoin)
                      GestureDetector(
                        onTap: _declineSeance,
                        child: Text(
                          'not now',
                          style: TextStyle(
                            fontFamily: GoogleFonts.martianMono().fontFamily,
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: const Color(0x50F3E4CF),
                          ),
                        ),
                      )
                    else
                      Text(
                        'blow it out',
                        style: TextStyle(
                          fontFamily: GoogleFonts.martianMono().fontFamily,
                          fontSize: 10,
                          letterSpacing: 1.4,
                          color: const Color(0x80F3E4CF),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4ADE80),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4ADE80)
                      .withValues(alpha: (1.0 - _pulse.value) * 0.5),
                  blurRadius: 8 * _pulse.value,
                  spreadRadius: 4 * _pulse.value,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'LIVE',
          style: TextStyle(
            fontFamily: GoogleFonts.martianMono().fontFamily,
            fontSize: 9,
            letterSpacing: 1.8,
            color: const Color(0xFF7FE0A0),
          ),
        ),
      ],
    );
  }
}
