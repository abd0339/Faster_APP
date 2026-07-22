import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/websocket_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../widgets/order_feedback_sheet.dart';

class CustomerOrderTrackingScreen extends StatefulWidget {
  final int orderId;
  final String trackingCode;

  const CustomerOrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.trackingCode,
  });

  @override
  State<CustomerOrderTrackingScreen> createState() =>
      _CustomerOrderTrackingScreenState();
}

class _CustomerOrderTrackingScreenState
    extends State<CustomerOrderTrackingScreen> {
  Map<String, dynamic>? _order;
  bool _isLoading = true;
  String _currentStatus = 'PENDING';
  // NEW — guards against showing the feedback prompt more
  // than once per screen session (e.g. on WebSocket
  // reconnect re-delivering the same DELIVERED status).
  bool _feedbackPromptShown = false;

  final _statusSteps = [
    'PENDING',
    'ACCEPTED',
    'PREPARING',
    'READY_FOR_PICKUP',
    'PICKED_UP',
    'DELIVERED',
  ];

  final _statusLabels = {
    'PENDING': 'Order Placed',
    'ACCEPTED': 'Driver Assigned',
    'PREPARING': 'Preparing',
    'READY_FOR_PICKUP': 'Ready',
    'PICKED_UP': 'On the Way',
    'DELIVERED': 'Delivered',
  };

  final _statusIcons = {
    'PENDING': Icons.receipt_outlined,
    'ACCEPTED': Icons.delivery_dining_outlined,
    'PREPARING': Icons.restaurant_menu_outlined,
    'READY_FOR_PICKUP': Icons.inventory_2_outlined,
    'PICKED_UP': Icons.directions_bike_outlined,
    'DELIVERED': Icons.check_circle_outlined,
  };

  @override
  void initState() {
    super.initState();
    _loadOrder();
    _subscribeToUpdates();
  }

  @override
  void dispose() {
    WebSocketService.instance
        .unsubscribe(ApiConstants.orderTopic(widget.orderId));
    super.dispose();
  }

  Future<void> _loadOrder() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.instance
          .get('${ApiConstants.orders}/${widget.orderId}');
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _order = data;
        _currentStatus = data['status'] as String? ?? 'PENDING';
      });
      _maybeShowFeedbackPrompt();
    } catch (e) {
      // Fallback — show with tracking code
      if (mounted) setState(() => _isLoading = false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToUpdates() async {
    await WebSocketService.instance.connect();
    WebSocketService.instance.subscribeToOrder(
      widget.orderId,
      (data) {
        if (!mounted) return;
        final status = data['status'] as String?;
        if (status != null) {
          setState(() => _currentStatus = status);
          // Reload full order data on update — this also
          // re-checks and shows the feedback prompt via
          // _maybeShowFeedbackPrompt() at the end of _loadOrder()
          _loadOrder();
        }
      },
    );
  }

  // ─── NEW — auto-show feedback prompt on delivery ──
  // Fires once the order's status is DELIVERED, whether
  // that's because the screen loaded with an already-
  // delivered order, or because the WebSocket just pushed
  // that status live while the customer was watching.
  // Guarded by _feedbackPromptShown so it can never appear
  // twice in the same screen session (e.g. a WebSocket
  // reconnect re-delivering the same status update).
  void _maybeShowFeedbackPrompt() {
    if (_currentStatus != 'DELIVERED') return;
    if (_feedbackPromptShown) return;
    if (!mounted) return;

    _feedbackPromptShown = true;

    // Small delay so the "Delivered" status animation/badge
    // is visible for a moment before the sheet slides up —
    // feels less jarring than an instant modal.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      showOrderFeedbackSheet(context, orderId: widget.orderId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentIdx = _statusSteps.indexOf(_currentStatus);
    final isDelivered = _currentStatus == 'DELIVERED';
    final isCancelled = _currentStatus == 'CANCELLED';

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
                    Text('Track Order', style: AppTextStyles.headlineMedium),
                    Text(
                      widget.trackingCode,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _loadOrder,
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
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        // ─── Status hero ─────────
                        GlassCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDelivered
                                    ? AppColors.accent.withValues(alpha: 0.15)
                                    : isCancelled
                                        ? AppColors.error
                                            .withValues(alpha: 0.15)
                                        : AppColors.primary
                                            .withValues(alpha: 0.15),
                                border: Border.all(
                                  color: isDelivered
                                      ? AppColors.accent
                                      : isCancelled
                                          ? AppColors.error
                                          : AppColors.primary,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isDelivered
                                            ? AppColors.accent
                                            : AppColors.primary)
                                        .withValues(alpha: 0.3),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _statusIcons[_currentStatus] ??
                                    Icons.local_shipping,
                                color: isDelivered
                                    ? AppColors.accent
                                    : isCancelled
                                        ? AppColors.error
                                        : AppColors.primary,
                                size: 36,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _statusLabels[_currentStatus] ?? _currentStatus,
                              style: AppTextStyles.headlineLarge,
                            ),
                            const SizedBox(height: 4),
                            StatusBadge(status: _currentStatus),
                          ]),
                        ),

                        const SizedBox(height: 20),

                        // ─── Progress steps ───────
                        if (!isCancelled)
                          GlassCard(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: List.generate(
                                _statusSteps.length,
                                (i) => _buildStep(
                                  i,
                                  currentIdx,
                                ),
                              ),
                            ),
                          ),

                        const SizedBox(height: 20),

                        // ─── Order details ────────
                        if (_order != null)
                          GlassCard(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Order Details',
                                    style: AppTextStyles.headlineSmall),
                                const SizedBox(height: 12),
                                _detailRow('Tracking', widget.trackingCode,
                                    AppColors.primary),
                                _detailRow(
                                    'Total',
                                    '\$${_order!['grandTotal'] ?? 0}',
                                    AppColors.accent),
                                if (_order!['deliveryAddress'] != null)
                                  _detailRow(
                                      'Delivery',
                                      _order!['deliveryAddress'].toString(),
                                      AppColors.textPrimary),
                                if (_order!['customerNotes'] != null &&
                                    (_order!['customerNotes'] as String)
                                        .isNotEmpty)
                                  _detailRow(
                                      'Notes',
                                      _order!['customerNotes'].toString(),
                                      AppColors.textHint),
                              ],
                            ),
                          ),

                        if (isDelivered) ...[
                          const SizedBox(height: 20),
                          GlassCard(
                            color: AppColors.accent,
                            padding: const EdgeInsets.all(20),
                            child: Column(children: [
                              const Icon(Icons.check_circle,
                                  color: AppColors.accent, size: 36),
                              const SizedBox(height: 12),
                              Text('Order Delivered!',
                                  style: AppTextStyles.headlineMedium
                                      .copyWith(color: AppColors.accent)),
                              const SizedBox(height: 8),
                              Text(
                                'Thank you for ordering with Faster.',
                                style: AppTextStyles.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ]),
                          ),
                        ],
                      ]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int index, int currentIndex) {
    final status = _statusSteps[index];
    final label = _statusLabels[status] ?? status;
    final icon = _statusIcons[status] ?? Icons.radio_button_unchecked;
    final isDone = index <= currentIndex;
    final isCurrent = index == currentIndex;
    final isLast = index == _statusSteps.length - 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? AppColors.accent : AppColors.glassWhite,
              border: Border.all(
                color: isDone ? AppColors.accent : AppColors.glassBorder,
                width: isCurrent ? 2 : 1,
              ),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.4),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isDone ? Icons.check_rounded : icon,
              color: isDone ? AppColors.background : AppColors.textHint,
              size: 18,
            ),
          ),
          if (!isLast)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 2,
              height: 32,
              color: index < currentIndex
                  ? AppColors.accent
                  : AppColors.glassBorder,
            ),
        ]),
        const SizedBox(width: 14),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.labelLarge.copyWith(
                  color: isDone ? AppColors.textPrimary : AppColors.textHint,
                ),
              ),
              if (isCurrent)
                Text(
                  'Current status',
                  style:
                      AppTextStyles.caption.copyWith(color: AppColors.accent),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style:
                    AppTextStyles.caption.copyWith(color: AppColors.textHint)),
          ),
          Expanded(
            child: Text(value,
                style: AppTextStyles.bodyMedium.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
