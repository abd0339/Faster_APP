import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/location_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_input.dart';
import 'customer_order_tracking_screen.dart';

class CustomerRideScreen extends StatefulWidget {
  const CustomerRideScreen({super.key});

  @override
  State<CustomerRideScreen> createState() => _CustomerRideScreenState();
}

class _CustomerRideScreenState extends State<CustomerRideScreen> {
  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  double? _pickupLat;
  double? _pickupLng;
  bool _isDetecting = false;
  bool _isRequesting = false;

  // Base ride fee — future: calculate dynamically from distance
  final double _rideFee = 3.00;

  @override
  void initState() {
    super.initState();
    // Auto-detect pickup on screen open (mobile only)
    if (!kIsWeb) {
      _detectPickup();
    }
  }

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ─── Detect current GPS location for pickup ───────
  Future<void> _detectPickup() async {
    if (!mounted) return;
    setState(() => _isDetecting = true);

    try {
      final position = await LocationService.instance.getCurrentPosition();

      if (position == null || !mounted) {
        setState(() => _isDetecting = false);
        return;
      }

      // Store coordinates for the order request
      setState(() {
        _pickupLat = position.latitude;
        _pickupLng = position.longitude;
      });

      // Reverse geocode with Nominatim (free, no API key)
      try {
        final geoRes = await dio.Dio().get(
          'https://nominatim.openstreetmap.org/reverse',
          queryParameters: {
            'format': 'json',
            'lat': position.latitude.toString(),
            'lon': position.longitude.toString(),
          },
          options: dio.Options(
            headers: {
              'Accept-Language': 'en',
              'User-Agent': 'FasterApp/1.0',
            },
            receiveTimeout: const Duration(seconds: 5),
          ),
        );
        final address = geoRes.data?['display_name'];
        if (address != null && mounted) {
          _pickupCtrl.text = address.toString();
        }
      } catch (_) {
        // Geocoding failed — show coordinates as fallback
        if (mounted) {
          _pickupCtrl.text = '${position.latitude.toStringAsFixed(5)}, '
              '${position.longitude.toStringAsFixed(5)}';
        }
      }
    } catch (_) {
      // Location permission denied or unavailable
      // User will type manually
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  // ─── Request the ride ─────────────────────────────
  Future<void> _requestRide() async {
    if (_pickupCtrl.text.trim().isEmpty) {
      _showError('Please set your pickup location');
      return;
    }
    if (_dropoffCtrl.text.trim().isEmpty) {
      _showError('Please enter your destination');
      return;
    }
    if (!mounted) return;

    setState(() => _isRequesting = true);

    try {
      // MOBILITY order — backend notifies PEOPLE + HYBRID drivers
      final res = await ApiService.instance.post(
        ApiConstants.orders,
        data: {
          'totalPrice': 0.00, // No products in a ride
          'deliveryFee': _rideFee, // Ride fare
          'pickupAddress': _pickupCtrl.text.trim(),
          'pickupLat': _pickupLat,
          'pickupLng': _pickupLng,
          'deliveryAddress': _dropoffCtrl.text.trim(),
          'customerNotes': _notesCtrl.text.trim(),
          'orderType': 'MOBILITY',
          'isO2O': false,
          // No merchantId for MOBILITY orders
        },
      );

      final orderData = res.data as Map<String, dynamic>;
      final orderId = orderData['id'] as int?;
      final tracking = orderData['trackingCode'] as String? ?? '';

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
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  // ─── BUILD ────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header ──────────────────────────────
              Row(children: [
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
                    Text('Request a Ride', style: AppTextStyles.displayMedium),
                    Text('Driver picks you up',
                        style: AppTextStyles.bodyMedium),
                  ],
                ),
              ]),

              const SizedBox(height: 28),

              // ─── Fare card ───────────────────────────
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.directions_car_rounded,
                        color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ride fare',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textHint)),
                        Text(
                          '\$${_rideFee.toStringAsFixed(2)}',
                          style: AppTextStyles.price,
                        ),
                        Text('Pay driver cash on arrival',
                            style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  // How commission works info
                  GestureDetector(
                    onTap: () => _showFareInfo(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      child: const Icon(Icons.info_outline_rounded,
                          color: AppColors.textHint, size: 18),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 24),

              // ─── Pickup location ─────────────────────
              Row(children: [
                Text('Pickup Location', style: AppTextStyles.headlineSmall),
                const Spacer(),
                GestureDetector(
                  onTap: _detectPickup,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: _isDetecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                color: AppColors.primary, strokeWidth: 2))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.my_location_rounded,
                                  color: AppColors.primary, size: 14),
                              const SizedBox(width: 4),
                              Text('Use GPS',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ],
                          ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),

              // GPS detected indicator
              if (_pickupLat != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Icon(Icons.location_on_rounded,
                        color: AppColors.accent, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'GPS detected',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.accent),
                    ),
                  ]),
                ),

              AppInput(
                controller: _pickupCtrl,
                hint: kIsWeb
                    ? 'Type your pickup location'
                    : 'Tap "Use GPS" or type your location',
                label: 'Pickup',
                prefixIcon: Icons.location_on_rounded,
                maxLines: 2,
              ),

              const SizedBox(height: 20),

              // ─── Destination ─────────────────────────
              Text('Destination', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 10),
              AppInput(
                controller: _dropoffCtrl,
                hint: 'Where are you going?',
                label: 'Destination',
                prefixIcon: Icons.flag_rounded,
                maxLines: 2,
              ),

              const SizedBox(height: 16),

              // ─── Notes ───────────────────────────────
              AppInput(
                controller: _notesCtrl,
                hint: 'Any notes for the driver? (optional)',
                label: 'Notes',
                prefixIcon: Icons.note_outlined,
              ),

              const SizedBox(height: 32),

              // ─── Request button ───────────────────────
              AppButton(
                label: 'Request Ride — \$${_rideFee.toStringAsFixed(2)}',
                icon: Icons.directions_car_rounded,
                isLoading: _isRequesting,
                color: AppColors.primary,
                textColor: AppColors.background,
                onPressed: _requestRide,
              ),

              const SizedBox(height: 16),

              // ─── Commission note ──────────────────────
              GlassCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.payments_outlined,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pay \$${_rideFee.toStringAsFixed(2)} cash to your driver when they arrive.',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.warning),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Fare info sheet ──────────────────────────────
  void _showFareInfo() {
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
            Text('How Fares Work', style: AppTextStyles.headlineMedium),
            const SizedBox(height: 16),
            _fareRow('Ride Fare', '\$${_rideFee.toStringAsFixed(2)}',
                AppColors.textPrimary),
            _fareRow('Driver Keeps (80%)',
                '\$${(_rideFee * 0.80).toStringAsFixed(2)}', AppColors.accent),
            _fareRow(
                'Platform Fee (20%)',
                '\$${(_rideFee * 0.20).toStringAsFixed(2)}',
                AppColors.textHint),
            const SizedBox(height: 16),
            Text(
              'You pay the driver in cash. The platform '
              'collects its 20% commission separately '
              'at end of day.',
              style: AppTextStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fareRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium),
          Text(value, style: AppTextStyles.labelLarge.copyWith(color: color)),
        ],
      ),
    );
  }

  // ─── Error snackbar ───────────────────────────────
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
