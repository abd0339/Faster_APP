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
import '../../core/constants/app_text_styles.dart';
import '../../core/constants/app_motion.dart';
import '../../features/customer/screens/customer_order_tracking_screen.dart';
import '../services/push_notification_service.dart';
import '../services/notification_log_service.dart';
import '../models/notification_entry.dart';

/// Global navigator key — lets a push notification tap navigate
/// even though it fires outside any widget's BuildContext.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Handles navigation for a tapped notification — shared by the push
/// notification tap wiring below (where the tap fires outside any widget's
/// BuildContext) and by [NotificationCenterScreen]'s own row taps.
///
/// FIX (Finding 1): tapping a push used to do nothing but log. Order-related
/// pushes now open that order's tracking screen, where the recipient can
/// follow the delivery and — for an incoming_delivery — optionally share
/// their exact location.
void handleNotificationNavigation(
    BuildContext context, Map<String, dynamic> data) {
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
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  // Verifying or resending an OTP code re-emits AuthLoading before the
  // next OtpRequired (see AuthBloc._onVerifyOtp/_onResendOtp) — without
  // this, _screenFor would swap OtpScreen out for _SplashLoader and
  // back on every single attempt, tearing down and recreating
  // OtpScreen's State each time: its resend countdown timer resets to
  // 60s and its typed digits are lost, even for a plain wrong-code
  // retry that never asked to resend anything. Tracking the last
  // non-loading state lets a loading blip mid-OTP-flow keep rendering
  // OtpScreen itself instead of the splash screen, so Flutter's normal
  // widget reconciliation (same type, same key) reuses the existing
  // Element/State instead of disposing and recreating it.
  AuthState? _lastSubstantiveState;

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
          // Fire-and-forget: loads the on-device notification log from
          // SharedPreferences so it's ready by the time anything reads it,
          // such as a dashboard unread-count badge.
          // ignore: discarded_futures
          NotificationLogService.instance.init();
          PushNotificationService.instance.initialize(
            onForegroundMessage: (message) =>
                NotificationLogService.instance
                    .add(NotificationEntry.fromRemoteMessage(message)),
            onNotificationTap: (data) =>
                handleNotificationNavigation(context, data),
          );
        }
      },
      builder: (context, state) {
        if (state is! AuthLoading) {
          _lastSubstantiveState = state;
        }

        // This top-level builder swaps whole screens (splash -> login ->
        // OTP -> role dashboard) directly, with no Navigator/PageRoute
        // involved — so without this wrapper the switch was an instant
        // snap. AnimatedSwitcher gives it a real transition, driven by
        // the shared motion constants.
        return AnimatedSwitcher(
          duration: AppMotion.transitionDuration,
          switchInCurve: AppMotion.transitionCurve,
          switchOutCurve: AppMotion.transitionCurve,
          child: _screenFor(state),
        );
      },
    );
  }

  Widget _screenFor(AuthState state) {
    // Loading / splash
    if (state is AuthInitial || state is AuthLoading) {
      final last = _lastSubstantiveState;
      if (last is OtpRequired) {
        return OtpScreen(
          key: ValueKey(last.phone),
          phone: last.phone,
          fullName: last.fullName,
        );
      }
      return const _SplashLoader();
    }

    // OTP required — after register or unverified login
    if (state is OtpRequired) {
      return OtpScreen(
        key: ValueKey(state.phone),
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
  }
}

class _SplashLoader extends StatelessWidget {
  const _SplashLoader();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delivery_dining_rounded,
                color: AppColors.primary, size: 56),
            const SizedBox(height: 24),
            Text('FASTER',
                style: AppTextStyles.displayLarge.copyWith(
                  color: AppColors.primary,
                  letterSpacing: 8,
                )),
            const SizedBox(height: 32),
            const SizedBox(
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
