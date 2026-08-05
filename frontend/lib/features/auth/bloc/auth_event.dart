abstract class AuthEvent {}

class LoginRequested extends AuthEvent {
  final String emailOrPhone;
  final String password;
  final bool isEmail;

  LoginRequested({
    required this.emailOrPhone,
    required this.password,
    required this.isEmail,
  });
}

class RegisterRequested extends AuthEvent {
  final String fullName;
  final String phone;
  final String email;
  final String password;
  final String role;

  RegisterRequested({
    required this.fullName,
    required this.phone,
    required this.email,
    required this.password,
    required this.role,
  });
}

// ─── OTP Events ───────────────────────────────────────

/// User submits the 6-digit code
class VerifyOtpRequested extends AuthEvent {
  final String phone;
  final String code;

  VerifyOtpRequested({
    required this.phone,
    required this.code,
  });
}

/// User requests a new OTP (expired / not received)
class ResendOtpRequested extends AuthEvent {
  final String phone;
  // Optional — "SMS" (default) or "WHATSAPP". Lets the OTP
  // screen offer both as equally visible buttons, since
  // WhatsApp only works for numbers that have already
  // messaged the business (Meta Message Template
  // requirement — see CommunicationService on the backend).
  final String? channel;
  ResendOtpRequested({required this.phone, this.channel});
}

// ─── Session Events ───────────────────────────────────
class LogoutRequested extends AuthEvent {}

class CheckAuthStatus extends AuthEvent {}
