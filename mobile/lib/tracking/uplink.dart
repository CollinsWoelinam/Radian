import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:fixnum/fixnum.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../gen/radian/telemetry/v1/telemetry.pb.dart';
import 'status.dart';

/// WebSocket link to the ingest service. Reconnects with jittered backoff and
/// sends heartbeats so the server's idle timeout never fires while parked.
class Uplink {
  Uplink({
    required this.url,
    required this.token,
    required this.onMessage,
    required this.onState,
    required this.onAuthRejected,
  });

  final String url;
  /// Used for the next connection attempt; updated when the token is refreshed.
  String token;
  final void Function(ServerMessage) onMessage;
  final void Function(LinkState) onState;
  final void Function() onAuthRejected;

  IOWebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _retryTimer;
  Timer? _heartbeat;
  int _attempt = 0;
  bool _stopped = true;
  bool _open = false;

  bool get isOpen => _open;

  void start() {
    _stopped = false;
    _connect();
  }

  Future<void> _connect() async {
    if (_stopped) return;
    onState(LinkState.connecting);
    final channel = IOWebSocketChannel.connect(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
      pingInterval: const Duration(seconds: 20),
      connectTimeout: const Duration(seconds: 10),
    );
    _channel = channel;
    try {
      await channel.ready;
    } catch (e) {
      if (_isUnauthorized(e)) {
        _stopped = true;
        onState(LinkState.offline);
        onAuthRejected();
        return;
      }
      _scheduleRetry();
      return;
    }
    if (_stopped) {
      channel.sink.close();
      return;
    }

    _attempt = 0;
    _open = true;
    onState(LinkState.online);
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      send(ClientMessage(heartbeat: Heartbeat(clientTimeMs: Int64(DateTime.now().millisecondsSinceEpoch))));
    });
    _sub = channel.stream.listen(
      (data) {
        if (data is List<int>) onMessage(ServerMessage.fromBuffer(data));
      },
      onDone: _onClosed,
      onError: (_) => _onClosed(),
      cancelOnError: true,
    );
  }

  void _onClosed() {
    _open = false;
    _heartbeat?.cancel();
    _sub?.cancel();
    if (_stopped) return;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    onState(LinkState.offline);
    final base = math.min(1000 * math.pow(2, _attempt++).toInt(), 30000);
    final jittered = (base * (0.75 + math.Random().nextDouble() * 0.5)).round();
    _retryTimer = Timer(Duration(milliseconds: jittered), _connect);
  }

  /// Returns false if the socket isn't open; the caller keeps the data buffered.
  bool send(ClientMessage msg) {
    if (!_open) return false;
    _channel!.sink.add(msg.writeToBuffer());
    return true;
  }

  Future<void> stop() async {
    _stopped = true;
    _open = false;
    _retryTimer?.cancel();
    _heartbeat?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close(1000, 'shift ended');
    onState(LinkState.offline);
  }

  /// The ingest service rejects bad or expired tokens with HTTP 401 during
  /// the upgrade, which dart:io surfaces as a WebSocketException.
  static bool _isUnauthorized(Object e) {
    final inner = e is WebSocketChannelException ? e.inner : e;
    return inner is WebSocketException && inner.message.contains('401');
  }
}
