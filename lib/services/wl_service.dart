import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';

class WatchlistEvent {
  final String type;
  final Map<String, dynamic> data;
  const WatchlistEvent(this.type, this.data);
}

class WatchlistService {
  static String get _wsBase =>
      Platform.isAndroid ? 'ws://10.0.2.2:3000' : 'ws://localhost:3000';
  WebSocketChannel? _channel;

  final _controller = StreamController<WatchlistEvent>.broadcast();
  Stream<WatchlistEvent> get events => _controller.stream;

  void connect(String watchlistId) {
    _channel?.sink.close();
    _channel = WebSocketChannel.connect(
      Uri.parse('$_wsBase?watchlistId=$watchlistId'),
    );
    
    _channel!.stream.listen((raw) {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      _controller.add(WatchlistEvent(msg['type'] as String, msg));
    }, 
    cancelOnError: false);
  }

  void disconnect(){
    _channel?.sink.close();
    _channel = null;
  }
  void dispose(){
    disconnect();
    _controller.close();
  }
}