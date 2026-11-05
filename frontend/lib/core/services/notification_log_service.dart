import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_entry.dart';

/// On-device log of received push notifications.
///
/// Holds an in-memory cache (`_entries`) backed by `SharedPreferences`.
/// [init] must be called once at startup (see the AuthSuccess listener in
/// app_router.dart) to populate the cache from disk; every other
/// read/write below is synchronous and operates purely on that in-memory
/// cache, firing off a non-awaited persist afterwards. This keeps the API
/// usable from synchronous build methods (e.g. NotificationBellButton's
/// unread-count badge) without ever needing a `FutureBuilder`.
///
/// It is also a [ChangeNotifier]: every change to the in-memory log
/// ([init] finishing, [add], [markRead], [clear]) notifies listeners, so
/// widgets that show the log (the bell badge, the notification center)
/// rebuild themselves when a push arrives instead of waiting for an
/// unrelated parent rebuild.
///
/// The log belongs to the signed-in account: [clear] must run on logout so
/// the next account on this device does not inherit it.
class NotificationLogService extends ChangeNotifier {
  NotificationLogService._();
  static final NotificationLogService instance = NotificationLogService._();

  static const String _prefsKey = 'notification_log_v1';
  static const int _maxEntries = 50;

  List<NotificationEntry> _entries = [];

  /// Bumped by [clear]. A load or persist that started under an older
  /// generation must not write its (now stale) result back.
  int _generation = 0;

  /// Number of [init] calls currently waiting on disk. While non-zero,
  /// [_persist] is skipped: writing the in-memory list at that point would
  /// overwrite the on-disk history [init] has not read yet. [init] persists
  /// the merged result itself once it finishes.
  int _loadsInFlight = 0;

  /// Loads the in-memory cache from `SharedPreferences`. Call once at
  /// startup. Any failure (missing key, malformed JSON, wrong shape)
  /// leaves the loaded history empty rather than throwing.
  ///
  /// Entries added or marked read while the load is in flight are kept and
  /// take precedence over the copies read from disk, so an early push is
  /// never lost to the reload.
  Future<void> init() async {
    final generation = _generation;
    final before = _entries;
    _loadsInFlight++;
    List<NotificationEntry> loaded;
    try {
      final prefs = await SharedPreferences.getInstance();
      loaded = _decode(prefs.getString(_prefsKey));
    } catch (e) {
      debugPrint('⚠️ NotificationLogService: failed to load log: $e');
      loaded = [];
    } finally {
      _loadsInFlight--;
    }

    // Cleared (logout) while loading: the disk copy belongs to the
    // previous session, so drop it.
    if (generation != _generation) return;

    // Anything in the list now that was not there when the load started
    // was added (or re-created by markRead) during the load.
    final changed = _entries
        .where((e) => !before.any((b) => identical(b, e)))
        .toList();
    final changedIds = changed.map((e) => e.id).toSet();
    _entries = [
      ...changed,
      ...loaded.where((e) => !changedIds.contains(e.id)),
    ];
    if (_entries.length > _maxEntries) {
      _entries = _entries.sublist(0, _maxEntries);
    }
    if (changed.isNotEmpty) _persist();
    notifyListeners();
  }

  List<NotificationEntry> _decode(String? raw) {
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => NotificationEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Returns the in-memory log, newest first. Returns `[]` if called
  /// before [init] completes, or if [init] found nothing usable.
  List<NotificationEntry> getAll() => List.unmodifiable(_entries);

  /// Adds a new entry to the front of the log (newest first), mutating
  /// the in-memory list synchronously, then capping at [_maxEntries] by
  /// dropping the oldest entry/entries, then fires off a non-awaited
  /// persist of the resulting list.
  ///
  /// An entry whose [NotificationEntry.id] is already in the log is
  /// ignored, so the same push delivered twice is only logged once.
  void add(NotificationEntry entry) {
    if (_entries.any((e) => e.id == entry.id)) return;
    _entries = [entry, ..._entries];
    if (_entries.length > _maxEntries) {
      _entries = _entries.sublist(0, _maxEntries);
    }
    _persist();
    notifyListeners();
  }

  /// Marks the entry with the given [id] as read, if present. Synchronous
  /// mutate, then fire-and-forget persist — same pattern as [add].
  void markRead(String id) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index == -1) return;
    if (_entries[index].read) return;
    final updated = _entries[index].copyWith(read: true);
    _entries = [
      ..._entries.sublist(0, index),
      updated,
      ..._entries.sublist(index + 1),
    ];
    _persist();
    notifyListeners();
  }

  /// Empties the log, in memory and on disk. Called on logout so the next
  /// account signed in on this device starts with an empty log. The
  /// in-memory reset (and the listener notification) happens synchronously;
  /// the returned future completes once the persisted copy is removed.
  /// Never throws.
  Future<void> clear() async {
    _generation++;
    _entries = [];
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('⚠️ NotificationLogService: failed to clear log: $e');
    }
  }

  /// Number of entries in the in-memory log that are not yet read.
  int get unreadCount => _entries.where((e) => !e.read).length;

  /// Fires off a non-awaited write of the current in-memory list to
  /// `SharedPreferences`. Failures are swallowed — persistence is
  /// best-effort; the in-memory cache remains the source of truth for the
  /// rest of this app session. This must never throw back into `add`/
  /// `markRead`, so the JSON encoding itself (not just the write) is
  /// guarded too — a non-serializable value in some entry's `data` map
  /// should not be able to blow up a synchronous caller.
  void _persist() {
    if (_loadsInFlight > 0) return;
    final generation = _generation;
    try {
      final encoded = jsonEncode(_entries.map((e) => e.toJson()).toList());
      // ignore: discarded_futures
      SharedPreferences.getInstance().then((prefs) {
        // A clear() since this write was queued means the list it holds
        // belongs to the previous session — do not write it back.
        if (generation != _generation) return false;
        return prefs.setString(_prefsKey, encoded);
      }).catchError((e) {
        debugPrint('⚠️ NotificationLogService: failed to persist log: $e');
        return false;
      });
    } catch (e) {
      debugPrint('⚠️ NotificationLogService: failed to persist log: $e');
    }
  }
}
