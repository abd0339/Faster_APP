// ─────────────────────────────────────────────────────
// DEV LAUNCHER — Development only, never ships to users
//
// HOW TO USE:
//   flutter run --dart-define=DEV_MODE=true
//
// This gives you a full screen grid of every page
// in the app. Tap any card → goes directly there.
// No login, no auth, no waiting.
//
// In production (flutter build web) DEV_MODE is false
// by default so this screen never appears.
// ─────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

// ── Auth
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/otp_screen.dart';

// ── Merchant
import '../../features/merchant/screens/merchant_dashboard_screen.dart';
import '../../features/merchant/screens/merchant_categories_screen.dart';
import '../../features/merchant/screens/merchant_items_screen.dart';
import '../../features/merchant/screens/merchant_offers_screen.dart';
import '../../features/merchant/screens/merchant_schedule_screen.dart';

// ── Driver
import '../../features/driver/screens/driver_verification_screen.dart';
import '../../features/driver/screens/driver_dashboard_screen.dart';

// ── Customer
import '../../features/customer/screens/customer_dashboard_screen.dart';
import '../../features/customer/screens/customer_stores_screen.dart';
import '../../features/customer/screens/customer_cart_screen.dart';
import '../../features/customer/screens/customer_order_tracking_screen.dart';
import '../../features/customer/screens/customer_ride_screen.dart';

// ── Admin
import '../../features/admin/screens/admin_dashboard_screen.dart';

// ── Shared
import '../../shared/widgets/map_picker_screen.dart';

class DevLauncher extends StatelessWidget {
  const DevLauncher({super.key});

  // ─── All screens grouped by role ──────────────────
  static final _sections = [
    _Section(
      title: '🔐 Auth',
      color: const Color(0xFF6C63FF),
      pages: [
        _Page('Login', Icons.login_rounded,
            () => const LoginScreen()),
        _Page('Register', Icons.person_add_rounded,
            () => const RegisterScreen()),
        _Page('OTP Screen', Icons.sms_outlined,
            () => const OtpScreen(
                phone: '+96170000001',
                fullName: 'Test User')),
      ],
    ),
    _Section(
      title: '🏪 Merchant',
      color: AppColors.primary,
      pages: [
        _Page('Dashboard', Icons.dashboard_rounded,
            () => const MerchantDashboardScreen()),
        _Page('Categories', Icons.category_rounded,
            () => const MerchantCategoriesScreen()),
        _Page('Items', Icons.fastfood_rounded, () => const MerchantItemsScreen(
          category: {
            'id': 1, 
            'name': 'Test Category', 
            'icon': '🍔'
            },
            )),
            
        _Page('Offers', Icons.local_offer_rounded,
            () => const MerchantOffersScreen()),
        _Page('Schedule', Icons.schedule_rounded,
            () => const MerchantScheduleScreen()),
      ],
    ),
    _Section(
      title: '🚗 Driver',
      color: AppColors.driverColor,
      pages: [
        _Page('Verification', Icons.verified_user_rounded,
            () => const DriverVerificationScreen()),
        _Page('Dashboard', Icons.local_shipping_rounded,
            () => const DriverDashboardScreen()),
      ],
    ),
    _Section(
      title: '👤 Customer',
      color: AppColors.customerColor,
      pages: [
        _Page('Dashboard', Icons.home_rounded,
            () => const CustomerDashboardScreen()),
        _Page('Stores', Icons.store_rounded,
            () => const Scaffold(
                  backgroundColor: AppColors.background,
                  body: CustomerStoresScreen())),
        _Page('Cart', Icons.shopping_cart_rounded,
            () => const CustomerCartScreen()),
        _Page('Track Order', Icons.location_on_rounded,
            () => const CustomerOrderTrackingScreen(
                orderId: 1,
                trackingCode: 'FST-20260101-TEST')),
        _Page('Request Ride', Icons.directions_car_rounded,
            () => const CustomerRideScreen()),
      ],
    ),
    _Section(
      title: '⚙️ Admin',
      color: const Color(0xFFFF6B35),
      pages: [
        _Page('Dashboard', Icons.admin_panel_settings_rounded,
            () => const AdminDashboardScreen()),
      ],
    ),
    _Section(
      title: '🗺️ Shared',
      color: AppColors.accent,
      pages: [
        _Page('Map Picker', Icons.map_rounded,
            () => const MapPickerScreen(
                title: 'Test Map Picker',
                confirmLabel: 'Confirm')),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header ────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bug_report_rounded,
                              color: Colors.amber, size: 14),
                          SizedBox(width: 4),
                          Text('DEV MODE',
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              )),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_sections.fold(0, (s, sec) => s + sec.pages.length)} screens',
                      style: AppTextStyles.caption,
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text('Faster Dev Launcher',
                      style: AppTextStyles.displayMedium),
                  Text('Tap any screen to navigate directly',
                      style: AppTextStyles.bodyMedium),
                ],
              ),
            ),

            // ─── Screen list ───────────────────────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: _sections.length,
                itemBuilder: (ctx, sectionIdx) {
                  final section = _sections[sectionIdx];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section header
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(4, 8, 0, 10),
                        child: Row(children: [
                          Container(
                            width: 4,
                            height: 18,
                            decoration: BoxDecoration(
                              color: section.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(section.title,
                              style: AppTextStyles.headlineSmall
                                  .copyWith(color: section.color)),
                        ]),
                      ),

                      // Pages grid
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.1,
                        ),
                        itemCount: section.pages.length,
                        itemBuilder: (ctx, pageIdx) {
                          final page = section.pages[pageIdx];
                          return _PageCard(
                            page: page,
                            color: section.color,
                          );
                        },
                      ),

                      const SizedBox(height: 16),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tappable page card ───────────────────────────────
class _PageCard extends StatelessWidget {
  final _Page page;
  final Color color;

  const _PageCard({required this.page, required this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => page.builder()),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(page.icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                page.label,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data models ──────────────────────────────────────
class _Section {
  final String title;
  final Color color;
  final List<_Page> pages;
  const _Section(
      {required this.title,
      required this.color,
      required this.pages});
}

class _Page {
  final String label;
  final IconData icon;
  final Widget Function() builder;
  const _Page(this.label, this.icon, this.builder);
}