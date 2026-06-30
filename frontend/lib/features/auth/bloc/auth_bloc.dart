import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/constants/api_constants.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(AuthInitial()) {
    on<LoginRequested>(_onLogin);
    on<RegisterRequested>(_onRegister);
    on<VerifyOtpRequested>(_onVerifyOtp);
    on<ResendOtpRequested>(_onResendOtp);
    on<LogoutRequested>(_onLogout);
    on<CheckAuthStatus>(_onCheckAuth);
  }

  // ─── REGISTER ─────────────────────────────────────
  // Backend returns requiresOtp=true — no token yet
  // BLoC emits OtpRequired → AppRouter shows OtpScreen
  Future<void> _onRegister(
    RegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final res = await ApiService.instance.post(
        ApiConstants.register,
        data: {
          'fullName': event.fullName,
          'phone': event.phone,
          'email': event.email,
          'password': event.password,
          'role': event.role,
        },
      );

      final data = res.data as Map<String, dynamic>;

      // requiresOtp=true → user must verify phone before getting token
      if (data['requiresOtp'] == true) {
        emit(OtpRequired(
          phone: data['phone'] ?? event.phone,
          fullName: data['fullName'] ?? event.fullName,
          message: data['message'] ?? 'Check your phone for the code.',
        ));
      } else {
        // Fallback: if backend issued token directly
        await _saveAndEmitSuccess(data, emit);
      }
    } catch (e) {
      emit(AuthFailure(ApiService.getErrorMessage(e)));
    }
  }

  // ─── LOGIN ────────────────────────────────────────
  // Returns OtpRequired if phone not verified yet
  // Returns AuthSuccess if everything is verified
  Future<void> _onLogin(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final body = event.isEmail
          ? {'email': event.emailOrPhone, 'password': event.password}
          : {'phone': event.emailOrPhone, 'password': event.password};

      final res =
          await ApiService.instance.post(ApiConstants.login, data: body);
      final data = res.data as Map<String, dynamic>;

      if (data['requiresOtp'] == true) {
        // Phone not verified — show OTP screen
        emit(OtpRequired(
          phone: data['phone'] ?? event.emailOrPhone,
          fullName: data['fullName'] ?? '',
          message: data['message'] ?? 'Enter the code we sent you.',
        ));
      } else {
        await _saveAndEmitSuccess(data, emit);
      }
    } catch (e) {
      emit(AuthFailure(ApiService.getErrorMessage(e)));
    }
  }

  // ─── VERIFY OTP ───────────────────────────────────
  // User submits the 6-digit code from their phone
  // On success: saves auth data + emits AuthSuccess
  Future<void> _onVerifyOtp(
    VerifyOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final res = await ApiService.instance.post(
        ApiConstants.verifyOtp,
        data: {
          'phone': event.phone,
          'code': event.code,
        },
      );

      final data = res.data as Map<String, dynamic>;
      // Backend returns token after successful OTP
      await _saveAndEmitSuccess(data, emit);
    } catch (e) {
      emit(AuthFailure(ApiService.getErrorMessage(e)));
    }
  }

  // ─── RESEND OTP ───────────────────────────────────
  Future<void> _onResendOtp(
    ResendOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final res = await ApiService.instance.post(
        ApiConstants.resendOtp,
        data: {'phone': event.phone},
      );
      final data = res.data as Map<String, dynamic>;

      // Stay on OTP screen — just show confirmation message
      emit(OtpRequired(
        phone: event.phone,
        fullName: data['fullName'] ?? '',
        message: data['message'] ?? 'New code sent.',
      ));
    } catch (e) {
      emit(AuthFailure(ApiService.getErrorMessage(e)));
    }
  }

  // ─── LOGOUT ───────────────────────────────────────
  Future<void> _onLogout(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await StorageService.instance.clearAll();
    emit(AuthLoggedOut());
  }

  // ─── CHECK SESSION ────────────────────────────────
  Future<void> _onCheckAuth(
    CheckAuthStatus event,
    Emitter<AuthState> emit,
  ) async {
    final isLoggedIn = await StorageService.instance.isLoggedIn();
    if (!isLoggedIn) {
      emit(AuthLoggedOut());
      return;
    }
    final role = await StorageService.instance.getRole();
    final fullName = await StorageService.instance.getFullName();
    final email = await StorageService.instance.getEmail();
    final phone = await StorageService.instance.getPhone();
    final token = await StorageService.instance.getToken();

    emit(AuthSuccess(
      token: token ?? '',
      role: role ?? '',
      fullName: fullName ?? '',
      email: email ?? '',
      phone: phone ?? '',
    ));
  }

  // ─── Save auth data and emit AuthSuccess ──────────
  Future<void> _saveAndEmitSuccess(
    Map<String, dynamic> data,
    Emitter<AuthState> emit,
  ) async {
    await StorageService.instance.saveAuthData(
      token: data['token'],
      role: data['role'],
      fullName: data['fullName'],
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
    );
    emit(AuthSuccess(
      token: data['token'],
      role: data['role'],
      fullName: data['fullName'],
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
    ));
  }
}
