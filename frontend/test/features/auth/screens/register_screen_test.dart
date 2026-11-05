import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/features/auth/bloc/auth_bloc.dart';
import 'package:faster_app/features/auth/bloc/auth_state.dart';
import 'package:faster_app/features/auth/screens/register_screen.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

/// AuthBloc subclass that lets a test push states without hitting the API.
class _FakeAuthBloc extends AuthBloc {
  void push(AuthState state) => emit(state);
}

void main() {
  tearDown(AppToast.debugReset);

  testWidgets(
      'a failed registration shows the server message in an AppToast error, '
      'not a SnackBar', (tester) async {
    final bloc = _FakeAuthBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthBloc>.value(
          value: bloc,
          child: const RegisterScreen(),
        ),
      ),
    );

    bloc.push(AuthFailure('Email already registered'));
    await tester.pump();

    expect(find.text('Email already registered'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(AppToast.displayDuration);
    await tester.pumpAndSettle();
  });
}
