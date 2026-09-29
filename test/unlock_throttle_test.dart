// Adversarial tests for desktop unlock rate limiting (audit finding V-010).
// State lives in `<HOME>/.config/firewood/unlock_attempts.json` — these tests
// create and remove that file, exactly like quick_unlock_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:firewood_desktop/src/services/unlock_throttle_service.dart';

File stateFile() => File(
    '${Platform.environment['HOME']}/.config/firewood/unlock_attempts.json');

Future<void> wipe() async {
  await UnlockThrottleService.reset();
  if (stateFile().existsSync()) stateFile().deleteSync();
}

void main() {
  setUp(wipe);
  tearDown(wipe);

  group(
      'V-010 backoff schedule (mirrors SecurePreferences.calculateBackoffSeconds)',
      () {
    test('exact mobile-parity schedule', () {
      expect(UnlockThrottleService.backoffSecondsFor(0), 0);
      expect(UnlockThrottleService.backoffSecondsFor(1), 0);
      expect(UnlockThrottleService.backoffSecondsFor(4), 0,
          reason: 'first four attempts are unthrottled');
      expect(UnlockThrottleService.backoffSecondsFor(5), 5);
      expect(UnlockThrottleService.backoffSecondsFor(6), 10);
      expect(UnlockThrottleService.backoffSecondsFor(7), 20);
      expect(UnlockThrottleService.backoffSecondsFor(8), 40);
      expect(UnlockThrottleService.backoffSecondsFor(9), 80);
      expect(UnlockThrottleService.backoffSecondsFor(10), 300);
      expect(UnlockThrottleService.backoffSecondsFor(11), 300);
      expect(UnlockThrottleService.backoffSecondsFor(1000), 300,
          reason: 'capped at 300 s — no unbounded growth');
    });
  });

  group('V-010 persisted counter', () {
    test('first four failures stay unthrottled, fifth locks out', () async {
      for (var i = 1; i <= 4; i++) {
        final count = await UnlockThrottleService.recordFailure();
        expect(count, i);
        expect(UnlockThrottleService.remainingLockout(), Duration.zero,
            reason: 'failure #$i must not lock out');
      }
      await UnlockThrottleService.recordFailure();
      final lockout = UnlockThrottleService.remainingLockout();
      expect(lockout, greaterThan(Duration.zero),
          reason: 'fifth failure must start the 5 s lockout');
      expect(lockout, lessThan(const Duration(seconds: 6)));
    });

    test('counter is persisted to disk (restart cannot launder attempts)',
        () async {
      for (var i = 1; i <= 5; i++) {
        await UnlockThrottleService.recordFailure();
      }
      expect(stateFile().existsSync(), isTrue,
          reason: 'counter file must exist after failures');
      final data = jsonDecode(stateFile().readAsStringSync());
      expect(data['attempts'], 5);
      expect((data['lockoutUntil'] as num).toInt(),
          greaterThan(DateTime.now().millisecondsSinceEpoch));
    });

    test('successful unlock resets counter and removes the file', () async {
      for (var i = 0; i < 6; i++) {
        await UnlockThrottleService.recordFailure();
      }
      expect(
          UnlockThrottleService.remainingLockout(), greaterThan(Duration.zero));
      await UnlockThrottleService.reset();
      expect(UnlockThrottleService.remainingLockout(), Duration.zero);
      expect(stateFile().existsSync(), isFalse);
    });

    test('lockout state file is chmod 600', () async {
      for (var i = 0; i < 5; i++) {
        await UnlockThrottleService.recordFailure();
      }
      expect(stateFile().existsSync(), isTrue);
      if (Platform.isLinux) {
        final res = Process.runSync('stat', ['-c', '%a', stateFile().path]);
        expect(res.stdout.toString().trim(), '600',
            reason: 'counter file must not be readable by other users');
      }
    });

    test('corrupt state file degrades to session counter, not fail-open',
        () async {
      stateFile().parent.createSync(recursive: true);
      stateFile().writeAsStringSync('{not json');
      // First record falls back to memory (attempts = 0 + 1) and rewrites
      // a valid file.
      final count = await UnlockThrottleService.recordFailure();
      expect(count, 1);
      final data = jsonDecode(stateFile().readAsStringSync());
      expect(data['attempts'], 1,
          reason: 'a corrupt file must not silently disable counting');
    });
  });
}
