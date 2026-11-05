import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/notification_log_service.dart';
import '../screens/notification_center_screen.dart';

/// Bell icon + unread-count badge, shared by the customer/driver/merchant
/// dashboard headers. Styled as the same glass chip those headers already
/// use for their logout control, so the two sit side by side as a matching
/// pair.
///
/// Listens to [NotificationLogService.instance] and rebuilds itself whenever
/// the log changes (a push arrives, an entry is marked read, the log is
/// cleared), so the badge stays current without depending on the parent
/// dashboard to rebuild. That also makes a `const` call site safe.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NotificationLogService.instance,
      builder: (context, _) => _buildBell(
        context,
        NotificationLogService.instance.unreadCount,
      ),
    );
  }

  Widget _buildBell(BuildContext context, int unreadCount) {
    return badges.Badge(
      showBadge: unreadCount > 0,
      badgeContent: Text(
        '$unreadCount',
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Icon(
            unreadCount > 0
                ? Icons.notifications_rounded
                : Icons.notifications_none_rounded,
            color: AppColors.textPrimary,
            size: 20,
          ),
        ),
      ),
    );
  }
}
