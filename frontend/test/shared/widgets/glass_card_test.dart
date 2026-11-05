import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/shared/widgets/glass_card.dart';

/// Pumps a GlassCard and returns the box shadows painted by its outer
/// Container (the one holding margin/width/height). When [elevation] is
/// null the argument is omitted entirely, exercising the default.
Future<List<BoxShadow>> _pumpAndReadShadows(
    WidgetTester tester, int? elevation) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: elevation == null
          ? const GlassCard(child: SizedBox())
          : GlassCard(elevation: elevation, child: const SizedBox()),
    ),
  ));
  final outer = tester.widget<Container>(
    find
        .descendant(
            of: find.byType(GlassCard), matching: find.byType(Container))
        .first,
  );
  final decoration = outer.decoration as BoxDecoration?;
  return decoration?.boxShadow ?? const <BoxShadow>[];
}

void main() {
  testWidgets('GlassCard elevation 1 paints no shadow', (tester) async {
    final shadows = await _pumpAndReadShadows(tester, 1);
    expect(shadows, isEmpty);
  });

  testWidgets('GlassCard with no elevation argument defaults to no shadow',
      (tester) async {
    final shadows = await _pumpAndReadShadows(tester, null);
    expect(shadows, isEmpty);
  });

  testWidgets('GlassCard elevation 2 paints one shadow with the level-2 shadow values',
      (tester) async {
    final shadows = await _pumpAndReadShadows(tester, 2);
    expect(shadows, hasLength(1));
    expect(shadows.single.blurRadius, 12);
    expect(shadows.single.offset, const Offset(0, 4));
    expect(shadows.single.color, Colors.black.withValues(alpha: 0.3));
  });

  testWidgets('GlassCard elevation 3 paints one shadow with the level-3 shadow values',
      (tester) async {
    final shadows = await _pumpAndReadShadows(tester, 3);
    expect(shadows, hasLength(1));
    expect(shadows.single.blurRadius, 24);
    expect(shadows.single.offset, const Offset(0, 4));
    expect(shadows.single.color, Colors.black.withValues(alpha: 0.3));
  });
}
