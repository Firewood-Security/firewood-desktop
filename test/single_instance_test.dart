import 'package:flutter_test/flutter_test.dart';
import 'package:firewood_desktop/src/services/single_instance_lock.dart';

void main() {
  group('SingleInstanceLock', () {
    test('lockSocketPath is valid, non-empty and never in /tmp', () {
      final path = SingleInstanceLock.lockSocketPath;
      expect(path, isNotNull);
      expect(path, isNotEmpty);
      expect(path, contains('.sock'));
      // V-023: the lock must never live in world-writable /tmp.
      expect(path, isNot(startsWith('/tmp/')));
    });

    test('acquireOrFocus acquires lock and releases cleanly', () async {
      final isPrimary = await SingleInstanceLock.acquireOrFocus();
      expect(isPrimary, isTrue);

      // A second call from the same or another client should see it's already running
      final isSecond = await SingleInstanceLock.acquireOrFocus();
      expect(isSecond, isFalse);

      // Release the lock
      await SingleInstanceLock.release();

      // After release, should be able to acquire again
      final isPrimaryAfterRelease = await SingleInstanceLock.acquireOrFocus();
      expect(isPrimaryAfterRelease, isTrue);

      await SingleInstanceLock.release();
    });
  });
}
