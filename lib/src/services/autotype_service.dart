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

  /// Checks if a compatible keyboard simulation tool is available on the host system.
  static Future<bool> isAvailable() async {
    if (_cachedAvailable != null) return _cachedAvailable!;

    if (Platform.isLinux) {
      if (File('/usr/bin/xdotool').existsSync() || File('/bin/xdotool').existsSync()) {
        _cachedAvailable = true;
        return true;
      }
      try {
        final res = await Process.run('which', ['xdotool']);
        _cachedAvailable = res.exitCode == 0;
        return _cachedAvailable!;
      } catch (_) {
        _cachedAvailable = false;
        return false;
      }
    }

    _cachedAvailable = false;
    return false;
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
        message: 'AutoType backend (xdotool) not found. Please install xdotool.',
      );
    }

    // Countdown giving user time to switch focus to target application
    for (var s = initialCountdownSeconds; s > 0; s--) {
      onCountdownTick?.call(s);
      await Future.delayed(const Duration(seconds: 1));
    }
    onCountdownTick?.call(0);

    final username = (item.fields['username'] ?? item.fields['email'] ?? '').toString();
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
    final res = await Process.run('xdotool', [
      'type',
      '--clearmodifiers',
      '--delay',
      delayMs.toString(),
      '--',
      text,
    ]);
    if (res.exitCode != 0) {
      throw Exception('xdotool type error: ${res.stderr}');
    }
  }

  static Future<void> _sendKey(String key) async {
    final res = await Process.run('xdotool', [
      'key',
      '--clearmodifiers',
      key,
    ]);
    if (res.exitCode != 0) {
      throw Exception('xdotool key error: ${res.stderr}');
    }
  }
}
