import 'package:flutter/material.dart';

/// Lazily mounts a bottom-nav tab's screen the first time it's selected,
/// then keeps it mounted (switching back and forth doesn't lose its
/// state or rebuild it from scratch) — without this, every tab's screen
/// would build eagerly at dashboard startup even if the user never
/// visits it.
///
/// Replaces an identical pattern (a dedicated `bool _xVisited` field +
/// an `if (!_xVisited && _currentIndex == n) _xVisited = true;` check)
/// that was copy-pasted independently per tab across
/// MerchantDashboardScreen (3 tabs) and CustomerDashboardScreen (1 tab).
mixin LazyTabMixin<T extends StatefulWidget> on State<T> {
  final Set<int> _visitedTabIndexes = {};

  Widget lazyTab(int index, int currentIndex, Widget Function() builder) {
    if (currentIndex == index) {
      _visitedTabIndexes.add(index);
    }
    return _visitedTabIndexes.contains(index)
        ? builder()
        : const SizedBox.shrink();
  }

  /// True exactly once per tab index — the first time it becomes the
  /// current tab. For a tab that always renders its real content (so
  /// [lazyTab] doesn't apply) but needs a one-time side effect on first
  /// visit, such as an initial data load, instead of re-running it on
  /// every rebuild.
  bool onFirstVisit(int index, int currentIndex) {
    if (currentIndex == index && !_visitedTabIndexes.contains(index)) {
      _visitedTabIndexes.add(index);
      return true;
    }
    return false;
  }
}
