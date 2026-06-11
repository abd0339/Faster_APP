import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

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
  bool _isLoading = false;
  bool _isTogglingStatus = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final res = await ApiService.instance.get(ApiConstants.driverStatus);
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _isOnline = data['isOnline'] ?? false;
        _currentMode = data['mode'] ?? 'PACKAGE';
      });
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final ordersRes =
          await ApiService.instance.get(ApiConstants.driverOrders);
      final debtRes = await ApiService.instance.get(ApiConstants.myDebt);
      setState(() {
        _orders = ordersRes.data as List<dynamic>;
        _debtInfo = debtRes.data as Map<String, dynamic>;
      });
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  // ─── Toggle online/offline ────────────────────────
  Future<void> _toggleOnlineStatus() async {
    setState(() => _isTogglingStatus = true);
    HapticFeedback.heavyImpact();

    try {
      if (_isOnline) {
        await ApiService.instance.post(ApiConstants.driverOffline);
        setState(() => _isOnline = false);
      } else {
        // Get current location
        final position = await LocationService.instance.getCurrentPosition();

        await ApiService.instance.post(
          ApiConstants.driverOnline,
          data: {
            'mode': _currentMode,
            'lat': position?.latitude ?? 33.8938,
            'lng': position?.longitude ?? 35.5018,
          },
        );
        setState(() => _isOnline = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ApiService.getErrorMessage(e)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    setState(() => _isTogglingStatus = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _buildOrdersTab(),
          _buildEarningsTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ─── HOME TAB ─────────────────────────────────────
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
              // ─── Header ───────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Mission Control',
                    style: AppTextStyles.displayMedium,
                  ),
                  GestureDetector(
                    onTap: () =>
                        context.read<AuthBloc>().add(LogoutRequested()),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.glassWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.glassBorder,
                        ),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: AppColors.error,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ─── Blocked banner ───────────────
              if (isBlocked)
                GlassCard(
                  color: AppColors.error,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 20),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.block_rounded,
                        color: AppColors.error,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Account Paused',
                              style: AppTextStyles.headlineSmall.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                            Text(
                              'Pay \$$debt via OMT or WishMoney\nthen contact admin.',
                              style: AppTextStyles.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // ─── Online toggle ────────────────
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isOnline
                                  ? '🟢 You are Online'
                                  : '⚫ You are Offline',
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
                        // ─── Pulsing orb ──────
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isOnline
                                ? AppColors.accent
                                : AppColors.textHint,
                            boxShadow: _isOnline
                                ? [
                                    BoxShadow(
                                      color: AppColors.accent
                                          .withValues(alpha: 0.4),
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

                    // ─── Mode selector ────────
                    if (!_isOnline)
                      Row(
                        children: ['PACKAGE', 'PEOPLE', 'HYBRID'].map((mode) {
                          final isSelected = _currentMode == mode;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _currentMode = mode),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                          .withValues(alpha: 0.15)
                                      : AppColors.glassWhite,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
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

                    // ─── Go online button ─────
                    AppButton(
                      label: _isOnline
                          ? 'Go Offline'
                          : 'Go Online — $_currentMode',
                      isLoading: _isTogglingStatus,
                      color: _isOnline ? AppColors.error : AppColors.accent,
                      textColor: AppColors.background,
                      onPressed: isBlocked ? null : _toggleOnlineStatus,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ─── Debt card ────────────────────
              GlassCard(
                padding: const EdgeInsets.all(16),
                color: debt > 15 ? AppColors.error : AppColors.primary,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Commission Debt',
                          style: AppTextStyles.bodyMedium,
                        ),
                        Text(
                          '\$$debt / \$20.00',
                          style: AppTextStyles.price,
                        ),
                      ],
                    ),
                    // ─── Debt progress ────────
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

              // ─── Recent orders ────────────────
              Text(
                'Recent Orders',
                style: AppTextStyles.headlineMedium,
              ),
              const SizedBox(height: 16),

              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                )
              else if (_orders.isEmpty)
                Center(
                  child: Column(
                    children: [
                      const Text(
                        '🛵',
                        style: TextStyle(fontSize: 48),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No orders yet',
                        style: AppTextStyles.headlineMedium,
                      ),
                      Text(
                        'Go online to start receiving orders',
                        style: AppTextStyles.bodyMedium,
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _orders.take(5).length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final order = _orders[index];
                    return GlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  order['trackingCode'] ?? '',
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: AppColors.primary,
                                  ),
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
                              StatusBadge(
                                status: order['status'] ?? '',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '\$${order['grandTotal'] ?? 0}',
                                style: AppTextStyles.priceSmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── ORDERS TAB ───────────────────────────────────
  Widget _buildOrdersTab() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Orders',
              style: AppTextStyles.displayMedium,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _orders.isEmpty
                  ? const Center(
                      child: Text('No orders yet',
                          style: AppTextStyles.bodyMedium))
                  : ListView.separated(
                      itemCount: _orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final order = _orders[index];
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
                                    style: AppTextStyles.labelLarge.copyWith(
                                      color: AppColors.primary,
                                    ),
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
                                    'Commission: \$${order['commissionAmount'] ?? 0}',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.error,
                                    ),
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

  // ─── EARNINGS TAB ─────────────────────────────────
  Widget _buildEarningsTab() {
    final debt = (_debtInfo?['currentDebt'] as num?)?.toDouble() ?? 0.0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Earnings',
              style: AppTextStyles.displayMedium,
            ),
            const SizedBox(height: 24),
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Current Debt',
                        style: AppTextStyles.bodyLarge,
                      ),
                      Text(
                        '\$$debt',
                        style: AppTextStyles.price.copyWith(
                          color: debt > 15 ? AppColors.error : AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                  Text(
                    '\$$debt of \$20.00 limit',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.glassBorder),
                  const SizedBox(height: 16),
                  Text(
                    'Pay via OMT or WishMoney,\nthen contact admin to reactivate.',
                    style: AppTextStyles.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Bottom nav ───────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.glassBorder,
            width: 1,
          ),
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
}
