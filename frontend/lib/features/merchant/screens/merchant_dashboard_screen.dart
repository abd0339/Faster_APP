import 'package:animate_do/animate_do.dart';
import 'package:dio/dio.dart' as dio;
import 'package:latlong2/latlong.dart' hide DistanceCalculator;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_motion.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/exchange_rate_service.dart';
import '../../../core/utils/currency_converter.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../core/constants/business_rules.dart';
import '../../../core/utils/distance_calculator.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/app_skeleton_card.dart';
import '../../../shared/widgets/phone_input_field.dart';
import '../../../shared/widgets/google_places_search_field.dart';
import '../../../shared/widgets/map_picker_screen.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/notification_bell_button.dart';
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
  bool _loadFailed = false;
  bool _menuVisited = false;
  bool _offersVisited = false;
  bool _scheduleVisited = false;

  // Merchant's own location (auto-detected)
  double? _merchantLat;
  double? _merchantLng;
  String _merchantAddress = '';

  // Number of skeleton rows shown while the recent-orders list is loading —
  // a typical phone screen's worth, independent of how many orders will
  // actually come back.
  static const int _recentOrdersSkeletonCount = 4;

  // Only the first few visible order cards get a staggered entrance
  // animation; a long list beyond that would just mean a long wait for
  // the last items to appear.
  static const int _maxAnimatedOrderCards = 5;

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
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final ordersRes =
          await ApiService.instance.get(ApiConstants.merchantOrders);
      final data = ordersRes.data;
      if (!mounted) return;
      setState(() {
        _activeOrders =
            data is List ? data : (data as Map?)?['content'] as List? ?? [];
      });
    } catch (_) {
      // Recorded rather than rethrown: an empty list after a failed load
      // shows AppErrorState with a retry instead of "No orders yet".
      _loadFailed = true;
    }
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
                  Row(children: [
                    const NotificationBellButton(),
                    const SizedBox(width: 8),
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
                  ]),
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
              // Skeletons only on a first load; a refresh (e.g. after
              // creating an order) updates the existing list in place.
              if (_isLoading && _activeOrders.isEmpty)
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentOrdersSkeletonCount,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, __) => const AppSkeletonCard(),
                )
              else if (_activeOrders.isEmpty && _loadFailed)
                AppErrorState(
                  message: "Couldn't load orders",
                  onRetry: _loadData,
                )
              else if (_activeOrders.isEmpty)
                const AppEmptyState(
                  icon: Icons.storefront_outlined,
                  message: 'No orders yet',
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _activeOrders.take(5).length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) =>
                      _buildRecentOrderItem(context, i),
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
                  ? (_loadFailed
                      ? AppErrorState(
                          message: "Couldn't load orders",
                          onRetry: _loadData,
                        )
                      : _buildEmptyState(Icons.receipt_long_rounded,
                          'No orders yet', 'Orders will appear here'))
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

  // Wraps the first few recent-order cards in a staggered fade/slide
  // entrance, skipped entirely under the platform's reduced-motion setting.
  Widget _buildRecentOrderItem(BuildContext context, int index) {
    final card = _buildOrderCard(_activeOrders[index]);
    if (index >= _maxAnimatedOrderCards || AppMotion.reduceMotion(context)) {
      return card;
    }
    return FadeInUp(
      duration: AppMotion.listEntranceDuration,
      delay: Duration(
          milliseconds: index * AppMotion.listStaggerDelay.inMilliseconds),
      child: card,
    );
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

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textHint),
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
    // Full E.164 composed by PhoneInputField — the dial code is
    // selected, never typed, so this is always well-formed.
    String phoneE164 = '';
    final landmarkCtrl = TextEditingController();
    // NEW — captured when merchant picks the destination on
    // the map instead of only typing a text landmark. Sent as
    // deliveryLat/deliveryLng so the backend can compute a
    // real distance-based delivery fee for this O2O order
    // instead of always falling back to the minimum fee.
    double? o2oDeliveryLat;
    double? o2oDeliveryLng;
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
    // NEW — which currency the merchant is typing the price in.
    // The backend only ever sees USD: when this is 'LBP', the typed
    // amount is converted via CurrencyConverter.lbpToUsd right
    // before the order is submitted.
    String priceCurrency = 'USD';
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
            final phone = phoneE164;
            if (phone.isEmpty) return;
            setSheet(() {
              isLookingUpPhone = true;
              foundCustomer = null;
            });
            try {
              final res = await ApiService.instance.get(
                ApiConstants.customerLookup(phone),
              );
              final data = res.data as Map<String, dynamic>;
              setSheet(() => foundCustomer = data);
            } catch (_) {
              // Phone not found is okay — O2O works with unregistered numbers
              setSheet(() => foundCustomer = {
                    'found': false,
                    'phone': phone,
                  });
            }
            setSheet(() => isLookingUpPhone = false);
          }

          // ─── Create the order ────────────────────
          Future<void> createOrder() async {
            final price = double.tryParse(priceCtrl.text.trim());
            final fee = double.tryParse(feeCtrl.text.trim());
            if (price == null || price <= 0) {
              AppToast.error(context, 'Enter a valid order price');
              return;
            }

            // Resolves the typed price (in whichever currency is
            // selected) to the USD amount the backend expects.
            // Converts via the live exchange rate when the merchant
            // typed in LBP, then rejects an amount that rounds away
            // to (near) nothing after conversion — closing the same
            // "silent $0 order" gap this task fixed for raw input,
            // just reachable through a tiny LBP entry instead of
            // garbage input. Deliberately called AFTER the
            // isO2O/manual-address validation below (not before) so
            // a merchant who also left phone/landmark blank sees
            // that error immediately instead of waiting on a
            // network round-trip first.
            Future<double?> resolveTotalPriceUsd() async {
              double totalPrice = price;
              if (priceCurrency == 'LBP') {
                final rate = await ExchangeRateService.instance.getCurrentRate();
                totalPrice = CurrencyConverter.lbpToUsd(price, rate);
              }
              if (totalPrice < 0.01) {
                // context may be stale after the (possible) await above —
                // guard the same way the catch block below already does.
                if (context.mounted) {
                  AppToast.error(context,
                      'Converted price is too small — enter a larger amount');
                }
                return null;
              }
              return totalPrice;
            }

            // Client-side, UX-only pre-check: warns before the network
            // call when pickup/delivery are farther apart than the
            // backend will allow. Mirrors
            // PricingService.exceedsMaxDeliveryDistance — if the two
            // ever drift, the backend's check (Tasks 5/6) still wins;
            // this only decides how early the merchant finds out.
            // Coordinates are missing whenever the merchant hasn't
            // picked a map location for delivery yet (o2oDeliveryLat/
            // Lng stay null) — skipped rather than blocked, same
            // null-safety philosophy as the backend.
            bool isWithinMaxDistance() {
              if (pickupLat == null ||
                  pickupLng == null ||
                  o2oDeliveryLat == null ||
                  o2oDeliveryLng == null) {
                return true;
              }
              final distanceKm = DistanceCalculator.kilometersBetween(
                  pickupLat!, pickupLng!, o2oDeliveryLat!, o2oDeliveryLng!);
              return distanceKm <= kMaxDeliveryDistanceKm;
            }

            setSheet(() => isCreatingOrder = true);
            try {
              Map<String, dynamic> body;

              if (isO2O) {
                // O2O order
                final phone = phoneE164;
                final landmark = landmarkCtrl.text.trim();
                if (phone.isEmpty || landmark.isEmpty) {
                  AppToast.error(context, 'Phone and delivery address required');
                  setSheet(() => isCreatingOrder = false);
                  return;
                }
                if (!isWithinMaxDistance()) {
                  AppToast.error(
                    context,
                    'Delivery address is too far from pickup (over ${kMaxDeliveryDistanceKm.toStringAsFixed(0)}km)',
                  );
                  setSheet(() => isCreatingOrder = false);
                  return;
                }
                final totalPrice = await resolveTotalPriceUsd();
                if (totalPrice == null) {
                  setSheet(() => isCreatingOrder = false);
                  return;
                }
                body = {
                  'totalPrice': totalPrice,
                  'pickupAddress': pickupCtrl.text.trim(),
                  'pickupLat': pickupLat,
                  'pickupLng': pickupLng,
                  'isO2O': true,
                  'offlineCustomerPhone': phone,
                  'offlineLandmark': landmark,
                  // Delivery fee is NEVER sent from the client —
                  // the backend always computes it from real
                  // distance via PricingService. Sending lat/lng
                  // (when the merchant picked an exact map location)
                  // lets that calculation be accurate immediately
                  // instead of falling back to the minimum fee.
                  'deliveryLat': o2oDeliveryLat,
                  'deliveryLng': o2oDeliveryLng,
                  'customerNotes': notesCtrl.text.trim(),
                };
              } else {
                // Standard order (merchant types the address manually)
                final delivery = deliveryCtrl.text.trim();
                final manualPhone = phoneE164;

                // FIX: this branch used to send no merchantId, so the
                // backend saved the order with merchant=null and the
                // merchant recorded as the CUSTOMER — it then vanished
                // from the merchant's own order list (which filters by
                // merchant_id). It now routes through the O2O path,
                // where the merchant is correctly recorded as the
                // merchant.
                //
                // That path sends the customer a tracking-link SMS, so
                // a phone number is now genuinely required here. It was
                // optional before, which produced Twilio error 21211
                // ("The 'To' number is not a valid phone number") on an
                // empty string.
                if (delivery.isEmpty || manualPhone.isEmpty) {
                  AppToast.error(
                      context, 'Customer phone and delivery address required');
                  setSheet(() => isCreatingOrder = false);
                  return;
                }
                if (!isWithinMaxDistance()) {
                  AppToast.error(
                    context,
                    'Delivery address is too far from pickup (over ${kMaxDeliveryDistanceKm.toStringAsFixed(0)}km)',
                  );
                  setSheet(() => isCreatingOrder = false);
                  return;
                }
                final totalPrice = await resolveTotalPriceUsd();
                if (totalPrice == null) {
                  setSheet(() => isCreatingOrder = false);
                  return;
                }
                body = {
                  'totalPrice': totalPrice,
                  // deliveryFee deliberately NOT sent — the backend
                  // always computes it from real distance (C2 rule).
                  'pickupAddress': pickupCtrl.text.trim(),
                  'pickupLat': pickupLat,
                  'pickupLng': pickupLng,
                  'offlineLandmark': delivery,
                  'deliveryLat': o2oDeliveryLat,
                  'deliveryLng': o2oDeliveryLng,
                  'orderType': 'LOGISTICS',
                  'isO2O': true,
                  'offlineCustomerPhone': manualPhone,
                  'customerNotes': notesCtrl.text.trim(),
                };
              }

              await ApiService.instance.post(ApiConstants.orders, data: body);

              if (ctx.mounted) Navigator.pop(ctx);
              await _loadData();

              if (mounted) {
                AppToast.success(
                  context,
                  'Order created!'
                  '${isO2O ? ' WhatsApp the customer with their tracking link.' : ' Searching for drivers...'}',
                );
              }
            } catch (e) {
              if (ctx.mounted) {
                AppToast.error(ctx, ApiService.getErrorMessage(e));
              }
            }
            // FIX (crash): the sheet is popped above, so by the time
            // this runs the StatefulBuilder is disposed and calling
            // setSheet threw "setState() called after dispose()".
            if (ctx.mounted) {
              setSheet(() => isCreatingOrder = false);
            }
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
                                child: PhoneInputField(
                                  label: 'Customer Phone',
                                  onChanged: (e164) => phoneE164 = e164,
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
                              // FIX (review 2026-11-01): the backend
                              // never errors for "not registered" —
                              // it returns 200 {"found": false, ...},
                              // which lands in the SAME success path
                              // as a real match. foundCustomer is
                              // therefore never empty either way, so
                              // checking .isEmpty here always picked
                              // the "found" branch, even for phone
                              // numbers with no account — merchants
                              // saw "Customer Found" and skipped
                              // sending the WhatsApp tracking link,
                              // and the customer never got notified.
                              foundCustomer!['found'] != true
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

                          PhoneInputField(
                            label: 'Customer Phone',
                            onChanged: (e164) => phoneE164 = e164,
                          ),
                          const SizedBox(height: 12),

                          AppInput(
                            controller: landmarkCtrl,
                            hint: 'Area, street, building, landmark...',
                            label: 'Delivery Location',
                            prefixIcon: Icons.location_on_outlined,
                            maxLines: 2,
                          ),

                          const SizedBox(height: 8),

                          // NEW — "Pick on Map" button for O2O,
                          // matching the map picker already used
                          // elsewhere in the app. Previously O2O
                          // only had a text field with no way to
                          // set an exact map pin — this was the
                          // explicitly requested missing piece.
                          GestureDetector(
                            onTap: () async {
                              final result =
                                  await Navigator.push<MapPickResult>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MapPickerScreen(
                                    title: 'Pick Delivery Location',
                                    initialLocation: o2oDeliveryLat != null &&
                                            o2oDeliveryLng != null
                                        ? LatLng(
                                            o2oDeliveryLat!, o2oDeliveryLng!)
                                        : null,
                                  ),
                                ),
                              );
                              if (result != null) {
                                setSheet(() {
                                  landmarkCtrl.text = result.address;
                                  o2oDeliveryLat = result.lat;
                                  o2oDeliveryLng = result.lng;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 14),
                              decoration: BoxDecoration(
                                color: o2oDeliveryLat != null
                                    ? AppColors.accent.withValues(alpha: 0.1)
                                    : AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: o2oDeliveryLat != null
                                      ? AppColors.accent.withValues(alpha: 0.4)
                                      : AppColors.primary
                                          .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    o2oDeliveryLat != null
                                        ? Icons.check_circle_rounded
                                        : Icons.map_outlined,
                                    size: 18,
                                    color: o2oDeliveryLat != null
                                        ? AppColors.accent
                                        : AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    o2oDeliveryLat != null
                                        ? 'Location pinned on map'
                                        : 'Pick exact location on map',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: o2oDeliveryLat != null
                                          ? AppColors.accent
                                          : AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                            const Text('Yes'),
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
                                            const Text('No'),
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
                                      'After creating the order, '
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

                        // NEW — currency toggle for the price field.
                        // The backend only ever sees USD; picking LBP
                        // just changes what the merchant types, and
                        // the typed amount is converted to USD right
                        // before the order is submitted (see
                        // createOrder above).
                        Row(children: [
                          TextButton(
                            onPressed: () => setSheet(() {
                              priceCurrency = 'USD';
                              priceCtrl.clear();
                            }),
                            style: TextButton.styleFrom(
                              backgroundColor: priceCurrency == 'USD'
                                  ? AppColors.primary
                                  : Colors.transparent,
                              foregroundColor: priceCurrency == 'USD'
                                  ? AppColors.background
                                  : AppColors.textHint,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('USD \$'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => setSheet(() {
                              priceCurrency = 'LBP';
                              priceCtrl.clear();
                            }),
                            style: TextButton.styleFrom(
                              backgroundColor: priceCurrency == 'LBP'
                                  ? AppColors.primary
                                  : Colors.transparent,
                              foregroundColor: priceCurrency == 'LBP'
                                  ? AppColors.background
                                  : AppColors.textHint,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('LBP'),
                          ),
                        ]),
                        const SizedBox(height: 10),

                        Row(children: [
                          Expanded(
                            child: AppInput(
                              controller: priceCtrl,
                              hint: priceCurrency == 'USD' ? '0.00' : '0',
                              label: priceCurrency == 'USD'
                                  ? 'Order Price \$'
                                  : 'Order Price (LBP)',
                              prefixIcon: Icons.attach_money_rounded,
                              keyboardType: TextInputType.numberWithOptions(
                                  decimal: priceCurrency == 'USD'),
                              // NEW (final review fix wave, findings #4
                              // and #5) — shared formatter (rejects just
                              // the bad keystroke instead of clearing the
                              // whole field) plus a hard length cap. The
                              // cap is the real defense against a long
                              // digit string parsing to Infinity and
                              // leaking a raw Dart error to the user
                              // (double.tryParse('1'*309+) is already
                              // Infinity, which the <=0 check doesn't
                              // catch) — the shape-only regex alone never
                              // limited length.
                              inputFormatters: [
                                priceCurrency == 'USD'
                                    ? CurrencyInputFormatter.usd()
                                    : CurrencyInputFormatter.lbp(),
                              ],
                              maxLength: priceCurrency == 'USD' ? 10 : 12,
                              counterText: '',
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
                              // NEW — for O2O specifically, this
                              // field is read-only and ignored: the
                              // backend always computes delivery
                              // fee from real distance. Left active
                              // for the non-O2O manual-address flow
                              // for now (separate, still-open item).
                              readOnly: isO2O,
                            ),
                          ),
                        ]),

                        if (isO2O) ...[
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.auto_awesome_rounded,
                                size: 14, color: AppColors.accent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Delivery fee is calculated automatically '
                                'based on real distance once a location '
                                'is set.',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.accent),
                              ),
                            ),
                          ]),
                        ],

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
                          label: isO2O ? 'Create O2O Order' : 'Create Order',
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
