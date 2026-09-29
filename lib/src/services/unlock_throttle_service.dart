// V-010: desktop unlock rate limiting.
//
// Mirrors the mobile native schedule (SecurePreferences.calculateBackoffSeconds
// in firewood-mobile/android/app/src/main/kotlin/net/firewood/app/security/
// SecurePreferences.kt):
//   <5 failures → no lockout
//    5 failures →   5 s
//    6 failures →  10 s
//    7 failures →  20 s
//    8 failures →  40 s
//    9 failures →  80 s
//   10+ failures → 300 s (5 minutes)
//
// The counter persists in `<XDG_CONFIG_HOME>/firewood/unlock_attempts.json`
// (dir 0700, file 0600 — same posture as the Quick Unlock payload) so a
// restart cannot launder failed attempts and other local users cannot tamper
// with it. In-memory counters back the file up for the session, so an
// unreadable state file degrades to session-scoped limiting instead of none.

import 'dart:convert';
import 'dart:io';

class UnlockThrottleService {
  UnlockThrottleService._();

  // Session-scoped fallback when the state file is unreadable/unwritable.
  static int _memAttempts = 0;
  static int _memLockoutUntilMs = 0;

  static String? get _configDir {
    final home = Platform.environment['HOME'];
    final base = Platform.environment['XDG_CONFIG_HOME'] ??
        (home != null && home.isNotEmpty ? '$home/.config' : null);
    if (base == null || base.isEmpty) return null;
    return '$base/firewood';
  }

  static File? get _stateFile {
    final dir = _configDir;
    return dir == null ? null : File('$dir/unlock_attempts.json');
  }

  /// How long the caller must still wait before the next attempt,
  /// or [Duration.zero] when attempts are allowed.
  static Duration remainingLockout() {
    var lockoutUntilMs = _memLockoutUntilMs;
    try {
      final file = _stateFile;
      if (file != null && file.existsSync()) {
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        lockoutUntilMs = (data['lockoutUntil'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {
      // Unreadable/corrupt state — the in-memory counters still apply.
    }
    final remaining = lockoutUntilMs - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? Duration(milliseconds: remaining) : Duration.zero;
  }

  /// Records a failed unlock attempt and returns the count after
  /// incrementing. From the 5th attempt on this starts the lockout.
  static Future<int> recordFailure() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var attempts = _memAttempts + 1;
    try {
      final file = _stateFile;
      if (file != null && file.existsSync()) {
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        attempts = ((data['attempts'] as num?)?.toInt() ?? 0) + 1;
      }
    } catch (_) {
      // Fall through with the in-memory count.
    }
    _memAttempts = attempts;

    final lockoutSeconds = backoffSecondsFor(attempts);
    if (lockoutSeconds > 0) {
      _memLockoutUntilMs = now + lockoutSeconds * 1000;
    }

    await _persist({
      'attempts': attempts,
      'lockoutUntil': _memLockoutUntilMs,
    });
    return attempts;
  }

  /// Clears the counter and lockout after a successful unlock.
  static Future<void> reset() async {
    _memAttempts = 0;
    _memLockoutUntilMs = 0;
    try {
      final file = _stateFile;
      if (file != null && file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// Exponential backoff schedule — identical to the mobile native
  /// implementation so both platforms throttle identically.
  static int backoffSecondsFor(int failedAttempts) {
    if (failedAttempts >= 10) return 300;
    if (failedAttempts >= 5) {
      final seconds = 5 << (failedAttempts - 5);
      return seconds > 300 ? 300 : seconds;
    }
    return 0;
  }

  static Future<void> _persist(Map<String, dynamic> data) async {
    final dirPath = _configDir;
    if (dirPath == null) return;
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      if (Platform.isLinux || Platform.isMacOS) {
        final res = Process.runSync('chmod', ['700', dirPath]);
        if (res.exitCode != 0) return;
      }
      final file = _stateFile!;
      file.writeAsStringSync(jsonEncode(data), flush: true);
      if (Platform.isLinux || Platform.isMacOS) {
        final res = Process.runSync('chmod', ['600', file.path]);
        if (res.exitCode != 0) {
          // Do not leave an unsecured counter file behind.
          file.deleteSync();
        }
      }
    } catch (_) {
      // Best effort: the in-memory counter still throttles this session.
    }
  }
}
