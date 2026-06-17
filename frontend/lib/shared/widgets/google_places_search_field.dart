import 'dart:async';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// PlaceResult — what we get back after the user picks an address
class PlaceResult {
  final String address; // human-readable full address
  final double? lat; // latitude
  final double? lng; // longitude
  final String? placeId; // Google Place ID (for details)

  const PlaceResult({
    required this.address,
    this.lat,
    this.lng,
    this.placeId,
  });
}

/// GooglePlacesSearchField
/// ─────────────────────────────────────────────────────────
/// Uses Google Places Autocomplete API ONLY for address search.
/// Cost: $2.83 per 1000 requests (only charged when user picks)
/// Map display: flutter_map + OSM (FREE, unlimited)
/// ─────────────────────────────────────────────────────────
class GooglePlacesSearchField extends StatefulWidget {
  final String hint;
  final String label;
  final IconData prefixIcon;
  final String apiKey;
  final ValueChanged<PlaceResult> onPlaceSelected;
  final TextEditingController? controller;
  final int maxLines;

  const GooglePlacesSearchField({
    super.key,
    required this.hint,
    required this.label,
    required this.apiKey,
    required this.onPlaceSelected,
    this.prefixIcon = Icons.location_on_outlined,
    this.controller,
    this.maxLines = 1,
  });

  @override
  State<GooglePlacesSearchField> createState() =>
      _GooglePlacesSearchFieldState();
}

class _GooglePlacesSearchFieldState extends State<GooglePlacesSearchField> {
  late TextEditingController _ctrl;
  Timer? _debounce;
  List<Map<String, dynamic>> _predictions = [];
  bool _isSearching = false;
  bool _showDropdown = false;
  final _dio = dio.Dio();

  static const _autocompleteUrl =
      'https://maps.googleapis.com/maps/api/place/autocomplete/json';
  static const _detailsUrl =
      'https://maps.googleapis.com/maps/api/place/details/json';

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  // ─── Debounced search — 400ms after user stops typing ─
  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.length < 3) {
      setState(() {
        _predictions = [];
        _showDropdown = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _searchPlaces(value);
    });
  }

  // ─── Call Google Places Autocomplete ──────────────────
  Future<void> _searchPlaces(String query) async {
    if (widget.apiKey.isEmpty ||
        widget.apiKey == 'YOUR_GOOGLE_PLACES_KEY_HERE') {
      // No API key — show nothing, user types manually
      return;
    }

    if (!mounted) return;
    setState(() => _isSearching = true);

    try {
      final response = await _dio.get(
        _autocompleteUrl,
        queryParameters: {
          'input': query,
          'key': widget.apiKey,
          // Bias results toward Lebanon
          'components': 'country:lb',
          'language': 'en',
          'types': 'geocode|establishment',
        },
      );

      if (!mounted) return;

      final data = response.data as Map<String, dynamic>;
      final predictions =
          (data['predictions'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      setState(() {
        _predictions = predictions;
        _showDropdown = predictions.isNotEmpty;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _predictions = [];
          _showDropdown = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // ─── Get lat/lng from Place ID ─────────────────────────
  Future<PlaceResult> _getPlaceDetails(
      String placeId, String description) async {
    try {
      final response = await _dio.get(
        _detailsUrl,
        queryParameters: {
          'place_id': placeId,
          'key': widget.apiKey,
          'fields': 'geometry,formatted_address',
        },
      );

      final data = response.data as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      final location = result?['geometry']?['location'];

      return PlaceResult(
        address: result?['formatted_address'] ?? description,
        lat: (location?['lat'] as num?)?.toDouble(),
        lng: (location?['lng'] as num?)?.toDouble(),
        placeId: placeId,
      );
    } catch (_) {
      return PlaceResult(address: description, placeId: placeId);
    }
  }

  // ─── User picks a prediction ──────────────────────────
  Future<void> _selectPrediction(Map<String, dynamic> prediction) async {
    final description = prediction['description'] as String? ?? '';
    final placeId = prediction['place_id'] as String? ?? '';

    _ctrl.text = description;
    setState(() {
      _predictions = [];
      _showDropdown = false;
    });

    // Get coordinates
    final result = await _getPlaceDetails(placeId, description);
    widget.onPlaceSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Input field ────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _showDropdown ? AppColors.primary : AppColors.glassBorder,
            ),
          ),
          child: TextField(
            controller: _ctrl,
            onChanged: _onChanged,
            maxLines: widget.maxLines,
            style:
                AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: AppTextStyles.bodyMedium,
              labelText: widget.label,
              labelStyle:
                  AppTextStyles.caption.copyWith(color: AppColors.textHint),
              prefixIcon:
                  Icon(widget.prefixIcon, color: AppColors.textHint, size: 18),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2),
                      ),
                    )
                  : _ctrl.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _ctrl.clear();
                            setState(() {
                              _predictions = [];
                              _showDropdown = false;
                            });
                          },
                          child: const Icon(Icons.clear_rounded,
                              color: AppColors.textHint, size: 18),
                        )
                      : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),

        // ─── Predictions dropdown ────────────────────
        if (_showDropdown && _predictions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: _predictions.map((pred) {
                final main =
                    pred['structured_formatting']?['main_text'] as String? ??
                        pred['description'] as String? ??
                        '';
                final secondary = pred['structured_formatting']
                        ?['secondary_text'] as String? ??
                    '';
                return InkWell(
                  onTap: () => _selectPrediction(pred),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.location_on_outlined,
                            color: AppColors.primary, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(main,
                                style: AppTextStyles.labelLarge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            if (secondary.isNotEmpty)
                              Text(secondary,
                                  style: AppTextStyles.caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const Icon(Icons.north_west_rounded,
                          color: AppColors.textHint, size: 14),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
