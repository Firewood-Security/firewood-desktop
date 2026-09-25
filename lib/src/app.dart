// Root widget: desktop chrome (minimal title bar + command palette) wrapped
// around the authentication gate and workspace.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_ui_desktop/firewood_ui_desktop.dart';
import 'package:window_manager/window_manager.dart';

import 'providers.dart';
import 'screens/auth_screens.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/secure_clipboard.dart';
import 'widgets/command_palette.dart';

class FirewoodDesktopApp extends ConsumerWidget {
  const FirewoodDesktopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getDarkTheme(ref.watch(accentColorProvider)),
      home: const _DesktopFrame(child: _SplashGate(child: _AuthGate())),
    );
  }
}

class _DesktopFrame extends ConsumerStatefulWidget {
  final Widget child;
  const _DesktopFrame({required this.child});

  @override
  ConsumerState<_DesktopFrame> createState() => _DesktopFrameState();
}

class _DesktopFrameState extends ConsumerState<_DesktopFrame> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(browserBridgeEnabledProvider)) {
        ref.read(browserBridgeServiceProvider).startServer(reader: ref.read);
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    ref.read(browserBridgeServiceProvider).stopServer();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    final minimizeToTray = ref.read(minimizeToTrayProvider);
    if (minimizeToTray) {
      await windowManager.hide();
    } else {
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(browserBridgeEnabledProvider, (prev, enabled) {
      if (enabled) {
        ref.read(browserBridgeServiceProvider).startServer(reader: ref.read);
      } else {
        ref.read(browserBridgeServiceProvider).stopServer();
      }
    });

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          ref.read(commandPaletteOpenProvider.notifier).state = true;
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          ref.read(commandPaletteOpenProvider.notifier).state = true;
        },
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          ref.read(commandPaletteOpenProvider.notifier).state = true;
        },
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () {
          ref.read(commandPaletteOpenProvider.notifier).state = true;
        },
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () {
          ref.read(authProvider.notifier).state = null;
        },
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () {
          ref.read(authProvider.notifier).state = null;
        },
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
          WidgetsBinding.instance.reassembleApplication();
        },
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () {
          WidgetsBinding.instance.reassembleApplication();
        },
        const SingleActivator(LogicalKeyboardKey.f5): () {
          WidgetsBinding.instance.reassembleApplication();
        },
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Material(
              color: AppColors.coal,
              child: Column(
                children: [
                  HearthTitleBar(
                    logo: Image.asset('assets/FWS.png', width: 22, height: 22),
                  ),
                  Expanded(child: widget.child),
                ],
              ),
            ),
            const DesktopCommandPalette(),
          ],
        ),
      ),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(authProvider) != null;
    final vaults = ref.watch(vaultServiceProvider);

    ref.listen(authProvider, (previous, current) {
      if (current == null && ref.read(clipboardClearProvider)) {
        SecureClipboard.clear();
      }
    });

    return FutureBuilder<bool>(
      future: vaults.hasAnyVault(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.coal,
            body: Center(child: CircularProgressIndicator(color: AppColors.ember)),
          );
        }
        if (snapshot.data != true) return const SetupScreen();
        if (!unlocked) return const UnlockScreen();
        return const HomeScreen();
      },
    );
  }
}

/// Shows the branded splash, then swaps in the app content.
class _SplashGate extends StatefulWidget {
  final Widget child;
  const _SplashGate({required this.child});

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return SplashScreen(
      onFinished: () {
        if (mounted) setState(() => _done = true);
      },
    );
  }
}
