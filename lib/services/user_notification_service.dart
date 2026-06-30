// user_notification_service.dart — Dedicated per-user WebSocket channel for app-level notifications; connects with userId query param and auto-reconnects on drop.
import 'dart:async';
import 'dart:convert';
import '../config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class UserNotificationService {
  static String get _wsBase => Config.wsBase;

  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _controller.stream;

  String? _userId;
  Timer? _reconnectTimer;
  bool _disposed = false;

  void connect(String userId) {
    _userId = userId;
    _reconnectTimer?.cancel();
    _doConnect();
  }

  void _doConnect() {
    if (_disposed || _userId == null) return;
    _channel?.sink.close();
    _channel = WebSocketChannel.connect(
      Uri.parse('$_wsBase?userId=${Uri.encodeQueryComponent(_userId!)}'),
    );
    _channel!.stream.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(msg);
        } catch (_) {}
      },
      onError: (_) => _scheduleReconnect(),
      onDone: () => _scheduleReconnect(),
      cancelOnError: false,
    );
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), _doConnect);
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _userId = null;
  }

  void dispose() {
    _disposed = true;
    disconnect();
    _controller.close();
  }
}
