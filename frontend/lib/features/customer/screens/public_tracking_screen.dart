import 'dart:async';
import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_motion.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/location_service.dart';
import '../../../shared/widgets/app_skeleton_card.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_toast.dart';

/// PublicTrackingScreen
/// ────────────────────────────────────────────────────
/// FIX: this is the actual page that opens when a customer
/// clicks the tracking link sent via WhatsApp/SMS
/// (https://faster-app.org/tracking/public/{code}).
///
/// Previously that URL was accidentally routed straight to
/// the backend's raw JSON endpoint — a customer clicking the
/// link saw plain text, not a page. Now nginx serves the
/// Flutter app for that path, and main.dart detects the
/// /tracking/public/{code} URL at boot and shows THIS screen
/// directly, bypassing login entirely (matches the whole
/// point of a public, no-account-needed tracking link).
///
/// No login, no auth header, no WebSocket (which requires a
/// JWT — see JwtAuthFilter/WebSocketConfig) — this screen
/// polls the public JSON endpoint every few seconds instead,
/// which is simple and doesn't touch the authenticated
/// WebSocket path at all.
class PublicTrackingScreen extends StatefulWidget {
  final String trackingCode;

  const PublicTrackingScreen({super.key, required this.trackingCode});

  @override
  State<PublicTrackingScreen> createState() => _PublicTrackingScreenState();
}

class _PublicTrackingScreenState extends State<PublicTrackingScreen> {
  Map<String, dynamic>? _order;
  bool _isLoading = true;
  String? _error;

  bool _isSharingLocation = false;
  bool _locationShared = false;
  // NEW (final review fix wave, finding #1) — true when the backend
  // FLAGGED the last location share instead of applying it (reported
  // location beyond the delivery-distance cap). Deliberately separate
  // from _locationShared: the share card (and its retry button) must
  // stay visible in this case — the recipient may have a one-off bad
  // GPS fix and should be able to try again — unlike the real success
  // case, which hides it.
  bool _locationFlagged = false;

  Timer? _pollTimer;

  // Skeleton placeholders shown while the initial tracking-data fetch is
  // in flight, echoing the eventual status-timeline / driver-info /
  // order-details card layout below instead of a single centered spinner.
  static const List<double> _loadingSkeletonHeights = [200, 220, 100, 140];

  static const _statusSteps = [
    'PENDING',
    'ACCEPTED',
    'PREPARING',
    'READY_FOR_PICKUP',
    'PICKED_UP',
    'DELIVERED',
  ];

  @override
  void initState() {
    super.initState();
    _fetchOrder();
    // Poll every 8 seconds for live status — no WebSocket
    // needed since this page has no auth token at all.
    _pollTimer = Timer.periodic(
        const Duration(seconds: 8), (_) => _fetchOrder(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrder({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final res = await ApiService.instance
          .get(ApiConstants.publicTrackingData(widget.trackingCode));
      if (!mounted) return;
      setState(() {
        _order = res.data as Map<String, dynamic>;
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = silent
            ? _error
            : 'Order not found. Check your tracking link.';
        _isLoading = false;
      });
    }
  }

  Future<void> _shareLocation() async {
    setState(() => _isSharingLocation = true);
    try {
      final position = await LocationService.instance.getCurrentPosition();
      if (position == null) {
        _showMessage(
            'Could not get your location. Please allow location access.',
            isError: true);
        return;
      }

      final res = await ApiService.instance.patch(
        ApiConstants.publicTrackingLocation(widget.trackingCode),
        data: {
          'lat': position.latitude,
          'lng': position.longitude,
        },
      );

      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      // FIX (final review fix wave, finding #1): OrderController now
      // tells the truth about whether this update was actually
      // applied or just flagged for admin review (beyond the
      // delivery-distance cap) — previously this screen showed the
      // success state either way, with no way for the recipient to
      // know their location wasn't used and no way to retry (the
      // share card was hidden as soon as _locationShared was set).
      final flagged = data['distanceFlagged'] == true;
      setState(() {
        _locationFlagged = flagged;
        // Only the real success case hides the share card — a
        // flagged attempt leaves it (and its retry button) visible.
        _locationShared = !flagged;
        if (_order != null) {
          _order!['deliveryFee'] = data['deliveryFee'];
          _order!['grandTotal'] = data['grandTotal'];
        }
      });
      if (flagged) {
        _showMessage(
          (data['message'] as String?) ??
              "We received your location, but it's outside our delivery "
                  'area — our team will review it.',
          isWarning: true,
        );
      } else {
        _showMessage('Location shared! Delivery fee updated.');
      }
    } catch (e) {
      _showMessage(ApiService.getErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _isSharingLocation = false);
    }
  }

  void _showMessage(String msg, {bool isError = false, bool isWarning = false}) {
    if (!mounted) return;
    if (isError) {
      AppToast.error(context, msg);
    } else if (isWarning) {
      AppToast.warning(context, msg);
    } else {
      AppToast.success(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isLoading && _order == null
            ? ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: _loadingSkeletonHeights.length,
                separatorBuilder: (_, __) => const SizedBox(height: 20),
                itemBuilder: (_, i) =>
                    AppSkeletonCard(height: _loadingSkeletonHeights[i]),
              )
            : _error != null && _order == null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded,
                color: AppColors.textHint, size: 56),
            const SizedBox(height: 20),
            Text(_error!,
                style: AppTextStyles.headlineSmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final order = _order!;
    final status = order['status'] as String? ?? 'PENDING';
    final trackingCode = order['trackingCode'] as String? ?? '';
    final grandTotal = order['grandTotal']?.toString() ?? '0.00';
    final deliveryFee = order['deliveryFee']?.toString() ?? '0.00';
    final deliveryAddress = order['deliveryAddress'] as String? ?? '';
    final driverName = order['driverName'] as String?;
    final driverVehicle = order['driverVehicleType'] as String?;
    final driverPlate = order['driverVehiclePlate'] as String?;
    final hasDeliveryLocation = order['deliveryLat'] != null;

    final currentStepIndex = _statusSteps.indexOf(status);
    final isCancelled = status == 'CANCELLED';
    final isDisputed = status == 'DISPUTED';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Brand header ─────────────────────────
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Text('FASTER',
                  style: AppTextStyles.headlineMedium
                      .copyWith(letterSpacing: 3)),
            ],
          ),
          const SizedBox(height: 24),

          Text('Order Tracking', style: AppTextStyles.displayMedium),
          const SizedBox(height: 4),
          Text(trackingCode,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.primary)),
          const SizedBox(height: 24),

          // ─── Status ────────────────────────────────
          if (isCancelled || isDisputed)
            GlassCard(
              padding: const EdgeInsets.all(20),
              borderColor: AppColors.error.withValues(alpha: 0.4),
              child: Row(children: [
                Icon(
                    isCancelled
                        ? Icons.cancel_outlined
                        : Icons.report_problem_outlined,
                    color: AppColors.error),
                const SizedBox(width: 12),
                Text(
                  isCancelled ? 'Order Cancelled' : 'Order Under Review',
                  style: AppTextStyles.headlineSmall
                      .copyWith(color: AppColors.error),
                ),
              ]),
            )
          else
            _buildStatusTimeline(currentStepIndex),

          const SizedBox(height: 20),

          // ─── Driver info (once assigned) ──────────
          if (driverName != null) ...[
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.driverColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delivery_dining_rounded,
                      color: AppColors.driverColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(driverName, style: AppTextStyles.headlineSmall),
                      if (driverVehicle != null)
                        Text(
                          '$driverVehicle${driverPlate != null && driverPlate.isNotEmpty ? " • $driverPlate" : ""}',
                          style: AppTextStyles.bodyMedium,
                        ),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // ─── Share location ────────────────────────
          // NEW (final review fix wave, finding #1): a FLAGGED attempt
          // (reported location beyond the delivery-distance cap) must
          // not look like success — show a distinct notice and keep
          // the retry button, instead of silently matching the
          // success card below (which hides the button entirely).
          if (!hasDeliveryLocation && !_locationShared &&
              !isCancelled && status != 'DELIVERED') ...[
            if (_locationFlagged) ...[
              GlassCard(
                padding: const EdgeInsets.all(14),
                borderColor: AppColors.warning.withValues(alpha: 0.5),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "That location looked outside our delivery area, "
                      'so our team will review it. You can try sharing '
                      'again below.',
                      style: AppTextStyles.bodyMedium,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.location_on_outlined,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Share your exact location',
                          style: AppTextStyles.headlineSmall),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'This helps us calculate the correct delivery '
                    'fee and helps your driver find you faster.',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  AppButton(
                    label: _locationFlagged
                        ? 'Try Sharing Again'
                        : 'Share My Location',
                    icon: Icons.my_location_rounded,
                    isLoading: _isSharingLocation,
                    onPressed: _shareLocation,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else if (_locationShared) ...[
            GlassCard(
              padding: const EdgeInsets.all(14),
              borderColor: AppColors.accent.withValues(alpha: 0.4),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.accent, size: 18),
                const SizedBox(width: 8),
                Text('Location shared', style: AppTextStyles.bodyMedium),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // ─── Order details ─────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order Details', style: AppTextStyles.headlineSmall),
                const SizedBox(height: 12),
                if (deliveryAddress.isNotEmpty) ...[
                  _detailRow(Icons.place_outlined, 'Delivering to',
                      deliveryAddress),
                  const SizedBox(height: 10),
                ],
                _detailRow(Icons.delivery_dining_outlined,
                    'Delivery fee', '\$$deliveryFee'),
                const SizedBox(height: 10),
                _detailRow(Icons.payments_outlined, 'Total to pay',
                    '\$$grandTotal', highlight: true),
              ],
            ),
          ),

          const SizedBox(height: 16),

          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(Icons.payments_outlined,
                  color: AppColors.warning, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pay \$$grandTotal cash to the driver upon arrival.',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.warning),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline(int currentStepIndex) {
    const labels = [
      'Order Placed',
      'Accepted',
      'Preparing',
      'Ready',
      'Picked Up',
      'Delivered',
    ];

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: List.generate(
          labels.length,
          (i) => _buildAnimatedTimelineStep(i, labels, currentStepIndex),
        ),
      ),
    );
  }

  // Wraps a status-timeline step in a staggered fade/slide entrance,
  // skipped entirely under the platform's reduced-motion setting.
  Widget _buildAnimatedTimelineStep(
      int index, List<String> labels, int currentStepIndex) {
    final step = _buildTimelineStep(index, labels, currentStepIndex);
    if (AppMotion.reduceMotion(context)) return step;
    return FadeInUp(
      duration: AppMotion.listEntranceDuration,
      delay: Duration(
          milliseconds: index * AppMotion.listStaggerDelay.inMilliseconds),
      child: step,
    );
  }

  Widget _buildTimelineStep(
      int i, List<String> labels, int currentStepIndex) {
    final done = i <= currentStepIndex;
    final isLast = i == labels.length - 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.accent : AppColors.glassWhite,
                border: Border.all(
                  color: done ? AppColors.accent : AppColors.glassBorder,
                ),
              ),
              child: done
                  ? const Icon(Icons.check_rounded,
                      size: 12, color: AppColors.background)
                  : null,
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 32,
                color: done ? AppColors.accent : AppColors.glassBorder,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            labels[i],
            style: AppTextStyles.bodyMedium.copyWith(
              color: done ? AppColors.textPrimary : AppColors.textHint,
              fontWeight: done ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      {bool highlight = false}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textHint),
        const SizedBox(width: 8),
        Text(label, style: AppTextStyles.bodyMedium),
        const Spacer(),
        Text(
          value,
          style: highlight
              ? AppTextStyles.headlineSmall
                  .copyWith(color: AppColors.accent)
              : AppTextStyles.bodyMedium,
        ),
      ],
    );
  }
}