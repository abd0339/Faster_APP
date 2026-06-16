import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeIn;
  late Animation<double> _scaleUp;
  late Animation<double> _taglineFade;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );

    _scaleUp = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.0, 0.6, curve: Curves.elasticOut)),
    );

    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl, curve: const Interval(0.5, 1.0, curve: Curves.easeIn)),
    );

    _ctrl.forward();

    // Trigger auth check after animation
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) {
        context.read<AuthBloc>().add(CheckAuthStatus());
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        // AppRouter handles navigation — just listen
        // so BLoC fires and router rebuilds
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ─── Logo mark ──────────────────────────
                FadeTransition(
                  opacity: _fadeIn,
                  child: ScaleTransition(
                    scale: _scaleUp,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            AppColors.primary,
                            Color(0xFF0099BB),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.5),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.delivery_dining_rounded,
                          color: AppColors.background,
                          size: 52,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ─── App name ───────────────────────────
                FadeTransition(
                  opacity: _fadeIn,
                  child: Text(
                    'FASTER',
                    style: AppTextStyles.displayLarge.copyWith(
                      color: AppColors.primary,
                      letterSpacing: 8,
                      fontSize: 36,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ─── Tagline ────────────────────────────
                FadeTransition(
                  opacity: _taglineFade,
                  child: Text(
                    'Delivery · Rides · Everything',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textHint,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),

                const SizedBox(height: 80),

                // ─── Loading indicator ──────────────────
                FadeTransition(
                  opacity: _taglineFade,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: AppColors.primary.withValues(alpha: 0.6),
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
