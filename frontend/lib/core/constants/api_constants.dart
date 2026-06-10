class ApiConstants {
  ApiConstants._();

  // ─── Base URL ─────────────────────────────────────
  // Change to your server IP when deploying
  static const String baseUrl = 'http://localhost:8080';

  // ─── Auth ─────────────────────────────────────────
  static const String register = '/api/auth/register';
  static const String login = '/api/auth/login';

  // ─── Merchant ─────────────────────────────────────
  static const String categories = '/api/merchant/categories';
  static const String items = '/api/merchant/items';
  static const String schedule = '/api/merchant/schedule';
  static const String offers = '/api/merchant/offers';

  // ─── Driver ───────────────────────────────────────
  static const String driverOnline = '/api/driver/online';
  static const String driverOffline = '/api/driver/offline';
  static const String driverLocation = '/api/driver/location';
  static const String driverMode = '/api/driver/mode';
  static const String driverStatus = '/api/driver/status';

  // ─── Orders ───────────────────────────────────────
  static const String orders = '/api/orders';
  static const String merchantOrders = '/api/orders/merchant';
  static const String driverOrders = '/api/orders/driver';
  static const String activeOrders = '/api/orders/driver/active';

  // ─── Ledger ───────────────────────────────────────
  static const String myLedger = '/api/ledger/my';
  static const String myDebt = '/api/ledger/my/debt';

  // ─── Admin ────────────────────────────────────────
  static const String adminStats = '/api/admin/stats';
  static const String adminUsers = '/api/admin/users';
  static const String adminDrivers = '/api/admin/drivers';
  static const String adminOrders = '/api/admin/orders';
  static const String adminLedger = '/api/admin/ledger';
  static const String adminRevenue = '/api/admin/revenue';

  // ─── Public ───────────────────────────────────────
  static String storeMenu(int merchantId) => '/api/store/$merchantId/menu';
  static String storeStatus(int merchantId) => '/api/store/$merchantId/status';
  static String trackOrder(String code) => '/tracking/public/$code';

  // ─── Dynamic ──────────────────────────────────────
  static String orderAccept(int id) => '/api/orders/$id/accept';
  static String orderStatus(int id) => '/api/orders/$id/status';
  static String itemToggle(int id) => '/api/merchant/items/$id/toggle';
  static String itemSnooze(int id) => '/api/merchant/items/$id/snooze';
  static String itemImage(int id) => '/api/merchant/items/$id/image';
  static String blockUser(int id) => '/api/admin/users/$id/block';
  static String unblockUser(int id) => '/api/admin/users/$id/unblock';
  static String settleDriver(int id) => '/api/admin/drivers/$id/settle';

  // ─── WebSocket ────────────────────────────────────
  static const String wsUrl = 'http://localhost:8080/ws';
  static String orderTopic(int id) => '/topic/order/$id';
  static String driverTopic(int id) => '/topic/driver/$id';
  static String merchantTopic(int id) => '/topic/merchant/$id';
}
