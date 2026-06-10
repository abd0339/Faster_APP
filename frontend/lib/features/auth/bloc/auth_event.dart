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

class LogoutRequested extends AuthEvent {}

class CheckAuthStatus extends AuthEvent {}
