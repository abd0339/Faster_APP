import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_input.dart';

/// OrderFeedbackSheet
/// ────────────────────────────────────────────────────
/// Shown automatically the moment a customer's order status
/// flips to DELIVERED — see CustomerOrderTrackingScreen.
///
/// Two independent things, matching how Uber/other delivery
/// platforms do it:
///   1. Driver thumbs up/down — negative REQUIRES a note,
///      which goes straight to the admin dashboard.
///   2. Star ratings (1-5) for BOTH driver and merchant,
///      each independently optional.
///
/// "Skip" dismisses without submitting anything at all — no
/// feedback row gets created server-side in that case.
Future<void> showOrderFeedbackSheet(
  BuildContext context, {
  required int orderId,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _OrderFeedbackContent(orderId: orderId),
  );
}

class _OrderFeedbackContent extends StatefulWidget {
  final int orderId;
  const _OrderFeedbackContent({required this.orderId});

  @override
  State<_OrderFeedbackContent> createState() => _OrderFeedbackContentState();
}

class _OrderFeedbackContentState extends State<_OrderFeedbackContent> {
  // null = not chosen yet, true = thumbs up, false = thumbs down
  bool? _driverThumbsUp;
  final _noteCtrl = TextEditingController();

  int? _driverStars;
  int? _merchantStars;

  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_driverThumbsUp == false && _noteCtrl.text.trim().isEmpty) {
      setState(() => _error =
          'Please tell us what went wrong so we can help');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ApiService.instance.post(
        ApiConstants.orderFeedback(widget.orderId),
        data: {
          'driverThumbsUp': _driverThumbsUp,
          'negativeNote': _driverThumbsUp == false
              ? _noteCtrl.text.trim()
              : null,
          'driverStars': _driverStars,
          'merchantStars': _merchantStars,
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiService.getErrorMessage(e);
          _isSubmitting = false;
        });
      }
    }
  }

  void _skip() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Text('How was your delivery?',
                style: AppTextStyles.headlineMedium),
            const SizedBox(height: 6),
            Text('Your feedback helps us improve',
                style: AppTextStyles.bodyMedium),
            const SizedBox(height: 24),

            // ─── Driver thumbs up/down ─────────────
            Text('Rate your driver', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _thumbButton(
                    icon: Icons.thumb_up_alt_rounded,
                    label: 'Good',
                    selected: _driverThumbsUp == true,
                    color: AppColors.accent,
                    onTap: () => setState(() {
                      _driverThumbsUp = true;
                      _error = null;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _thumbButton(
                    icon: Icons.thumb_down_alt_rounded,
                    label: 'Not good',
                    selected: _driverThumbsUp == false,
                    color: AppColors.error,
                    onTap: () => setState(() {
                      _driverThumbsUp = false;
                    }),
                  ),
                ),
              ],
            ),

            if (_driverThumbsUp == false) ...[
              const SizedBox(height: 14),
              AppInput(
                controller: _noteCtrl,
                hint: 'What went wrong?',
                label: 'Tell us more',
                maxLines: 3,
              ),
            ],

            const SizedBox(height: 24),

            // ─── Star ratings ───────────────────────
            Text('Rate this order', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 14),
            _starRow(
              label: 'Driver',
              value: _driverStars,
              onChanged: (v) => setState(() => _driverStars = v),
            ),
            const SizedBox(height: 14),
            _starRow(
              label: 'Store',
              value: _merchantStars,
              onChanged: (v) => setState(() => _merchantStars = v),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.error)),
              ),
            ],

            const SizedBox(height: 28),

            AppButton(
              label: 'Submit',
              icon: Icons.check_rounded,
              isLoading: _isSubmitting,
              color: AppColors.accent,
              textColor: AppColors.background,
              onPressed: _submit,
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: _isSubmitting ? null : _skip,
                child: Text('Skip',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textHint)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbButton({
    required IconData icon,
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.15)
              : AppColors.glassWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : AppColors.glassBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? color : AppColors.textHint, size: 26),
            const SizedBox(height: 6),
            Text(label,
                style: AppTextStyles.caption.copyWith(
                  color: selected ? color : AppColors.textHint,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }

  Widget _starRow({
    required String label,
    required int? value,
    required void Function(int) onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label, style: AppTextStyles.bodyMedium),
        ),
        ...List.generate(5, (i) {
          final starValue = i + 1;
          final filled = value != null && starValue <= value;
          return GestureDetector(
            onTap: () => onChanged(starValue),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_border_rounded,
                color: filled ? AppColors.warning : AppColors.textHint,
                size: 30,
              ),
            ),
          );
        }),
      ],
    );
  }
}