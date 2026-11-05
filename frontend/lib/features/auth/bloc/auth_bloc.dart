import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/notification_log_service.dart';
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
    // FIX (review 2026-11-01): capture the fullName BEFORE emitting
    // AuthLoading — that emit overwrites `state`, so the catch block
    // below can no longer read it from the (now-gone) OtpRequired
    // state. Needed to re-emit OtpRequired on failure instead of
    // AuthFailure (see below).
    final previousFullName = state is OtpRequired ? (state as OtpRequired).fullName : '';

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
      // FIX (review 2026-11-01): used to emit AuthFailure, which the
      // router maps straight to LoginScreen — so a single mistyped
      // digit tore down the whole OtpScreen (entered digits,
      // countdown, phone context) and bounced the user back to the
      // login form, contradicting the screen's own "3 attempts"
      // copy. Re-emitting OtpRequired keeps the router on OtpScreen;
      // it already listens for OtpRequired.message and shows it as
      // a snackbar (same mechanism it uses for "new code sent"), so
      // the error still reaches the user, just without leaving the
      // screen.
      emit(OtpRequired(
        phone: event.phone,
        fullName: previousFullName,
        message: ApiService.getErrorMessage(e),
        isError: true,
      ));
    }
  }

  // ─── RESEND OTP ───────────────────────────────────
  Future<void> _onResendOtp(
    ResendOtpRequested event,
    Emitter<AuthState> emit,
  ) async {
    // Same reasoning as _onVerifyOtp: capture fullName before
    // AuthLoading overwrites `state`, so a failure below can still
    // re-emit OtpRequired instead of bouncing to LoginScreen (e.g.
    // hitting the resend cooldown/rate limit shouldn't throw the user
    // out of the OTP flow any more than a wrong digit should).
    final previousFullName = state is OtpRequired ? (state as OtpRequired).fullName : '';

    emit(AuthLoading());
    try {
      final res = await ApiService.instance.post(
        ApiConstants.resendOtp,
        data: {
          'phone': event.phone,
          if (event.channel != null) 'channel': event.channel,
        },
      );
      final data = res.data as Map<String, dynamic>;

      // Stay on OTP screen — just show confirmation message
      emit(OtpRequired(
        phone: event.phone,
        fullName: data['fullName'] ?? '',
        message: data['message'] ?? 'New code sent.',
      ));
    } catch (e) {
      emit(OtpRequired(
        phone: event.phone,
        fullName: previousFullName,
        message: ApiService.getErrorMessage(e),
        isError: true,
      ));
    }
  }

  // ─── LOGOUT ───────────────────────────────────────
  Future<void> _onLogout(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    // NEW (Phase 4) — stop pushes from reaching this device
    // once signed out. Wrapped internally so any failure
    // here never blocks the actual logout below.
    await PushNotificationService.instance.unregister();

    // M5: tell the server to revoke this token before we drop it.
    // Must run BEFORE clearAll(), since the request needs the token
    // that clearAll() is about to delete. Wrapped so a network
    // failure can never trap the user in a logged-in state — local
    // sign-out proceeds regardless.
    try {
      await ApiService.instance.post(ApiConstants.logout);
    } catch (_) {}

    await StorageService.instance.clearAll();

    // The notification log belongs to the account that just signed out —
    // clear it so the next account on this device does not inherit it.
    await NotificationLogService.instance.clear();
    emit(AuthLoggedOut());
  }

  // ─── CHECK SESSION ────────────────────────────────
  Future<void> _onCheckAuth(
    CheckAuthStatus event,
    Emitter<AuthState> emit,
  ) async {
    // FIX (review 2026-11-01): this used to have no error handling at
    // all. flutter_secure_storage can throw (e.g. PlatformException
    // BAD_DECRYPT) when the Android Keystore key backing it becomes
    // invalid — a real case after an OS upgrade or restoring the app
    // from a device backup. With no catch, no state was ever emitted
    // and the app stayed on the splash screen (AuthInitial maps to
    // _SplashLoader in app_router.dart) forever, with no recovery
    // except uninstalling. Falling back to AuthLoggedOut on any read
    // failure at least gets the user to a login screen they can act on.
    try {
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
    } catch (_) {
      emit(AuthLoggedOut());
    }
  }

  // ─── Save auth data and emit AuthSuccess ──────────
  Future<void> _saveAndEmitSuccess(
    Map<String, dynamic> data,
    Emitter<AuthState> emit,
  ) async {
    // FIX (review 2026-11-01): token/role/fullName used to be passed
    // straight into non-nullable String parameters. If the backend
    // response were ever missing one of these keys (a contract
    // change, a partial response), the implicit null-to-String cast
    // threw a raw Dart type error that surfaced to the user as the
    // AuthFailure message — e.g. "type 'Null' is not a subtype of
    // type 'String'" — instead of a clean, actionable message.
    final token = data['token'] ?? '';
    final role = data['role'] ?? '';
    final fullName = data['fullName'] ?? '';
    final email = data['email'] ?? '';
    final phone = data['phone'] ?? '';

    await StorageService.instance.saveAuthData(
      token: token,
      role: role,
      fullName: fullName,
      email: email,
      phone: phone,
    );
    emit(AuthSuccess(
      token: token,
      role: role,
      fullName: fullName,
      email: email,
      phone: phone,
    ));
  }
}
