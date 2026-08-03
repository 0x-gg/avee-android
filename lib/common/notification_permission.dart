import 'package:shared_preferences/shared_preferences.dart';

/// Tracks whether the one-shot POST_NOTIFICATIONS prompt has already fired
/// (Android 13+). We ask exactly once — on the first successful VPN connect —
/// so the foreground-service VPN notification (uptime/speed) becomes visible.
/// The OS owns every subsequent grant flow; we never re-prompt.
///
/// Mirrors [VpnConsent]: minimal, versioned, best-effort. A failed read is
/// treated as "already requested" so a broken prefs store can't nag on every
/// connect.
class NotificationPermissionPrompt {
  const NotificationPermissionPrompt();

  /// Storage key for the one-shot flag. Public so callers/tests can inspect it.
  static const String storageKey = 'post_notifications_requested_v1';

  /// Returns true once the prompt has been fired. On a prefs failure returns
  /// true (fail-closed) so we don't re-request on a store we can't persist to.
  Future<bool> isRequested() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(storageKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  /// Persists the one-shot flag. Returns true on success.
  Future<bool> markRequested() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(storageKey, true);
    } catch (_) {
      return false;
    }
  }
}

/// Default instance — use this everywhere except in tests that need isolation.
const notificationPermissionPrompt = NotificationPermissionPrompt();
