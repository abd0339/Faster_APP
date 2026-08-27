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

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  // Holds the full E.164 number composed by PhoneInputField
  // (e.g. "+96170123456"). The user never types the dial code —
  // it's selected — so this is always well-formed or empty.
  String _phoneE164 = '';
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = 'CUSTOMER';

  final List<Map<String, dynamic>> _roles = [
    {
      'value': 'CUSTOMER',
      'label': 'Customer',
      'icon': Icons.person_outline,
      'color': AppColors.customerColor,
    },
    {
      'value': 'MERCHANT',
      'label': 'Merchant',
      'icon': Icons.store_outlined,
      'color': AppColors.merchantColor,
    },
    {
      'value': 'DRIVER',
      'label': 'Driver',
      'icon': Icons.delivery_dining_outlined,
      'color': AppColors.driverColor,
    },
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    // PhoneInputField isn't a FormField, so it can't take part in
    // _formKey validation — guard here instead. It emits an empty
    // string until a national number is entered.
    if (_phoneE164.isEmpty) {
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
          RegisterRequested(
            fullName: _nameController.text.trim(),
            phone: _phoneE164,
            email: _emailController.text.trim().toLowerCase(),
            password: _passwordController.text,
            role: _selectedRole,
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
        if (state is AuthSuccess) {
          Navigator.pop(context);
        }
        if (state is OtpRequired) {
          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Create Account'),
            backgroundColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Role selector ────────────
                  const Text(
                    'I am a...',
                    style: AppTextStyles.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: _roles.map((role) {
                      final isSelected = _selectedRole == role['value'];
                      return Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _selectedRole = role['value']),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (role['color'] as Color)
                                      .withValues(alpha: 0.15)
                                  : AppColors.glassWhite,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? role['color'] as Color
                                    : AppColors.glassBorder,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  role['icon'] as IconData,
                                  color: isSelected
                                      ? role['color'] as Color
                                      : AppColors.textHint,
                                  size: 28,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  role['label'] as String,
                                  style: AppTextStyles.labelMedium.copyWith(
                                    color: isSelected
                                        ? role['color'] as Color
                                        : AppColors.textHint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 32),

                  // ─── Form fields ──────────────
                  GlassCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        AppInput(
                          controller: _nameController,
                          hint: 'Full name',
                          prefixIcon: Icons.person_outline,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Full name is required';
                            }
                            if (v.length < 3) {
                              return 'Min 3 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // FIX: was a free-text field where users typed
                        // things like "70123456" or "0096170123456".
                        // normalizePhone() turned those into invalid
                        // numbers and Twilio rejected them (error
                        // 21211) — a paid API call wasted and an OTP
                        // that never arrived, with no clear reason
                        // shown to the user. The dial code is now
                        // chosen, not typed, so this is always E.164.
                        PhoneInputField(
                          label: 'Phone Number',
                          onChanged: (e164) => _phoneE164 = e164,
                        ),
                        const SizedBox(height: 16),
                        AppInput(
                          controller: _emailController,
                          hint: 'name@email.com',
                          prefixIcon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Email is required';
                            }
                            if (!v.contains('@')) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        AppInput(
                          controller: _passwordController,
                          hint: 'Password (min 8 chars)',
                          prefixIcon: Icons.lock_outline,
                          isPassword: true,
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Password is required';
                            }
                            if (v.length < 8) {
                              return 'Min 8 characters';
                            }
                            final hasUpper = v.contains(RegExp(r'[A-Z]'));
                            final hasLower = v.contains(RegExp(r'[a-z]'));
                            final hasNumber = v.contains(RegExp(r'[0-9]'));
                            if (!hasUpper || !hasLower || !hasNumber) {
                              return 'Need upper, lower & number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        AppButton(
                          label: 'Create Account',
                          isLoading: state is AuthLoading,
                          onPressed: _submit,
                          color: AppColors.accent,
                          textColor: AppColors.background,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: RichText(
                        text: TextSpan(
                          text: 'Already have an account? ',
                          style: AppTextStyles.bodyMedium,
                          children: [
                            TextSpan(
                              text: 'Sign In',
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
        );
      },
    );
  }
}
