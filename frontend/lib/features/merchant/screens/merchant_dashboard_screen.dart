import 'package:dio/dio.dart' as dio;
import 'package:faster_app/core/constants/app_config.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/location_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/google_places_search_field.dart';
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
  bool _isLoading = true;
  bool _menuVisited = false;
  bool _offersVisited = false;
  bool _scheduleVisited = false;

  // Merchant's own location (auto-detected)
  double? _merchantLat;
  double? _merchantLng;
  String _merchantAddress = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _detectMerchantLocation();
  }

  // ─── Auto-detect merchant location on startup ─────
  Future<void> _detectMerchantLocation() async {
    try {
      final pos = await LocationService.instance.getCurrentPosition();
      if (pos == null || !mounted) return;
      setState(() {
        _merchantLat = pos.latitude;
        _merchantLng = pos.longitude;
      });
      // Reverse geocode
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
              'User-Agent': 'FasterApp/1.0',
            },
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        if (mounted) {
          setState(() =>
              _merchantAddress = r.data?['display_name']?.toString() ?? '');
        }
      } catch (_) {
        if (mounted) {
          setState(
              () => _merchantAddress = '${pos.latitude.toStringAsFixed(4)}, '
                  '${pos.longitude.toStringAsFixed(4)}');
        }
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final ordersRes =
          await ApiService.instance.get(ApiConstants.merchantOrders);
      final data = ordersRes.data;
      if (!mounted) return;
      setState(() {
        _activeOrders =
            data is List ? data : (data as Map?)?['content'] as List? ?? [];
      });
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
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
    final activeCount = _activeOrders
        .where((o) => o['status'] != 'DELIVERED' && o['status'] != 'CANCELLED')
        .length;
    final deliveredCount =
        _activeOrders.where((o) => o['status'] == 'DELIVERED').length;

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Command Center',
                          style: AppTextStyles.displayMedium),
                      Text('Your store at a glance',
                          style: AppTextStyles.bodyMedium),
                    ],
                  ),
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
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: _buildStatCard('Active Orders', '$activeCount',
                      Icons.receipt_long_outlined, AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard('Delivered', '$deliveredCount',
                      Icons.check_circle_outline, AppColors.accent),
                ),
              ]),
              const SizedBox(height: 24),
              Text('Recent Orders', style: AppTextStyles.headlineMedium),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              else if (_activeOrders.isEmpty)
                _buildEmptyState('📦', 'No orders yet',
                    'Tap + New Order to create your first order')
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _activeOrders.take(5).length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _buildOrderCard(_activeOrders[i]),
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
            Row(children: [
              Text('All Orders', style: AppTextStyles.displayMedium),
              const Spacer(),
              GestureDetector(
                onTap: _loadData,
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
            const SizedBox(height: 24),
            Expanded(
              child: _activeOrders.isEmpty
                  ? _buildEmptyState(
                      '📋', 'No orders yet', 'Orders will appear here')
                  : ListView.separated(
                      itemCount: _activeOrders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _buildOrderCard(_activeOrders[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTab() {
    if (!_menuVisited && _currentIndex == 2) {
      _menuVisited = true;
    }
    return _menuVisited
        ? const MerchantCategoriesScreen()
        : const SizedBox.shrink();
  }

  Widget _buildOffersTab() {
    if (!_offersVisited && _currentIndex == 3) {
      _offersVisited = true;
    }
    return _offersVisited
        ? const MerchantOffersScreen()
        : const SizedBox.shrink();
  }

  Widget _buildScheduleTab() {
    if (!_scheduleVisited && _currentIndex == 4) {
      _scheduleVisited = true;
    }
    return _scheduleVisited
        ? const MerchantScheduleScreen()
        : const SizedBox.shrink();
  }

  // ─── ORDER CARD ───────────────────────────────────
  Widget _buildOrderCard(Map<String, dynamic> order) {
    final isO2O = order['offlineCustomerPhone'] != null;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  order['trackingCode'] ?? '',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: AppColors.primary),
                ),
              ),
              Row(children: [
                if (isO2O)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('O2O',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w800,
                        )),
                  ),
                StatusBadge(status: order['status'] ?? ''),
              ]),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.location_on_outlined,
                size: 14, color: AppColors.textHint),
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
            Text('\$${order['grandTotal'] ?? 0}',
                style: AppTextStyles.priceSmall),
          ]),
          if (isO2O) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.phone_outlined,
                  size: 14, color: AppColors.accent),
              const SizedBox(width: 4),
              Text(
                order['offlineCustomerPhone'] ?? '',
                style:
                    AppTextStyles.bodyMedium.copyWith(color: AppColors.accent),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value,
              style: AppTextStyles.displayMedium.copyWith(color: color)),
          const SizedBox(height: 4),
          Text(label, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String emoji, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(title, style: AppTextStyles.headlineMedium),
          const SizedBox(height: 8),
          Text(subtitle,
              style: AppTextStyles.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ─── FAB ──────────────────────────────────────────
  Widget _buildFAB() {
    return FloatingActionButton.extended(
      heroTag: 'merchant_order_fab',
      onPressed: () => _showCreateOrderSheet(context),
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.background,
      icon: const Icon(Icons.add_rounded),
      label: Text('New Order',
          style:
              AppTextStyles.labelLarge.copyWith(color: AppColors.background)),
    );
  }

  // ─────────────────────────────────────────────────
  // PROFESSIONAL ORDER CREATION SHEET
  // ─────────────────────────────────────────────────
  void _showCreateOrderSheet(BuildContext context) {
    // Controllers
    final pickupCtrl = TextEditingController(text: _merchantAddress);
    final deliveryCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final landmarkCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final feeCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    // State
    bool isO2O = false;
    // Delivery mode: 'phone' = lookup customer | 'manual' = type address
    String deliveryMode = 'phone';
    bool isDetectingPickup = false;
    bool isLookingUpPhone = false;
    bool isCreatingOrder = false;
    double? pickupLat = _merchantLat;
    double? pickupLng = _merchantLng;
    Map<String, dynamic>? foundCustomer;
    String? whatsappAvailable; // 'yes' | 'no' | null

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // ─── Detect merchant GPS ─────────────────
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
                      'User-Agent': 'FasterApp/1.0',
                    },
                    receiveTimeout: const Duration(seconds: 5),
                  ),
                );
                final addr = r.data?['display_name']?.toString() ?? '';
                setSheet(() => pickupCtrl.text = addr);
              } catch (_) {
                setSheet(() =>
                    pickupCtrl.text = '${pos.latitude.toStringAsFixed(4)}, '
                        '${pos.longitude.toStringAsFixed(4)}');
              }
            } catch (_) {}
            setSheet(() => isDetectingPickup = false);
          }

          // ─── Lookup customer by phone ────────────
          Future<void> lookupCustomer() async {
            final phone = phoneCtrl.text.trim();
            if (phone.isEmpty) return;
 
            setSheet(() {
              isLookingUpPhone = true;
              foundCustomer = null;
            });
 
            // For O2O orders, the customer is offline (called by phone).
            // They don't need to be registered — just store their phone.
            // Set foundCustomer to a minimal map so the UI shows "ready".
            await Future.delayed(const Duration(milliseconds: 300));
 
            setSheet(() {
              foundCustomer = {'phone': phone, 'fullName': 'Offline Customer'};
              isLookingUpPhone = false;
            });
          }

          // ─── Create the order ────────────────────
          Future<void> createOrder() async {
            final price = double.tryParse(priceCtrl.text.trim());
            final fee = double.tryParse(feeCtrl.text.trim());
            if (price == null || price <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Enter a valid order price'),
                  backgroundColor: AppColors.error,
                ),
              );
              return;
            }

            setSheet(() => isCreatingOrder = true);
            try {
              Map<String, dynamic> body;

              if (isO2O) {
                // O2O order
                final phone = phoneCtrl.text.trim();
                final landmark = landmarkCtrl.text.trim();
                if (phone.isEmpty || landmark.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Phone and delivery address required'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  setSheet(() => isCreatingOrder = false);
                  return;
                }
                body = {
                  'totalPrice': price,
                  'deliveryFee': fee ?? 2.0,
                  'pickupAddress': pickupCtrl.text.trim(),
                  'pickupLat': pickupLat,
                  'pickupLng': pickupLng,
                  'isO2O': true,
                  'offlineCustomerPhone': phone,
                  'offlineLandmark': landmark,
                  'customerNotes': notesCtrl.text.trim(),
                };
              } else {
                // Standard order
                final delivery = deliveryCtrl.text.trim();
                if (delivery.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter delivery address'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  setSheet(() => isCreatingOrder = false);
                  return;
                }
                body = {
                  'totalPrice': price,
                  'deliveryFee': fee ?? 2.0,
                  'pickupAddress': pickupCtrl.text.trim(),
                  'pickupLat': pickupLat,
                  'pickupLng': pickupLng,
                  'deliveryAddress': delivery,
                  'orderType': 'LOGISTICS',
                  'isO2O': false,
                  'customerNotes': notesCtrl.text.trim(),
                };
              }

              await ApiService.instance.post(ApiConstants.orders, data: body);

              if (ctx.mounted) Navigator.pop(ctx);
              await _loadData();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✅ Order created!'
                      '${isO2O ? ' WhatsApp the customer with their tracking link.' : ' Searching for drivers...'}',
                    ),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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
            setSheet(() => isCreatingOrder = false);
          }

          // ─── BUILD SHEET UI ──────────────────────
          return DraggableScrollableSheet(
            initialChildSize: 0.88,
            minChildSize: 0.5,
            maxChildSize: 0.96,
            expand: false,
            builder: (_, scrollCtrl) => Column(
              children: [
                const SizedBox(height: 12),
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
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(children: [
                    Text('Create New Order',
                        style: AppTextStyles.headlineLarge),
                    const Spacer(),
                    // O2O Toggle
                    Row(children: [
                      Text('O2O',
                          style: AppTextStyles.caption.copyWith(
                              color: isO2O
                                  ? AppColors.accent
                                  : AppColors.textHint)),
                      const SizedBox(width: 6),
                      Switch(
                        value: isO2O,
                        onChanged: (v) => setSheet(() {
                          isO2O = v;
                          foundCustomer = null;
                          deliveryCtrl.clear();
                          phoneCtrl.clear();
                          landmarkCtrl.clear();
                        }),
                        activeColor: AppColors.accent,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ]),
                  ]),
                ),
                if (isO2O)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.phone_outlined,
                            size: 14, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Text('Offline Customer Mode',
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollCtrl,
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── PICKUP ADDRESS ────────────────
                        Row(children: [
                          Text('Pickup Address',
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
                                            color: AppColors.primary, size: 14),
                                        const SizedBox(width: 4),
                                        Text('My Location',
                                            style:
                                                AppTextStyles.caption.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w600,
                                            )),
                                      ],
                                    ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        AppInput(
                          controller: pickupCtrl,
                          hint: 'Your store location',
                          label: 'Pickup Address',
                          prefixIcon: Icons.store_outlined,
                          maxLines: 2,
                        ),
                        if (pickupLat != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(children: [
                              const Icon(Icons.gps_fixed_rounded,
                                  color: AppColors.accent, size: 12),
                              const SizedBox(width: 4),
                              Text('GPS coordinates stored for driver',
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.accent)),
                            ]),
                          ),

                        const SizedBox(height: 20),
                        const Divider(color: AppColors.glassBorder),
                        const SizedBox(height: 16),

                        // ── DELIVERY SECTION ──────────────
                        if (!isO2O) ...[
                          Text('Delivery Address',
                              style: AppTextStyles.headlineSmall),
                          const SizedBox(height: 12),

                          // Delivery mode tabs
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.glassWhite,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setSheet(() {
                                    deliveryMode = 'phone';
                                    foundCustomer = null;
                                  }),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    decoration: BoxDecoration(
                                      color: deliveryMode == 'phone'
                                          ? AppColors.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.phone_rounded,
                                            size: 14,
                                            color: deliveryMode == 'phone'
                                                ? AppColors.background
                                                : AppColors.textHint),
                                        const SizedBox(width: 6),
                                        Text(
                                          'By Phone',
                                          style: AppTextStyles.caption.copyWith(
                                            color: deliveryMode == 'phone'
                                                ? AppColors.background
                                                : AppColors.textHint,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () =>
                                      setSheet(() => deliveryMode = 'manual'),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    decoration: BoxDecoration(
                                      color: deliveryMode == 'manual'
                                          ? AppColors.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.edit_location_rounded,
                                            size: 14,
                                            color: deliveryMode == 'manual'
                                                ? AppColors.background
                                                : AppColors.textHint),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Manual',
                                          style: AppTextStyles.caption.copyWith(
                                            color: deliveryMode == 'manual'
                                                ? AppColors.background
                                                : AppColors.textHint,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                          ),

                          const SizedBox(height: 14),

                          // ── BY PHONE ─────────────────
                          if (deliveryMode == 'phone') ...[
                            Row(children: [
                              Expanded(
                                child: AppInput(
                                  controller: phoneCtrl,
                                  hint: '+961 70 000 000',
                                  label: 'Customer Phone',
                                  prefixIcon: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: lookupCustomer,
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: isLookingUpPhone
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              color: AppColors.background,
                                              strokeWidth: 2))
                                      : const Icon(Icons.search_rounded,
                                          color: AppColors.background,
                                          size: 20),
                                ),
                              ),
                            ]),
                            if (foundCustomer != null) ...[
                              const SizedBox(height: 10),
                              foundCustomer!.isEmpty
                                  ? Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: AppColors.warning
                                                .withValues(alpha: 0.3)),
                                      ),
                                      child: Row(children: [
                                        const Icon(Icons.warning_amber_rounded,
                                            color: AppColors.warning, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'No account found — enter delivery address manually below',
                                            style: AppTextStyles.caption
                                                .copyWith(
                                                    color: AppColors.warning),
                                          ),
                                        ),
                                      ]),
                                    )
                                  : Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: AppColors.accent
                                                .withValues(alpha: 0.3)),
                                      ),
                                      child: Row(children: [
                                        const Icon(Icons.check_circle_rounded,
                                            color: AppColors.accent, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                foundCustomer!['fullName'] ??
                                                    'Customer Found',
                                                style: AppTextStyles.labelLarge,
                                              ),
                                              Text(
                                                'Customer account found — they will see the order in their app',
                                                style: AppTextStyles.caption
                                                    .copyWith(
                                                        color:
                                                            AppColors.accent),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ]),
                                    ),
                            ],
                            const SizedBox(height: 10),
                            GooglePlacesSearchField(
                              hint: 'Delivery address (area / landmark)',
                              label: 'Delivery Address',
                              apiKey: AppConfig.googlePlacesKey,
                              controller: deliveryCtrl,
                              maxLines: 2,
                              onPlaceSelected: (result) {
                                setSheet(() {
                                  deliveryCtrl.text = result.address;
                                });
                              },
                            ),
                          ],

                          // ── MANUAL ADDRESS — with map picker ─
                          if (deliveryMode == 'manual') ...[
                            GooglePlacesSearchField(
                              hint: 'Street, building, area...',
                              label: 'Delivery Address',
                              apiKey: AppConfig.googlePlacesKey,
                              controller: deliveryCtrl,
                              maxLines: 2,
                              onPlaceSelected: (result) {
                                setSheet(() {
                                  deliveryCtrl.text = result.address;
                                });
                              },
                            ),
                          ],
                        ],

                        // ── O2O FIELDS ───────────────────
                        if (isO2O) ...[
                          Text('Customer Details',
                              style: AppTextStyles.headlineSmall),
                          const SizedBox(height: 12),

                          AppInput(
                            controller: phoneCtrl,
                            hint: '+961 70 000 000',
                            label: 'Customer Phone (WhatsApp)',
                            prefixIcon: Icons.chat_rounded,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),

                          AppInput(
                            controller: landmarkCtrl,
                            hint: 'Area, street, building, landmark...',
                            label: 'Delivery Location',
                            prefixIcon: Icons.location_on_outlined,
                            maxLines: 2,
                          ),

                          const SizedBox(height: 10),

                          // WhatsApp availability
                          GlassCard(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(Icons.chat_rounded,
                                      color: Color(0xFF25D366), size: 18),
                                  const SizedBox(width: 8),
                                  Text('Does the customer have WhatsApp?',
                                      style: AppTextStyles.headlineSmall),
                                ]),
                                const SizedBox(height: 10),
                                Row(children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setSheet(
                                          () => whatsappAvailable = 'yes'),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: whatsappAvailable == 'yes'
                                              ? const Color(0xFF25D366)
                                                  .withValues(alpha: 0.15)
                                              : AppColors.glassWhite,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: whatsappAvailable == 'yes'
                                                ? const Color(0xFF25D366)
                                                : AppColors.glassBorder,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Text('✅ Yes'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setSheet(
                                          () => whatsappAvailable = 'no'),
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: whatsappAvailable == 'no'
                                              ? AppColors.warning
                                                  .withValues(alpha: 0.15)
                                              : AppColors.glassWhite,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: whatsappAvailable == 'no'
                                                ? AppColors.warning
                                                : AppColors.glassBorder,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Text('❌ No'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ]),

                                // WhatsApp instructions
                                if (whatsappAvailable == 'yes') ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF25D366)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '📲 After creating the order, '
                                      'send the tracking link to '
                                      'the customer on WhatsApp. '
                                      'They can share their live '
                                      'location to the driver.',
                                      style: AppTextStyles.caption.copyWith(
                                          color: const Color(0xFF25D366)),
                                    ),
                                  ),
                                ],

                                // No WhatsApp — manual note
                                if (whatsappAvailable == 'no') ...[
                                  const SizedBox(height: 10),
                                  AppInput(
                                    controller: notesCtrl,
                                    hint:
                                        'Detailed location description for driver...',
                                    label: 'Location Notes for Driver',
                                    prefixIcon: Icons.note_outlined,
                                    maxLines: 3,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),
                        const Divider(color: AppColors.glassBorder),
                        const SizedBox(height: 16),

                        // ── PRICING ──────────────────────
                        Text('Pricing', style: AppTextStyles.headlineSmall),
                        const SizedBox(height: 12),

                        Row(children: [
                          Expanded(
                            child: AppInput(
                              controller: priceCtrl,
                              hint: '0.00',
                              label: 'Order Price \$',
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

                        if (!isO2O || whatsappAvailable == 'yes') ...[
                          const SizedBox(height: 12),
                          AppInput(
                            controller: notesCtrl,
                            hint: 'Any special instructions? (optional)',
                            label: 'Notes',
                            prefixIcon: Icons.note_outlined,
                          ),
                        ],

                        const SizedBox(height: 24),

                        // ── CREATE BUTTON ─────────────────
                        AppButton(
                          label:
                              isO2O ? '📱 Create O2O Order' : '🚀 Create Order',
                          isLoading: isCreatingOrder,
                          color: isO2O
                              ? const Color(0xFF25D366)
                              : AppColors.primary,
                          textColor: AppColors.background,
                          onPressed: createOrder,
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── BOTTOM NAV ───────────────────────────────────
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
