import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_motion.dart';
import '../../core/constants/app_text_styles.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// ─── Primary Button ───────────────────────────────────
class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isFullWidth;
  final Color? color;
  final Color? textColor;
  final IconData? icon;
  final double height;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.isFullWidth = true,
    this.color,
    this.textColor,
    this.icon,
    this.height = 56,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _isPressed = false;

  void _setPressed(bool pressed) {
    if (_isPressed == pressed) return;
    setState(() => _isPressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: AppMotion.microDuration,
        curve: AppMotion.microCurve,
        child: SizedBox(
          width: widget.isFullWidth ? double.infinity : null,
          height: widget.height,
          child: ElevatedButton(
            onPressed: widget.isLoading
                ? null
                : () {
                    if (!kIsWeb) HapticFeedback.lightImpact();
                    widget.onPressed?.call();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.color ?? AppColors.primary,
              foregroundColor: widget.textColor ?? AppColors.background,
              disabledBackgroundColor:
                  (widget.color ?? AppColors.primary).withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: widget.isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: widget.textColor ?? AppColors.background,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.label,
                        style: AppTextStyles.button.copyWith(
                          color: widget.textColor ?? AppColors.background,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Outline Button ───────────────────────────────────
class AppOutlineButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? borderColor;
  final Color? textColor;
  final IconData? icon;
  final double height;

  const AppOutlineButton({
    super.key,
    required this.label,
    this.onPressed,
    this.borderColor,
    this.textColor,
    this.icon,
    this.height = 56,
  });

  @override
  State<AppOutlineButton> createState() => _AppOutlineButtonState();
}

class _AppOutlineButtonState extends State<AppOutlineButton> {
  bool _isPressed = false;

  void _setPressed(bool pressed) {
    if (_isPressed == pressed) return;
    setState(() => _isPressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final resolvedBorderColor = widget.borderColor ?? AppColors.primary;
    final resolvedTextColor = widget.textColor ?? AppColors.primary;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: AppMotion.microDuration,
        curve: AppMotion.microCurve,
        child: SizedBox(
          width: double.infinity,
          height: widget.height,
          child: OutlinedButton(
            onPressed: widget.onPressed == null
                ? null
                : () {
                    if (!kIsWeb) HapticFeedback.lightImpact();
                    widget.onPressed?.call();
                  },
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: resolvedBorderColor,
                width: 1.5,
              ),
              foregroundColor: resolvedTextColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith((states) {
                final color = states.contains(WidgetState.disabled)
                    ? resolvedBorderColor.withValues(alpha: 0.4)
                    : resolvedBorderColor;
                return BorderSide(color: color, width: 1.5);
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.disabled)
                    ? resolvedTextColor.withValues(alpha: 0.4)
                    : resolvedTextColor;
              }),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: 20,
                    color: widget.onPressed == null
                        ? resolvedTextColor.withValues(alpha: 0.4)
                        : resolvedTextColor,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label,
                  style: AppTextStyles.buttonOutline.copyWith(
                    color: widget.onPressed == null
                        ? resolvedTextColor.withValues(alpha: 0.4)
                        : resolvedTextColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Slide to Action Button ───────────────────────────
class SlideToActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onCompleted;
  final Color? color;

  const SlideToActionButton({
    super.key,
    required this.label,
    required this.onCompleted,
    this.color,
  });

  @override
  State<SlideToActionButton> createState() => _SlideToActionButtonState();
}

class _SlideToActionButtonState extends State<SlideToActionButton> {
  double _dragPosition = 0;
  final double _buttonWidth = 60;
  bool _completed = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDrag = trackWidth - _buttonWidth - 8;

        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.glassBorder,
            ),
          ),
          child: Stack(
            children: [
              // ─── Progress fill ─────────────────
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: maxDrag > 0
                      ? (_dragPosition / maxDrag).clamp(0.0, 1.0)
                      : 0.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: (widget.color ?? AppColors.primary)
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),

              // ─── Label ─────────────────────────
              Center(
                child: Text(
                  _completed ? '✓ Done!' : widget.label,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              // ─── Draggable thumb ───────────────
              Positioned(
                left: _dragPosition + 4,
                top: 4,
                bottom: 4,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (_completed) return;
                    setState(() {
                      _dragPosition = (_dragPosition + details.delta.dx)
                          .clamp(0.0, maxDrag);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    if (_dragPosition >= maxDrag * 0.85) {
                      setState(() {
                        _dragPosition = maxDrag;
                        _completed = true;
                      });
                      HapticFeedback.heavyImpact();
                      widget.onCompleted();
                    } else {
                      setState(() => _dragPosition = 0);
                    }
                  },
                  child: Container(
                    width: _buttonWidth,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.color ?? AppColors.primary,
                          (widget.color ?? AppColors.primary)
                              .withValues(alpha: 0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.background,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
