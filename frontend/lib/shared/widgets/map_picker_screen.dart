import 'dart:async';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/location_service.dart';
import 'google_places_search_field.dart';

/// MapPickerScreen
/// ────────────────────────────────────────────────────────
/// Full-screen OSM map where user drags to pick a location.
/// Returns a MapPickResult with address + coordinates.
/// Uses OpenStreetMap tiles — completely FREE, unlimited.
/// ────────────────────────────────────────────────────────
class MapPickResult {
  final String address;
  final double lat;
  final double lng;

  const MapPickResult({
    required this.address,
    required this.lat,
    required this.lng,
  });
}

class MapPickerScreen extends StatefulWidget {
  /// Initial location to center the map on.
  /// If null, tries to get user's GPS location.
  final LatLng? initialLocation;

  /// Title shown in the header
  final String title;

  /// Confirm button label
  final String confirmLabel;

  const MapPickerScreen({
    super.key,
    this.initialLocation,
    this.title = 'Pick Location',
    this.confirmLabel = 'Confirm Location',
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  // Default center — Beirut, Lebanon
  static const _beirut = LatLng(33.8938, 35.5018);

  late LatLng _center;
  LatLng _pinLocation = _beirut;
  String _address = 'Move the map to set location';
  bool _isGeocoding = false;
  bool _isLoadingLocation = true;
  late MapController _mapController;
  Timer? _geocodeDebounce;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _center = widget.initialLocation ?? _beirut;
    _pinLocation = _center;

    if (widget.initialLocation != null) {
      _isLoadingLocation = false;
      _reverseGeocode(_center);
    } else {
      _detectLocation();
    }
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    super.dispose();
  }

  // ─── Try to get user's current GPS ────────────────
  Future<void> _detectLocation() async {
    try {
      final pos = await LocationService.instance.getCurrentPosition();
      if (pos != null && mounted) {
        final loc = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _center = loc;
          _pinLocation = loc;
          _isLoadingLocation = false;
        });
        // Move map to GPS location
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _mapController.move(loc, 16.0);
          }
        });
        _reverseGeocode(loc);
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoadingLocation = false);
      _reverseGeocode(_center);
    }
  }

  // ─── Reverse geocode with Nominatim (free) ─────────
  Future<void> _reverseGeocode(LatLng location) async {
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() => _isGeocoding = true);

      try {
        final response = await dio.Dio().get(
          'https://nominatim.openstreetmap.org/reverse',
          queryParameters: {
            'format': 'json',
            'lat': location.latitude.toString(),
            'lon': location.longitude.toString(),
            'zoom': '18',
            'addressdetails': '1',
          },
          options: dio.Options(
            headers: {
              'Accept-Language': 'en',
              'User-Agent': 'FasterApp/1.0',
            },
            receiveTimeout: const Duration(seconds: 6),
          ),
        );

        if (!mounted) return;
        final addr = response.data?['display_name'] as String?;
        setState(() => _address = addr ?? 'Location selected');
      } catch (_) {
        if (mounted) {
          setState(() => _address = '${location.latitude.toStringAsFixed(5)}, '
              '${location.longitude.toStringAsFixed(5)}');
        }
      } finally {
        if (mounted) setState(() => _isGeocoding = false);
      }
    });
  }

  // ─── Map moved — update pin + geocode ──────────────
  void _onMapPositionChanged(MapPosition position, bool hasGesture) {
    if (!hasGesture) return;
    // Assign first, then null-check — Dart narrows LatLng? to LatLng after check
    final center = position.center;
    if (center == null) return;
    setState(() {
      _pinLocation = center; // LatLng — safe after null check
      _address = 'Finding address...';
    });
    _reverseGeocode(center); // LatLng — safe after null check
  }

  // ─── Confirm selection ─────────────────────────────
  void _confirm() {
    Navigator.pop(
      context,
      MapPickResult(
        address: _address,
        lat: _pinLocation.latitude,
        lng: _pinLocation.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header ──────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              color: AppColors.background,
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
                      Text(widget.title, style: AppTextStyles.headlineMedium),
                      Text('Drag the map to set location',
                          style: AppTextStyles.caption),
                    ],
                  ),
                ),
                // My location button
                GestureDetector(
                  onTap: _detectLocation,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.my_location_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                ),
              ]),
            ),

            // ─── Map ─────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // OSM Map (free tiles)
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 15.0,
                      minZoom: 4.0,
                      maxZoom: 19.0,
                      onPositionChanged: _onMapPositionChanged,
                    ),
                    children: [
                      // OpenStreetMap tile layer — FREE
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.faster.app',
                        tileBuilder: (context, child, tile) => child,
                      ),

                      // Optional: Marker for visual reference
                      // The center of the screen IS the pin
                      // so no marker needed — crosshair handles it
                    ],
                  ),

                  // ─── Center crosshair pin ─────────
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Shadow under pin
                        Container(
                          width: 20,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Pin body
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                blurRadius: 16,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        // Pin stem
                        Container(
                          width: 3,
                          height: 16,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),

                  // ─── Loading overlay ──────────────
                  if (_isLoadingLocation)
                    Container(
                      color: AppColors.background.withValues(alpha: 0.7),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: AppColors.primary),
                            SizedBox(height: 16),
                            Text('Finding your location...',
                                style: AppTextStyles.bodyMedium),
                          ],
                        ),
                      ),
                    ),

                  // ─── OSM attribution ──────────────
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      color: Colors.white.withValues(alpha: 0.7),
                      child: const Text(
                        '© OpenStreetMap contributors',
                        style: TextStyle(fontSize: 8, color: Colors.black54),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ─── Bottom address card + confirm ────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _isGeocoding
                          ? const SizedBox(
                              key: ValueKey('loading'),
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: AppColors.primary, strokeWidth: 2))
                          : const Icon(
                              key: ValueKey('icon'),
                              Icons.location_on_rounded,
                              color: AppColors.primary,
                              size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Selected Location',
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textHint)),
                          const SizedBox(height: 2),
                          Text(
                            _address,
                            style: AppTextStyles.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // Coordinates display
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.gps_fixed_rounded,
                            color: AppColors.accent, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '${_pinLocation.latitude.toStringAsFixed(5)}, '
                          '${_pinLocation.longitude.toStringAsFixed(5)}',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.accent, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isGeocoding ? null : _confirm,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: Text(widget.confirmLabel,
                          style: AppTextStyles.labelLarge),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.background,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
