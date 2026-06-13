import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/api_service.dart';
import '../../../core/constants/api_constants.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.instance.get(ApiConstants.adminStats);
      setState(() {
        _stats = res.data as Map<String, dynamic>;
      });
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStats,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Header ───────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin Panel',
                          style: AppTextStyles.displayMedium,
                        ),
                        Text(
                          'Platform overview',
                          style: AppTextStyles.bodyMedium,
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () =>
                          context.read<AuthBloc>().add(LogoutRequested()),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.glassWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.glassBorder,
                          ),
                        ),
                        child: const Icon(
                          Icons.logout_rounded,
                          color: AppColors.error,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                  )
                else if (_stats != null) ...[
                  // ─── Revenue card ──────────
                  GlassCard(
                    color: AppColors.primary,
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Revenue',
                              style: AppTextStyles.bodyMedium,
                            ),
                            Text(
                              '\$${_stats!['totalPlatformRevenue'] ?? 0}',
                              style: AppTextStyles.price,
                            ),
                            Text(
                              "Today: \$${_stats!['todayRevenue'] ?? 0}",
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                        const Icon(
                          Icons.trending_up_rounded,
                          color: AppColors.primary,
                          size: 48,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ─── Stats grid ────────────
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.4,
                    children: [
                      _buildStatCard(
                        'Total Orders',
                        '${_stats!['totalOrders'] ?? 0}',
                        Icons.receipt_long_outlined,
                        AppColors.primary,
                      ),
                      _buildStatCard(
                        'Delivered',
                        '${_stats!['deliveredOrders'] ?? 0}',
                        Icons.check_circle_outline,
                        AppColors.accent,
                      ),
                      _buildStatCard(
                        'Disputed',
                        '${_stats!['disputedOrders'] ?? 0}',
                        Icons.warning_amber_outlined,
                        AppColors.warning,
                      ),
                      _buildStatCard(
                        'Blocked Drivers',
                        '${_stats!['blockedDrivers'] ?? 0}',
                        Icons.block_rounded,
                        AppColors.error,
                      ),
                      _buildStatCard(
                        'Total Users',
                        '${_stats!['totalUsers'] ?? 0}',
                        Icons.people_outline,
                        AppColors.primary,
                      ),
                      _buildStatCard(
                        'Active Drivers',
                        '${_stats!['activeDrivers'] ?? 0}',
                        Icons.delivery_dining,
                        AppColors.accent,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ─── Today summary ─────────
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Today's Activity",
                          style: AppTextStyles.headlineMedium,
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryRow(
                          'Orders Today',
                          '${_stats!['todayOrders'] ?? 0}',
                          AppColors.primary,
                        ),
                        _buildSummaryRow(
                          'Deliveries Today',
                          '${_stats!['todayDeliveries'] ?? 0}',
                          AppColors.accent,
                        ),
                        _buildSummaryRow(
                          'Total Merchants',
                          '${_stats!['totalMerchants'] ?? 0}',
                          AppColors.merchantColor,
                        ),
                        _buildSummaryRow(
                          'Total Drivers',
                          '${_stats!['totalDrivers'] ?? 0}',
                          AppColors.driverColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const Spacer(),
          Text(
            value,
            style: AppTextStyles.headlineLarge.copyWith(color: color),
          ),
          Text(label, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodyMedium),
          Text(
            value,
            style: AppTextStyles.labelLarge.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
