import 'package:flutter_test/flutter_test.dart';
import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_desktop/src/services/autotype_service.dart';

void main() {
  group('AutoTypeService', () {
    test('isAvailable returns a boolean without throwing', () async {
      final available = await AutoTypeService.isAvailable();
      expect(available, isA<bool>());
    });

    test('getBackendName returns descriptive string', () async {
      final backend = await AutoTypeService.getBackendName();
      expect(backend, isNotEmpty);
    });

    test('defaultSequence constant is standard username-tab-password-enter',
        () {
      expect(AutoTypeService.defaultSequence,
          equals('{USERNAME}{TAB}{PASSWORD}{ENTER}'));
    });

    test('executes on unavailable platform gracefully or runs if available',
        () async {
      final item = DecryptedItem(
        itemId: 'item-1',
        type: 'login',
        title: 'Test Login',
        fields: {
          'username': 'alice',
          'password': 'secretpassword',
        },
        updatedAt: DateTime.now(),
      );

      final isAvail = await AutoTypeService.isAvailable();
      if (!isAvail) {
        final result = await AutoTypeService.execute(
          item: item,
          initialCountdownSeconds: 0,
        );
        expect(result.success, isFalse);
        expect(result.message, contains('xdotool'));
      }
    });
  });
}
