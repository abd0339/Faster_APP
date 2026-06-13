import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import 'merchant_categories_screen.dart';
import 'merchant_offers_screen.dart';
import 'merchant_schedule_screen.dart';

class MerchantDashboardScreen extends StatefulWidget {
  const MerchantDashboardScreen({super.key});

  @override
  State<MerchantDashboardScreen> createState() =>
      _MerchantDashboardScreenState();
}

class _MerchantDashboardScreenState extends State<MerchantDashboardScreen> {
  int _currentIndex = 0;
  List<dynamic> _activeOrders = [];
  Map<String, dynamic>? _storeStatus;
  bool _isLoading = true;
  bool _menuVisited = false;
  bool _offersVisited = false;
  bool _scheduleVisited = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final ordersRes =
          await ApiService.instance.get(ApiConstants.merchantOrders);
      final data = ordersRes.data;
      setState(() {
        _activeOrders =
            data is List ? data : (data as Map?)?['content'] as List? ?? [];
      });
    } catch (_) {}
    setState(() => _isLoading = false);
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
          _buildMenuTab(),
          _buildOffersTab(),
          _buildScheduleTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _currentIndex == 0 ? _buildFAB() : null,
    );
  }

  // ─── HOME TAB ─────────────────────────────────────
  Widget _buildHomeTab() {
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Command Center',
                        style: AppTextStyles.displayMedium,
                      ),
                      Text(
                        'Your store at a glance',
                        style: AppTextStyles.bodyMedium,
                      ),
                    ],
                  ),
                  // ─── Logout ─────────────────
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

              // ─── Stats row ────────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Active Orders',
                      _activeOrders
                          .where((o) =>
                              o['status'] != 'DELIVERED' &&
                              o['status'] != 'CANCELLED')
                          .length
                          .toString(),
                      Icons.receipt_long_outlined,
                      AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Delivered',
                      _activeOrders
                          .where((o) => o['status'] == 'DELIVERED')
                          .length
                          .toString(),
                      Icons.check_circle_outline,
                      AppColors.accent,
                    ),
                  ),
                ],
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
              else if (_activeOrders.isEmpty)
                _buildEmptyState(
                  '📦',
                  'No orders yet',
                  'Create your first order using\nthe + button below',
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _activeOrders.take(5).length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final order = _activeOrders[index];
                    return _buildOrderCard(order);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleTab() {
    if (!_scheduleVisited && _currentIndex == 4) {
      _scheduleVisited = true;
    }
    return _scheduleVisited
        ? const MerchantScheduleScreen()
        : const SizedBox.shrink();
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
              'All Orders',
              style: AppTextStyles.displayMedium,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _activeOrders.isEmpty
                  ? _buildEmptyState(
                      '📋',
                      'No orders yet',
                      'Orders will appear here',
                    )
                  : ListView.separated(
                      itemCount: _activeOrders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _buildOrderCard(_activeOrders[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── MENU TAB ─────────────────────────────────────
  Widget _buildMenuTab() {
    if (!_menuVisited && _currentIndex == 2) {
      _menuVisited = true;
    }
    return _menuVisited
        ? const MerchantCategoriesScreen()
        : const SizedBox.shrink();
  }

  // ─── OFFERS TAB (placeholder) ─────────────────────
  Widget _buildOffersTab() {
    if (!_offersVisited && _currentIndex == 3) {
      _offersVisited = true;
    }
    return _offersVisited
        ? const MerchantOffersScreen()
        : const SizedBox.shrink();
  }

  // ─── Order card ───────────────────────────────────
  Widget _buildOrderCard(Map<String, dynamic> order) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                order['trackingCode'] ?? '',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
              StatusBadge(
                status: order['status'] ?? '',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 14,
                color: AppColors.textHint,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  order['deliveryAddress'] ??
                      order['offlineCustomerLandmark'] ??
                      'No address',
                  style: AppTextStyles.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '\$${order['grandTotal'] ?? 0}',
                style: AppTextStyles.priceSmall,
              ),
            ],
          ),
          if (order['offlineCustomerPhone'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.phone_outlined,
                    size: 14,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    order['offlineCustomerPhone'],
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'O2O',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ─── Stat card ────────────────────────────────────
  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: AppTextStyles.displayMedium.copyWith(color: color),
          ),
          const SizedBox(height: 4),
          Text(label, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────
  Widget _buildEmptyState(
    String emoji,
    String title,
    String subtitle,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 48),
          ),
          const SizedBox(height: 16),
          Text(title, style: AppTextStyles.headlineMedium),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ─── FAB — Create Order ───────────────────────────
  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: () => _showCreateOrderDialog(context),
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.background,
      icon: const Icon(Icons.add_rounded),
      label: Text(
        'New Order',
        style: AppTextStyles.labelLarge.copyWith(
          color: AppColors.background,
        ),
      ),
    );
  }

  // ─── Create Order Dialog ──────────────────────────
  void _showCreateOrderDialog(BuildContext context) {
    final priceController = TextEditingController();
    final feeController = TextEditingController();
    final pickupController = TextEditingController();
    final deliveryController = TextEditingController();
    final phoneController = TextEditingController();
    final landmarkController = TextEditingController();
    bool isO2O = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Handle ───────────────────
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.glassBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Create New Order',
                  style: AppTextStyles.headlineLarge,
                ),
                const SizedBox(height: 20),

                // ─── O2O toggle ───────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Offline Customer (O2O)',
                          style: AppTextStyles.labelLarge,
                        ),
                        Text(
                          'Customer called by phone',
                          style: AppTextStyles.bodyMedium,
                        ),
                      ],
                    ),
                    Switch(
                      value: isO2O,
                      onChanged: (v) => setModalState(() => isO2O = v),
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ─── O2O fields ───────────────
                if (isO2O) ...[
                  TextField(
                    controller: phoneController,
                    style: AppTextStyles.bodyLarge,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: 'Customer phone',
                      prefixIcon: Icon(
                        Icons.phone_outlined,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: landmarkController,
                    style: AppTextStyles.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: 'Delivery landmark',
                      prefixIcon: Icon(
                        Icons.location_on_outlined,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: pickupController,
                    style: AppTextStyles.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: 'Pickup address',
                      prefixIcon: Icon(
                        Icons.store_outlined,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: deliveryController,
                    style: AppTextStyles.bodyLarge,
                    decoration: const InputDecoration(
                      hintText: 'Delivery address',
                      prefixIcon: Icon(
                        Icons.location_on_outlined,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: priceController,
                        style: AppTextStyles.bodyLarge,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Order price \$',
                          prefixIcon: Icon(
                            Icons.attach_money,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: feeController,
                        style: AppTextStyles.bodyLarge,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: 'Delivery fee \$',
                          prefixIcon: Icon(
                            Icons.delivery_dining,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ─── Submit ───────────────────
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        final body = isO2O
                            ? {
                                'totalPrice':
                                    double.tryParse(priceController.text) ?? 0,
                                'deliveryFee':
                                    double.tryParse(feeController.text) ?? 0,
                                'isO2O': true,
                                'offlineCustomerPhone': phoneController.text,
                                'offlineLandmark': landmarkController.text,
                              }
                            : {
                                'totalPrice':
                                    double.tryParse(priceController.text) ?? 0,
                                'deliveryFee':
                                    double.tryParse(feeController.text) ?? 0,
                                'pickupAddress': pickupController.text,
                                'deliveryAddress': deliveryController.text,
                                'orderType': 'LOGISTICS',
                                'isO2O': false,
                              };

                        await ApiService.instance
                            .post(ApiConstants.orders, data: body);

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          _loadData();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                  '✅ Order created! Searching for drivers...'),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(ApiService.getErrorMessage(e)),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      isO2O ? '📱 Create O2O Order' : '🚀 Create Order',
                      style: AppTextStyles.button,
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

  // ─── Bottom Nav ───────────────────────────────────
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
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu_outlined),
            activeIcon: Icon(Icons.restaurant_menu),
            label: 'Menu',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_offer_outlined),
            activeIcon: Icon(Icons.local_offer),
            label: 'Offers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.schedule_outlined),
            activeIcon: Icon(Icons.schedule),
            label: 'Hours',
          ),
        ],
      ),
    );
  }
}
