import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/features/auth/bloc/auth_bloc.dart';
import 'package:faster_app/features/auth/bloc/auth_state.dart';
import 'package:faster_app/features/auth/screens/otp_screen.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

/// AuthBloc subclass that lets a test push states without hitting the API.
class _FakeAuthBloc extends AuthBloc {
  void push(AuthState state) => emit(state);
}

void main() {
  tearDown(AppToast.debugReset);

  testWidgets('a wrong OTP code shows an AppToast error, not a SnackBar',
      (tester) async {
    final bloc = _FakeAuthBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: bloc,
          child: const OtpScreen(phone: '+96170123456', fullName: 'Test User'),
        ),
      ),
    );

    bloc.push(
      OtpRequired(
        phone: '+96170123456',
        fullName: 'Test User',
        message: 'Invalid code. Try again.',
        isError: true,
      ),
    );
    await tester.pump();

    expect(find.text('Invalid code. Try again.'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(AppToast.displayDuration);
    // Unmount the screen so its resend countdown timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });
}
