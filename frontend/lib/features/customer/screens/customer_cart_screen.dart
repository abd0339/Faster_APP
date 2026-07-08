import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_config.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/location_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/google_places_search_field.dart';
import '../services/cart_service.dart';
import 'customer_order_tracking_screen.dart';

// FIX (C2 — server-side pricing):
// This screen no longer sends totalPrice/deliveryFee to the backend.
// It sends WHAT was ordered (itemId + quantity per line) and WHERE
// (delivery coordinates). The server looks up real prices from the
// merchant's own catalog and computes delivery fee from distance —
// see PricingService.java. This screen calls /api/orders/quote to
// SHOW the real price before the customer confirms, but that quote
// is a display convenience only — the actual order creation
// recomputes everything from scratch server-side regardless.
class CustomerCartScreen extends StatefulWidget {
  const CustomerCartScreen({super.key});

  @override
  State<CustomerCartScreen> createState() => _CustomerCartScreenState();
}

class _CustomerCartScreenState extends State<CustomerCartScreen> {
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isPlacingOrder = false;
  bool _isDetectingLocation = false;
  bool _isQuoting = false;

  // ─── Server-computed pricing (never client-computed) ──
  // Populated by _fetchQuote(). Until the first quote comes
  // back these are null and the UI shows a loading state
  // instead of a guessed number.
  double? _serverTotalPrice;
  double? _serverDeliveryFee;
  double? _serverGrandTotal;
  String? _quoteError;

  // Customer GPS coordinates
  double? _deliveryLat;
  double? _deliveryLng;

  @override
  void initState() {
    super.initState();
    // Auto-detect location on open
    _autoDetectLocation();
    // Get an initial price quote for whatever's already in the cart
    _fetchQuote();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ─── Auto-detect GPS on screen open ──────────────
  Future<void> _autoDetectLocation() async {
    if (kIsWeb) {
      // Web geolocation works but needs permission
      // Don't auto-request — let user tap the button
      return;
    }
    await _detectLocation();
  }

  Future<void> _detectLocation() async {
    if (!mounted) return;
    setState(() => _isDetectingLocation = true);
    try {
      final position = await LocationService.instance.getCurrentPosition();
      if (position == null || !mounted) return;

      setState(() {
        _deliveryLat = position.latitude;
        _deliveryLng = position.longitude;
      });

      // Try reverse geocoding via Nominatim (free, no key)
      try {
        final geoRes = await dio.Dio().get(
          'https://nominatim.openstreetmap.org/reverse',
          queryParameters: {
            'format': 'json',
            'lat': position.latitude.toString(),
            'lon': position.longitude.toString(),
          },
          options: dio.Options(headers: {
            'Accept-Language': 'en',
            'User-Agent': 'FasterApp/1.0',
          }),
        );
        final address = geoRes.data?['display_name'];
        if (address != null && mounted) {
          _addressCtrl.text = address.toString();
        }
      } catch (_) {
        if (mounted) {
          _addressCtrl.text = '${position.latitude.toStringAsFixed(5)}, '
              '${position.longitude.toStringAsFixed(5)}';
        }
      }
    } catch (e) {
      // Location permission denied — user types manually
    } finally {
      if (mounted) setState(() => _isDetectingLocation = false);
      // Coordinates may have just changed — refresh the quote
      _fetchQuote();
    }
  }

  // ─── Build the cart lines the server actually needs ──
  // itemId + quantity only for now. Modifier/addon selection
  // in the cart UI is a separate future feature; when added,
  // include modifierOptionIds/addonIds per line here too.
  List<Map<String, dynamic>> _buildItemLines() {
    return CartService.instance.items
        .map((item) => {
              'itemId': item.itemId,
              'quantity': item.quantity,
            })
        .toList();
  }

  // ─── Get a real, server-computed price quote ─────────
  // Called on load and whenever the cart or delivery
  // location changes. Never trust a locally-computed
  // total for display — this is what the backend will
  // actually charge.
  Future<void> _fetchQuote() async {
    final cart = CartService.instance;
    if (cart.isEmpty || cart.merchantId == null) return;

    if (!mounted) return;
    setState(() {
      _isQuoting = true;
      _quoteError = null;
    });

    try {
      final res = await ApiService.instance.post(
        '/api/orders/quote',
        data: {
          'merchantId': cart.merchantId,
          'items': _buildItemLines(),
          'deliveryLat': _deliveryLat,
          'deliveryLng': _deliveryLng,
        },
      );
      final data = res.data as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _serverTotalPrice = (data['totalPrice'] as num).toDouble();
        _serverDeliveryFee = (data['deliveryFee'] as num).toDouble();
        _serverGrandTotal = (data['grandTotal'] as num).toDouble();
      });
    } catch (e) {
      if (mounted) {
        setState(
            () => _quoteError = 'Could not calculate price. Pull to refresh.');
      }
    } finally {
      if (mounted) setState(() => _isQuoting = false);
    }
  }

  Future<void> _placeOrder() async {
    if (_addressCtrl.text.trim().isEmpty) {
      _showError('Please enter your delivery address');
      return;
    }
    if (CartService.instance.isEmpty) {
      _showError('Your cart is empty');
      return;
    }
    if (!mounted) return;
    setState(() => _isPlacingOrder = true);
    try {
      final cart = CartService.instance;
      // Only sends WHAT was ordered — never a price.
      // The server computes totalPrice/deliveryFee itself.
      final res = await ApiService.instance.post(
        ApiConstants.orders,
        data: {
          'merchantId': cart.merchantId,
          'items': _buildItemLines(),
          'deliveryAddress': _addressCtrl.text.trim(),
          'deliveryLat': _deliveryLat,
          'deliveryLng': _deliveryLng,
          'customerNotes': _notesCtrl.text.trim(),
          'orderType': 'LOGISTICS',
          'isO2O': false,
        },
      );
      final orderData = res.data as Map<String, dynamic>;
      final orderId = orderData['id'] as int?;
      final tracking = orderData['trackingCode'] as String? ?? '';
      CartService.instance.clear();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerOrderTrackingScreen(
            orderId: orderId ?? 0,
            trackingCode: tracking,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isPlacingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartService.instance;
    // These are LOCAL estimates shown only while the real quote
    // is loading — the button label and final charge always use
    // the server-computed values once available.
    final localSubtotalEstimate = cart.subtotal;

    final displayTotal = _serverTotalPrice ?? localSubtotalEstimate;
    final displayDeliveryFee = _serverDeliveryFee;
    final displayGrandTotal = _serverGrandTotal;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.textPrimary, size: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your Cart', style: AppTextStyles.headlineMedium),
                    Text(
                      cart.merchantName ?? '',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ]),
            ),

            Expanded(
              child: cart.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.shopping_cart_outlined,
                              color: AppColors.textHint, size: 56),
                          const SizedBox(height: 16),
                          Text('Cart is empty',
                              style: AppTextStyles.headlineMedium),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Items
                          ...cart.items.map((item) => _cartItemRow(item)),

                          const SizedBox(height: 20),

                          // ─── Address ─────────────
                          Row(children: [
                            Text('Delivery Address',
                                style: AppTextStyles.headlineSmall),
                            const Spacer(),
                            // GPS detect button
                            GestureDetector(
                              onTap: _detectLocation,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: _isDetectingLocation
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          color: AppColors.primary,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.my_location_rounded,
                                              color: AppColors.primary,
                                              size: 14),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Use GPS',
                                            style:
                                                AppTextStyles.caption.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),

                          // GPS status indicator
                          if (_deliveryLat != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(children: [
                                const Icon(Icons.location_on_rounded,
                                    color: AppColors.accent, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'GPS detected — driver will navigate to your location',
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.accent),
                                ),
                              ]),
                            ),

                          GooglePlacesSearchField(
                            hint: 'Your delivery address',
                            label: 'Address',
                            apiKey: AppConfig.googlePlacesKey,
                            onPlaceSelected: (result) {
                              _addressCtrl.text = result.address;
                              _deliveryLat = result.lat;
                              _deliveryLng = result.lng;
                              setState(() {});
                              // Address changed → real delivery fee changes
                              _fetchQuote();
                            },
                          ),
                          const SizedBox(height: 16),

                          // Notes
                          AppInput(
                            controller: _notesCtrl,
                            hint: 'Special instructions (optional)',
                            label: 'Notes',
                            prefixIcon: Icons.note_outlined,
                          ),
                          const SizedBox(height: 24),

                          // ─── Order summary ───────────
                          GlassCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(children: [
                              _summaryRow(
                                  'Items subtotal',
                                  '\$${displayTotal.toStringAsFixed(2)}',
                                  AppColors.textPrimary),
                              const SizedBox(height: 8),
                              _summaryRow(
                                  'Delivery fee',
                                  displayDeliveryFee != null
                                      ? '\$${displayDeliveryFee.toStringAsFixed(2)}'
                                      : (_isQuoting ? 'Calculating…' : '—'),
                                  AppColors.textHint),
                              const Divider(
                                  color: AppColors.glassBorder, height: 20),
                              _summaryRow(
                                  'Total you pay',
                                  displayGrandTotal != null
                                      ? '\$${displayGrandTotal.toStringAsFixed(2)}'
                                      : (_isQuoting ? 'Calculating…' : '—'),
                                  AppColors.accent,
                                  isBold: true),
                              if (_quoteError != null) ...[
                                const SizedBox(height: 8),
                                Text(_quoteError!,
                                    style: AppTextStyles.caption
                                        .copyWith(color: AppColors.error)),
                              ],
                            ]),
                          ),

                          const SizedBox(height: 12),

                          // ─── Cash on delivery note ───
                          GlassCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              const Icon(Icons.payments_outlined,
                                  color: AppColors.warning, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  displayGrandTotal != null
                                      ? 'Pay \$${displayGrandTotal.toStringAsFixed(2)} cash to driver at your door.'
                                      : 'Final price is confirmed by the store before your driver arrives.',
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.warning),
                                ),
                              ),
                            ]),
                          ),

                          const SizedBox(height: 24),

                          // ─── Place order button ──────
                          AppButton(
                            label: displayGrandTotal != null
                                ? 'Place Order — \$${displayGrandTotal.toStringAsFixed(2)}'
                                : 'Place Order',
                            icon: Icons.check_rounded,
                            isLoading: _isPlacingOrder,
                            color: AppColors.accent,
                            textColor: AppColors.background,
                            onPressed: _placeOrder,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartItemRow(item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: AppTextStyles.headlineSmall),
                Text('\$${item.price.toStringAsFixed(2)} × ${item.quantity}',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textHint)),
              ],
            ),
          ),
          Row(children: [
            GestureDetector(
              onTap: () {
                if (!kIsWeb) HapticFeedback.selectionClick();
                CartService.instance
                    .updateQuantity(item.itemId, item.quantity - 1);
                setState(() {});
                _fetchQuote();
              },
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: const Icon(Icons.remove_rounded,
                    size: 15, color: AppColors.textPrimary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('${item.quantity}', style: AppTextStyles.labelLarge),
            ),
            GestureDetector(
              onTap: () {
                if (!kIsWeb) HapticFeedback.selectionClick();
                CartService.instance
                    .updateQuantity(item.itemId, item.quantity + 1);
                setState(() {});
                _fetchQuote();
              },
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_rounded,
                    size: 15, color: AppColors.background),
              ),
            ),
          ]),
          const SizedBox(width: 12),
          Text('\$${item.subtotal.toStringAsFixed(2)}',
              style: AppTextStyles.priceSmall),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              CartService.instance.removeItem(item.itemId);
              setState(() {});
              _fetchQuote();
            },
            child: const Icon(Icons.delete_outline_rounded,
                color: AppColors.error, size: 18),
          ),
        ]),
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color color,
      {bool isBold = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: AppTextStyles.bodyMedium),
      Text(value,
          style:
              (isBold ? AppTextStyles.headlineSmall : AppTextStyles.bodyMedium)
                  .copyWith(color: color)),
    ]);
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
