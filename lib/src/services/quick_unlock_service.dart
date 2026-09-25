// Desktop Quick Unlock & Biometric Service
// Allows fast vault unlock via device PIN or system biometrics (fprintd/PAM)
// without re-typing long master passwords on every auto-lock.

import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firewood_core/firewood_core.dart';

class QuickUnlockService {
  static const _prefKey = 'firewood_quick_unlock_v1';
  static const _failedAttemptsKey = 'firewood_quick_unlock_failed_attempts';
  static const int maxFailedAttempts = 3;

  final CryptoService _crypto = CryptoService();

  /// Checks if system fingerprint daemon or biometric helper is installed on Linux.
  Future<bool> isBiometricHardwareAvailable() async {
    if (!Platform.isLinux) return false;
    try {
      if (File('/usr/bin/fprintd-verify').existsSync()) {
        final res = await Process.run('fprintd-list', [Platform.environment['USER'] ?? '']);
        // If devices exist and not "No devices available"
        if (res.exitCode == 0 && !res.stdout.toString().contains('No devices available')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Verifies user fingerprint via fprintd on Linux.
  Future<bool> verifyFingerprint() async {
    if (!Platform.isLinux) return false;
    try {
      final user = Platform.environment['USER'] ?? '';
      final process = await Process.run('fprintd-verify', [if (user.isNotEmpty) user]);
      return process.exitCode == 0 && process.stdout.toString().contains('verify-match');
    } catch (_) {
      return false;
    }
  }

  /// Checks whether Quick Unlock has been configured and is active.
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_prefKey);
  }

  /// Checks if biometric verification is enforced for Quick Unlock.
  Future<bool> requiresBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return false;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map['requireBiometric'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Sets up Quick Unlock by wrapping the existing MEK with a PIN-derived key.
  Future<void> enableQuickUnlock({
    required SecretKey currentMek,
    required String pin,
    bool requireBiometric = false,
  }) async {
    if (pin.length < 4) {
      throw const VaultException('Quick Unlock PIN must be at least 4 digits');
    }

    final mekBytes = await currentMek.extractBytes();
    final salt = _crypto.generateSalt();
    final pinKey = await _crypto.deriveKey(pin, salt);
    final enc = await _crypto.encrypt(mekBytes, pinKey);

    final payload = {
      'salt': base64Encode(salt),
      'wrappedMek': base64Encode(enc.ciphertext),
      'nonce': base64Encode(enc.nonce),
      'requireBiometric': requireBiometric,
      'createdAt': DateTime.now().toIso8601String(),
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(payload));
    await prefs.setInt(_failedAttemptsKey, 0);
  }

  /// Unlocks the vault using the Quick PIN and optional biometric check.
  Future<SecretKey> unlockWithPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) {
      throw const VaultException('Quick Unlock is not enabled');
    }

    final failedAttempts = prefs.getInt(_failedAttemptsKey) ?? 0;
    if (failedAttempts >= maxFailedAttempts) {
      await disableQuickUnlock();
      throw const VaultException(
        'Too many failed PIN attempts. Quick Unlock disabled. Unlock with master password.',
      );
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await disableQuickUnlock();
      throw const VaultException('Corrupted Quick Unlock configuration');
    }

    if (data['requireBiometric'] == true) {
      final bioSuccess = await verifyFingerprint();
      if (!bioSuccess) {
        throw const VaultException('Biometric verification failed');
      }
    }

    final salt = base64Decode(data['salt'] as String);
    final ciphertext = base64Decode(data['wrappedMek'] as String);
    final nonce = base64Decode(data['nonce'] as String);

    try {
      final pinKey = await _crypto.deriveKey(pin, salt);
      final mekBytes = await _crypto.decrypt(ciphertext, nonce, pinKey);
      await prefs.setInt(_failedAttemptsKey, 0);
      return SecretKey(mekBytes);
    } catch (_) {
      final updated = failedAttempts + 1;
      await prefs.setInt(_failedAttemptsKey, updated);
      final remaining = maxFailedAttempts - updated;
      if (remaining <= 0) {
        await disableQuickUnlock();
        throw const VaultException(
          'Incorrect PIN. Quick Unlock disabled. Master password required.',
        );
      }
      throw VaultException('Incorrect PIN. $remaining attempt${remaining == 1 ? '' : 's'} remaining.');
    }
  }

  /// Removes Quick Unlock configuration completely.
  Future<void> disableQuickUnlock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    await prefs.remove(_failedAttemptsKey);
  }
}
