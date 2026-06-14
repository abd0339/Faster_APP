import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/app_button.dart';
import '../models/cart_item.dart';
import '../services/cart_service.dart';
import 'customer_cart_screen.dart';

class CustomerStoreMenuScreen extends StatefulWidget {
  final int merchantId;
  final String merchantName;

  const CustomerStoreMenuScreen({
    super.key,
    required this.merchantId,
    required this.merchantName,
  });

  @override
  State<CustomerStoreMenuScreen> createState() =>
      _CustomerStoreMenuScreenState();
}

class _CustomerStoreMenuScreenState extends State<CustomerStoreMenuScreen> {
  List<dynamic> _categories = [];
  List<dynamic> _offers = [];
  Map<String, dynamic>? _storeStatus;
  bool _isLoading = true;
  bool _showConflictDialog = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.get(ApiConstants.storeMenu(widget.merchantId)),
        ApiService.instance.get(ApiConstants.storeStatus(widget.merchantId)),
        ApiService.instance.get('/api/store/${widget.merchantId}/offers'),
      ]);
      if (!mounted) return;

      final menuResponse = results[0].data as Map<String, dynamic>?;
      final cats = menuResponse?['menu'] as List? ?? [];

      final offerData = results[2].data;
      setState(() {
        _categories = cats;
        _storeStatus = results[1].data as Map<String, dynamic>?;
        _offers = offerData is List ? offerData : [];
      });
    } catch (e) {
      if (!mounted) return;
      _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addToCart(Map<String, dynamic> item) {
    if (!kIsWeb) HapticFeedback.lightImpact();

    final cartItem = CartItem(
      itemId: item['id'] as int,
      name: item['name'] as String,
      price: (item['price'] as num).toDouble(),
      imageUrl: item['imageUrl'] as String?,
    );

    final success = CartService.instance.addItem(
      cartItem,
      widget.merchantId,
      widget.merchantName,
    );

    if (!success && mounted) {
      // Cart has items from different merchant
      _showMerchantConflictSheet();
      return;
    }

    setState(() {}); // Rebuild cart badge
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item['name']} added to cart'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showMerchantConflictSheet() {
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
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 40),
            const SizedBox(height: 16),
            Text('Start a new cart?', style: AppTextStyles.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Your cart has items from "${CartService.instance.merchantName}". '
              'Starting a new order will clear your current cart.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Clear cart & continue',
              icon: Icons.refresh_rounded,
              color: AppColors.warning,
              textColor: AppColors.background,
              onPressed: () {
                CartService.instance.clear();
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Keep current cart',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.textHint)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _cartQty(int itemId) {
    final items = CartService.instance.items;
    try {
      return items.firstWhere((i) => i.itemId == itemId).quantity;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = CartService.instance.totalItems;
    final isOpen = _storeStatus?['isOpen'] as bool? ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isOpen, cartCount),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : _buildMenu(),
            ),
          ],
        ),
      ),
      // Cart FAB
      floatingActionButton: cartCount > 0
          ? FloatingActionButton.extended(
              heroTag: 'cart_fab',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomerCartScreen()),
                );
                setState(() {}); // Refresh cart badge
              },
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              icon: const Icon(Icons.shopping_cart_rounded),
              label: Text(
                '$cartCount items — \$${CartService.instance.subtotal.toStringAsFixed(2)}',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.background),
              ),
            )
          : null,
    );
  }

  Widget _buildHeader(bool isOpen, int cartCount) {
    return Padding(
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.merchantName,
                  style: AppTextStyles.headlineMedium,
                  overflow: TextOverflow.ellipsis),
              Row(children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isOpen ? AppColors.accent : AppColors.error,
                  ),
                ),
                Text(
                  isOpen ? 'Open' : 'Closed',
                  style: AppTextStyles.caption.copyWith(
                    color: isOpen ? AppColors.accent : AppColors.error,
                  ),
                ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildMenu() {
    if (_categories.isEmpty) {
      return const Center(
        child: Text('No items available', style: AppTextStyles.bodyMedium),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
        children: [
          // ─── Offers banner ─────────────────────
          if (_offers.isNotEmpty) ...[
            _buildOffersBanner(),
            const SizedBox(height: 20),
          ],

          // ─── Categories + items ────────────────
          ..._categories.map((cat) {
            final catMap = cat as Map<String, dynamic>;
            final items = (catMap['items'] as List?) ?? [];
            // Only show active items
            final activeItems = items
                .where((i) =>
                    (i as Map<String, dynamic>)['isAvailable'] == true &&
                    (i)['isSnoozed'] != true)
                .toList();
            if (activeItems.isEmpty) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _categoryHeader(catMap),
                ...activeItems
                    .map((item) => _itemCard(item as Map<String, dynamic>)),
                const SizedBox(height: 12),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOffersBanner() {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _offers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final offer = _offers[i] as Map<String, dynamic>;
          final discount = offer['discountPercent'];
          final type = offer['offerType'] as String? ?? '';
          return Container(
            width: 200,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
              ),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (discount != null)
                  Text(
                    type == 'PERCENTAGE' ? '$discount% OFF' : '\$$discount OFF',
                    style: AppTextStyles.price.copyWith(fontSize: 22),
                  ),
                const SizedBox(height: 4),
                Text(
                  offer['title'] as String? ?? '',
                  style: AppTextStyles.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _categoryHeader(Map<String, dynamic> cat) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        if ((cat['icon'] as String? ?? '').isNotEmpty)
          Text(cat['icon'] as String, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Text(
          cat['name'] as String? ?? '',
          style: AppTextStyles.headlineSmall,
        ),
      ]),
    );
  }

  Widget _itemCard(Map<String, dynamic> item) {
    final itemId = item['id'] as int;
    final price = (item['price'] as num).toDouble();
    final imageUrl = item['imageUrl'] as String?;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final qty = _cartQty(itemId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Row(children: [
          // Image
          ClipRRect(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(20)),
            child: SizedBox(
              width: 90,
              height: 90,
              child: hasImage
                  ? Image.network(
                      '${ApiConstants.baseUrl}$imageUrl',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(),
                    )
                  : _imagePlaceholder(),
            ),
          ),

          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'] as String? ?? '',
                    style: AppTextStyles.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item['description'] != null &&
                      (item['description'] as String).isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item['description'] as String,
                      style: AppTextStyles.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text('\$$price', style: AppTextStyles.priceSmall),
                ],
              ),
            ),
          ),

          // Add / Qty control
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: qty == 0
                ? GestureDetector(
                    onTap: () => _addToCart(item),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: AppColors.background, size: 20),
                    ),
                  )
                : _qtyControl(itemId, qty),
          ),
        ]),
      ),
    );
  }

  Widget _qtyControl(int itemId, int qty) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            if (!kIsWeb) HapticFeedback.selectionClick();
            CartService.instance.updateQuantity(itemId, qty - 1);
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
                size: 16, color: AppColors.textPrimary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$qty', style: AppTextStyles.labelLarge),
        ),
        GestureDetector(
          onTap: () {
            if (!kIsWeb) HapticFeedback.selectionClick();
            CartService.instance.updateQuantity(itemId, qty + 1);
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
                size: 16, color: AppColors.background),
          ),
        ),
      ],
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: AppColors.glassWhite,
      child: const Center(
        child:
            Icon(Icons.fastfood_outlined, color: AppColors.textHint, size: 28),
      ),
    );
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
