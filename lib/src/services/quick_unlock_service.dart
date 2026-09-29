// Desktop Quick Unlock & Biometric Service
// Allows fast vault unlock via device PIN or system biometrics (fprintd/PAM)
// without re-typing long master passwords on every auto-lock.
//
// V-004 hardening:
//  * Payload lives in a private file (dir 0700, file 0600) instead of
//    shared_preferences, which may be world-readable.
//  * Payload is versioned (v2). Legacy plaintext payloads are wiped on
//    sight — re-enable with a 6-digit PIN.
//  * Plaintext metadata (requireBiometric, createdAt) is bound to the
//    PIN-derived key with HMAC-SHA256; any edit invalidates it and the
//    blob is wiped (fail closed).
//  * PIN floor raised to 6 digits; payload expires after 7 days.
//  * Every parse/decrypt/permission anomaly disables Quick Unlock instead
//    of continuing with attacker-influenced state.

import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firewood_core/firewood_core.dart';

class QuickUnlockService {
  static const _payloadVersion = 2;
  static const int maxFailedAttempts = 3;
  static const Duration maxAge = Duration(days: 7);

  // Legacy (v1, pre-hardening) shared_preferences keys — purged on sight.
  static const _legacyPayloadKey = 'firewood_quick_unlock_v1';
  static const _legacyCounterKey = 'firewood_quick_unlock_failed_attempts';

  final CryptoService _crypto = CryptoService();

  // ---------------------------------------------------------------- storage

  /// Private config directory for Quick Unlock state. Null when no home
  /// directory is available — Quick Unlock then stays disabled (fail closed).
  static String? get _configDir {
    final home = Platform.environment['HOME'];
    final base = Platform.environment['XDG_CONFIG_HOME'] ??
        (home != null && home.isNotEmpty ? '$home/.config' : null);
    if (base == null || base.isEmpty) return null;
    return '$base/firewood';
  }

  static File? get _payloadFile {
    final dir = _configDir;
    return dir == null ? null : File('$dir/quick_unlock.json');
  }

  /// Ensures the config dir exists with 0700. Returns false on failure.
  static bool _prepareConfigDir() {
    final dirPath = _configDir;
    if (dirPath == null) return false;
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      if (Platform.isLinux || Platform.isMacOS) {
        final res = Process.runSync('chmod', ['700', dirPath]);
        if (res.exitCode != 0) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Writes the payload and locks it to 0600. Fails closed: if permissions
  /// cannot be enforced, the file is removed and an error is thrown so no
  /// insecure Quick Unlock state ever persists.
  static Future<void> _writePayload(Map<String, dynamic> payload) async {
    if (!_prepareConfigDir()) {
      throw const VaultException(
          'Cannot secure the Quick Unlock directory permissions.');
    }
    final file = _payloadFile!;
    try {
      file.writeAsStringSync(jsonEncode(payload), flush: true);
      if (Platform.isLinux || Platform.isMacOS) {
        final res = Process.runSync('chmod', ['600', file.path]);
        if (res.exitCode != 0) {
          file.deleteSync();
          throw const VaultException(
              'Cannot secure the Quick Unlock file permissions.');
        }
      }
    } on FileSystemException {
      throw const VaultException('Cannot write Quick Unlock state.');
    }
  }

  /// Reads and decodes the payload. Returns null when not configured.
  /// Returns a corrupted marker via [VaultException] on parse errors so the
  /// caller can wipe and fail closed.
  static Future<Map<String, dynamic>?> _readPayload(
      {bool wipeOnCorrupt = true}) async {
    final file = _payloadFile;
    if (file == null || !file.existsSync()) return null;
    String raw;
    try {
      raw = file.readAsStringSync();
    } catch (_) {
      return null;
    }
    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) return data;
      throw const FormatException('not an object');
    } catch (_) {
      if (wipeOnCorrupt) await _wipe();
      throw const VaultException('Corrupted Quick Unlock configuration');
    }
  }

  /// Updates the (plaintext, best-effort) attempt counter inside the payload
  /// without touching the authenticated fields.
  static Future<void> _writeCounter(
      Map<String, dynamic> data, int count) async {
    data['failedAttempts'] = count;
    try {
      await _writePayload(data);
    } catch (_) {
      // Best effort: if we cannot persist, the next attempt re-reads state.
    }
  }

  /// Removes Quick Unlock state and legacy prefs keys (static core).
  static Future<void> _wipe() async {
    final file = _payloadFile;
    if (file != null && file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyPayloadKey);
      await prefs.remove(_legacyCounterKey);
    } catch (_) {}
  }

  /// Removes Quick Unlock configuration completely.
  Future<void> disableQuickUnlock() => _wipe();

  // -------------------------------------------------------------- biometrics

  /// Checks if system fingerprint daemon or biometric helper is installed on Linux.
  Future<bool> isBiometricHardwareAvailable() async {
    if (!Platform.isLinux) return false;
    try {
      if (File('/usr/bin/fprintd-verify').existsSync()) {
        final res = await Process.run(
            'fprintd-list', [Platform.environment['USER'] ?? '']);
        // If devices exist and not "No devices available"
        if (res.exitCode == 0 &&
            !res.stdout.toString().contains('No devices available')) {
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
      final process =
          await Process.run('fprintd-verify', [if (user.isNotEmpty) user]);
      return process.exitCode == 0 &&
          process.stdout.toString().contains('verify-match');
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- queries

  /// Checks whether Quick Unlock has been configured and is active.
  Future<bool> isEnabled() async {
    await _purgeLegacyState();
    final file = _payloadFile;
    return file != null && file.existsSync();
  }

  /// Checks if biometric verification is enforced for Quick Unlock.
  Future<bool> requiresBiometric() async {
    final data = await _readPayload();
    if (data == null || data['v'] != _payloadVersion) return false;
    return data['requireBiometric'] == true;
  }

  /// Purges any pre-hardening (v1) shared_preferences state.
  static Future<void> _purgeLegacyState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_legacyPayloadKey) ||
          prefs.containsKey(_legacyCounterKey)) {
        await prefs.remove(_legacyPayloadKey);
        await prefs.remove(_legacyCounterKey);
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------------- MAC

  /// Canonical metadata covered by the PIN-derived HMAC. Must be byte-identical
  /// at enable time and at verification time.
  static List<int> _macInput(Map<String, dynamic> data) {
    final meta = {
      'v': _payloadVersion,
      'requireBiometric': data['requireBiometric'] == true,
      'createdAt': data['createdAt']?.toString() ?? '',
    };
    return utf8.encode(jsonEncode(meta));
  }

  static Future<List<int>> _mac(List<int> input, SecretKey pinKey) async {
    final mac = await Hmac.sha256().calculateMac(input, secretKey: pinKey);
    return mac.bytes;
  }

  static bool _macMatches(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // ---------------------------------------------------------------- enable

  /// Sets up Quick Unlock by wrapping the existing MEK with a PIN-derived key.
  Future<void> enableQuickUnlock({
    required SecretKey currentMek,
    required String pin,
    bool requireBiometric = false,
  }) async {
    await _purgeLegacyState();
    if (pin.length < 6 || !RegExp(r'^[0-9]+$').hasMatch(pin)) {
      throw const VaultException('Quick Unlock PIN must be at least 6 digits');
    }

    final mekBytes = await currentMek.extractBytes();
    final salt = _crypto.generateSalt();
    final pinKey = await _crypto.deriveKey(pin, salt);
    // V-028: wrap under a purpose subkey — this ciphertext is never
    // directly decryptable as/with the PIN key used for the payload MAC
    // below (HMAC domain vs AEAD wrap domain), and pre-V-028 blobs written
    // under the raw PIN key still load via the legacy fallback.
    final wrapKey =
        await _crypto.deriveSubkey(pinKey, CryptoService.purposeQuickUnlock);
    final enc = await _crypto.encrypt(mekBytes, wrapKey);

    final payload = <String, dynamic>{
      'v': _payloadVersion,
      'salt': base64Encode(salt),
      'wrappedMek': base64Encode(enc.ciphertext),
      'nonce': base64Encode(enc.nonce),
      'requireBiometric': requireBiometric,
      'createdAt': DateTime.now().toIso8601String(),
      'failedAttempts': 0,
    };
    // Bind the plaintext metadata to the PIN-derived key: flipping the
    // biometric flag or back-dating createdAt invalidates this MAC.
    payload['mac'] = base64Encode(await _mac(_macInput(payload), pinKey));

    await _writePayload(payload);
  }

  // ---------------------------------------------------------------- unlock

  /// Unlocks the vault using the Quick PIN and optional biometric check.
  Future<SecretKey> unlockWithPin(String pin) async {
    await _purgeLegacyState();
    final data = await _readPayload();
    if (data == null) {
      throw const VaultException('Quick Unlock is not enabled');
    }

    // V-004: only the hardened v2 payload is honored. Anything else (legacy
    // plaintext state, mixed/edited files) is wiped and the user must
    // re-enable with the master password + a 6-digit PIN.
    if (data['v'] != _payloadVersion) {
      await disableQuickUnlock();
      throw const VaultException(
          'Quick Unlock was reset for security reasons. Unlock with your master password, then re-enable it with a 6-digit PIN.');
    }

    final failedAttempts = (data['failedAttempts'] as num?)?.toInt() ?? 0;
    if (failedAttempts >= maxFailedAttempts) {
      await disableQuickUnlock();
      throw const VaultException(
        'Too many failed PIN attempts. Quick Unlock disabled. Unlock with master password.',
      );
    }

    // TTL: expire old blobs so a stale wrapped MEK does not sit on disk.
    final created = DateTime.tryParse(data['createdAt']?.toString() ?? '');
    final now = DateTime.now();
    if (created == null ||
        now.difference(created) > maxAge ||
        created.isAfter(now.add(const Duration(minutes: 10)))) {
      await disableQuickUnlock();
      throw const VaultException(
          'Quick Unlock expired. Unlock with master password and re-enable it.');
    }

    if (data['requireBiometric'] == true) {
      final bioSuccess = await verifyFingerprint();
      if (!bioSuccess) {
        throw const VaultException('Biometric verification failed');
      }
    }

    final String saltB64;
    final String wrappedB64;
    final String nonceB64;
    try {
      saltB64 = data['salt'] as String;
      wrappedB64 = data['wrappedMek'] as String;
      nonceB64 = data['nonce'] as String;
    } catch (_) {
      await disableQuickUnlock();
      throw const VaultException('Corrupted Quick Unlock configuration');
    }

    final salt = base64Decode(saltB64);
    final ciphertext = base64Decode(wrappedB64);
    final nonce = base64Decode(nonceB64);

    late final SecretKey pinKey;
    late final List<int> mekBytes;
    try {
      pinKey = await _crypto.deriveKey(pin, salt);
      // V-028: subkey unwrap first, then the pre-V-028 raw-PIN-key format.
      mekBytes = await _crypto.decryptBoundOrLegacy(ciphertext, nonce, pinKey,
          purpose: CryptoService.purposeQuickUnlock);
    } catch (_) {
      final updated = failedAttempts + 1;
      await _writeCounter(data, updated);
      final remaining = maxFailedAttempts - updated;
      if (remaining <= 0) {
        await disableQuickUnlock();
        throw const VaultException(
          'Incorrect PIN. Quick Unlock disabled. Master password required.',
        );
      }
      throw VaultException(
          'Incorrect PIN. $remaining attempt${remaining == 1 ? '' : 's'} remaining.');
    }

    // V-004: the decrypted payload is authentic for THIS PIN — now verify the
    // plaintext metadata was not edited (biometric flag, timestamp). Any
    // mismatch means tampering: wipe the blob and fail closed.
    final List<int> storedMac;
    try {
      storedMac = base64Decode(data['mac'] as String);
    } catch (_) {
      await disableQuickUnlock();
      throw const VaultException(
          'Quick Unlock data is incomplete or tampered with. Unlock with master password.');
    }
    final computedMac = await _mac(_macInput(data), pinKey);
    if (!_macMatches(storedMac, computedMac)) {
      await disableQuickUnlock();
      throw const VaultException(
          'Quick Unlock data was tampered with. Unlock with master password.');
    }

    await _writeCounter(data, 0);
    return SecretKey(mekBytes);
  }
}
