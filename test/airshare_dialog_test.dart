import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_desktop/src/widgets/airshare_dialog.dart';

void main() {
  testWidgets('AirShareDialog renders Spark QR and switches to 4-Digit Flame Code', (tester) async {
    final testItem = DecryptedItem(
      itemId: 'item-demo-1',
      type: 'login',
      title: 'Demo Work Account',
      fields: {
        'username': 'demo_user',
        'password': 'SecureDemoPassword123!',
      },
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AirShareDialog.show(
                  context,
                  item: testItem,
                  role: AirShareRole.send,
                ),
                child: const Text('Open AirShare'),
              ),
            ),
          ),
        ),
      ),
    );

    // Tap button to open AirShare dialog
    await tester.tap(find.text('Open AirShare'));
    await tester.pumpAndSettle();

    // Verify dialog header
    expect(find.text('Firewood AirShare'), findsOneWidget);
    expect(find.text('Spark Mode'), findsOneWidget);
    expect(find.text('Flame Code'), findsOneWidget);

    // Switch to Flame Code mode
    await tester.tap(find.text('Flame Code'));
    await tester.pumpAndSettle();

    // Verify 4-digit Flame Code section
    expect(find.text('Verify 4-Digit Flame Code'), findsOneWidget);
    expect(find.text('I confirm the 4-digit Flame Code matches the receiver.'), findsOneWidget);

    // Switch to Receive transfer
    await tester.tap(find.text('Receive'));
    await tester.pumpAndSettle();

    expect(find.text('Incoming Connection Flame Code'), findsOneWidget);
    expect(find.text('Accept & Decrypt'), findsOneWidget);
  });
}
