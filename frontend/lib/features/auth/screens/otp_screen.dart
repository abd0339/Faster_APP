import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/app_button.dart';
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  final String fullName;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.fullName,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  // 6 individual controllers — one per digit
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  // Resend timer — 60 seconds
  int _resendSeconds = 60;
  Timer? _timer;
  bool _isVerifying = false;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _startResendTimer();
    // Auto-focus first digit
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ─── Countdown timer ──────────────────────────────
  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendSeconds = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendSeconds <= 0) {
        t.cancel();
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  // ─── Get the 6-digit code ─────────────────────────
  String get _code => _controllers.map((c) => c.text).join();

  // ─── Handle digit input ───────────────────────────
  void _onDigitChanged(int index, String value) {
    if (value.isEmpty) {
      // Backspace — go to previous
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
      return;
    }

    // Only keep last digit
    if (value.length > 1) {
      _controllers[index].text = value[value.length - 1];
      _controllers[index].selection =
          TextSelection.fromPosition(TextPosition(offset: 1));
    }

    // Move to next field
    if (index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else {
      // Last digit — auto-submit
      _focusNodes[index].unfocus();
      _verify();
    }

    setState(() {});
  }

  // ─── Submit OTP ───────────────────────────────────
  void _verify() {
    if (_code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter all 6 digits'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!kIsWeb) HapticFeedback.mediumImpact();
    context.read<AuthBloc>().add(
          VerifyOtpRequested(
            phone: widget.phone,
            code: _code,
          ),
        );
  }

  // ─── Resend OTP ───────────────────────────────────
  void _resend() {
    if (_resendSeconds > 0) return;
    // Clear all digits
    for (final c in _controllers) c.clear();
    _focusNodes[0].requestFocus();
    _startResendTimer();
    context.read<AuthBloc>().add(
          ResendOtpRequested(phone: widget.phone),
        );
  }

  // ─── Mask phone for display ───────────────────────
  String get _maskedPhone {
    final p = widget.phone;
    if (p.length < 6) return p;
    return p.substring(0, 4) + '***' + p.substring(p.length - 4);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthFailure) {
          // Clear digits on failure — user needs to retype
          for (final c in _controllers) c.clear();
          _focusNodes[0].requestFocus();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(state.message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ));
        }
        // AuthSuccess is handled by AppRouter → navigates to dashboard
      },
      builder: (context, state) {
        final isLoading = state is AuthLoading;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    // ─── Icon ──────────────────────
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            width: 2),
                      ),
                      child: const Icon(Icons.sms_outlined,
                          color: AppColors.primary, size: 36),
                    ),

                    const SizedBox(height: 28),

                    Text('Verify Your Phone',
                        style: AppTextStyles.displayMedium,
                        textAlign: TextAlign.center),

                    const SizedBox(height: 10),

                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        text: 'We sent a 6-digit code to\n',
                        style: AppTextStyles.bodyMedium,
                        children: [
                          TextSpan(
                            text: _maskedPhone,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ─── 6 digit inputs ────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(6, (i) {
                        final isFilled = _controllers[i].text.isNotEmpty;
                        return Container(
                          width: 46,
                          height: 56,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: isFilled
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : AppColors.glassWhite,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isFilled
                                  ? AppColors.primary
                                  : AppColors.glassBorder,
                              width: isFilled ? 2 : 1,
                            ),
                          ),
                          child: TextField(
                            controller: _controllers[i],
                            focusNode: _focusNodes[i],
                            onChanged: (v) => _onDigitChanged(i, v),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 2, // 2 to detect backspace
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: AppTextStyles.headlineLarge.copyWith(
                              color: AppColors.primary,
                              fontSize: 22,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              counterText: '',
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 36),

                    // ─── Verify button ─────────────
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        label: 'Verify & Continue',
                        icon: Icons.check_circle_outline_rounded,
                        isLoading: isLoading,
                        color: AppColors.accent,
                        textColor: AppColors.background,
                        onPressed: _code.length == 6 ? _verify : null,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ─── Resend ────────────────────
                    GestureDetector(
                      onTap: _resendSeconds == 0 ? _resend : null,
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          text: "Didn't receive the code? ",
                          style: AppTextStyles.bodyMedium,
                          children: [
                            TextSpan(
                              text: _resendSeconds > 0
                                  ? 'Resend in ${_resendSeconds}s'
                                  : 'Resend Code',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: _resendSeconds > 0
                                    ? AppColors.textHint
                                    : AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ─── Info ──────────────────────
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.glassWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.textHint, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Code expires in 10 minutes. '
                            'After 3 wrong attempts you\'ll '
                            'need to request a new code.',
                            style: AppTextStyles.caption,
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
