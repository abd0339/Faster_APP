import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/constants/app_colors.dart';

/// Shared loading placeholder for card-shaped content.
///
/// Wraps a plain rounded [Container] placeholder in a [Shimmer.fromColors]
/// animation (base [AppColors.surface], highlight [AppColors.glassWhite]).
class AppSkeletonCard extends StatelessWidget {
  final double height;
  final double borderRadius;

  const AppSkeletonCard({
    super.key,
    this.height = 80,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.glassWhite,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}
