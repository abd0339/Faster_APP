import 'dart:async';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import 'map_picker_screen.dart';

/// PlaceResult — returned after user picks an address
class PlaceResult {
  final String address;
  final double? lat;
  final double? lng;
  final String? placeId;

  const PlaceResult({
    required this.address,
    this.lat,
    this.lng,
    this.placeId,
  });
}

/// SmartAddressField (exported as GooglePlacesSearchField)
/// ─────────────────────────────────────────────────────────
/// Hybrid strategy:
///   TYPE → Google Places autocomplete (if key configured)
///   MAP  → OSM full-screen map picker (always free, always shown)
///
/// The map button is ALWAYS visible.
/// Even without a Google key, user can pick on map.
/// ─────────────────────────────────────────────────────────
class GooglePlacesSearchField extends StatefulWidget {
  final String hint;
  final String label;
  final IconData prefixIcon;
  final String apiKey;
  final ValueChanged<PlaceResult> onPlaceSelected;
  final TextEditingController? controller;
  final int maxLines;
  final double? initialLat;
  final double? initialLng;

  const GooglePlacesSearchField({
    super.key,
    required this.hint,
    required this.label,
    required this.apiKey,
    required this.onPlaceSelected,
    this.prefixIcon = Icons.location_on_outlined,
    this.controller,
    this.maxLines = 1,
    this.initialLat,
    this.initialLng,
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

  bool get _hasApiKey =>
      widget.apiKey.isNotEmpty &&
      widget.apiKey != 'YOUR_GOOGLE_PLACES_KEY_HERE';

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

  void _onChanged(String value) {
    setState(() {});
    if (!_hasApiKey) return;
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

  Future<void> _searchPlaces(String query) async {
    if (!_hasApiKey || !mounted) return;
    setState(() => _isSearching = true);
    try {
      final r = await _dio.get(_autocompleteUrl, queryParameters: {
        'input': query,
        'key': widget.apiKey,
        'components': 'country:lb',
        'language': 'en',
        'types': 'geocode|establishment',
      });
      if (!mounted) return;
      final preds =
          (r.data['predictions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() {
        _predictions = preds;
        _showDropdown = preds.isNotEmpty;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _predictions = [];
          _showDropdown = false;
        });
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<PlaceResult> _getPlaceDetails(String placeId, String desc) async {
    try {
      final r = await _dio.get(_detailsUrl, queryParameters: {
        'place_id': placeId,
        'key': widget.apiKey,
        'fields': 'geometry,formatted_address',
      });
      final result = r.data['result'] as Map<String, dynamic>?;
      final loc = result?['geometry']?['location'];
      return PlaceResult(
        address: result?['formatted_address'] ?? desc,
        lat: (loc?['lat'] as num?)?.toDouble(),
        lng: (loc?['lng'] as num?)?.toDouble(),
        placeId: placeId,
      );
    } catch (_) {
      return PlaceResult(address: desc, placeId: placeId);
    }
  }

  Future<void> _selectPrediction(Map<String, dynamic> pred) async {
    final desc = pred['description'] as String? ?? '';
    final placeId = pred['place_id'] as String? ?? '';
    _ctrl.text = desc;
    setState(() {
      _predictions = [];
      _showDropdown = false;
    });
    final result = await _getPlaceDetails(placeId, desc);
    widget.onPlaceSelected(result);
  }

  // ─── Open OSM full-screen map picker ─────────────────
  Future<void> _openMapPicker() async {
    FocusScope.of(context).unfocus();

    final LatLng? initialLoc =
        (widget.initialLat != null && widget.initialLng != null)
            ? LatLng(widget.initialLat!, widget.initialLng!)
            : null;

    final result = await Navigator.push<MapPickResult>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          title: widget.label,
          confirmLabel: 'Confirm ${widget.label}',
          initialLocation: initialLoc,
        ),
        fullscreenDialog: true,
      ),
    );

    if (result != null && mounted) {
      _ctrl.text = result.address;
      setState(() {
        _showDropdown = false;
        _predictions = [];
      });
      widget.onPlaceSelected(PlaceResult(
        address: result.address,
        lat: result.lat,
        lng: result.lng,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Input + Map button row ───────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Text input
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.glassWhite,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _showDropdown
                        ? AppColors.primary
                        : AppColors.glassBorder,
                  ),
                ),
                child: TextField(
                  controller: _ctrl,
                  onChanged: _onChanged,
                  maxLines: widget.maxLines,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: AppTextStyles.bodyMedium,
                    labelText: widget.label,
                    labelStyle: AppTextStyles.caption
                        .copyWith(color: AppColors.textHint),
                    prefixIcon: Icon(widget.prefixIcon,
                        color: AppColors.textHint, size: 18),
                    suffixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    color: AppColors.primary, strokeWidth: 2)))
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
                                    color: AppColors.textHint, size: 18))
                            : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // ─── MAP BUTTON — always visible ─────────
            // This is the core of the hybrid strategy.
            // Tapping opens OSM full-screen map (free).
            // User drags, drops pin, confirms — address fills in.
            Tooltip(
              message: 'Pick on Map',
              child: GestureDetector(
                onTap: _openMapPicker,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.map_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),

        // ─── Autocomplete dropdown (only if Google key) ──
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
                    offset: const Offset(0, 4)),
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

        // ─── Helper hint ──────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded,
                size: 12, color: AppColors.textHint),
            const SizedBox(width: 4),
            Text(
              _hasApiKey
                  ? 'Type to search or tap 🗺 to pick on map'
                  : 'Type your address or tap 🗺 to pick on map',
              style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
            ),
          ]),
        ),
      ],
    );
  }
}
