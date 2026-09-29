// Adversarial tests for Quick Unlock hardening (audit finding V-004).
// Note: QuickUnlockService stores state in `<HOME>/.config/firewood/
// quick_unlock.json` — these tests create and remove that file.

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_desktop/src/services/quick_unlock_service.dart';

File payloadFile() =>
    File('${Platform.environment['HOME']}/.config/firewood/quick_unlock.json');

Future<void> wipe() async {
  if (payloadFile().existsSync()) payloadFile().deleteSync();
}

void main() {
  final svc = QuickUnlockService();
  final mek = SecretKey(List<int>.generate(32, (i) => i));

  setUp(wipe);
  tearDown(wipe);

  group('V-004 PIN floor', () {
    test('rejects PINs shorter than 6 digits and non-digit PINs', () async {
      for (final bad in ['1', '1234', '12345', 'abcdef', 'ab12cd', '12345x']) {
        await expectLater(
          svc.enableQuickUnlock(currentMek: mek, pin: bad),
          throwsA(isA<VaultException>()),
          reason: 'PIN "$bad" must be rejected',
        );
        expect(payloadFile().existsSync(), isFalse,
            reason: 'failed enable must not persist state');
      }
      await svc.enableQuickUnlock(currentMek: mek, pin: '123456');
      expect(payloadFile().existsSync(), isTrue);
      expect(await svc.isEnabled(), isTrue);
    });
  });

  group('V-004 roundtrip & lockout', () {
    test('correct 6-digit PIN unlocks and returns the MEK', () async {
      await svc.enableQuickUnlock(currentMek: mek, pin: '654321');
      final out = await svc.unlockWithPin('654321');
      expect(await out.extractBytes(), await mek.extractBytes());
    });

    test('three wrong PINs disable Quick Unlock and wipe the payload',
        () async {
      await svc.enableQuickUnlock(currentMek: mek, pin: '654321');
      for (var i = 1; i <= 2; i++) {
        await expectLater(
          svc.unlockWithPin('999999'),
          throwsA(isA<VaultException>()),
        );
        expect(payloadFile().existsSync(), isTrue,
            reason: 'blob must survive until the attempt limit');
      }
      await expectLater(
        svc.unlockWithPin('999999'),
        throwsA(isA<VaultException>()),
      );
      expect(payloadFile().existsSync(), isFalse,
          reason: 'attempt limit must wipe the payload');
      expect(await svc.isEnabled(), isFalse);
    });

    test('attempt counter is stored in the 0600 payload file, not prefs',
        () async {
      await svc.enableQuickUnlock(currentMek: mek, pin: '654321');
      await expectLater(
        svc.unlockWithPin('000000'),
        throwsA(isA<VaultException>()),
      );
      final data = jsonDecode(payloadFile().readAsStringSync());
      expect(data['failedAttempts'], 1);
      expect(data['v'], 2);
      // Ground truth via /bin/stat: this machine's Dart runtime misreports
      // FileStat.mode (reads 400 for a 600 file), so don't trust statSync here.
      final st = Process.runSync('stat', ['-c', '%a', payloadFile().path]);
      expect((st.stdout as String).trim(), '600');
    });
  });

  group('V-004 tamper detection (fail closed)', () {
    test('editing createdAt with the CORRECT PIN is detected and wiped',
        () async {
      await svc.enableQuickUnlock(currentMek: mek, pin: '654321');

      // Attacker back-dates the timestamp (still inside TTL) to try to
      // extend the blob's life. The HMAC over the metadata no longer matches.
      final data = jsonDecode(payloadFile().readAsStringSync());
      data['createdAt'] =
          DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
      payloadFile().writeAsStringSync(jsonEncode(data));

      await expectLater(
        svc.unlockWithPin('654321'),
        throwsA(isA<VaultException>()),
      );
      expect(payloadFile().existsSync(), isFalse,
          reason: 'tampered payload must be wiped');
      expect(await svc.isEnabled(), isFalse);
    });

    test('flipping requireBiometric is detected at unlock (correct PIN)',
        () async {
      await svc.enableQuickUnlock(
          currentMek: mek, pin: '654321', requireBiometric: false);
      final data = jsonDecode(payloadFile().readAsStringSync());
      data['requireBiometric'] = true; // try to force bio on/off
      payloadFile().writeAsStringSync(jsonEncode(data));

      // Bio gate triggers first (no fprintd match here) → denied either way.
      await expectLater(
        svc.unlockWithPin('654321'),
        throwsA(isA<VaultException>()),
      );
    });

    test('expired payload (TTL > 7 days) is wiped', () async {
      await svc.enableQuickUnlock(currentMek: mek, pin: '654321');
      final data = jsonDecode(payloadFile().readAsStringSync());
      data['createdAt'] =
          DateTime.now().subtract(const Duration(days: 8)).toIso8601String();
      payloadFile().writeAsStringSync(jsonEncode(data));

      await expectLater(
        svc.unlockWithPin('654321'),
        throwsA(isA<VaultException>()),
      );
      expect(payloadFile().existsSync(), isFalse);
    });

    test('legacy v1 payload (no version) is wiped, not honored', () async {
      payloadFile().parent.createSync(recursive: true);
      payloadFile().writeAsStringSync(jsonEncode({
        'salt': 'AAAA',
        'wrappedMek': 'BBBB',
        'nonce': 'CCCC',
        'requireBiometric': false,
        'createdAt': DateTime.now().toIso8601String(),
      }));

      await expectLater(
        svc.unlockWithPin('123456'),
        throwsA(isA<VaultException>()),
      );
      expect(payloadFile().existsSync(), isFalse,
          reason: 'legacy plaintext payload must be wiped');
    });

    test('garbage payload is wiped, not honored', () async {
      payloadFile().parent.createSync(recursive: true);
      payloadFile().writeAsStringSync('not json at all {{{');

      await expectLater(
        svc.unlockWithPin('123456'),
        throwsA(isA<VaultException>()),
      );
      expect(payloadFile().existsSync(), isFalse);
    });
  });
}
