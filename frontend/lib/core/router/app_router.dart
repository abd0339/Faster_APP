import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_state.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/driver/screens/driver_verification_screen.dart';
import '../../features/driver/screens/driver_dashboard_screen.dart';
import '../../features/merchant/screens/merchant_dashboard_screen.dart';
import '../../features/customer/screens/customer_dashboard_screen.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../core/constants/app_colors.dart';

class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        // ─── Initial / Loading ─────────────────────────
        if (state is AuthInitial || state is AuthLoading) {
          return const _SplashLoader();
        }

        // ─── Not logged in ─────────────────────────────
        if (state is AuthLoggedOut || state is AuthFailure) {
          return const LoginScreen();
        }

        // ─── Logged in → route by role ─────────────────
        if (state is AuthSuccess) {
          switch (state.role) {
            case 'MERCHANT':
              return const MerchantDashboardScreen();

            case 'DRIVER':
              // Driver must complete verification before dashboard
              // DriverVerificationScreen checks its own status
              // and shows the correct step (pending/submitted/approved)
              return const DriverVerificationScreen();

            case 'CUSTOMER':
              return const CustomerDashboardScreen();

            case 'ADMIN':
              return const AdminDashboardScreen();

            default:
              return const LoginScreen();
          }
        }

        return const LoginScreen();
      },
    );
  }
}

// ─── Splash loader (shown during auth check) ──────────
class _SplashLoader extends StatelessWidget {
  const _SplashLoader();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Icon(
              Icons.delivery_dining_rounded,
              color: AppColors.primary,
              size: 56,
            ),
            SizedBox(height: 24),
            Text(
              'FASTER',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                letterSpacing: 8,
              ),
            ),
            SizedBox(height: 32),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
