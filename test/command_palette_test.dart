import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_desktop/src/providers.dart';
import 'package:firewood_desktop/src/widgets/command_palette.dart';

void main() {
  testWidgets('DesktopCommandPalette opens, filters, and closes on ESC',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        commandPaletteOpenProvider.overrideWith((ref) => true),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.getDarkTheme(),
          home: const Scaffold(
            body: Stack(
              children: [
                Center(child: Text('Main App')),
                DesktopCommandPalette(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify search field exists
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search credentials, commands, or settings...'),
        findsOneWidget);

    // Or check RenderBox of the palette container
    final containerFinder = find.ancestor(
      of: find.byType(TextField),
      matching: find.byType(Container),
    );
    expect(containerFinder, findsWidgets);
    final size = tester.getSize(containerFinder.first);
    expect(size.width, equals(580));

    // Type query to filter
    await tester.enterText(find.byType(TextField), 'Generator');
    await tester.pumpAndSettle();

    expect(find.text('Password Generator'), findsOneWidget);

    // Press Escape to close
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(container.read(commandPaletteOpenProvider), isFalse);
  });
}
