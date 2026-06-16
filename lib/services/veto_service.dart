import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';

class VetoEvent {
  final String type;
  final Map<String, dynamic> data;
  const VetoEvent(this.type, this.data);
}

class VetoService {
  static String get _wsBase =>
      Platform.isAndroid ? 'ws://10.0.2.2:3000' : 'ws://localhost:3000';

  WebSocketChannel? _channel;
  final _controller = StreamController<VetoEvent>.broadcast();

  Stream<VetoEvent> get events => _controller.stream;

  void connect(String watchlistId) {
    _channel?.sink.close();
    _channel = WebSocketChannel.connect(
      Uri.parse('$_wsBase?watchlistId=$watchlistId'),
    );
    _channel!.stream.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(VetoEvent(msg['type'] as String, msg));
        } catch (_) {}
      },
      onError: (_) {},
      onDone: () {},
      cancelOnError: false,
    );
  }

  // Picker has chosen films — pickCount determines veto budget (1→0 vetos, 2→1, 3→2)
  void startGame({
    required List<String> pickedIds,
    required String pickerId,
    required String pickerName,
    required int pickCount,
    bool sendInvite = true,
  }) {
    _send({
      'type': 'veto_start',
      'pickedIds': pickedIds,
      'pickerId': pickerId,
      'pickerName': pickerName,
      'pickCount': pickCount,
      'sendInvite': sendInvite,
    });
  }

  // A user adds their picks to an existing pool
  void addPicks({
    required List<String> additionalPickIds,
    required String pickerId,
    required String pickerName,
    required int pickCount,
  }) {
    _send({
      'type': 'veto_add_picks',
      'additionalPickIds': additionalPickIds,
      'pickerId': pickerId,
      'pickerName': pickerName,
      'pickCount': pickCount,
    });
  }

  // Vetoer has eliminated a film — sends to server, server broadcasts to all members
  void vetoMovie({
    required String vetoedId,
    required String vetoerId,
    required String vetoerName,
  }) {
    _send({
      'type': 'veto_action',
      'vetoedId': vetoedId,
      'vetoerId': vetoerId,
      'vetoerName': vetoerName,
    });
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

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void resetGame() {
    _send({'type': 'veto_reset'});
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
