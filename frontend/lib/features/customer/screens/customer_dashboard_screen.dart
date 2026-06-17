import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/location_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/google_places_search_field.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import 'customer_stores_screen.dart';
import 'customer_order_tracking_screen.dart';
import 'customer_ride_screen.dart';
import 'package:dio/dio.dart' as dio;

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
      // + New Order FAB (only on home tab)
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              heroTag: 'customer_order_fab',
              onPressed: () => _showNewOrderSheet(context),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              icon: const Icon(Icons.add_rounded),
              label: Text('New Order',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: AppColors.background)),
            )
          : null,
    );
  }

  // ═══════════════════════════════════════════════
  // + NEW ORDER SHEET — 2 types
  // ═══════════════════════════════════════════════
  void _showNewOrderSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Text('New Order', style: AppTextStyles.headlineLarge),
            const SizedBox(height: 6),
            Text('Choose how you want to order',
                style: AppTextStyles.bodyMedium),
            const SizedBox(height: 24),

            // Option 1 — Order from store (LOGISTICS)
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _currentIndex = 1); // Go to Stores tab
              },
              child: GlassCard(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.store_rounded,
                        color: AppColors.primary, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order from Store',
                            style: AppTextStyles.headlineSmall),
                        Text('Browse stores, pick items, add to cart',
                            style: AppTextStyles.bodyMedium),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textHint),
                ]),
              ),
            ),

            const SizedBox(height: 12),

            // Option 2 — Direct delivery order (without browsing)
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _showDirectOrderSheet(context);
              },
              child: GlassCard(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.delivery_dining_rounded,
                        color: AppColors.accent, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Direct Delivery Order',
                            style: AppTextStyles.headlineSmall),
                        Text('Send anything from any location',
                            style: AppTextStyles.bodyMedium),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textHint),
                ]),
              ),
            ),

            const SizedBox(height: 12),

            // Option 3 — Request a ride
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomerRideScreen()),
                );
              },
              child: GlassCard(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.driverColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.directions_car_rounded,
                        color: AppColors.driverColor, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Request a Ride',
                            style: AppTextStyles.headlineSmall),
                        Text('Moto, Car, or Toktok — Moto \$2.50',
                            style: AppTextStyles.bodyMedium),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textHint),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // DIRECT DELIVERY ORDER SHEET
  // Customer sends a package from A to B without browsing stores
  // ═══════════════════════════════════════════════
  void _showDirectOrderSheet(BuildContext context) {
    final pickupCtrl = TextEditingController();
    final deliveryCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final feeCtrl = TextEditingController(text: '2.00');

    bool isDetectingPickup = false;
    bool isCreatingOrder = false;
    double? pickupLat, pickupLng, deliveryLat, deliveryLng;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // Auto-detect pickup GPS
          Future<void> detectPickup() async {
            setSheet(() => isDetectingPickup = true);
            try {
              final pos = await LocationService.instance.getCurrentPosition();
              if (pos == null) return;
              pickupLat = pos.latitude;
              pickupLng = pos.longitude;
              try {
                final r = await dio.Dio().get(
                  'https://nominatim.openstreetmap.org/reverse',
                  queryParameters: {
                    'format': 'json',
                    'lat': pos.latitude.toString(),
                    'lon': pos.longitude.toString(),
                  },
                  options: dio.Options(
                    headers: {
                      'Accept-Language': 'en',
                      'User-Agent': 'FasterApp/1.0'
                    },
                    receiveTimeout: const Duration(seconds: 5),
                  ),
                );
                setSheet(() => pickupCtrl.text =
                    r.data?['display_name']?.toString() ?? '');
              } catch (_) {
                setSheet(() => pickupCtrl.text =
                    '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}');
              }
            } catch (_) {}
            setSheet(() => isDetectingPickup = false);
          }

          // Place the order
          Future<void> placeOrder() async {
            if (pickupCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Set pickup location'),
                  backgroundColor: AppColors.error));
              return;
            }
            if (deliveryCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Set delivery address'),
                  backgroundColor: AppColors.error));
              return;
            }
            final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
            final fee = double.tryParse(feeCtrl.text.trim()) ?? 2.0;

            setSheet(() => isCreatingOrder = true);
            try {
              final res = await ApiService.instance.post(
                ApiConstants.orders,
                data: {
                  'totalPrice': price,
                  'deliveryFee': fee,
                  'pickupAddress': pickupCtrl.text.trim(),
                  'pickupLat': pickupLat,
                  'pickupLng': pickupLng,
                  'deliveryAddress': deliveryCtrl.text.trim(),
                  'deliveryLat': deliveryLat,
                  'deliveryLng': deliveryLng,
                  'customerNotes': notesCtrl.text.trim(),
                  'orderType': 'LOGISTICS',
                  'isO2O': false,
                },
              );
              final orderData = res.data as Map<String, dynamic>;
              final orderId = orderData['id'] as int?;
              final tracking = orderData['trackingCode'] as String? ?? '';
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomerOrderTrackingScreen(
                        orderId: orderId ?? 0, trackingCode: tracking),
                  ),
                );
              }
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(ApiService.getErrorMessage(e)),
                    backgroundColor: AppColors.error));
              }
            }
            setSheet(() => isCreatingOrder = false);
          }

          return DraggableScrollableSheet(
            initialChildSize: 0.88,
            minChildSize: 0.5,
            maxChildSize: 0.96,
            expand: false,
            builder: (_, scrollCtrl) => Column(children: [
              const SizedBox(height: 12),
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.glassBorder,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child:
                    Text('Direct Delivery', style: AppTextStyles.headlineLarge),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 32),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── PICKUP — GPS button only, no map ────
                        Row(children: [
                          Text('Pickup Location',
                              style: AppTextStyles.headlineSmall),
                          const Spacer(),
                          GestureDetector(
                            onTap: detectPickup,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3)),
                              ),
                              child: isDetectingPickup
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          color: AppColors.primary,
                                          strokeWidth: 2))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                          const Icon(Icons.my_location_rounded,
                                              color: AppColors.primary,
                                              size: 14),
                                          const SizedBox(width: 4),
                                          Text('My GPS',
                                              style: AppTextStyles.caption
                                                  .copyWith(
                                                      color: AppColors.primary,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                        ]),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        AppInput(
                          controller: pickupCtrl,
                          hint: 'Tap GPS or type pickup location',
                          label: 'Pickup',
                          prefixIcon: Icons.radio_button_checked_rounded,
                          maxLines: 2,
                        ),
                        if (pickupLat != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(children: [
                              const Icon(Icons.gps_fixed_rounded,
                                  color: AppColors.accent, size: 12),
                              const SizedBox(width: 4),
                              Text('GPS set',
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.accent)),
                            ]),
                          ),

                        const SizedBox(height: 20),

                        // ── DELIVERY — with map picker button ────
                        Text('Delivery Address',
                            style: AppTextStyles.headlineSmall),
                        const SizedBox(height: 8),
                        GooglePlacesSearchField(
                          hint: 'Where to deliver?',
                          label: 'Delivery Address',
                          apiKey: AppConfig.googlePlacesKey,
                          controller: deliveryCtrl,
                          maxLines: 2,
                          onPlaceSelected: (result) {
                            setSheet(() {
                              deliveryCtrl.text = result.address;
                              deliveryLat = result.lat;
                              deliveryLng = result.lng;
                            });
                          },
                        ),

                        const SizedBox(height: 20),

                        // ── PRICING ──────────────────────────────
                        Text('Order Details',
                            style: AppTextStyles.headlineSmall),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: AppInput(
                              controller: priceCtrl,
                              hint: '0.00',
                              label: 'Item Value \$',
                              prefixIcon: Icons.attach_money_rounded,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppInput(
                              controller: feeCtrl,
                              hint: '2.00',
                              label: 'Delivery Fee \$',
                              prefixIcon: Icons.delivery_dining_outlined,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        AppInput(
                          controller: notesCtrl,
                          hint: 'Any notes for the driver? (optional)',
                          label: 'Notes',
                          prefixIcon: Icons.note_outlined,
                        ),

                        const SizedBox(height: 8),
                        GlassCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            const Icon(Icons.payments_outlined,
                                color: AppColors.warning, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Cash on delivery. Driver collects from recipient.',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.warning),
                              ),
                            ),
                          ]),
                        ),

                        const SizedBox(height: 24),
                        AppButton(
                          label: '🚀 Place Order',
                          isLoading: isCreatingOrder,
                          color: AppColors.accent,
                          textColor: AppColors.background,
                          onPressed: placeOrder,
                        ),
                        const SizedBox(height: 32),
                      ]),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // TAB 1 — HOME
  // ═══════════════════════════════════════════════
  Widget _buildHomeTab(String name) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hello, ${name.split(' ').first}!',
                    style: AppTextStyles.displayMedium),
                Text('What do you need today?',
                    style: AppTextStyles.bodyMedium),
              ]),
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
            ]),

            const SizedBox(height: 28),

            // Quick actions grid
            Row(children: [
              Expanded(
                  child: _quickAction(
                icon: Icons.store_rounded,
                label: 'Browse\nStores',
                color: AppColors.primary,
                onTap: () => setState(() => _currentIndex = 1),
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: _quickAction(
                icon: Icons.receipt_long_rounded,
                label: 'My\nOrders',
                color: AppColors.accent,
                onTap: () => setState(() => _currentIndex = 2),
              )),
            ]),

            const SizedBox(height: 12),

            // Ride card
            GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CustomerRideScreen())),
              child: GlassCard(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.driverColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.directions_car_rounded,
                        color: AppColors.driverColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Request a Ride',
                              style: AppTextStyles.headlineSmall),
                          Text('Moto \$2.50 · Car \$5.00 · Toktok \$3.00',
                              style: AppTextStyles.bodyMedium),
                        ]),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textHint),
                ]),
              ),
            ),

            const SizedBox(height: 28),

            // How it works
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
                    _howItWorksRow('1', 'Tap + New Order or browse stores',
                        AppColors.primary),
                    _howItWorksRow('2', 'Add items or set delivery details',
                        AppColors.accent),
                    _howItWorksRow(
                        '3', 'Driver picks up and delivers', AppColors.warning),
                    _howItWorksRow(
                        '4', 'Pay cash on delivery', AppColors.customerColor),
                  ]),
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
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      ]),
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
          child: Text('Stores', style: AppTextStyles.displayMedium),
        ),
        const Expanded(child: CustomerStoresScreen()),
      ]),
    );
  }

  // ═══════════════════════════════════════════════
  // TAB 3 — MY ORDERS
  // ═══════════════════════════════════════════════
  Widget _buildOrdersTab() {
    if (!_ordersVisited && _currentIndex == 2) {
      _ordersVisited = true;
      _loadOrders();
    }

    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                            Text('Tap + New Order to get started',
                                style: AppTextStyles.bodyMedium,
                                textAlign: TextAlign.center),
                          ]),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadOrders,
                      color: AppColors.primary,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        itemCount: _myOrders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) =>
                            _orderCard(_myOrders[i] as Map<String, dynamic>),
                      ),
                    ),
        ),
      ]),
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
    final isMobility = order['orderType'] == 'MOBILITY';

    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerOrderTrackingScreen(
              orderId: orderId, trackingCode: tracking),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (isMobility)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.driverColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('RIDE',
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.driverColor,
                      fontWeight: FontWeight.w800)),
            ),
          Text(tracking,
              style:
                  AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
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
      ]),
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
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.store_outlined),
              activeIcon: Icon(Icons.store),
              label: 'Stores'),
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long),
              label: 'Orders'),
        ],
      ),
    );
  }
}
