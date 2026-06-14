import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import 'customer_stores_screen.dart';
import 'customer_order_tracking_screen.dart';

class CustomerDashboardScreen extends StatefulWidget {
  const CustomerDashboardScreen({super.key});

  @override
  State<CustomerDashboardScreen> createState() =>
      _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> {
  int _currentIndex = 0;
  List<dynamic> _myOrders = [];
  bool _ordersLoading = false;
  bool _ordersVisited = false;

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final name = authState is AuthSuccess ? authState.fullName : '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(name),
          _buildBrowseTab(),
          _buildOrdersTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ═══════════════════════════════════════════════
  // TAB 1 — HOME
  // ═══════════════════════════════════════════════
  Widget _buildHomeTab(String name) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hello, ${name.split(' ').first}!',
                        style: AppTextStyles.displayMedium),
                    Text('What are you craving today?',
                        style: AppTextStyles.bodyMedium),
                  ],
                ),
                GestureDetector(
                  onTap: () => context.read<AuthBloc>().add(LogoutRequested()),
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

            const SizedBox(height: 28),

            // Quick action cards
            Row(children: [
              Expanded(
                child: _quickAction(
                  icon: Icons.store_rounded,
                  label: 'Browse\nStores',
                  color: AppColors.primary,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _quickAction(
                  icon: Icons.receipt_long_rounded,
                  label: 'My\nOrders',
                  color: AppColors.accent,
                  onTap: () => setState(() => _currentIndex = 2),
                ),
              ),
            ]),

            const SizedBox(height: 28),

            // Info card
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.info_outline,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text('How it works', style: AppTextStyles.headlineSmall),
                  ]),
                  const SizedBox(height: 16),
                  _howItWorksRow('1', 'Browse stores and add items to cart',
                      AppColors.primary),
                  _howItWorksRow('2', 'Place your order with delivery address',
                      AppColors.accent),
                  _howItWorksRow('3', 'Driver picks up and delivers to you',
                      AppColors.warning),
                  _howItWorksRow(
                      '4', 'Pay cash on delivery', AppColors.customerColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 10),
          Text(label,
              style: AppTextStyles.labelLarge, textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _howItWorksRow(String num, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(num,
                  style: AppTextStyles.caption
                      .copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTextStyles.bodyMedium)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // TAB 2 — BROWSE
  // ═══════════════════════════════════════════════
  Widget _buildBrowseTab() {
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(children: [
            Text('Stores', style: AppTextStyles.displayMedium),
          ]),
        ),
        const Expanded(child: CustomerStoresScreen()),
      ]),
    );
  }

  // ═══════════════════════════════════════════════
  // TAB 3 — MY ORDERS
  // ═══════════════════════════════════════════════
  Widget _buildOrdersTab() {
    // Lazy load
    if (!_ordersVisited && _currentIndex == 2) {
      _ordersVisited = true;
      _loadOrders();
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(children: [
              Text('My Orders', style: AppTextStyles.displayMedium),
              const Spacer(),
              GestureDetector(
                onTap: _loadOrders,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.glassWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      color: AppColors.textPrimary, size: 20),
                ),
              ),
            ]),
          ),
          Expanded(
            child: _ordersLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : _myOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.receipt_long_outlined,
                                color: AppColors.textHint, size: 56),
                            const SizedBox(height: 16),
                            Text('No orders yet',
                                style: AppTextStyles.headlineMedium),
                            const SizedBox(height: 8),
                            Text(
                              'Browse stores and place\nyour first order',
                              style: AppTextStyles.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadOrders,
                        color: AppColors.primary,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          itemCount: _myOrders.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) =>
                              _orderCard(_myOrders[i] as Map<String, dynamic>),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    setState(() => _ordersLoading = true);
    try {
      final res = await ApiService.instance.get('/api/orders/customer');
      if (!mounted) return;
      final d = res.data;
      setState(() =>
          _myOrders = d is List ? d : (d as Map?)?['content'] as List? ?? []);
    } catch (_) {}
    if (mounted) setState(() => _ordersLoading = false);
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final orderId = order['id'] as int;
    final tracking = order['trackingCode'] as String? ?? '';
    final status = order['status'] as String? ?? '';
    final total = order['grandTotal'] ?? 0;
    final address = order['deliveryAddress'] ?? '';
    final isActive = status != 'DELIVERED' && status != 'CANCELLED';

    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerOrderTrackingScreen(
            orderId: orderId,
            trackingCode: tracking,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(tracking,
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.primary)),
            const Spacer(),
            StatusBadge(status: status),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.location_on_outlined,
                size: 13, color: AppColors.textHint),
            const SizedBox(width: 4),
            Expanded(
              child: Text(address.toString(),
                  style: AppTextStyles.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Text('\$$total', style: AppTextStyles.priceSmall),
          ]),
          if (isActive) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.touch_app_outlined,
                  size: 13, color: AppColors.primary),
              const SizedBox(width: 4),
              Text('Tap to track live',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.primary)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
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
            icon: Icon(Icons.store_outlined),
            activeIcon: Icon(Icons.store),
            label: 'Stores',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
        ],
      ),
    );
  }
}
