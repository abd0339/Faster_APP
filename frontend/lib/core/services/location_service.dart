import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  // ─── Request permission ───────────────────────────
  Future<bool> requestPermission() async {
    // Web: browser handles permission prompt automatically
    if (kIsWeb) return true;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  // ─── Get current position ─────────────────────────
  // geolocator 10.1.1 — uses desiredAccuracy + timeLimit directly.
  // (locationSettings param only exists in geolocator ^13+)
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      return null;
    }
  }

  // ─── Stream live location (for driver) ────────────
  // getPositionStream uses LocationSettings in both 10.x and 13.x — no change
  Stream<Position> getLiveLocationStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // meters — matches backend update interval
      ),
    );
  }

  // ─── Check if location service is enabled ─────────
  Future<bool> isLocationEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }
}
