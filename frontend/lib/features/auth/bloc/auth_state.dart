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

  OtpRequired({
    required this.phone,
    required this.fullName,
    required this.message,
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
