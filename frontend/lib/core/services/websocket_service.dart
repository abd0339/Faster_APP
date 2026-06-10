import 'dart:convert';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../constants/api_constants.dart';
import 'storage_service.dart';

class WebSocketService {
  WebSocketService._();
  static final WebSocketService instance = WebSocketService._();

  StompClient? _client;
  bool _isConnected = false;

  final Map<String, StompUnsubscribe> _subscriptions = {};

  // ─── Connect ──────────────────────────────────────
  Future<void> connect() async {
    if (_isConnected) return;

    final token = await StorageService.instance.getToken();

    _client = StompClient(
      config: StompConfig.sockJS(
        url: ApiConstants.wsUrl,
        onConnect: _onConnect,
        onDisconnect: _onDisconnect,
        onWebSocketError: (error) => print('WS error: $error'),
        stompConnectHeaders:
            token != null ? {'Authorization': 'Bearer $token'} : {},
        webSocketConnectHeaders:
            token != null ? {'Authorization': 'Bearer $token'} : {},
      ),
    );

    _client!.activate();
  }

  void _onConnect(StompFrame frame) {
    _isConnected = true;
    print('✅ WebSocket connected');
  }

  void _onDisconnect(StompFrame frame) {
    _isConnected = false;
    print('❌ WebSocket disconnected');
  }

  // ─── Subscribe to order tracking ──────────────────
  void subscribeToOrder(
    int orderId,
    void Function(Map<String, dynamic>) onUpdate,
  ) {
    _subscribe(
      ApiConstants.orderTopic(orderId),
      onUpdate,
    );
  }

  // ─── Subscribe to driver notifications ────────────
  void subscribeToDriver(
    int driverId,
    void Function(Map<String, dynamic>) onUpdate,
  ) {
    _subscribe(
      ApiConstants.driverTopic(driverId),
      onUpdate,
    );
  }

  // ─── Subscribe to merchant notifications ──────────
  void subscribeToMerchant(
    int merchantId,
    void Function(Map<String, dynamic>) onUpdate,
  ) {
    _subscribe(
      ApiConstants.merchantTopic(merchantId),
      onUpdate,
    );
  }

  // ─── Internal subscribe helper ────────────────────
  void _subscribe(
    String destination,
    void Function(Map<String, dynamic>) onUpdate,
  ) {
    if (_client == null || !_isConnected) return;

    if (_subscriptions.containsKey(destination)) {
      _subscriptions[destination]!();
    }

    final unsubscribe = _client!.subscribe(
      destination: destination,
      callback: (frame) {
        if (frame.body != null) {
          try {
            final data = jsonDecode(frame.body!) as Map<String, dynamic>;
            onUpdate(data);
          } catch (_) {}
        }
      },
    );

    _subscriptions[destination] = unsubscribe;
  }

  // ─── Send driver GPS via WebSocket ────────────────
  void sendDriverLocation(double lat, double lng) {
    if (_client == null || !_isConnected) return;
    _client!.send(
      destination: '/app/driver.location',
      body: jsonEncode({'lat': lat, 'lng': lng}),
    );
  }

  // ─── Unsubscribe ──────────────────────────────────
  void unsubscribe(String destination) {
    _subscriptions[destination]?.call();
    _subscriptions.remove(destination);
  }

  // ─── Disconnect ───────────────────────────────────
  void disconnect() {
    _subscriptions.forEach((_, unsub) => unsub());
    _subscriptions.clear();
    _client?.deactivate();
    _isConnected = false;
  }

  bool get isConnected => _isConnected;
}
