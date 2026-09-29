import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_desktop/src/widgets/airshare_dialog.dart';

void main() {
  testWidgets('AirShareDialog renders local QR send and switches to receive',
      (tester) async {
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

    // Verify dialog header and local QR badge
    expect(find.text('AirShare'), findsOneWidget);
    expect(find.text('Local QR P2P'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('Receive'), findsOneWidget);

    // Switch to Receive transfer (using pump since QR display has continuous animation)
    await tester.tap(find.text('Receive'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
        find.text('Display this QR code to the sender device'), findsOneWidget);
  });
}
