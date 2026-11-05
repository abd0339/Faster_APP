import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/models/notification_entry.dart';
import '../../core/router/app_router.dart';
import '../../core/services/notification_log_service.dart';
import '../widgets/app_empty_state.dart';

/// Lists every entry in [NotificationLogService], newest first — the
/// customer/merchant/driver/admin surface for notifications they may have
/// missed (or dismissed) when they arrived as a push.
///
/// Reads the singleton service directly rather than taking it as a
/// constructor parameter, matching how other screens in this codebase
/// consume singleton services. Listens to it as well, so a push that
/// arrives while this screen is open shows up immediately.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NotificationLogService.instance,
      builder: (context, _) =>
          _buildScaffold(NotificationLogService.instance.getAll()),
    );
  }

  Widget _buildScaffold(List<NotificationEntry> entries) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Notifications', style: AppTextStyles.headlineSmall),
      ),
      body: entries.isEmpty
          ? const AppEmptyState(
              icon: Icons.notifications_none_rounded,
              message: 'No notifications yet',
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: AppColors.glassBorder,
              ),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _NotificationRow(
                  entry: entry,
                  onTap: () => _handleTap(entry),
                );
              },
            ),
    );
  }

  void _handleTap(NotificationEntry entry) {
    // markRead() notifies the service's listeners, which rebuilds this
    // screen through the ListenableBuilder above.
    NotificationLogService.instance.markRead(entry.id);
    handleNotificationNavigation(context, entry.data);
  }
}

class _NotificationRow extends StatelessWidget {
  final NotificationEntry entry;
  final VoidCallback onTap;

  const _NotificationRow({required this.entry, required this.onTap});

  bool get _isUnread => !entry.read;

  String get _formattedTimestamp {
    final dt = entry.receivedAt;
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 10,
        child: _isUnread
            ? const Center(
                child: _UnreadDot(),
              )
            : null,
      ),
      title: Text(
        entry.title,
        style: AppTextStyles.bodyLarge.copyWith(
          fontWeight: _isUnread ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        _formattedTimestamp,
        style: AppTextStyles.bodySmall.copyWith(
          color: _isUnread ? AppColors.textHint : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}
