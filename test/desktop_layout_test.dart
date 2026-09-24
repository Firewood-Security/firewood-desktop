// Regression tests for desktop shell layout: no overflow and no missing
// Material ancestors on any section. Mirrors the real shell (HomeScreen is
// mounted without a Scaffold wrapper).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_ui_desktop/firewood_ui_desktop.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_desktop/src/providers.dart';
import 'package:firewood_desktop/src/screens/home_screen.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, int tab) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          desktopTabProvider.overrideWith((ref) => tab),
          autoLockEnabledProvider.overrideWith((ref) => false),
        ],
        child: MaterialApp(
          theme: AppTheme.getDarkTheme(),
          home: Material(color: AppColors.coal, child: const HomeScreen()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('auth scaffold lays out without overflow', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.getDarkTheme(),
        home: AuthScaffold(
          icon: HugeIcons.strokeRoundedSquareLock02,
          title: 'Unlock Vault',
          subtitle: 'Subtitle',
          child: Column(children: const [SizedBox(height: 48)]),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final tab in [0, 1, 2, 3, 4]) {
    testWidgets('home section $tab renders without exceptions', (tester) async {
      await pumpHome(tester, tab);
      expect(tester.takeException(), isNull);
    });
  }
}
