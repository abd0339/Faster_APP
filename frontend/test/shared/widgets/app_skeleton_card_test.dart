import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';
import 'package:faster_app/shared/widgets/app_skeleton_card.dart';

void main() {
  group('AppSkeletonCard', () {
    testWidgets('wraps the placeholder Container in a Shimmer ancestor',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppSkeletonCard(),
          ),
        ),
      );

      expect(find.byType(Shimmer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Shimmer),
          matching: find.byType(Container),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders the placeholder at the given height', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppSkeletonCard(height: 120),
          ),
        ),
      );

      final size = tester.getSize(find.byType(AppSkeletonCard));
      expect(size.height, 120);
    });
  });
}
