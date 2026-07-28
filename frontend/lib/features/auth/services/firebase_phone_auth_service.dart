import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// FirebasePhoneAuthService
/// ────────────────────────────────────────────────────
/// Wraps Firebase Phone Auth — an ADDITIONAL, independent
/// way to verify a phone number, alongside the existing
/// Twilio OTP flow. Firebase sends its own SMS directly
/// (via Google's infrastructure, not through our backend
/// at all); once the user enters the code (or Android's
/// SMS Retriever auto-detects it), this produces a Firebase
/// ID token, which gets sent to our backend's
/// /api/auth/verify-firebase-phone endpoint for server-side
/// verification (see AuthService.verifyFirebasePhone on the
/// backend — it never trusts a client-supplied phone
/// number, only what's inside the verified token).
class FirebasePhoneAuthService {
  FirebasePhoneAuthService._();
  static final FirebasePhoneAuthService instance = FirebasePhoneAuthService._();

  String? _verificationId;

  /// Starts phone verification. Firebase sends an SMS to
  /// [phone] (must be in E.164 format, e.g. +96170123456).
  ///
  /// [onCodeSent] fires once Firebase has dispatched the SMS
  /// — the UI should show the 6-digit input at this point.
  ///
  /// [onAutoVerified] fires ONLY on Android, ONLY when the
  /// SMS Retriever API auto-detects the code without the
  /// user typing anything — this already gives us a ready
  /// Firebase ID token directly, no manual code entry needed
  /// at all. Never fires on web/iOS — that's normal, not
  /// an error; those platforms always need manual entry.
  ///
  /// [onError] fires for any failure — invalid phone format,
  /// quota exceeded, network issue, etc. The friendly Twilio
  /// fallback button should be offered to the user here.
  Future<void> sendCode({
    required String phone,
    required void Function() onCodeSent,
    required void Function(String idToken) onAutoVerified,
    required void Function(String error) onError,
  }) async {
    try {
      if (kIsWeb) {
        // Web uses a different, promise-based API (no
        // auto-verification concept — always manual entry).
        final confirmationResult =
            await FirebaseAuth.instance.signInWithPhoneNumber(phone);
        _webConfirmationResult = confirmationResult;
        onCodeSent();
        return;
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Android SMS auto-detection — no typing needed
          try {
            final userCredential =
                await FirebaseAuth.instance.signInWithCredential(credential);
            final idToken = await userCredential.user?.getIdToken();
            if (idToken != null) {
              onAutoVerified(idToken);
            }
          } catch (e) {
            onError(_friendlyError(e));
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          onError(_friendlyError(e));
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          onCodeSent();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      onError(_friendlyError(e));
    }
  }

  // Web uses a ConfirmationResult object instead of a
  // verificationId string — kept separately since the two
  // platforms' APIs genuinely work differently here.
  ConfirmationResult? _webConfirmationResult;

  /// Confirms the 6-digit code the user typed. Returns the
  /// Firebase ID token on success — send this straight to
  /// POST /api/auth/verify-firebase-phone.
  Future<String> confirmCode(String smsCode) async {
    if (kIsWeb) {
      if (_webConfirmationResult == null) {
        throw Exception(
            'No verification in progress. Please request a new code.');
      }
      final userCredential = await _webConfirmationResult!.confirm(smsCode);
      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null) {
        throw Exception('Verification succeeded but no token was returned.');
      }
      return idToken;
    }

    if (_verificationId == null) {
      throw Exception(
          'No verification in progress. Please request a new code.');
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: smsCode,
    );

    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);
    final idToken = await userCredential.user?.getIdToken();
    if (idToken == null) {
      throw Exception('Verification succeeded but no token was returned.');
    }
    return idToken;
  }

  String _friendlyError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-phone-number':
          return 'That phone number doesn\'t look valid.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later, '
              'or use SMS/WhatsApp instead.';
        case 'invalid-verification-code':
          return 'That code is incorrect. Please check and try again.';
        case 'session-expired':
          return 'This code has expired. Please request a new one.';
        default:
          // TEMPORARY — shows the real Firebase error code/message
          // so we can diagnose exactly what's failing, instead of
          // guessing. Remove this once Phase 2 is confirmed working.
          return 'DEBUG [${e.code}]: ${e.message}';
      }
    }
    // TEMPORARY — same reasoning for non-Firebase exceptions
    return 'DEBUG (non-Firebase): $e';
  }
}
