import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  AppConfig._();

  // ─── Backend URL ──────────────────────────────────
  static String get backendUrl =>
      dotenv.env['BACKEND_URL'] ?? 'http://localhost:8080';

  // ─── Google Places API Key ─────────────────────────
  static String get googlePlacesKey =>
      dotenv.env['GOOGLE_PLACES_API_KEY'] ?? '';

  // ─── Admin WhatsApp ────────────────────────────────
  static String get adminWhatsApp =>
      dotenv.env['ADMIN_WHATSAPP'] ?? '96100000000';

  // ─── Is Google Places enabled? ────────────────────
  static bool get hasGooglePlaces => googlePlacesKey.isNotEmpty;

  // ─── Commission rates ──────────────────────────────
  static double get driverCommissionRate =>
      double.tryParse(dotenv.env['DRIVER_COMMISSION_RATE'] ?? '') ?? 0.20;

  static double get merchantCommissionRate =>
      double.tryParse(dotenv.env['MERCHANT_COMMISSION_RATE'] ?? '') ?? 0.10;

  // ─── Static config (no secrets) ────────────────────
  static const Map<String, double> rideFares = {
    'MOTO': 2.50,
    'CAR': 5.00,
    'TOKTOK': 3.00,
  };

  static const double defaultDeliveryFee = 2.00;
  static const double searchRadiusKm = 5.0;
}
