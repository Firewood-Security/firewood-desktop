import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:firewood_design/firewood_design.dart';

import 'src/app.dart';
import 'src/data/isar_secret_store.dart';
import 'src/services/single_instance_lock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Strict single-instance enforcement: focus existing instance and exit if duplicate
  final isPrimary = await SingleInstanceLock.acquireOrFocus();
  if (!isPrimary) {
    stdout.writeln(
        'Firewood Desktop is already running. Existing window focused.');
    exit(0);
  }

  await windowManager.ensureInitialized();
  await windowManager.setAsFrameless();

  const fixedSize = Size(1280, 820);
  const windowOptions = WindowOptions(
    size: fixedSize,
    minimumSize: fixedSize,
    maximumSize: fixedSize,
    center: true,
    title: AppStrings.appName,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setResizable(false);
    await windowManager.setMaximizable(false);
    await windowManager.setFullScreen(false);
    await windowManager.setSize(fixedSize);
    await windowManager.show();
    await windowManager.focus();
  });

  await IsarSecretStore.initialize();

  runApp(const ProviderScope(child: FirewoodDesktopApp()));
}
