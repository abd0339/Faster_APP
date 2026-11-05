import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/core/constants/app_spacing.dart';

void main() {
  test('AppSpacing scale values', () {
    expect(AppSpacing.xs, 4.0);
    expect(AppSpacing.sm, 8.0);
    expect(AppSpacing.md, 12.0);
    expect(AppSpacing.lg, 16.0);
    expect(AppSpacing.xl, 24.0);
    expect(AppSpacing.xxl, 32.0);
    expect(AppSpacing.xxxl, 48.0);
  });
}
