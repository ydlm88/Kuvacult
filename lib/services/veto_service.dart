// veto_service.dart — Manages the WebSocket connection and outbound message protocol for the Veto game session.
import 'dart:async';
import 'dart:convert';
import '../config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class VetoEvent {
  final String type;
  final Map<String, dynamic> data;
  const VetoEvent(this.type, this.data);
}

class VetoService {
  static String get _wsBase => Config.wsBase;

  WebSocketChannel? _channel;
  String? _watchlistId;
  int _generation = 0;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  final _controller = StreamController<VetoEvent>.broadcast();
  Stream<VetoEvent> get events => _controller.stream;

  void connect(String watchlistId) {
    _watchlistId = watchlistId;
    _reconnect();
  }

  void _reconnect() {
    if (_watchlistId == null) return;
    _channel?.sink.close();
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();

    final watchlistId = _watchlistId!;
    final gen = ++_generation;

    _channel = WebSocketChannel.connect(
      Uri.parse('$_wsBase?watchlistId=$watchlistId'),
    );

    _channel!.ready.catchError((_) {
      if (_watchlistId == watchlistId && _generation == gen) _scheduleReconnect();
    });

    _channel!.stream.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(VetoEvent(msg['type'] as String, msg));
        } catch (_) {}
      },
      onError: (_) {
        if (_watchlistId == watchlistId && _generation == gen) _scheduleReconnect();
      },
      onDone: () {
        if (_watchlistId == watchlistId && _generation == gen) _scheduleReconnect();
      },
      cancelOnError: false,
    );

    // Keep connection alive — Cloudflare Tunnel has ~100s idle timeout
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      try { _channel?.sink.add('{"type":"ping"}'); } catch (_) {}
    });
  }

  void _scheduleReconnect() {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _reconnect);
  }

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void createLobby({
    required String pickerId,
    required String pickerName,
    required int pickCount,
    required bool notifyAll,
  }) {
    _send({
      'type': 'veto_create',
      'pickerId': pickerId,
      'pickerName': pickerName,
      'pickCount': pickCount,
      'notifyAll': notifyAll,
    });
  }

  void joinLobby({required String playerId, required String playerName}) {
    _send({'type': 'veto_join', 'playerId': playerId, 'playerName': playerName});
  }

  void hostStartGame({required String hostId}) {
    _send({'type': 'veto_start_game', 'hostId': hostId});
  }

  void submitPicks({required String playerId, required List<String> pickedIds}) {
    _send({'type': 'veto_add_picks', 'playerId': playerId, 'pickedIds': pickedIds});
  }

  void vetoMovie({
    required String vetoedId,
    required String vetoerId,
    required String vetoerName,
  }) {
    _send({'type': 'veto_action', 'vetoedId': vetoedId, 'vetoerId': vetoerId, 'vetoerName': vetoerName});
  }

  void blackjackBet({required String playerId, required String playerName, required String betMovieId}) {
    _send({'type': 'blackjack_bet', 'playerId': playerId, 'playerName': playerName, 'betMovieId': betMovieId});
  }

  void blackjackHit({required String playerId}) {
    _send({'type': 'blackjack_hit', 'playerId': playerId});
  }

  void blackjackStand({required String playerId}) {
    _send({'type': 'blackjack_stand', 'playerId': playerId});
  }

  void blackjackDealAgain() {
    _send({'type': 'blackjack_deal_again'});
  }

  void cancelLobby({required String hostId}) {
    _send({'type': 'veto_cancel', 'hostId': hostId});
  }

  void resetGame() {
    _send({'type': 'veto_reset'});
  }

  void disconnect() {
    _watchlistId = null;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
