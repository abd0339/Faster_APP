import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_motion.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';

enum _ToastVariant {
  success(Icons.check_circle_rounded, AppColors.success),
  error(Icons.cancel_rounded, AppColors.error),
  warning(Icons.warning_rounded, AppColors.warning),
  info(Icons.info_rounded, AppColors.info);

  const _ToastVariant(this.icon, this.color);

  final IconData icon;
  final Color color;
}

class _ToastRequest {
  _ToastRequest({
    required this.overlay,
    required this.variant,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  /// Captured when the request is made, so a queued request does not need
  /// the caller's [BuildContext] to still be mounted when it is shown.
  final OverlayState overlay;
  final _ToastVariant variant;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Toasts with an action stay up until the action is tapped (or another
  /// toast replaces them) — there is no auto-dismiss timer.
  bool get isSticky => actionLabel != null;
}

/// Transient top-of-screen notification, replacing ad-hoc [SnackBar]s.
///
/// ```dart
/// AppToast.success(context, 'Order placed');
/// AppToast.error(context, 'Upload failed',
///     actionLabel: 'Retry', onAction: _upload);
/// ```
///
/// At most one toast is visible at a time, process-wide:
/// * No toast showing → the new one shows immediately.
/// * Same variant as the one showing → the new one replaces it immediately.
/// * Different variant → the new one is queued (FIFO) and shown once the
///   current toast is dismissed, so a burst of mixed toasts is never dropped.
///   Exception: a toast with an action has no timer, so rather than letting
///   it block the queue indefinitely, any new request (of any variant)
///   replaces it immediately, ahead of anything already queued.
///
/// A toast without an action auto-dismisses after [displayDuration]. A toast
/// with an action stays until the action is tapped, which calls `onAction`
/// and then dismisses it.
class AppToast {
  AppToast._();

  /// How long a toast without an action stays on screen.
  static const Duration displayDuration = Duration(seconds: 4);

  static OverlayEntry? _current;
  static _ToastRequest? _currentRequest;
  static Timer? _timer;
  static final Queue<_ToastRequest> _queue = Queue<_ToastRequest>();

  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      _request(context, _ToastVariant.success, message, actionLabel, onAction);

  static void error(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      _request(context, _ToastVariant.error, message, actionLabel, onAction);

  static void warning(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      _request(context, _ToastVariant.warning, message, actionLabel, onAction);

  static void info(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      _request(context, _ToastVariant.info, message, actionLabel, onAction);

  /// Removes any visible toast, cancels its timer and clears the queue.
  /// Static state outlives individual widget tests, so tests call this in
  /// `tearDown`.
  @visibleForTesting
  static void debugReset() {
    _removeCurrent();
    _queue.clear();
  }

  static void _request(
    BuildContext context,
    _ToastVariant variant,
    String message,
    String? actionLabel,
    VoidCallback? onAction,
  ) {
    final request = _ToastRequest(
      overlay: Overlay.of(context),
      variant: variant,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );

    final showing = _currentRequest;
    if (showing == null) {
      _present(request);
    } else if (showing.variant == request.variant || showing.isSticky) {
      // Interrupt: replace the current toast; the queue is untouched. A
      // sticky (action) toast has no timer, so any request interrupts it —
      // otherwise it could block the queue forever.
      _removeCurrent();
      _present(request);
    } else {
      _queue.add(request);
    }
  }

  static void _present(_ToastRequest request) {
    assert(_current == null && _timer == null);
    if (!request.overlay.mounted) {
      // The Navigator this was requested on has gone away; skip it.
      _showNext();
      return;
    }

    final entry = OverlayEntry(
      builder: (_) => _ToastView(
        request: request,
        onAction: () => _handleAction(request),
      ),
    );
    _current = entry;
    _currentRequest = request;
    request.overlay.insert(entry);

    if (!request.isSticky) {
      _timer = Timer(displayDuration, () => _dismiss(request));
    }
  }

  static void _handleAction(_ToastRequest request) {
    if (!identical(_currentRequest, request)) return;
    request.onAction?.call();
    // onAction may itself have shown a toast that already replaced this one;
    // _dismiss is a no-op in that case.
    _dismiss(request);
  }

  /// Dismisses [request] if it is still the visible toast, then shows the
  /// next queued request. Identity-checked so a stale timer or a late action
  /// tap can never remove a newer toast.
  static void _dismiss(_ToastRequest request) {
    if (!identical(_currentRequest, request)) return;
    _removeCurrent();
    _showNext();
  }

  static void _showNext() {
    if (_queue.isEmpty) return;
    _present(_queue.removeFirst());
  }

  static void _removeCurrent() {
    _timer?.cancel();
    _timer = null;
    final entry = _current;
    _current = null;
    _currentRequest = null;
    if (entry != null) {
      // remove() is safe even if the Overlay has since been disposed.
      entry
        ..remove()
        ..dispose();
    }
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({required this.request, required this.onAction});

  final _ToastRequest request;
  final VoidCallback onAction;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.transitionDuration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.transitionCurve,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.5),
    end: Offset.zero,
  ).animate(_curve);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduceMotion(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final color = request.variant.color;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          child: FadeTransition(
            opacity: _curve,
            child: SlideTransition(
              position: _slide,
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Material(
                  color: AppColors.surface,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(AppSpacing.md),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppSpacing.md),
                      border: Border.all(color: color.withValues(alpha: 0.5)),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Icon(request.variant.icon, color: color, size: 22),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            request.message,
                            style: AppTextStyles.bodyMedium,
                          ),
                        ),
                        if (request.actionLabel != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          TextButton(
                            onPressed: widget.onAction,
                            style: TextButton.styleFrom(foregroundColor: color),
                            child: Text(request.actionLabel!),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
