import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_input.dart';
import '../../../shared/widgets/phone_input_field.dart';
import '../../../shared/widgets/glass_card.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  // Phone mode uses PhoneInputField (dial code selected, not typed)
  // so the value sent is always clean E.164. Email mode keeps using
  // _emailController above.
  String _phoneE164 = '';
  final _passwordController = TextEditingController();
  bool _isEmailMode = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    // PhoneInputField isn't a FormField, so it can't take part in
    // _formKey validation — guard phone mode explicitly here.
    if (!_isEmailMode && _phoneE164.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone number is required'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    context.read<AuthBloc>().add(
          LoginRequested(
            emailOrPhone:
                _isEmailMode ? _emailController.text.trim() : _phoneE164,
            password: _passwordController.text,
            isEmail: _isEmailMode,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              // ─── Background glow ──────────────
              Positioned(
                top: -100,
                left: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                bottom: -80,
                right: -80,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: 0.05),
                  ),
                ),
              ),

              // ─── Main content ─────────────────
              SafeArea(
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 40),

                          // ─── Logo ─────────────
                          Center(
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.bolt_rounded,
                                color: AppColors.background,
                                size: 40,
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // ─── Title ────────────
                          const Text(
                            'Welcome back',
                            style: AppTextStyles.displayMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Sign in to continue',
                            style: AppTextStyles.bodyMedium,
                          ),

                          const SizedBox(height: 40),

                          // ─── Glass card ───────
                          GlassCard(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                // ─── Toggle ───────
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.glassDark,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      _buildToggleTab(
                                        'Email',
                                        Icons.email_outlined,
                                        true,
                                      ),
                                      _buildToggleTab(
                                        'Phone',
                                        Icons.phone_outlined,
                                        false,
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 20),

                                // ─── Email/Phone ──
                                // FIX: phone mode used to be free text,
                                // so a user could type "70123456" and
                                // login would look up a number that
                                // doesn't match what was registered
                                // (stored E.164). Now the dial code is
                                // selected, matching registration
                                // exactly. Email mode is unchanged.
                                if (_isEmailMode)
                                  AppInput(
                                    controller: _emailController,
                                    hint: 'name@email.com',
                                    prefixIcon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return 'Email is required';
                                      }
                                      return null;
                                    },
                                  )
                                else
                                  PhoneInputField(
                                    label: 'Phone Number',
                                    onChanged: (e164) => _phoneE164 = e164,
                                  ),

                                const SizedBox(height: 16),

                                // ─── Password ─────
                                AppInput(
                                  controller: _passwordController,
                                  hint: 'Your password',
                                  prefixIcon: Icons.lock_outline,
                                  isPassword: true,
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Password is required';
                                    }
                                    if (v.length < 8) {
                                      return 'Min 8 characters';
                                    }
                                    return null;
                                  },
                                ),

                                const SizedBox(height: 24),

                                // ─── Login button ─
                                AppButton(
                                  label: 'Sign In',
                                  isLoading: state is AuthLoading,
                                  onPressed: _submit,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ─── Register link ────
                          Center(
                            child: TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BlocProvider.value(
                                      value: context.read<AuthBloc>(),
                                      child: const RegisterScreen(),
                                    ),
                                  ),
                                );
                              },
                              child: RichText(
                                text: TextSpan(
                                  text: "Don't have an account? ",
                                  style: AppTextStyles.bodyMedium,
                                  children: [
                                    TextSpan(
                                      text: 'Register',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Toggle tab widget ────────────────────────────
  Widget _buildToggleTab(
    String label,
    IconData icon,
    bool isEmail,
  ) {
    final isSelected = _isEmailMode == isEmail;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _isEmailMode = isEmail),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppColors.background : AppColors.textHint,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: isSelected ? AppColors.background : AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Navigate by role ─────────────────────────────
}
