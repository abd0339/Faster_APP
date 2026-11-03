import '../constants/api_constants.dart';
import 'api_service.dart';

/// ExchangeRateService — fetches the current USD→LBP rate.
/// ────────────────────────────────────────────────────
/// Thin wrapper around GET /api/exchange-rate. The backend
/// owns the actual rate (manually set by an admin); this just
/// reads it so the frontend can convert amounts consistently
/// via [CurrencyConverter].
class ExchangeRateService {
  ExchangeRateService._();
  static final ExchangeRateService instance = ExchangeRateService._();

  Future<double> getCurrentRate() async {
    final res = await ApiService.instance.get(ApiConstants.exchangeRate);
    final rate = res.data['usdToLbpRate'] as num;
    return rate.toDouble();
  }
}
