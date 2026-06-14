import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  int _currentIndex = 0;
  bool _isOnline = false;
  String _currentMode = 'PACKAGE';
  List<dynamic> _orders = [];
  Map<String, dynamic>? _debtInfo;
  Map<String, dynamic>? _activeOrder;
  bool _isLoading = false;
  bool _isTogglingStatus = false;
  bool _isUpdatingOrder = false;

  // WebSocket + GPS
  StreamSubscription? _locationSub;
  int? _driverId;

  // Incoming order overlay
  Map<String, dynamic>? _incomingOrder;
  bool _showIncomingOrder = false;

  @override
  void initState() {
    super.initState();
    _loadDriverId();
    _loadData();
    _checkStatus();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    WebSocketService.instance.disconnect();
    super.dispose();
  }

  // ─── Get driver ID from auth state ────────────────
  void _loadDriverId() {
    final state = context.read<AuthBloc>().state;
    if (state is AuthSuccess) {
      // We store email, not ID — fetch from status endpoint
      _fetchDriverId();
    }
  }

  Future<void> _fetchDriverId() async {
    try {
      final res = await ApiService.instance.get(ApiConstants.driverStatus);
      final data = res.data as Map<String, dynamic>?;
      if (data != null && mounted) {
        setState(() => _driverId = data['driverId'] as int?);
        // If already online from previous session, connect WS
        if (data['isOnline'] == true) {
          _connectWebSocket();
          _startLocationStream();
        }
      }
    } catch (_) {}
  }

  // ─── CHECK STATUS ─────────────────────────────────
  Future<void> _checkStatus() async {
    try {
      final res = await ApiService.instance.get(ApiConstants.driverStatus);
      final data = res.data as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _isOnline = data['isOnline'] ?? false;
        _currentMode = data['mode'] ?? 'PACKAGE';
      });
    } catch (_) {}
  }

  // ─── LOAD DATA ────────────────────────────────────
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.get(ApiConstants.driverOrders),
        ApiService.instance.get(ApiConstants.myDebt),
      ]);
      if (!mounted) return;
      final ordersData = results[0].data;
      setState(() {
        _orders = ordersData is List
            ? ordersData
            : (ordersData as Map?)?['content'] as List? ?? [];
        _debtInfo = results[1].data as Map<String, dynamic>?;
        // Find active order (ACCEPTED or PICKED_UP)
        _activeOrder = _orders.cast<Map<String, dynamic>?>().firstWhere(
              (o) =>
                  o?['status'] == 'ACCEPTED' ||
                  o?['status'] == 'PREPARING' ||
                  o?['status'] == 'READY_FOR_PICKUP' ||
                  o?['status'] == 'PICKED_UP',
              orElse: () => null,
            );
      });
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  // ─── WEBSOCKET ────────────────────────────────────
  void _connectWebSocket() async {
    await WebSocketService.instance.connect();
    if (_driverId != null) {
      WebSocketService.instance.subscribeToDriver(
        _driverId!,
        _onDriverMessage,
      );
    }
  }

  void _onDriverMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;

    if (type == 'NEW_ORDER' && mounted) {
      // New order ping — show incoming card
      setState(() {
        _incomingOrder = data['order'] as Map<String, dynamic>? ?? data;
        _showIncomingOrder = true;
      });
      if (!kIsWeb) HapticFeedback.heavyImpact();
    } else if (type == 'BLOCKED' && mounted) {
      // Admin blocked this driver
      setState(() => _isOnline = false);
      _showError('Account paused. Pay your balance to continue.');
    } else if (type == 'ORDER_UPDATE' && mounted) {
      _loadData();
    }
  }

  // ─── GPS STREAM ───────────────────────────────────
  void _startLocationStream() {
    _locationSub?.cancel();
    _locationSub =
        LocationService.instance.getLiveLocationStream().listen((position) {
      // Send GPS via WebSocket (faster) + REST fallback
      WebSocketService.instance.sendDriverLocation(
        position.latitude,
        position.longitude,
      );
      // Also POST via REST every update
      ApiService.instance.post(
        ApiConstants.driverLocation,
        data: {
          'lat': position.latitude,
          'lng': position.longitude,
        },
      ).catchError((_) {});
    });
  }

  void _stopLocationStream() {
    _locationSub?.cancel();
    _locationSub = null;
  }

  // ─── TOGGLE ONLINE ────────────────────────────────
  Future<void> _toggleOnlineStatus() async {
    if (!mounted) return;
    setState(() => _isTogglingStatus = true);
    if (!kIsWeb) HapticFeedback.heavyImpact();

    try {
      if (_isOnline) {
        // Go offline
        await ApiService.instance.post(ApiConstants.driverOffline);
        _stopLocationStream();
        WebSocketService.instance.disconnect();
        if (!mounted) return;
        setState(() => _isOnline = false);
      } else {
        // Get location
        final position = await LocationService.instance.getCurrentPosition();
        await ApiService.instance.post(
          ApiConstants.driverOnline,
          data: {
            'mode': _currentMode,
            'lat': position?.latitude ?? 33.8938,
            'lng': position?.longitude ?? 35.5018,
          },
        );
        _connectWebSocket();
        _startLocationStream();
        if (!mounted) return;
        setState(() => _isOnline = true);
      }
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isTogglingStatus = false);
    }
  }

  // ─── ACCEPT ORDER ─────────────────────────────────
  Future<void> _acceptOrder(int orderId) async {
    if (!mounted) return;
    setState(() {
      _showIncomingOrder = false;
      _incomingOrder = null;
    });
    try {
      await ApiService.instance.post(ApiConstants.orderAccept(orderId));
      await _loadData();
      if (mounted) _showSuccess('Order accepted!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── UPDATE ORDER STATUS ──────────────────────────
  Future<void> _updateOrderStatus(int orderId, String status) async {
    if (!mounted) return;
    setState(() => _isUpdatingOrder = true);
    try {
      await ApiService.instance.patch(
        ApiConstants.orderStatus(orderId),
        data: {'status': status},
      );
      await _loadData();
      if (mounted) {
        _showSuccess(_statusLabel(status));
      }
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isUpdatingOrder = false);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'PREPARING':
        return 'Merchant is preparing!';
      case 'READY_FOR_PICKUP':
        return 'Order is ready!';
      case 'PICKED_UP':
        return 'Picked up — on the way!';
      case 'DELIVERED':
        return 'Delivered! Commission recorded.';
      default:
        return 'Status updated';
    }
  }

  // ─── NEXT STATUS after current ────────────────────
  String? _nextStatus(String current) {
    switch (current) {
      case 'ACCEPTED':
        return 'PREPARING';
      case 'PREPARING':
        return 'READY_FOR_PICKUP';
      case 'READY_FOR_PICKUP':
        return 'PICKED_UP';
      case 'PICKED_UP':
        return 'DELIVERED';
      default:
        return null;
    }
  }

  String _nextStatusLabel(String current) {
    switch (current) {
      case 'ACCEPTED':
        return 'Merchant is Preparing';
      case 'PREPARING':
        return 'Ready for Pickup';
      case 'READY_FOR_PICKUP':
        return 'Picked Up';
      case 'PICKED_UP':
        return 'Mark Delivered';
      default:
        return 'Update';
    }
  }

  IconData _nextStatusIcon(String current) {
    switch (current) {
      case 'ACCEPTED':
        return Icons.restaurant_menu_rounded;
      case 'PREPARING':
        return Icons.inventory_2_outlined;
      case 'READY_FOR_PICKUP':
        return Icons.delivery_dining;
      case 'PICKED_UP':
        return Icons.check_circle_outline;
      default:
        return Icons.update;
    }
  }

  // ─── BUILD ────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Main content
          IndexedStack(
            index: _currentIndex,
            children: [
              _buildHomeTab(),
              _buildOrdersTab(),
              _buildEarningsTab(),
            ],
          ),
          // Incoming order overlay
          if (_showIncomingOrder && _incomingOrder != null)
            _buildIncomingOrderOverlay(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ═══════════════════════════════════════════════════
  // INCOMING ORDER OVERLAY
  // ═══════════════════════════════════════════════════
  Widget _buildIncomingOrderOverlay() {
    final order = _incomingOrder!;
    final orderId = order['id'] as int? ?? 0;
    final total = order['grandTotal'] ?? order['totalPrice'] ?? 0;
    final fee = order['deliveryFee'] ?? 0;
    final address = order['deliveryAddress'] ??
        order['offlineCustomerLandmark'] ??
        'No address';
    final pickup = order['pickupAddress'] ?? 'Store location';
    final tracking = order['trackingCode'] ?? '';

    return GestureDetector(
      onTap: () {}, // Block tap-through
      child: Container(
        color: AppColors.background.withValues(alpha: 0.92),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ─── Pulsing indicator ──────────
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOut,
                  builder: (_, v, child) =>
                      Transform.scale(scale: v, child: child),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(alpha: 0.15),
                      border: Border.all(color: AppColors.accent, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.4),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.delivery_dining,
                          color: AppColors.accent, size: 40),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                Text('New Order!',
                    style: AppTextStyles.displayMedium
                        .copyWith(color: AppColors.accent)),
                const SizedBox(height: 4),
                Text(tracking,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.primary)),
                const SizedBox(height: 24),

                // ─── Order details ──────────────
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _orderDetailRow(
                        Icons.store_outlined,
                        'Pickup',
                        pickup.toString(),
                        AppColors.primary,
                      ),
                      const SizedBox(height: 12),
                      _orderDetailRow(
                        Icons.location_on_outlined,
                        'Delivery',
                        address.toString(),
                        AppColors.accent,
                      ),
                      const Divider(color: AppColors.glassBorder, height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Collect from customer',
                                  style: AppTextStyles.caption),
                              Text('\$$total', style: AppTextStyles.price),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Your delivery fee',
                                  style: AppTextStyles.caption),
                              Text('\$$fee',
                                  style: AppTextStyles.price
                                      .copyWith(color: AppColors.primary)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ─── Accept button ──────────────
                AppButton(
                  label: 'Accept Order',
                  icon: Icons.check_rounded,
                  color: AppColors.accent,
                  textColor: AppColors.background,
                  onPressed: () => _acceptOrder(orderId),
                ),

                const SizedBox(height: 12),

                // ─── Decline ────────────────────
                GestureDetector(
                  onTap: () => setState(() {
                    _showIncomingOrder = false;
                    _incomingOrder = null;
                  }),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.center,
                    child: Text(
                      'Skip this order',
                      style: AppTextStyles.labelLarge
                          .copyWith(color: AppColors.textHint),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _orderDetailRow(
      IconData icon, String label, String value, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              Text(value,
                  style: AppTextStyles.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // HOME TAB
  // ═══════════════════════════════════════════════════
  Widget _buildHomeTab() {
    final debt = (_debtInfo?['currentDebt'] as num?)?.toDouble() ?? 0.0;
    final isBlocked = _debtInfo?['isBlocked'] as bool? ?? false;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Mission Control', style: AppTextStyles.displayMedium),
                  GestureDetector(
                    onTap: () =>
                        context.read<AuthBloc>().add(LogoutRequested()),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.glassWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: const Icon(Icons.logout_rounded,
                          color: AppColors.error, size: 20),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Blocked banner
              if (isBlocked)
                GlassCard(
                  color: AppColors.error,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Row(children: [
                    const Icon(Icons.block_rounded,
                        color: AppColors.error, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Account Paused',
                              style: AppTextStyles.headlineSmall
                                  .copyWith(color: AppColors.error)),
                          Text(
                              'Pay \$$debt via OMT or WishMoney then contact admin.',
                              style: AppTextStyles.bodyMedium),
                        ],
                      ),
                    ),
                  ]),
                ),

              // Active order card — shown when has active order
              if (_activeOrder != null) ...[
                _buildActiveOrderCard(_activeOrder!),
                const SizedBox(height: 20),
              ],

              // Online toggle card
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isOnline ? 'You are Online' : 'You are Offline',
                            style: AppTextStyles.headlineMedium,
                          ),
                          Text(
                            _isOnline
                                ? 'Mode: $_currentMode'
                                : 'Go online to receive orders',
                            style: AppTextStyles.bodyMedium,
                          ),
                        ],
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              _isOnline ? AppColors.accent : AppColors.textHint,
                          boxShadow: _isOnline
                              ? [
                                  BoxShadow(
                                    color:
                                        AppColors.accent.withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    spreadRadius: 4,
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          _isOnline
                              ? Icons.wifi_rounded
                              : Icons.wifi_off_rounded,
                          color: AppColors.background,
                          size: 28,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Mode selector (only when offline)
                  if (!_isOnline)
                    Row(
                      children: ['PACKAGE', 'PEOPLE', 'HYBRID'].map((mode) {
                        final isSel = _currentMode == mode;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _currentMode = mode),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? AppColors.primary.withValues(alpha: 0.15)
                                    : AppColors.glassWhite,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSel
                                      ? AppColors.primary
                                      : AppColors.glassBorder,
                                ),
                              ),
                              child: Text(
                                mode == 'PACKAGE'
                                    ? '📦'
                                    : mode == 'PEOPLE'
                                        ? '👥'
                                        : '⚡',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: 16),

                  AppButton(
                    label:
                        _isOnline ? 'Go Offline' : 'Go Online — $_currentMode',
                    isLoading: _isTogglingStatus,
                    color: _isOnline ? AppColors.error : AppColors.accent,
                    textColor: AppColors.background,
                    onPressed: isBlocked ? null : _toggleOnlineStatus,
                  ),
                ]),
              ),

              const SizedBox(height: 20),

              // Debt card
              GlassCard(
                padding: const EdgeInsets.all(16),
                color: debt > 0 ? AppColors.warning : AppColors.primary,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Commission Due', style: AppTextStyles.bodyMedium),
                        Text('\$$debt', style: AppTextStyles.price),
                      ],
                    ),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        value: (debt / 20.0).clamp(0.0, 1.0),
                        backgroundColor: AppColors.glassWhite,
                        color: debt > 15 ? AppColors.error : AppColors.accent,
                        strokeWidth: 4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text('Recent Orders', style: AppTextStyles.headlineMedium),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              else if (_orders.isEmpty)
                Center(
                  child: Column(children: [
                    const Text('🛵', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text('No orders yet', style: AppTextStyles.headlineMedium),
                    Text('Go online to receive orders',
                        style: AppTextStyles.bodyMedium),
                  ]),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _orders.take(5).length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final order = _orders[i] as Map<String, dynamic>;
                    return GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                order['trackingCode'] ?? '',
                                style: AppTextStyles.labelLarge
                                    .copyWith(color: AppColors.primary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                order['deliveryAddress'] ??
                                    order['offlineCustomerLandmark'] ??
                                    'No address',
                                style: AppTextStyles.bodyMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            StatusBadge(status: order['status'] ?? ''),
                            const SizedBox(height: 4),
                            Text(
                              '\$${order['grandTotal'] ?? 0}',
                              style: AppTextStyles.priceSmall,
                            ),
                          ],
                        ),
                      ]),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // ACTIVE ORDER CARD
  // ═══════════════════════════════════════════════════
  Widget _buildActiveOrderCard(Map<String, dynamic> order) {
    final orderId = order['id'] as int;
    final status = order['status'] as String? ?? '';
    final nextStatus = _nextStatus(status);
    final tracking = order['trackingCode'] as String? ?? '';
    final address = order['deliveryAddress'] ??
        order['offlineCustomerLandmark'] ??
        'No address';
    final total = order['grandTotal'] ?? 0;
    final fee = order['deliveryFee'] ?? 0;

    return GlassCard(
      borderColor: AppColors.accent.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('ACTIVE ORDER',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  )),
            ),
            const Spacer(),
            StatusBadge(status: status),
          ]),

          const SizedBox(height: 12),

          Text(tracking,
              style:
                  AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
          const SizedBox(height: 4),
          Text(address.toString(),
              style: AppTextStyles.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),

          const SizedBox(height: 12),

          Row(children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Collect', style: AppTextStyles.caption),
                Text('\$$total', style: AppTextStyles.price),
              ],
            ),
            const SizedBox(width: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your fee', style: AppTextStyles.caption),
                Text('\$$fee',
                    style:
                        AppTextStyles.price.copyWith(color: AppColors.primary)),
              ],
            ),
          ]),

          const SizedBox(height: 16),

          // Status progress bar
          _buildStatusProgress(status),

          const SizedBox(height: 16),

          // Action button
          if (nextStatus != null)
            AppButton(
              label: _nextStatusLabel(status),
              icon: _nextStatusIcon(status),
              color:
                  status == 'PICKED_UP' ? AppColors.accent : AppColors.primary,
              textColor: AppColors.background,
              isLoading: _isUpdatingOrder,
              onPressed: () => _updateOrderStatus(orderId, nextStatus),
            ),

          if (status == 'DELIVERED')
            GlassCard(
              color: AppColors.accent,
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.check_circle,
                    color: AppColors.accent, size: 20),
                const SizedBox(width: 8),
                Text('Delivered! Commission recorded.',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.accent)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusProgress(String current) {
    final steps = [
      'ACCEPTED',
      'PREPARING',
      'READY_FOR_PICKUP',
      'PICKED_UP',
      'DELIVERED',
    ];
    final labels = ['Accepted', 'Prep', 'Ready', 'Picked', 'Done'];
    final currentIdx = steps.indexOf(current);

    return Row(
      children: List.generate(steps.length, (i) {
        final done = i <= currentIdx;
        final isCurrent = i == currentIdx;
        return Expanded(
          child: Row(children: [
            Expanded(
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? AppColors.accent : AppColors.glassWhite,
                    border: Border.all(
                      color: done ? AppColors.accent : AppColors.glassBorder,
                      width: isCurrent ? 2 : 1,
                    ),
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.4),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded,
                          color: AppColors.background, size: 14)
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: AppTextStyles.caption.copyWith(
                    color: done ? AppColors.accent : AppColors.textHint,
                    fontSize: 8,
                  ),
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
            if (i < steps.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 16),
                  color:
                      i < currentIdx ? AppColors.accent : AppColors.glassBorder,
                ),
              ),
          ]),
        );
      }),
    );
  }

  // ═══════════════════════════════════════════════════
  // ORDERS TAB
  // ═══════════════════════════════════════════════════
  Widget _buildOrdersTab() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My Orders', style: AppTextStyles.displayMedium),
            const SizedBox(height: 24),
            Expanded(
              child: _orders.isEmpty
                  ? const Center(
                      child: Text('No orders yet',
                          style: AppTextStyles.bodyMedium))
                  : ListView.separated(
                      itemCount: _orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final order = _orders[i] as Map<String, dynamic>;
                        return GlassCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    order['trackingCode'] ?? '',
                                    style: AppTextStyles.labelLarge
                                        .copyWith(color: AppColors.primary),
                                  ),
                                  StatusBadge(status: order['status'] ?? ''),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Pickup: ${order['pickupAddress'] ?? 'N/A'}',
                                style: AppTextStyles.bodyMedium,
                              ),
                              Text(
                                'Delivery: ${order['deliveryAddress'] ?? order['offlineCustomerLandmark'] ?? 'N/A'}',
                                style: AppTextStyles.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Collect: \$${order['grandTotal'] ?? 0}',
                                    style: AppTextStyles.price,
                                  ),
                                  Text(
                                    'Fee: \$${order['commissionAmount'] ?? 0}',
                                    style: AppTextStyles.bodyMedium
                                        .copyWith(color: AppColors.error),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // EARNINGS TAB
  // ═══════════════════════════════════════════════════
  Widget _buildEarningsTab() {
    final debt = (_debtInfo?['currentDebt'] as num?)?.toDouble() ?? 0.0;
    final totalDeliveries =
        _orders.where((o) => o['status'] == 'DELIVERED').length;
    final totalEarned = _orders
        .where((o) => o['status'] == 'DELIVERED')
        .fold<double>(0,
            (sum, o) => sum + ((o['deliveryFee'] as num?)?.toDouble() ?? 0.0));

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('My Earnings', style: AppTextStyles.displayMedium),
            const SizedBox(height: 24),

            // Stats row
            Row(children: [
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: AppColors.accent, size: 22),
                      const SizedBox(height: 8),
                      Text('$totalDeliveries',
                          style: AppTextStyles.headlineLarge
                              .copyWith(color: AppColors.accent)),
                      Text('Deliveries', style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.attach_money_rounded,
                          color: AppColors.primary, size: 22),
                      const SizedBox(height: 8),
                      Text('\$$totalEarned',
                          style: AppTextStyles.headlineLarge
                              .copyWith(color: AppColors.primary)),
                      Text('Total Earned', style: AppTextStyles.bodySmall),
                    ],
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 20),

            // Debt card
            GlassCard(
              padding: const EdgeInsets.all(20),
              color: debt > 15 ? AppColors.error : AppColors.primary,
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Commission Due', style: AppTextStyles.bodyLarge),
                    Text('\$$debt',
                        style: AppTextStyles.price.copyWith(
                          color: debt > 15 ? AppColors.error : AppColors.accent,
                        )),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (debt / 20.0).clamp(0.0, 1.0),
                    backgroundColor: AppColors.glassWhite,
                    color: debt > 15 ? AppColors.error : AppColors.accent,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text('\$$debt of \$20.00 limit',
                    style: AppTextStyles.bodyMedium),
                if (debt > 0) ...[
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.glassBorder),
                  const SizedBox(height: 12),
                  Text(
                    'Pay via OMT or WishMoney,\nthen contact admin to reactivate.',
                    style: AppTextStyles.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ─── BOTTOM NAV ───────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Earnings',
          ),
        ],
      ),
    );
  }

  // ─── HELPERS ──────────────────────────────────────
  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}
