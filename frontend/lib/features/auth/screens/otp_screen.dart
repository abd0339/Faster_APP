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
import '../services/firebase_phone_auth_service.dart';

/// OtpScreen
/// ────────────────────────────────────────────────────
/// FIX (Phase 2): now defaults to Firebase Phone Auth —
/// Firebase sends its own SMS the moment this screen opens,
/// automatically, no button tap needed. This is NOT a
/// replacement for the Twilio OTP flow — it's the new
/// default, with Twilio kept as one clear, explicit fallback
/// ("Use SMS/WhatsApp instead") if Firebase's SMS doesn't
/// arrive. The two never run at the same time by default —
/// switching to the fallback clearly changes which backend
/// endpoint the typed code is checked against, avoiding any
/// ambiguity about which code (from which sender) the user
/// should type.
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
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  int _resendSeconds = 60;
  Timer? _timer;

  // true = Firebase Phone Auth (default), false = Twilio
  // (SMS/WhatsApp) fallback, switched only if the user
  // explicitly taps "Use SMS/WhatsApp instead".
  bool _useFirebase = true;

  // Loading state for the Firebase send/confirm steps
  // specifically (separate from AuthBloc's own loading
  // state, which only kicks in once we reach the backend).
  bool _isVerifying = false;
  bool _isSendingInitialCode = true;
  String? _sendError;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
    // Kick off Firebase verification immediately — this is
    // what actually sends the code now; registration itself
    // no longer auto-sends a Twilio message (see AuthService
    // .register() on the backend for why).
    _startFirebaseVerification();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ─── Start / restart Firebase phone verification ──
  void _startFirebaseVerification() {
    setState(() {
      _isSendingInitialCode = true;
      _sendError = null;
    });

    FirebasePhoneAuthService.instance.sendCode(
      phone: widget.phone,
      onCodeSent: () {
        if (!mounted) return;
        setState(() => _isSendingInitialCode = false);
      },
      onAutoVerified: (idToken) {
        // Android SMS auto-detection — no typing needed at all
        if (!mounted) return;
        context
            .read<AuthBloc>()
            .add(VerifyFirebasePhoneRequested(idToken: idToken));
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _isSendingInitialCode = false;
          _sendError = error;
        });
      },
    );
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

  String get _code => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.isEmpty) {
      if (index > 0) _focusNodes[index - 1].requestFocus();
      return;
    }
    if (value.length > 1) {
      _controllers[index].text = value[value.length - 1];
      _controllers[index].selection =
          TextSelection.fromPosition(TextPosition(offset: 1));
    }
    if (index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else {
      _focusNodes[index].unfocus();
      _verify();
    }
    setState(() {});
  }

  // ─── Submit code — routes to Firebase or Twilio ───
  // depending on which mode is currently active
  void _verify() async {
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

    if (_useFirebase) {
      setState(() => _isVerifying = true);
      try {
        final idToken =
            await FirebasePhoneAuthService.instance.confirmCode(_code);
        if (!mounted) return;
        context
            .read<AuthBloc>()
            .add(VerifyFirebasePhoneRequested(idToken: idToken));
      } catch (e) {
        if (!mounted) return;
        setState(() => _isVerifying = false);
        for (final c in _controllers) c.clear();
        _focusNodes[0].requestFocus();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ));
      }
    } else {
      // Twilio fallback path — unchanged from before
      context.read<AuthBloc>().add(
            VerifyOtpRequested(phone: widget.phone, code: _code),
          );
    }
  }

  // ─── Resend — Firebase or Twilio depending on mode ─
  void _resend() {
    if (_resendSeconds > 0) return;
    for (final c in _controllers) c.clear();
    _focusNodes[0].requestFocus();
    _startResendTimer();

    if (_useFirebase) {
      _startFirebaseVerification();
    } else {
      context.read<AuthBloc>().add(ResendOtpRequested(phone: widget.phone));
    }
  }

  // ─── Explicit switch to the Twilio fallback ────────
  // The one clear escape hatch — tapping this changes which
  // backend endpoint the typed code is checked against, so
  // there's never ambiguity about which code (Firebase's or
  // Twilio's) the user should be typing.
  void _switchToTwilioFallback() {
    setState(() {
      _useFirebase = false;
      _sendError = null;
    });
    for (final c in _controllers) c.clear();
    _focusNodes[0].requestFocus();
    _startResendTimer();
    context.read<AuthBloc>().add(ResendOtpRequested(phone: widget.phone));
  }

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
          setState(() => _isVerifying = false);
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
        final isLoading = state is AuthLoading || _isVerifying;

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
                        text: _isSendingInitialCode
                            ? 'Sending a code to\n'
                            : 'We sent a 6-digit code to\n',
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

                    if (_isSendingInitialCode) ...[
                      const SizedBox(height: 16),
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2),
                      ),
                    ],

                    if (_sendError != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(_sendError!,
                            style: AppTextStyles.bodyMedium
                                .copyWith(color: AppColors.error),
                            textAlign: TextAlign.center),
                      ),
                    ],

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
                            maxLength: 2,
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

                    // ─── Twilio fallback — only shown while
                    // still in Firebase mode ────────────
                    if (_useFirebase) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: _switchToTwilioFallback,
                        child: Text(
                          'Having trouble? Use SMS/WhatsApp instead',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textHint,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

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
                            _useFirebase
                                ? 'Code expires in a few minutes.'
                                : 'Code expires in 10 minutes. '
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