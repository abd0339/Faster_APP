import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;

  // Data per tab — lazy loaded
  Map<String, dynamic>? _stats;
  List<dynamic> _drivers = [];
  List<dynamic> _pendingDrivers = [];
  List<dynamic> _merchants = [];
  List<dynamic> _orders = [];
  List<dynamic> _disputedOrders = [];
  List<dynamic> _ledger = [];

  // Loading flags per tab
  bool _statsLoading = true;
  bool _driversLoading = false;
  bool _merchantsLoading = false;
  bool _ordersLoading = false;
  bool _ledgerLoading = false;

  // Track which tabs have been loaded
  final Set<int> _loadedTabs = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentTab = _tabController.index);
        _loadTabIfNeeded(_tabController.index);
      }
    });
    _loadTab(0); // Load overview immediately
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadTabIfNeeded(int tab) {
    if (!_loadedTabs.contains(tab)) {
      _loadTab(tab);
    }
  }

  Future<void> _loadTab(int tab) async {
    _loadedTabs.add(tab);
    switch (tab) {
      case 0:
        await _loadStats();
        break;
      case 1:
        await _loadDrivers();
        break;
      case 2:
        await _loadMerchants();
        break;
      case 3:
        await _loadOrders();
        break;
      case 4:
        await _loadLedger();
        break;
    }
  }

  Future<void> _refreshCurrentTab() async {
    _loadedTabs.remove(_currentTab);
    await _loadTab(_currentTab);
  }

  // ─── LOAD STATS ───────────────────────────────────
  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _statsLoading = true);
    try {
      final res = await ApiService.instance.get(ApiConstants.adminStats);
      if (!mounted) return;
      setState(() => _stats = res.data as Map<String, dynamic>?);
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  // ─── LOAD DRIVERS ─────────────────────────────────
  Future<void> _loadDrivers() async {
    if (!mounted) return;
    setState(() => _driversLoading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.get(ApiConstants.adminDrivers),
        ApiService.instance.get(ApiConstants.adminDriversPending),
      ]);
      if (!mounted) return;
      final d = results[0].data;
      final p = results[1].data;
      setState(() {
        _drivers = d is List ? d : [];
        _pendingDrivers = p is List ? p : [];
      });
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _driversLoading = false);
    }
  }

  // ─── LOAD MERCHANTS ───────────────────────────────
  Future<void> _loadMerchants() async {
    if (!mounted) return;
    setState(() => _merchantsLoading = true);
    try {
      final res = await ApiService.instance.get(ApiConstants.adminMerchants);
      if (!mounted) return;
      final d = res.data;
      setState(() => _merchants = d is List ? d : []);
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _merchantsLoading = false);
    }
  }

  // ─── LOAD ORDERS ──────────────────────────────────
  Future<void> _loadOrders() async {
    if (!mounted) return;
    setState(() => _ordersLoading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.get(ApiConstants.adminOrders),
        ApiService.instance.get(ApiConstants.adminOrdersDisputed),
      ]);
      if (!mounted) return;
      final o = results[0].data;
      final d = results[1].data;
      setState(() {
        _orders = o is List ? o : [];
        _disputedOrders = d is List ? d : [];
      });
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _ordersLoading = false);
    }
  }

  // ─── LOAD LEDGER ──────────────────────────────────
  Future<void> _loadLedger() async {
    if (!mounted) return;
    setState(() => _ledgerLoading = true);
    try {
      final res = await ApiService.instance.get(ApiConstants.adminLedger);
      if (!mounted) return;
      final d = res.data;
      setState(() => _ledger = d is List ? d : []);
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _ledgerLoading = false);
    }
  }

  // ─── ACTIONS ──────────────────────────────────────
  Future<void> _approveDriver(int id) async {
    try {
      await ApiService.instance.patch(ApiConstants.adminApproveDriver(id));
      await _loadDrivers();
      if (mounted) _showSuccess('Driver approved!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  Future<void> _rejectDriver(int id, String name) async {
    final reason = await _showRejectDialog(name);
    if (reason == null || reason.isEmpty) return;
    try {
      await ApiService.instance.patch(
        '${ApiConstants.adminRejectDriver(id)}?reason=${Uri.encodeComponent(reason)}',
      );
      await _loadDrivers();
      if (mounted) _showSuccess('Driver rejected.');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  Future<void> _blockUser(int id) async {
    try {
      await ApiService.instance.patch(ApiConstants.adminBlockUser(id));
      await _refreshCurrentTab();
      if (mounted) _showSuccess('User blocked.');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  Future<void> _unblockUser(int id) async {
    try {
      await ApiService.instance.patch(ApiConstants.adminUnblockUser(id));
      await _refreshCurrentTab();
      if (mounted) _showSuccess('User unblocked!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  Future<void> _resolveDispute(int orderId) async {
    try {
      await ApiService.instance.patch(ApiConstants.adminResolveOrder(orderId));
      await _loadOrders();
      if (mounted) _showSuccess('Dispute resolved!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  Future<void> _settleDriver(int id, String name) async {
    final result = await _showSettleDialog(name, 'Driver');
    if (result == null) return;
    try {
      await ApiService.instance.patch(
        ApiConstants.adminSettleDriver(id),
        data: {
          'amount': result['amount'],
          'paymentReference': result['ref'],
        },
      );
      await _loadDrivers();
      if (mounted) _showSuccess('Driver debt settled!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  Future<void> _settleMerchant(int id, String name) async {
    final result = await _showSettleDialog(name, 'Merchant');
    if (result == null) return;
    try {
      await ApiService.instance.patch(
        ApiConstants.adminSettleMerchant(id),
        data: {
          'amount': result['amount'],
          'paymentReference': result['ref'],
        },
      );
      await _loadMerchants();
      if (mounted) _showSuccess('Merchant commission settled!');
    } catch (e) {
      if (mounted) _showError(ApiService.getErrorMessage(e));
    }
  }

  // ─── BUILD ────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildDriversTab(),
                  _buildMerchantsTab(),
                  _buildOrdersTab(),
                  _buildLedgerTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── HEADER ───────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Admin Panel', style: AppTextStyles.displayMedium),
              Text('Platform control center', style: AppTextStyles.bodyMedium),
            ],
          ),
          const Spacer(),
          // Refresh
          GestureDetector(
            onTap: _refreshCurrentTab,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Icon(Icons.refresh_rounded,
                  color: AppColors.textPrimary, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          // Logout
          GestureDetector(
            onTap: () => context.read<AuthBloc>().add(LogoutRequested()),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: const Icon(Icons.logout_rounded,
                  color: AppColors.error, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TAB BAR ──────────────────────────────────────
  Widget _buildTabBar() {
    final tabs = [
      (Icons.dashboard_outlined, 'Overview'),
      (Icons.delivery_dining_outlined, 'Drivers'),
      (Icons.store_outlined, 'Merchants'),
      (Icons.receipt_long_outlined, 'Orders'),
      (Icons.account_balance_wallet_outlined, 'Ledger'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: AppColors.background,
          unselectedLabelColor: AppColors.textHint,
          dividerColor: Colors.transparent,
          padding: const EdgeInsets.all(4),
          labelPadding: EdgeInsets.zero,
          tabs: tabs
              .map((t) => Tab(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(t.$1, size: 16),
                        Text(t.$2,
                            style: const TextStyle(
                                fontSize: 9,
                                fontFamily: 'Montserrat',
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // TAB 1 — OVERVIEW
  // ═══════════════════════════════════════════════════
  Widget _buildOverviewTab() {
    if (_statsLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_stats == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Could not load stats', style: AppTextStyles.headlineMedium),
            const SizedBox(height: 16),
            AppButton(
              label: 'Retry',
              isFullWidth: false,
              icon: Icons.refresh_rounded,
              onPressed: _loadStats,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadStats,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          children: [
            // Revenue hero card
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Platform Revenue',
                            style: AppTextStyles.bodyMedium),
                        const SizedBox(height: 4),
                        Text(
                          '\$${_stats!['totalPlatformRevenue'] ?? 0}',
                          style: AppTextStyles.price.copyWith(fontSize: 28),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Today: \$${_stats!['todayRevenue'] ?? 0}",
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.trending_up_rounded,
                        color: AppColors.primary, size: 36),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Stats grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _statCard('Total Orders', '${_stats!['totalOrders'] ?? 0}',
                    Icons.receipt_long_outlined, AppColors.primary),
                _statCard('Delivered', '${_stats!['deliveredOrders'] ?? 0}',
                    Icons.check_circle_outline, AppColors.accent),
                _statCard('Disputed', '${_stats!['disputedOrders'] ?? 0}',
                    Icons.warning_amber_outlined, AppColors.warning),
                _statCard(
                    'Blocked Drivers',
                    '${_stats!['blockedDrivers'] ?? 0}',
                    Icons.block_rounded,
                    AppColors.error),
                _statCard('Total Users', '${_stats!['totalUsers'] ?? 0}',
                    Icons.people_outline, AppColors.primary),
                _statCard('Active Drivers', '${_stats!['activeDrivers'] ?? 0}',
                    Icons.delivery_dining, AppColors.accent),
              ],
            ),

            const SizedBox(height: 16),

            // Today summary
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.today_rounded,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    Text("Today's Summary", style: AppTextStyles.headlineSmall),
                  ]),
                  const SizedBox(height: 16),
                  _summaryRow('Orders Today', '${_stats!['todayOrders'] ?? 0}',
                      AppColors.primary),
                  _summaryRow('Deliveries',
                      '${_stats!['todayDeliveries'] ?? 0}', AppColors.accent),
                  _summaryRow(
                      'Total Merchants',
                      '${_stats!['totalMerchants'] ?? 0}',
                      AppColors.merchantColor),
                  _summaryRow('Total Drivers',
                      '${_stats!['totalDrivers'] ?? 0}', AppColors.driverColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(value,
              style: AppTextStyles.headlineLarge.copyWith(color: color)),
          Text(label, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color color) {
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

  // ═══════════════════════════════════════════════════
  // TAB 2 — DRIVERS
  // ═══════════════════════════════════════════════════
  Widget _buildDriversTab() {
    if (_driversLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return RefreshIndicator(
      onRefresh: _loadDrivers,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          // ─── Pending verification ──────────────
          if (_pendingDrivers.isNotEmpty) ...[
            _sectionHeader('Awaiting Verification', '${_pendingDrivers.length}',
                AppColors.warning),
            ..._pendingDrivers.map((d) => _driverCard(d, isPending: true)),
            const SizedBox(height: 20),
          ],

          // ─── All drivers ──────────────────────
          _sectionHeader(
              'All Drivers', '${_drivers.length}', AppColors.primary),
          if (_drivers.isEmpty)
            _emptyState('No drivers registered yet')
          else
            ..._drivers.map((d) => _driverCard(d)),
        ],
      ),
    );
  }

  Widget _driverCard(Map<String, dynamic> driver, {bool isPending = false}) {
    final id = driver['id'] as int;
    final name = driver['fullName'] as String? ?? 'Unknown';
    final isBlocked = driver['isBlocked'] as bool? ?? false;
    final debt = driver['debtAmount']?.toString() ?? '0.00';
    final verStatus = driver['verificationStatus'] as String? ?? '';
    final mode = driver['driverMode'] as String? ?? '';
    final isOnline = driver['isOnline'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.driverColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.delivery_dining,
                      color: AppColors.driverColor, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTextStyles.headlineSmall),
                    Text(
                      driver['phone'] as String? ?? '',
                      style: AppTextStyles.bodyMedium,
                    ),
                  ],
                ),
              ),
              // Status badges
              if (isBlocked)
                _badge('BLOCKED', AppColors.error)
              else if (isOnline)
                _badge('ONLINE', AppColors.accent)
              else
                _badge('OFFLINE', AppColors.textHint),
            ]),

            const SizedBox(height: 12),

            // Info row
            Row(children: [
              if (mode.isNotEmpty) ...[
                const Icon(Icons.directions_bike_outlined,
                    size: 13, color: AppColors.textHint),
                const SizedBox(width: 4),
                Text(mode, style: AppTextStyles.caption),
                const SizedBox(width: 16),
              ],
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 13, color: AppColors.warning),
              const SizedBox(width: 4),
              Text('Debt: \$$debt',
                  style: AppTextStyles.caption.copyWith(
                    color:
                        double.tryParse(debt) != null && double.parse(debt) > 0
                            ? AppColors.warning
                            : AppColors.textHint,
                  )),
              const Spacer(),
              if (verStatus.isNotEmpty) _badge(verStatus, _verColor(verStatus)),
            ]),

            // NEW — document thumbnails so admin can actually
            // review what the driver uploaded before approving.
            // Previously there was no way to see these at all
            // from the admin dashboard even though the backend
            // has stored them securely for a while.
            if (isPending) ...[
              const SizedBox(height: 12),
              _driverDocThumbnails(id, driver),
            ],

            const SizedBox(height: 12),
            const Divider(color: AppColors.glassBorder, height: 1),
            const SizedBox(height: 12),

            // Action buttons
            if (isPending)
              Row(children: [
                Expanded(
                  child: AppButton(
                    label: 'Approve',
                    icon: Icons.check_rounded,
                    color: AppColors.accent,
                    textColor: AppColors.background,
                    height: 44,
                    onPressed: () => _approveDriver(id),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'Reject',
                    icon: Icons.close_rounded,
                    color: AppColors.error,
                    height: 44,
                    onPressed: () => _rejectDriver(id, name),
                  ),
                ),
              ])
            else
              Row(children: [
                if (double.tryParse(debt) != null && double.parse(debt) > 0)
                  Expanded(
                    child: AppButton(
                      label: 'Settle Debt',
                      icon: Icons.payments_outlined,
                      color: AppColors.warning,
                      textColor: AppColors.background,
                      height: 44,
                      onPressed: () => _settleDriver(id, name),
                    ),
                  ),
                if (double.tryParse(debt) != null && double.parse(debt) > 0)
                  const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: isBlocked ? 'Unblock' : 'Block',
                    icon: isBlocked
                        ? Icons.lock_open_rounded
                        : Icons.block_rounded,
                    color: isBlocked ? AppColors.accent : AppColors.error,
                    textColor: isBlocked ? AppColors.background : null,
                    height: 44,
                    onPressed: () =>
                        isBlocked ? _unblockUser(id) : _blockUser(id),
                  ),
                ),
              ]),
          ],
        ),
      ),
    );
  }

  Color _verColor(String status) {
    switch (status) {
      case 'APPROVED':
        return AppColors.accent;
      case 'REJECTED':
        return AppColors.error;
      case 'SUBMITTED':
        return AppColors.warning;
      default:
        return AppColors.textHint;
    }
  }

  // ─── NEW — Driver document thumbnails ──────────────
  // Shows a small tappable thumbnail for each document the
  // driver has uploaded (booleans only come from the admin
  // user list — hasProfilePhoto etc. — never a raw file path).
  // Tapping fetches the actual bytes through the authenticated
  // admin endpoint and opens a full-screen viewer.
  Widget _driverDocThumbnails(int driverId, Map<String, dynamic> driver) {
    final docs = <Map<String, String>>[
      if (driver['hasProfilePhoto'] == true)
        {'type': 'PROFILE_PHOTO', 'label': 'Photo'},
      if (driver['hasNationalId'] == true)
        {'type': 'NATIONAL_ID', 'label': 'ID'},
      if (driver['hasLicenseFront'] == true)
        {'type': 'LICENSE_FRONT', 'label': 'License F'},
      if (driver['hasLicenseBack'] == true)
        {'type': 'LICENSE_BACK', 'label': 'License B'},
    ];

    if (docs.isEmpty) {
      return Text(
        'No documents uploaded yet',
        style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
      );
    }

    return Row(
      children: docs.map((doc) {
        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: GestureDetector(
            onTap: () => _viewDriverDocument(
                driverId, doc['type']!, doc['label']!),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: AppColors.glassWhite,
                    child: FutureBuilder<Uint8List>(
                      future: ApiService.instance.getBytes(
                        ApiConstants.adminDriverDocumentView(
                            driverId, doc['type']!),
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState !=
                            ConnectionState.done) {
                          return const Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.primary),
                            ),
                          );
                        }
                        if (snapshot.hasError || snapshot.data == null) {
                          return const Icon(Icons.broken_image_outlined,
                              color: AppColors.textHint, size: 18);
                        }
                        return Image.memory(snapshot.data!,
                            fit: BoxFit.cover);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(doc['label']!,
                    style: AppTextStyles.caption
                        .copyWith(fontSize: 9, color: AppColors.textHint)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Full-screen document viewer ──────────────────
  void _viewDriverDocument(int driverId, String docType, String label) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(label,
                            style: AppTextStyles.headlineSmall),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: AppColors.textPrimary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FutureBuilder<Uint8List>(
                      future: ApiService.instance.getBytes(
                        ApiConstants.adminDriverDocumentView(
                            driverId, docType),
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState !=
                            ConnectionState.done) {
                          return const SizedBox(
                            height: 200,
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary),
                            ),
                          );
                        }
                        if (snapshot.hasError || snapshot.data == null) {
                          return const SizedBox(
                            height: 120,
                            child: Center(
                              child: Text('Could not load document',
                                  style:
                                      TextStyle(color: AppColors.textHint)),
                            ),
                          );
                        }
                        return InteractiveViewer(
                          child: Image.memory(snapshot.data!),
                        );
                      },
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

  // ═══════════════════════════════════════════════════
  // TAB 3 — MERCHANTS
  // ═══════════════════════════════════════════════════
  Widget _buildMerchantsTab() {
    if (_merchantsLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return RefreshIndicator(
      onRefresh: _loadMerchants,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          _sectionHeader(
              'All Merchants', '${_merchants.length}', AppColors.merchantColor),
          if (_merchants.isEmpty)
            _emptyState('No merchants registered yet')
          else
            ..._merchants.map((m) => _merchantCard(m as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _merchantCard(Map<String, dynamic> merchant) {
    final id = merchant['id'] as int;
    final name = merchant['fullName'] as String? ?? 'Unknown';
    final isBlocked = merchant['isBlocked'] as bool? ?? false;
    final debt = merchant['debtAmount']?.toString() ?? '0.00';
    final hasDebt = double.tryParse(debt) != null && double.parse(debt) > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.merchantColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.store_outlined,
                      color: AppColors.merchantColor, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTextStyles.headlineSmall),
                    Text(
                      merchant['email'] as String? ?? '',
                      style: AppTextStyles.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (isBlocked)
                _badge('BLOCKED', AppColors.error)
              else
                _badge('ACTIVE', AppColors.accent),
            ]),
            if (hasDebt) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      color: AppColors.warning, size: 14),
                  const SizedBox(width: 6),
                  Text('Commission owed: \$$debt',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(color: AppColors.glassBorder, height: 1),
            const SizedBox(height: 12),
            Row(children: [
              if (hasDebt) ...[
                Expanded(
                  child: AppButton(
                    label: 'Settle',
                    icon: Icons.payments_outlined,
                    color: AppColors.warning,
                    textColor: AppColors.background,
                    height: 44,
                    onPressed: () => _settleMerchant(id, name),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: AppButton(
                  label: isBlocked ? 'Unblock' : 'Block',
                  icon:
                      isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                  color: isBlocked ? AppColors.accent : AppColors.error,
                  textColor: isBlocked ? AppColors.background : null,
                  height: 44,
                  onPressed: () =>
                      isBlocked ? _unblockUser(id) : _blockUser(id),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // TAB 4 — ORDERS
  // ═══════════════════════════════════════════════════
  Widget _buildOrdersTab() {
    if (_ordersLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return RefreshIndicator(
      onRefresh: _loadOrders,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          // Disputed first
          if (_disputedOrders.isNotEmpty) ...[
            _sectionHeader(
                'Disputes', '${_disputedOrders.length}', AppColors.error),
            ..._disputedOrders.map(
                (o) => _orderCard(o as Map<String, dynamic>, isDisputed: true)),
            const SizedBox(height: 20),
          ],

          _sectionHeader('All Orders', '${_orders.length}', AppColors.primary),
          if (_orders.isEmpty)
            _emptyState('No orders yet')
          else
            ..._orders.map((o) => _orderCard(o as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> order, {bool isDisputed = false}) {
    final id = order['id'] as int;
    final tracking = order['trackingCode'] as String? ?? '';
    final status = order['status'] as String? ?? '';
    final total = order['grandTotal'];
    final address = order['deliveryAddress'] ??
        order['offlineCustomerLandmark'] ??
        'No address';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderColor: isDisputed ? AppColors.error.withValues(alpha: 0.4) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(tracking,
                  style: AppTextStyles.labelLarge
                      .copyWith(color: AppColors.primary)),
              const Spacer(),
              StatusBadge(status: status),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.location_on_outlined,
                  size: 13, color: AppColors.textHint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(address.toString(),
                    style: AppTextStyles.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Text('\$$total', style: AppTextStyles.priceSmall),
            ]),
            if (order['disputeReason'] != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.error, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order['disputeReason'].toString(),
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.error),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Resolve Dispute',
                icon: Icons.gavel_rounded,
                color: AppColors.warning,
                textColor: AppColors.background,
                height: 44,
                onPressed: () => _resolveDispute(id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // TAB 5 — LEDGER
  // ═══════════════════════════════════════════════════
  Widget _buildLedgerTab() {
    if (_ledgerLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    return RefreshIndicator(
      onRefresh: _loadLedger,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          _sectionHeader(
              'All Transactions', '${_ledger.length}', AppColors.primary),
          if (_ledger.isEmpty)
            _emptyState('No transactions yet')
          else
            ..._ledger
                .map((entry) => _ledgerCard(entry as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _ledgerCard(Map<String, dynamic> entry) {
    final type = entry['type'] as String? ?? '';
    final amount = entry['amount']?.toString() ?? '0';
    final category = entry['category'] as String? ?? '';
    final desc = entry['description'] as String? ?? '';
    final isDebit = type == 'DEBIT';
    final createdAt = entry['createdAt']?.toString() ?? '';
    final dateStr =
        createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDebit
                  ? AppColors.error.withValues(alpha: 0.1)
                  : AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(
                isDebit
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: isDebit ? AppColors.error : AppColors.accent,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatCategory(category),
                  style: AppTextStyles.labelLarge,
                ),
                Text(desc,
                    style: AppTextStyles.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(dateStr, style: AppTextStyles.caption),
              ],
            ),
          ),
          Text(
            '${isDebit ? '+' : '-'}\$$amount',
            style: AppTextStyles.priceSmall.copyWith(
              color: isDebit ? AppColors.error : AppColors.accent,
            ),
          ),
        ]),
      ),
    );
  }

  String _formatCategory(String cat) {
    switch (cat) {
      case 'DRIVER_COMMISSION':
        return 'Driver Commission';
      case 'DRIVER_SETTLEMENT':
        return 'Driver Payment';
      case 'MERCHANT_COMMISSION':
        return 'Merchant Commission';
      case 'MERCHANT_SETTLEMENT':
        return 'Merchant Payment';
      case 'ADJUSTMENT':
        return 'Adjustment';
      case 'REFUND':
        return 'Refund';
      default:
        return cat;
    }
  }

  // ─── SHARED WIDGETS ───────────────────────────────
  Widget _sectionHeader(String title, String count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Text(title, style: AppTextStyles.headlineSmall),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(count,
              style: AppTextStyles.caption
                  .copyWith(color: color, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: AppTextStyles.caption
              .copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _emptyState(String msg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(msg, style: AppTextStyles.bodyMedium),
      ),
    );
  }

  // ─── DIALOGS ──────────────────────────────────────
  Future<String?> _showRejectDialog(String name) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reject $name', style: AppTextStyles.headlineMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Give a reason for rejection:',
                style: AppTextStyles.bodyMedium),
            const SizedBox(height: 12),
            AppInput(
              controller: ctrl,
              hint: 'e.g. Documents unclear',
              label: 'Reason',
              prefixIcon: Icons.message_outlined,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Reject',
                style:
                    AppTextStyles.labelLarge.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _showSettleDialog(
      String name, String type) async {
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Settle $name', style: AppTextStyles.headlineMedium),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Record payment received from this $type',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 16),
              AppInput(
                controller: amountCtrl,
                hint: 'e.g. 20.00',
                label: 'Amount Paid (\$)',
                prefixIcon: Icons.attach_money_rounded,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Required';
                  }
                  if (double.tryParse(v) == null) {
                    return 'Invalid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              AppInput(
                controller: refCtrl,
                hint: 'e.g. OMT-12345',
                label: 'Payment Reference',
                prefixIcon: Icons.receipt_outlined,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Required';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) {
                return;
              }
              Navigator.pop(ctx, {
                'amount': double.parse(amountCtrl.text.trim()),
                'ref': refCtrl.text.trim(),
              });
            },
            child: Text('Confirm',
                style:
                    AppTextStyles.labelLarge.copyWith(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  // ─── SNACKBARS ────────────────────────────────────
  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

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
