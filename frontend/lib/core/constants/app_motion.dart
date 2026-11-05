import 'package:flutter/material.dart';

/// Shared motion constants: durations and curves for the app's small
/// animations (button presses, page transitions, list entrances), plus a
/// helper to respect the platform's "reduce motion" accessibility setting.
class AppMotion {
  AppMotion._();

  /// Short, snappy animation used for micro-interactions such as button
  /// press feedback.
  static const Duration microDuration = Duration(milliseconds: 150);
  static const Curve microCurve = Curves.easeOut;

  /// Used for screen/page transitions.
  static const Duration transitionDuration = Duration(milliseconds: 250);
  static const Curve transitionCurve = Curves.easeInOut;

  /// Used for list-entrance animations: how long each item's entrance
  /// animation takes, and the delay staggered between successive items.
  static const Duration listEntranceDuration = Duration(milliseconds: 300);
  static const Duration listStaggerDelay = Duration(milliseconds: 40);

  /// Whether the user has requested reduced motion, per the platform
  /// accessibility setting. Callers should skip or shorten non-essential
  /// animations when this is true.
  static bool reduceMotion(BuildContext context) {
    return MediaQuery.of(context).disableAnimations;
  }
}
