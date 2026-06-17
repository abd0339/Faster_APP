import 'dart:convert';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'customer_order_tracking_screen.dart';

// ─── Saved destination model ──────────────────────────
class SavedDestination {
  final String id;
  final String name;
  final String address;
  final String icon;
  double? lat;
  double? lng;

  SavedDestination({
    required this.id,
    required this.name,
    required this.address,
    required this.icon,
    this.lat,
    this.lng,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'icon': icon,
        'lat': lat,
        'lng': lng,
      };

  factory SavedDestination.fromJson(Map<String, dynamic> j) => SavedDestination(
        id: j['id'] as String,
        name: j['name'] as String,
        address: j['address'] as String,
        icon: j['icon'] as String,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
      );
}

class CustomerRideScreen extends StatefulWidget {
  const CustomerRideScreen({super.key});
  @override
  State<CustomerRideScreen> createState() => _CustomerRideScreenState();
}

class _CustomerRideScreenState extends State<CustomerRideScreen> {
  final _pickupCtrl = TextEditingController();
  final _dropoffCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  double? _pickupLat, _pickupLng, _dropoffLat, _dropoffLng;
  bool _isDetecting = false, _isRequesting = false;
  String _selectedVehicle = 'MOTO';
  List<SavedDestination> _saved = [];

  static const _vehicles = [
    {'value': 'MOTO', 'label': 'Moto', 'icon': '🏍️', 'fare': 2.50},
    {'value': 'CAR', 'label': 'Car', 'icon': '🚗', 'fare': 5.00},
    {'value': 'TOKTOK', 'label': 'Toktok', 'icon': '🛺', 'fare': 3.00},
  ];

  double get _fare =>
      (_vehicles.firstWhere((v) => v['value'] == _selectedVehicle,
              orElse: () => _vehicles[0])['fare'] as num)
          .toDouble();

  @override
  void initState() {
    super.initState();
    _loadSaved();
    if (!kIsWeb) _detectPickup();
  }

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('saved_destinations') ?? '[]';
      final list = (jsonDecode(raw) as List)
          .map((e) => SavedDestination.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() => _saved = list);
    } catch (_) {}
  }

  Future<void> _persistSaved() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('saved_destinations',
          jsonEncode(_saved.map((d) => d.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _detectPickup() async {
    if (!mounted) return;
    setState(() => _isDetecting = true);
    try {
      final pos = await LocationService.instance.getCurrentPosition();
      if (pos == null || !mounted) return;
      setState(() {
        _pickupLat = pos.latitude;
        _pickupLng = pos.longitude;
      });
      try {
        final r = await dio.Dio().get(
          'https://nominatim.openstreetmap.org/reverse',
          queryParameters: {
            'format': 'json',
            'lat': pos.latitude.toString(),
            'lon': pos.longitude.toString()
          },
          options: dio.Options(
              headers: {'Accept-Language': 'en', 'User-Agent': 'FasterApp/1.0'},
              receiveTimeout: const Duration(seconds: 5)),
        );
        if (mounted)
          setState(() =>
              _pickupCtrl.text = r.data?['display_name']?.toString() ?? '');
      } catch (_) {
        if (mounted)
          setState(() => _pickupCtrl.text =
              '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}');
      }
    } catch (_) {}
    if (mounted) setState(() => _isDetecting = false);
  }

  void _useDestination(SavedDestination d) {
    if (!kIsWeb) HapticFeedback.selectionClick();
    setState(() {
      _dropoffCtrl.text = d.address;
      _dropoffLat = d.lat;
      _dropoffLng = d.lng;
    });
  }

  Future<void> _showSaveSheet({SavedDestination? existing}) async {
    if (_saved.length >= 3 && existing == null) {
      _showErr('Max 3 saved places allowed');
      return;
    }
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final addrCtrl = TextEditingController(text: existing?.address ?? '');
    String icon = existing?.icon ?? '📍';
    const icons = ['🏠', '💼', '☕', '🏋️', '🏥', '🏫', '🛒', '📍', '❤️', '⭐'];

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Padding(
          padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: AppColors.glassBorder,
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text(existing == null ? 'Save New Place' : 'Edit Place',
                style: AppTextStyles.headlineMedium),
            const SizedBox(height: 16),
            // Icon row
            SizedBox(
              height: 48,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: icons.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final sel = icon == icons[i];
                    return GestureDetector(
                        onTap: () => ss(() => icon = icons[i]),
                        child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color: sel
                                    ? AppColors.primary.withValues(alpha: 0.2)
                                    : AppColors.glassWhite,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: sel
                                        ? AppColors.primary
                                        : AppColors.glassBorder,
                                    width: sel ? 2 : 1)),
                            child: Center(
                                child: Text(icons[i],
                                    style: const TextStyle(fontSize: 20)))));
                  }),
            ),
            const SizedBox(height: 14),
            AppInput(
                controller: nameCtrl,
                hint: 'Home, Office, Gym...',
                label: 'Name',
                prefixIcon: Icons.label_outline_rounded),
            const SizedBox(height: 10),
            AppInput(
                controller: addrCtrl,
                hint: 'Full address or area',
                label: 'Address',
                prefixIcon: Icons.location_on_outlined,
                maxLines: 2),
            const SizedBox(height: 20),
            Row(children: [
              if (existing != null) ...[
                Expanded(
                    child: AppButton(
                        label: 'Delete',
                        icon: Icons.delete_outline_rounded,
                        color: AppColors.error,
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() =>
                              _saved.removeWhere((d) => d.id == existing.id));
                          _persistSaved();
                        })),
                const SizedBox(width: 12),
              ],
              Expanded(
                  child: AppButton(
                      label: 'Save',
                      icon: Icons.save_outlined,
                      color: AppColors.accent,
                      textColor: AppColors.background,
                      onPressed: () {
                        if (nameCtrl.text.trim().isEmpty ||
                            addrCtrl.text.trim().isEmpty) return;
                        Navigator.pop(ctx);
                        final d = SavedDestination(
                          id: existing?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          name: nameCtrl.text.trim(),
                          address: addrCtrl.text.trim(),
                          icon: icon,
                        );
                        setState(() {
                          if (existing != null) {
                            final idx =
                                _saved.indexWhere((s) => s.id == existing.id);
                            if (idx >= 0) _saved[idx] = d;
                          } else {
                            _saved.add(d);
                          }
                        });
                        _persistSaved();
                      })),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _requestRide() async {
    if (_pickupCtrl.text.trim().isEmpty) {
      _showErr('Set pickup location');
      return;
    }
    if (_dropoffCtrl.text.trim().isEmpty) {
      _showErr('Enter destination');
      return;
    }
    if (!mounted) return;
    setState(() => _isRequesting = true);
    try {
      final vLabel =
          (_vehicles.firstWhere((v) => v['value'] == _selectedVehicle)['label']
              as String);
      final res = await ApiService.instance.post(ApiConstants.orders, data: {
        'totalPrice': 0.00,
        'deliveryFee': _fare,
        'pickupAddress': _pickupCtrl.text.trim(),
        'pickupLat': _pickupLat,
        'pickupLng': _pickupLng,
        'deliveryAddress': _dropoffCtrl.text.trim(),
        'deliveryLat': _dropoffLat,
        'deliveryLng': _dropoffLng,
        'customerNotes': '[$vLabel] ${_notesCtrl.text.trim()}',
        'orderType': 'MOBILITY',
        'isO2O': false,
      });
      final orderData = res.data as Map<String, dynamic>;
      final orderId = orderData['id'] as int?;
      final tracking = orderData['trackingCode'] as String? ?? '';
      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => CustomerOrderTrackingScreen(
                  orderId: orderId ?? 0, trackingCode: tracking)));
    } catch (e) {
      if (mounted) _showErr(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(children: [
              GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.glassWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.glassBorder)),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary, size: 20))),
              const SizedBox(width: 14),
              Text('Request a Ride', style: AppTextStyles.headlineMedium),
            ]),
          ),
          const SizedBox(height: 16),

          // Vehicle selector
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _vehicles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final v = _vehicles[i];
                final isSel = _selectedVehicle == v['value'];
                return GestureDetector(
                  onTap: () {
                    if (!kIsWeb) HapticFeedback.selectionClick();
                    setState(() => _selectedVehicle = v['value'] as String);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 96,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: isSel
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : AppColors.glassWhite,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: isSel
                                ? AppColors.primary
                                : AppColors.glassBorder,
                            width: isSel ? 2 : 1),
                        boxShadow: isSel
                            ? [
                                BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.2),
                                    blurRadius: 12)
                              ]
                            : null),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(v['icon'] as String,
                              style: const TextStyle(fontSize: 26)),
                          const SizedBox(height: 4),
                          Text(v['label'] as String,
                              style: AppTextStyles.caption.copyWith(
                                  color: isSel
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                  fontWeight: FontWeight.w700)),
                          Text('\$${(v['fare'] as num).toStringAsFixed(2)}',
                              style: AppTextStyles.caption.copyWith(
                                  color: isSel
                                      ? AppColors.primary
                                      : AppColors.textHint)),
                        ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Scrollable form
          Expanded(
              child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Fare card
              GlassCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.payments_outlined,
                        color: AppColors.accent, size: 20),
                    const SizedBox(width: 10),
                    Text('Cash fare: ', style: AppTextStyles.bodyMedium),
                    Text('\$${_fare.toStringAsFixed(2)}',
                        style: AppTextStyles.price),
                    const Spacer(),
                    Text('Pay driver on arrival', style: AppTextStyles.caption),
                  ])),
              const SizedBox(height: 20),

              // Pickup
              Row(children: [
                Text('Pickup', style: AppTextStyles.headlineSmall),
                const Spacer(),
                if (!kIsWeb)
                  GestureDetector(
                    onTap: _detectPickup,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3))),
                      child: _isDetecting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  color: AppColors.primary, strokeWidth: 2))
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.my_location_rounded,
                                  color: AppColors.primary, size: 14),
                              const SizedBox(width: 4),
                              Text('GPS',
                                  style: AppTextStyles.caption.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600)),
                            ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              AppInput(
                  controller: _pickupCtrl,
                  hint: 'Your current location',
                  label: 'Pickup Point',
                  prefixIcon: Icons.radio_button_checked_rounded,
                  maxLines: 2),

              const SizedBox(height: 20),

              // Destination
              Row(children: [
                Text('Destination', style: AppTextStyles.headlineSmall),
                const Spacer(),
                if (_saved.length < 3)
                  GestureDetector(
                    onTap: () => _showSaveSheet(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.3))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.bookmark_add_outlined,
                            color: AppColors.accent, size: 14),
                        const SizedBox(width: 4),
                        Text('Save',
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),

              // Saved destinations chips
              if (_saved.isNotEmpty) ...[
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _saved.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final d = _saved[i];
                      final isSel = _dropoffCtrl.text == d.address;
                      return GestureDetector(
                        onTap: () => _useDestination(d),
                        onLongPress: () => _showSaveSheet(existing: d),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: isSel
                                  ? AppColors.accent.withValues(alpha: 0.15)
                                  : AppColors.glassWhite,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: isSel
                                      ? AppColors.accent
                                      : AppColors.glassBorder,
                                  width: isSel ? 2 : 1)),
                          child: Row(children: [
                            Text(d.icon, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(d.name,
                                      style: AppTextStyles.caption.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: isSel
                                              ? AppColors.accent
                                              : AppColors.textPrimary)),
                                  SizedBox(
                                      width: 90,
                                      child: Text(d.address,
                                          style: AppTextStyles.caption,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)),
                                ]),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                Text('Long press to edit a saved place',
                    style: AppTextStyles.caption),
                const SizedBox(height: 8),
              ],

              GooglePlacesSearchField(
                hint: 'Where are you going?',
                label: 'Destination',
                prefixIcon: Icons.flag_rounded,
                apiKey: AppConfig.googlePlacesKey,
                onPlaceSelected: (result) {
                  _dropoffCtrl.text = result.address;
                  _dropoffLat = result.lat;
                  _dropoffLng = result.lng;
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              AppInput(
                  controller: _notesCtrl,
                  hint: 'Notes for driver (optional)',
                  label: 'Notes',
                  prefixIcon: Icons.note_outlined),
              const SizedBox(height: 24),

              AppButton(
                label:
                    'Request ${(_vehicles.firstWhere((v) => v['value'] == _selectedVehicle)['label'] as String)} — \$${_fare.toStringAsFixed(2)}',
                icon: Icons.directions_car_rounded,
                isLoading: _isRequesting,
                color: AppColors.primary,
                textColor: AppColors.background,
                onPressed: _requestRide,
              ),
            ]),
          )),
        ]),
      ),
    );
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }
}
