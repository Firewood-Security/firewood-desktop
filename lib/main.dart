// Firewood desktop entry point: frameless window, Isar store, then the app.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:firewood_design/firewood_design.dart';

import 'src/app.dart';
import 'src/data/isar_secret_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  await windowManager.setAsFrameless();

  const windowOptions = WindowOptions(
    size: AppWindow.defaultSize,
    minimumSize: AppWindow.minimumSize,
    center: true,
    title: AppStrings.appName,
    titleBarStyle: TitleBarStyle.hidden,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  await IsarSecretStore.initialize();

  runApp(const ProviderScope(child: FirewoodDesktopApp()));
}
