// Zero-knowledge desktop AutoType service.
// Safely injects credentials into target windows via synthetic keystrokes
// without exposing secrets to the clipboard or disk.

import 'dart:async';
import 'dart:io';

import 'package:otp/otp.dart';
import 'package:firewood_core/firewood_core.dart';

class AutoTypeResult {
  final bool success;
  final String message;

  const AutoTypeResult({required this.success, required this.message});
}

class AutoTypeService {
  AutoTypeService._();

  static const String defaultSequence = '{USERNAME}{TAB}{PASSWORD}{ENTER}';

  /// Cached detection result
  static bool? _cachedAvailable;
  static String? _resolvedXdotool;

  /// Resolves xdotool to an absolute path, preferring system directories.
  /// V-003: secrets must never reach a PATH lookup — a hijacked PATH could
  /// otherwise route them to an attacker-controlled binary. Returns null
  /// when no xdotool binary is found.
  static String? _resolveXdotool() {
    if (_resolvedXdotool != null) return _resolvedXdotool;
    if (!Platform.isLinux) return null;

    const preferred = [
      '/usr/bin/xdotool',
      '/bin/xdotool',
      '/usr/local/bin/xdotool'
    ];
    for (final p in preferred) {
      if (File(p).existsSync()) {
        _resolvedXdotool = p;
        return p;
      }
    }

    // Fall back to a PATH scan (pure Dart — no `which` subprocess).
    for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
      if (dir.isEmpty || !dir.startsWith('/')) continue;
      final p = '$dir/xdotool';
      if (File(p).existsSync()) {
        _resolvedXdotool = p;
        return p;
      }
    }
    return null;
  }

  /// Checks if a compatible keyboard simulation tool is available on the host system.
  static Future<bool> isAvailable() async {
    if (_cachedAvailable != null) return _cachedAvailable!;
    _cachedAvailable = _resolveXdotool() != null;
    return _cachedAvailable!;
  }

  /// Returns a human-friendly name of the active automation backend.
  static Future<String> getBackendName() async {
    if (await isAvailable()) {
      return 'xdotool (X11 / Xwayland)';
    }
    return 'Unavailable (requires xdotool)';
  }

  /// Executes an AutoType sequence for the given [item].
  ///
  /// [sequence] supports tokens:
  /// - `{USERNAME}`: user's login username or email
  /// - `{PASSWORD}`: login password
  /// - `{TAB}`: Tab key
  /// - `{ENTER}`: Return key
  /// - `{SPACE}`: Spacebar
  /// - `{TOTP}`: live 6-digit TOTP token (if totp_secret exists)
  /// - `{DELAY:ms}`: custom delay in milliseconds
  static Future<AutoTypeResult> execute({
    required DecryptedItem item,
    String sequence = defaultSequence,
    int initialCountdownSeconds = 2,
    int keyDelayMs = 15,
    void Function(int secondsRemaining)? onCountdownTick,
  }) async {
    final available = await isAvailable();
    if (!available) {
      return const AutoTypeResult(
        success: false,
        message:
            'AutoType backend (xdotool) not found. Please install xdotool.',
      );
    }

    // Countdown giving user time to switch focus to target application
    for (var s = initialCountdownSeconds; s > 0; s--) {
      onCountdownTick?.call(s);
      await Future.delayed(const Duration(seconds: 1));
    }
    onCountdownTick?.call(0);

    final username =
        (item.fields['username'] ?? item.fields['email'] ?? '').toString();
    final password = (item.fields['password'] ?? '').toString();
    final totpSecret = (item.fields['totp_secret'] ?? '').toString().trim();

    String? totpCode;
    if (totpSecret.isNotEmpty) {
      try {
        final clean = totpSecret.replaceAll(' ', '').toUpperCase();
        totpCode = OTP.generateTOTPCodeString(
          clean,
          DateTime.now().millisecondsSinceEpoch,
          algorithm: Algorithm.SHA1,
          isGoogle: true,
        );
      } catch (_) {}
    }

    try {
      final tokens = _tokenize(sequence);
      for (final token in tokens) {
        if (token == '{USERNAME}') {
          if (username.isNotEmpty) {
            await _typeText(username, keyDelayMs);
          }
        } else if (token == '{PASSWORD}') {
          if (password.isNotEmpty) {
            await _typeText(password, keyDelayMs);
          }
        } else if (token == '{TOTP}') {
          if (totpCode != null && totpCode.isNotEmpty) {
            await _typeText(totpCode, keyDelayMs);
          }
        } else if (token == '{TAB}') {
          await _sendKey('Tab');
        } else if (token == '{ENTER}') {
          await _sendKey('Return');
        } else if (token == '{SPACE}') {
          await _sendKey('space');
        } else if (token.startsWith('{DELAY:') && token.endsWith('}')) {
          final msStr = token.substring(7, token.length - 1);
          final ms = int.tryParse(msStr) ?? 100;
          await Future.delayed(Duration(milliseconds: ms));
        } else {
          // Literal text
          await _typeText(token, keyDelayMs);
        }
      }

      return const AutoTypeResult(
        success: true,
        message: 'AutoType sequence completed successfully.',
      );
    } catch (e) {
      return AutoTypeResult(
        success: false,
        message: 'AutoType failed: $e',
      );
    }
  }

  static List<String> _tokenize(String sequence) {
    final result = <String>[];
    final regex = RegExp(r'\{[A-Z0-9_:]+\}');
    var lastIndex = 0;

    for (final match in regex.allMatches(sequence)) {
      if (match.start > lastIndex) {
        result.add(sequence.substring(lastIndex, match.start));
      }
      result.add(match.group(0)!);
      lastIndex = match.end;
    }

    if (lastIndex < sequence.length) {
      result.add(sequence.substring(lastIndex));
    }

    return result;
  }

  static Future<void> _typeText(String text, int delayMs) async {
    final exe = _resolveXdotool();
    if (exe == null) {
      throw Exception('xdotool not found');
    }

    // V-003: never pass the text through argv — `/proc/<pid>/cmdline` is
    // world-readable, so a command-line password would leak to any local
    // user while typing.
    //
    // Delivery: `xdotool -` reads a script from stdin. The script contains
    // only the fixed placeholder `$FW_SECRET`; xdotool's script tokenizer
    // splits the script into tokens FIRST and then replaces a leading `$NAME`
    // with the environment value verbatim (no re-tokenization, no
    // re-expansion), so spaces, quotes, `$`, `#` and newlines inside the
    // secret are typed literally and cannot inject extra commands. The value
    // itself travels in `/proc/<pid>/environ`, which is owner-only
    // (0400) — invisible to other local users.
    final env = Map<String, String>.from(Platform.environment);
    env.remove('DEBUG'); // keep xdotool from debug-printing script args
    env['FW_SECRET'] = text;

    final proc = await Process.start(exe, ['-'], environment: env);

    proc.stdout.drain<void>();
    proc.stderr.drain<void>();
    try {
      proc.stdin
          .write('type --clearmodifiers --delay $delayMs -- \$FW_SECRET\n');
      await proc.stdin.flush();
    } finally {
      await proc.stdin.close();
    }

    final code = await proc.exitCode;
    if (code != 0) {
      throw Exception('xdotool type failed (exit code $code)');
    }
  }

  static Future<void> _sendKey(String key) async {
    final exe = _resolveXdotool();
    if (exe == null) {
      throw Exception('xdotool not found');
    }
    final res = await Process.run(exe, [
      'key',
      '--clearmodifiers',
      key,
    ]);
    if (res.exitCode != 0) {
      throw Exception('xdotool key error: ${res.stderr}');
    }
  }
}
