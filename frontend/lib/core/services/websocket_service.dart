import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../constants/app_config.dart';
import 'storage_service.dart';

class WebSocketService {
  WebSocketService._();
  static final WebSocketService instance = WebSocketService._();

  StompClient? _client;
  bool _isConnected = false;
  bool _isConnecting = false;

  final Map<String, StompUnsubscribe> _subscriptions = {};

  // ─── Pending subscriptions ────────────────────────
  // If connect() hasn't finished yet, subscriptions are
  // queued here and re-applied once the socket connects.
  final List<_PendingSubscription> _pendingSubscriptions = [];

  // ─── Connect ──────────────────────────────────────
  // Reads backend URL from .env via AppConfig
  // Adds heartbeat + auto-reconnect
  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;
    _isConnecting = true;

    final token = await StorageService.instance.getToken();

    // Build WS URL from the same base URL as the REST API
    // e.g. http://localhost:8080 → http://localhost:8080/ws
    final wsUrl = '${AppConfig.backendUrl}/ws';

    _client = StompClient(
      config: StompConfig.sockJS(
        url: wsUrl,
        onConnect: _onConnect,
        onDisconnect: _onDisconnect,
        onWebSocketError: (error) => print('WS error: $error'),
        onStompError: (frame) => print('STOMP error: ${frame.body}'),

        // ─── Auth headers ─────────────────────────
        stompConnectHeaders:
            token != null ? {'Authorization': 'Bearer $token'} : {},
        // Browsers block custom WebSocket headers
        webSocketConnectHeaders: (!kIsWeb && token != null)
            ? {'Authorization': 'Bearer $token'}
            : {},

        // ─── Heartbeat ────────────────────────────
        // Keeps connection alive through NAT/proxies
        // Detects silent disconnects within 5 seconds
        heartbeatOutgoing: const Duration(seconds: 5),
        heartbeatIncoming: const Duration(seconds: 5),

        // ─── Auto-reconnect ───────────────────────
        // If network drops (phone lock, wifi switch),
        // automatically reconnects after 5 seconds.
        // Driver will not miss orders on reconnect.
        reconnectDelay: const Duration(seconds: 5),
      ),
    );

    _client!.activate();
  }

  void _onConnect(StompFrame frame) {
    _isConnected = true;
    _isConnecting = false;
    print('✅ WebSocket connected');

    // Re-apply any subscriptions that were queued
    // before the connection was established
    for (final pending in _pendingSubscriptions) {
      _subscribe(pending.destination, pending.onUpdate);
    }
    _pendingSubscriptions.clear();
  }

  void _onDisconnect(StompFrame frame) {
    _isConnected = false;
    _isConnecting = false;
    _subscriptions.clear();
    print('❌ WebSocket disconnected — will reconnect in 5s');
  }

  // ─── Subscribe to order tracking ──────────────────
  void subscribeToOrder(
    int orderId,
    void Function(Map<String, dynamic>) onUpdate,
  ) {
    _subscribe('/topic/order/$orderId', onUpdate);
  }

  // ─── Subscribe to driver notifications ────────────
  void subscribeToDriver(
    int driverId,
    void Function(Map<String, dynamic>) onUpdate,
  ) {
    _subscribe('/topic/driver/$driverId', onUpdate);
  }

  // ─── Subscribe to merchant notifications ──────────
  void subscribeToMerchant(
    int merchantId,
    void Function(Map<String, dynamic>) onUpdate,
  ) {
    _subscribe('/topic/merchant/$merchantId', onUpdate);
  }

  // ─── Internal subscribe helper ────────────────────
  void _subscribe(
    String destination,
    void Function(Map<String, dynamic>) onUpdate,
  ) {
    // If not connected yet, queue for when we connect
    if (_client == null || !_isConnected) {
      _pendingSubscriptions.removeWhere((p) => p.destination == destination);
      _pendingSubscriptions.add(_PendingSubscription(destination, onUpdate));
      return;
    }

    // Unsubscribe old listener for this destination
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
  // Primary GPS channel — no auth header per packet,
  // much lower overhead than REST
  void sendDriverLocation(double lat, double lng) {
    if (_client == null || !_isConnected) return;
    _client!.send(
      destination: '/app/driver.location',
      body: jsonEncode({'lat': lat, 'lng': lng}),
    );
  }

  // ─── Unsubscribe from a topic ─────────────────────
  void unsubscribe(String destination) {
    _subscriptions[destination]?.call();
    _subscriptions.remove(destination);
  }

  // ─── Disconnect ───────────────────────────────────
  void disconnect() {
    _subscriptions.forEach((_, unsub) => unsub());
    _subscriptions.clear();
    _pendingSubscriptions.clear();
    _client?.deactivate();
    _isConnected = false;
    _isConnecting = false;
  }

  bool get isConnected => _isConnected;
}

// ─── Internal helper class ─────────────────────────
class _PendingSubscription {
  final String destination;
  final void Function(Map<String, dynamic>) onUpdate;
  _PendingSubscription(this.destination, this.onUpdate);
}
