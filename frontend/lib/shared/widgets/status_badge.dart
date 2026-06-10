import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final double fontSize;

  const StatusBadge({
    super.key,
    required this.status,
    this.fontSize = 11,
  });

  Color get _color {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return AppColors.pending;
      case 'ACCEPTED':
        return AppColors.accepted;
      case 'PREPARING':
        return AppColors.preparing;
      case 'READY_FOR_PICKUP':
        return AppColors.readyPickup;
      case 'PICKED_UP':
        return AppColors.pickedUp;
      case 'DELIVERED':
        return AppColors.delivered;
      case 'CANCELLED':
        return AppColors.cancelled;
      case 'DISPUTED':
        return AppColors.disputed;
      case 'ONLINE':
        return AppColors.accent;
      case 'OFFLINE':
        return AppColors.textHint;
      default:
        return AppColors.textSecondary;
    }
  }

  String get _label {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return '⏳ Pending';
      case 'ACCEPTED':
        return '✅ Accepted';
      case 'PREPARING':
        return '👨‍🍳 Preparing';
      case 'READY_FOR_PICKUP':
        return '📦 Ready';
      case 'PICKED_UP':
        return '🚀 On the way';
      case 'DELIVERED':
        return '✅ Delivered';
      case 'CANCELLED':
        return '❌ Cancelled';
      case 'DISPUTED':
        return '⚠️ Disputed';
      case 'ONLINE':
        return '🟢 Online';
      case 'OFFLINE':
        return '⚫ Offline';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _color.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Text(
        _label,
        style: AppTextStyles.caption.copyWith(
          color: _color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
