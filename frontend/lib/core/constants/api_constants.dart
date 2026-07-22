import '../constants/app_config.dart';

class ApiConstants {
  ApiConstants._();

  // ─── Base URL ─────────────────────────────────────
  // Read from .env via AppConfig — set in frontend/.env
  // Dev:  BACKEND_URL=http://localhost:8080
  // Prod: BACKEND_URL=https://your-domain.com
  static String get baseUrl => AppConfig.backendUrl;

  // ─── WebSocket URL ────────────────────────────────
  // Same host as REST API, /ws path
  static String get wsUrl => '${AppConfig.backendUrl}/ws';

  // ─── Auth ─────────────────────────────────────────
  static const String register = '/api/auth/register';
  static const String login = '/api/auth/login';
  static const String verifyOtp = '/api/auth/verify-otp';
  static const String resendOtp = '/api/auth/resend-otp';

  // ─── Merchant ─────────────────────────────────────
  static const String categories = '/api/merchant/categories';
  static const String items = '/api/merchant/items';
  static const String schedule = '/api/merchant/schedule';
  static const String offers = '/api/merchant/offers';
  static const String scheduleBulk = '/api/merchant/schedule/bulk';
  static String customerLookup(String phone) =>
      '/api/merchant/customer/lookup?phone=${Uri.encodeComponent(phone)}';

  // ─── Driver ───────────────────────────────────────
  static const String driverOnline = '/api/driver/online';
  static const String driverOffline = '/api/driver/offline';
  static const String driverLocation = '/api/driver/location';
  static const String driverMode = '/api/driver/mode';
  static const String driverStatus = '/api/driver/status';

  // Driver document upload/view — docType is one of
  // PROFILE_PHOTO / NATIONAL_ID / LICENSE_FRONT / LICENSE_BACK
  static String driverDocumentUpload(String docType) =>
      '/api/driver/documents/$docType';
  static String driverDocumentView(String docType) =>
      '/api/driver/documents/$docType';

  // Admin viewing a specific driver's document
  static String adminDriverDocumentView(int driverId, String docType) =>
      '/api/admin/drivers/$driverId/documents/$docType';

  // ─── Orders ───────────────────────────────────────
  static const String orders = '/api/orders';

  // NEW — customer submits feedback after delivery confirmation
  static String orderFeedback(int orderId) => '/api/orders/$orderId/feedback';
  static const String driverRating = '/api/driver/rating';

  static const String merchantOrders = '/api/orders/merchant';
  static const String driverOrders = '/api/orders/driver';
  static const String activeOrders = '/api/orders/driver/active';
  static const String customerOrders = '/api/orders/customer';

  // ─── Ledger ───────────────────────────────────────
  static const String myLedger = '/api/ledger/my';
  static const String myDebt = '/api/ledger/my/debt';

  // ─── Admin ────────────────────────────────────────
  static const String adminStats = '/api/admin/stats';
  static const String adminUsers = '/api/admin/users';
  static const String adminDrivers = '/api/admin/drivers';
  static const String adminOrders = '/api/admin/orders';
  static const String adminLedger = '/api/admin/ledger';

  // NEW — Feedback tab
  static const String adminFeedback = '/api/admin/feedback';
  static const String adminFeedbackUnresolved =
      '/api/admin/feedback/unresolved';
  static String adminResolveFeedback(int id) =>
      '/api/admin/feedback/$id/resolve';
  static const String adminRevenue = '/api/admin/revenue';
  static const String adminDriversPending = '/api/admin/drivers/pending';
  static const String adminDriversBlocked = '/api/admin/drivers/blocked';
  static const String adminMerchants = '/api/admin/merchants';
  static const String adminOrdersDisputed = '/api/admin/orders/disputed';
  static const String allStores = '/api/store/all';

  // ─── Admin — dynamic ──────────────────────────────
  static String adminUserById(int id) => '/api/admin/users/$id';
  static String adminBlockUser(int id) => '/api/admin/users/$id/block';
  static String adminUnblockUser(int id) => '/api/admin/users/$id/unblock';
  static String adminDeactivateUser(int id) =>
      '/api/admin/users/$id/deactivate';
  static String adminApproveDriver(int id) => '/api/admin/drivers/$id/approve';
  static String adminRejectDriver(int id) => '/api/admin/drivers/$id/reject';
  static String adminDriverDebt(int id) => '/api/admin/drivers/$id/debt';
  static String adminSettleDriver(int id) => '/api/admin/drivers/$id/settle';
  static String adminSettleMerchant(int id) =>
      '/api/admin/merchants/$id/settle';
  static String adminResolveOrder(int id) => '/api/admin/orders/$id/resolve';
  static String adminDriverLedger(int id) => '/api/admin/ledger/driver/$id';
  static String adminMerchantLedger(int id) => '/api/admin/ledger/merchant/$id';

  // ─── Public ───────────────────────────────────────
  static String storeMenu(int merchantId) => '/api/store/$merchantId/menu';
  static String storeStatus(int merchantId) => '/api/store/$merchantId/status';
  // Human-facing page URL (served by Flutter itself)
  static String trackOrder(String code) => '/tracking/public/$code';

  // NEW — the JSON data endpoints PublicTrackingScreen calls.
  // Moved off /tracking/public/** since that path is now the
  // human page URL, served by the Flutter SPA via nginx.
  static String publicTrackingData(String code) => '/api/tracking/public/$code';
  static String publicTrackingLocation(String code) =>
      '/api/tracking/public/$code/location';

  static String orderById(int id) => '/api/orders/$id';

  // ─── Dynamic ──────────────────────────────────────
  static String orderAccept(int id) => '/api/orders/$id/accept';
  static String orderStatus(int id) => '/api/orders/$id/status';
  static String itemToggle(int id) => '/api/merchant/items/$id/toggle';
  static String itemSnooze(int id) => '/api/merchant/items/$id/snooze';
  static String itemUnsnooze(int id) => '/api/merchant/items/$id/unsnooze';
  static String itemImage(int id) => '/api/merchant/items/$id/image';
  static String categoryById(int id) => '/api/merchant/categories/$id';
  static String offerById(int id) => '/api/merchant/offers/$id';
  static String blockUser(int id) => '/api/admin/users/$id/block';
  static String unblockUser(int id) => '/api/admin/users/$id/unblock';
  static String settleDriver(int id) => '/api/admin/drivers/$id/settle';
  static String placeOrder(int merchantId) => '/api/orders';
  static String applyOffer(int orderId, int offerId) =>
      '/api/orders/$orderId/offer/$offerId';
  static String customerOrderById(int id) => '/api/orders/$id';

  // ─── WebSocket topics ─────────────────────────────
  static String orderTopic(int id) => '/topic/order/$id';
  static String driverTopic(int id) => '/topic/driver/$id';
  static String merchantTopic(int id) => '/topic/merchant/$id';
}
