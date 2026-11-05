import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/features/auth/bloc/auth_bloc.dart';
import 'package:faster_app/features/auth/bloc/auth_state.dart';
import 'package:faster_app/features/auth/screens/login_screen.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

/// AuthBloc subclass that lets a test push states without hitting the API.
class _FakeAuthBloc extends AuthBloc {
  void push(AuthState state) => emit(state);
}

void main() {
  tearDown(AppToast.debugReset);

  testWidgets(
      'phone login with no number shows an AppToast error, not a SnackBar',
      (tester) async {
    final bloc = _FakeAuthBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: bloc,
          child: const LoginScreen(),
        ),
      ),
    );

    await tester.tap(find.text('Phone'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'password123');
    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(find.text('Phone number is required'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(AppToast.displayDuration);
    await tester.pumpAndSettle();
  });
}
