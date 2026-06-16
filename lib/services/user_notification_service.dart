import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';

// Dedicated per-user WebSocket channel for app-level notifications (veto invites, etc.)
// Connects with ws://host:port?userId=<auth0Sub>
class UserNotificationService {
  static String get _wsBase =>
      Platform.isAndroid ? 'ws://10.0.2.2:3000' : 'ws://localhost:3000';

  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _controller.stream;

  void connect(String userId) {
    _channel?.sink.close();
    _channel = WebSocketChannel.connect(
      Uri.parse('$_wsBase?userId=${Uri.encodeQueryComponent(userId)}'),
    );
    _channel!.stream.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(msg);
        } catch (_) {}
      },
      onError: (_) {},
      onDone: () {},
      cancelOnError: false,
    );
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
