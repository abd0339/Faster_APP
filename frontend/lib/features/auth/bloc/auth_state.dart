abstract class AuthState {}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

// ─── OTP Required ─────────────────────────────────────
// Emitted after register or login when phone not verified.
// AppRouter shows OtpScreen when this state is active.
class OtpRequired extends AuthState {
  final String phone;
  final String fullName;
  final String message;
  // True when `message` is a verify-failure (wrong/expired code, too
  // many attempts) re-emitted to keep the router on OtpScreen instead
  // of bouncing to LoginScreen (see AuthBloc._onVerifyOtp). False for
  // the normal "new code sent" resend confirmation. The screen uses
  // this to pick error vs. confirmation styling.
  final bool isError;

  OtpRequired({
    required this.phone,
    required this.fullName,
    required this.message,
    this.isError = false,
  });
}

// ─── Fully authenticated ──────────────────────────────
class AuthSuccess extends AuthState {
  final String token;
  final String role;
  final String fullName;
  final String email;
  final String phone;

  AuthSuccess({
    required this.token,
    required this.role,
    required this.fullName,
    required this.email,
    required this.phone,
  });
}

class AuthFailure extends AuthState {
  final String message;
  AuthFailure(this.message);
}

class AuthLoggedOut extends AuthState {}
