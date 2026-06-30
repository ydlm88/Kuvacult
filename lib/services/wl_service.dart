// wl_service.dart — Maintains a self-reconnecting WebSocket subscription to a watchlist room and exposes its events as a broadcast stream.
import 'dart:async';
import 'dart:convert';
import '../config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WatchlistEvent {
  final String type;
  final Map<String, dynamic> data;
  const WatchlistEvent(this.type, this.data);
}

class WatchlistService {
  static String get _wsBase => Config.wsBase;
  WebSocketChannel? _channel;
  String? _watchlistId;
  // Incremented on each new connection
  int _generation = 0;
  Timer? _pingTimer;

  final _controller = StreamController<WatchlistEvent>.broadcast();
  Stream<WatchlistEvent> get events => _controller.stream;

  void connect(String watchlistId) {
    _watchlistId = watchlistId;
    _reconnect(watchlistId);
  }

  void _reconnect(String watchlistId) {
    if (_watchlistId != watchlistId) return;
    _channel?.sink.close();
    _pingTimer?.cancel();

    final gen = ++_generation;
    _channel = WebSocketChannel.connect(
      Uri.parse('$_wsBase?watchlistId=$watchlistId'),
    );

    _channel!.stream.listen(
      (raw) {
        final msg = jsonDecode(raw as String) as Map<String, dynamic>;
        _controller.add(WatchlistEvent(msg['type'] as String, msg));
      },
      onError: (_, __) {}, // network errors are handled by onDone -> reconnect
      cancelOnError: false,
      onDone: () {
        // Only reconnect if this is still the active connection
        if (_watchlistId == watchlistId && _generation == gen) {
          Future.delayed(const Duration(seconds: 3), () {
            if (_watchlistId == watchlistId && _generation == gen) {
              _reconnect(watchlistId);
            }
          });
        }
      },
    );

    // Keep connection alive(Tunnel has 100s idle timeout)
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      try { _channel?.sink.add('{"type":"ping"}'); } catch (_) {}
    });
  }

  void disconnect() {
    _watchlistId = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
