import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_input.dart';
import '../services/cart_service.dart';
import 'customer_order_tracking_screen.dart';

class CustomerCartScreen extends StatefulWidget {
  const CustomerCartScreen({super.key});

  @override
  State<CustomerCartScreen> createState() => _CustomerCartScreenState();
}

class _CustomerCartScreenState extends State<CustomerCartScreen> {
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isPlacingOrder = false;
  double _deliveryFee = 2.00; // Default — can be dynamic

  @override
  void dispose() {
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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
      // Build items list for the order
      final itemsList = cart.items
          .map((i) => {
                'itemId': i.itemId,
                'quantity': i.quantity,
                'unitPrice': i.price,
              })
          .toList();

      final res = await ApiService.instance.post(
        ApiConstants.orders,
        data: {
          'merchantId': cart.merchantId,
          'totalPrice': cart.subtotal,
          'deliveryFee': _deliveryFee,
          'deliveryAddress': _addressCtrl.text.trim(),
          'customerNotes': _notesCtrl.text.trim(),
          'orderType': 'LOGISTICS',
          'isO2O': false,
          'items': itemsList,
        },
      );

      final orderData = res.data as Map<String, dynamic>;
      final orderId = orderData['id'] as int?;
      final tracking = orderData['trackingCode'] as String? ?? '';

      // Clear cart after successful order
      CartService.instance.clear();

      if (!mounted) return;

      // Navigate to tracking screen
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
    final subtotal = cart.subtotal;
    final grandTotal = subtotal + _deliveryFee;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                          const SizedBox(height: 8),
                          Text('Add items to get started',
                              style: AppTextStyles.bodyMedium),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ─── Items list ──────────
                          ...cart.items.map((item) => _cartItemRow(item)),

                          const SizedBox(height: 20),

                          // ─── Delivery address ────
                          Text('Delivery Address',
                              style: AppTextStyles.headlineSmall),
                          const SizedBox(height: 10),
                          AppInput(
                            controller: _addressCtrl,
                            hint: 'Enter your full address',
                            label: 'Address',
                            prefixIcon: Icons.location_on_outlined,
                            maxLines: 2,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // ─── Notes ───────────────
                          AppInput(
                            controller: _notesCtrl,
                            hint: 'Special instructions (optional)',
                            label: 'Notes',
                            prefixIcon: Icons.note_outlined,
                          ),
                          const SizedBox(height: 24),

                          // ─── Order summary ───────
                          GlassCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _summaryRow(
                                    'Subtotal',
                                    '\$${subtotal.toStringAsFixed(2)}',
                                    AppColors.textPrimary),
                                const SizedBox(height: 8),
                                _summaryRow(
                                    'Delivery Fee',
                                    '\$${_deliveryFee.toStringAsFixed(2)}',
                                    AppColors.textSecondary),
                                const Divider(
                                    color: AppColors.glassBorder, height: 20),
                                _summaryRow(
                                    'Total',
                                    '\$${grandTotal.toStringAsFixed(2)}',
                                    AppColors.accent,
                                    isBold: true),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ─── Place order ─────────
                          AppButton(
                            label:
                                'Place Order — \$${grandTotal.toStringAsFixed(2)}',
                            icon: Icons.check_rounded,
                            isLoading: _isPlacingOrder,
                            color: AppColors.accent,
                            textColor: AppColors.background,
                            onPressed: _placeOrder,
                          ),

                          const SizedBox(height: 12),

                          // ─── Payment note ────────
                          GlassCard(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              const Icon(Icons.payments_outlined,
                                  color: AppColors.warning, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Payment is cash on delivery. '
                                  'Driver collects \$${grandTotal.toStringAsFixed(2)} at your door.',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                            ]),
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
                Text('\$${item.price.toStringAsFixed(2)}',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.primary)),
              ],
            ),
          ),

          // Qty control
          Row(children: [
            GestureDetector(
              onTap: () {
                if (!kIsWeb) HapticFeedback.selectionClick();
                CartService.instance
                    .updateQuantity(item.itemId, item.quantity - 1);
                setState(() {});
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
          Text(
            '\$${item.subtotal.toStringAsFixed(2)}',
            style: AppTextStyles.priceSmall,
          ),

          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              CartService.instance.removeItem(item.itemId);
              setState(() {});
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
