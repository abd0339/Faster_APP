import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// Bottom sheet offering Camera / Gallery as an [ImageSource]; returns the
/// chosen source, or null if dismissed without choosing.
///
/// [title] (with the drag handle above it) and the subtitles only render
/// when passed, so existing call sites with a bare two-line sheet and ones
/// with a titled, subtitled sheet both keep their own look.
Future<ImageSource?> showImageSourceSheet(
  BuildContext context, {
  String? title,
  String cameraLabel = 'Take a Photo',
  String? cameraSubtitle,
  String galleryLabel = 'Choose from Gallery',
  String? gallerySubtitle,
}) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.glassBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(title, style: AppTextStyles.headlineLarge),
              const SizedBox(height: 20),
            ],
            _SourceTile(
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
              icon: Icons.camera_alt_rounded,
              color: AppColors.primary,
              label: cameraLabel,
              subtitle: cameraSubtitle,
            ),
            const SizedBox(height: 12),
            _SourceTile(
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              icon: Icons.photo_library_rounded,
              color: AppColors.accent,
              label: galleryLabel,
              subtitle: gallerySubtitle,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                alignment: Alignment.center,
                child: Text('Cancel',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.textHint)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  final String label;
  final String? subtitle;

  const _SourceTile({
    required this.onTap,
    required this.icon,
    required this.color,
    required this.label,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(hasSubtitle ? 12 : 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: hasSubtitle ? 24 : 22),
            ),
            SizedBox(width: hasSubtitle ? 16 : 14),
            hasSubtitle
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTextStyles.headlineSmall),
                      Text(subtitle!, style: AppTextStyles.bodyMedium),
                    ],
                  )
                : Text(label, style: AppTextStyles.headlineSmall),
          ],
        ),
      ),
    );
  }
}
