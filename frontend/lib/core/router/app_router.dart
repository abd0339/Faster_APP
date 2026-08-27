import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_state.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/driver/screens/driver_verification_screen.dart';
import '../../features/merchant/screens/merchant_dashboard_screen.dart';
import '../../features/customer/screens/customer_dashboard_screen.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../core/constants/app_colors.dart';
import '../../features/customer/screens/customer_order_tracking_screen.dart';
import '../services/push_notification_service.dart';

/// Global navigator key — lets a push notification tap navigate
/// even though it fires outside any widget's BuildContext.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      // NEW (Phase 4) — initialize push notifications exactly
      // once, right when the user actually logs in (transitions
      // INTO AuthSuccess from something else). Wrapped so any
      // failure here can never affect the actual navigation
      // below — push is additive, not required for the app
      // to work.
      listenWhen: (previous, current) =>
          current is AuthSuccess && previous is! AuthSuccess,
      listener: (context, state) {
        if (state is AuthSuccess) {
          PushNotificationService.instance.initialize(
            onNotificationTap: (data) {
              // FIX (Finding 1): tapping a push used to do nothing
              // but log. Order-related pushes now open that order's
              // tracking screen, where the recipient can follow the
              // delivery and — for an incoming_delivery — optionally
              // share their exact location.
              debugPrint('📬 Notification tapped: $data');

              final orderIdRaw = data['orderId'];
              final trackingCodeRaw = data['trackingCode'];
              if (orderIdRaw == null || trackingCodeRaw == null) return;
              final orderId = int.tryParse(orderIdRaw.toString());
              if (orderId == null) return;

              // Pushed on top of whatever dashboard the user is on,
              // so backing out returns them where they were.
              navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => CustomerOrderTrackingScreen(
                    orderId: orderId,
                    trackingCode: trackingCodeRaw.toString(),
                  ),
                ),
              );
            },
          );
        }
      },
      builder: (context, state) {
        // Loading / splash
        if (state is AuthInitial || state is AuthLoading) {
          return const _SplashLoader();
        }

        // OTP required — after register or unverified login
        if (state is OtpRequired) {
          return OtpScreen(
            phone: state.phone,
            fullName: state.fullName,
          );
        }

        // Not logged in
        if (state is AuthLoggedOut || state is AuthFailure) {
          return const LoginScreen();
        }

        // Logged in → route by role
        if (state is AuthSuccess) {
          switch (state.role) {
            case 'MERCHANT':
              return const MerchantDashboardScreen();
            case 'DRIVER':
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
            Icon(Icons.delivery_dining_rounded,
                color: AppColors.primary, size: 56),
            SizedBox(height: 24),
            Text('FASTER',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: 8,
                )),
            SizedBox(height: 32),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
