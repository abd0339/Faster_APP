import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_event.dart';
import '../../features/auth/bloc/auth_state.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/driver/screens/driver_profile_screen.dart';
import '../../features/merchant/screens/merchant_dashboard_screen.dart';
import '../../features/driver/screens/driver_dashboard_screen.dart';
import '../../features/customer/screens/customer_dashboard_screen.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../core/constants/app_colors.dart';

class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {},
      builder: (context, state) {
        // ─── Loading ──────────────────────────────
        if (state is AuthLoading || state is AuthInitial) {
          return const _LoadingScreen();
        }

        // ─── Not logged in ────────────────────────
        if (state is AuthLoggedOut || state is AuthFailure) {
          return const LoginScreen();
        }

        // ─── Logged in → route by role ────────────
        if (state is AuthSuccess) {
          switch (state.role) {
            case 'MERCHANT':
              return const MerchantDashboardScreen();
            case 'DRIVER':
              return const DriverDashboardScreen();
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

// ─── Loading screen ───────────────────────────────────
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      ),
    );
  }
}
