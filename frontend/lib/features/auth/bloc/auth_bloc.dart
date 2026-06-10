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
    on<LogoutRequested>(_onLogout);
    on<CheckAuthStatus>(_onCheckAuth);
  }

  // ─── LOGIN ────────────────────────────────────────
  Future<void> _onLogin(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final body = event.isEmail
          ? {
              'email': event.emailOrPhone,
              'password': event.password,
            }
          : {
              'phone': event.emailOrPhone,
              'password': event.password,
            };

      final response =
          await ApiService.instance.post(ApiConstants.login, data: body);

      final data = response.data as Map<String, dynamic>;

      // Save to secure storage
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
    } catch (e) {
      emit(AuthFailure(ApiService.getErrorMessage(e)));
    }
  }

  // ─── REGISTER ─────────────────────────────────────
  Future<void> _onRegister(
    RegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final response = await ApiService.instance.post(
        ApiConstants.register,
        data: {
          'fullName': event.fullName,
          'phone': event.phone,
          'email': event.email,
          'password': event.password,
          'role': event.role,
        },
      );

      final data = response.data as Map<String, dynamic>;

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

  // ─── CHECK STATUS ─────────────────────────────────
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
}
