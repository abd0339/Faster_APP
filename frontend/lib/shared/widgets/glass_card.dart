import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blurAmount;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  /// Surface level: 1 = flat (no shadow, default), 2 = raised, 3 = floating.
  final int elevation;

  const GlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 20,
    this.blurAmount = 10,
    this.color,
    this.borderColor,
    this.onTap,
    this.elevation = 1,
  }) : assert(elevation >= 1 && elevation <= 3,
            'GlassCard elevation must be between 1 and 3');

  List<BoxShadow>? get _shadows => switch (elevation) {
        2 => [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        3 => [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final shadows = _shadows;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        margin: margin,
        decoration: shadows == null
            ? null
            : BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                boxShadow: shadows,
              ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: blurAmount,
              sigmaY: blurAmount,
            ),
            child: Container(
              padding: padding ?? const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    (color ?? AppColors.glassWhite).withValues(alpha: 0.12),
                    (color ?? AppColors.glassWhite).withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: borderColor ?? AppColors.glassBorder,
                  width: 1,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
