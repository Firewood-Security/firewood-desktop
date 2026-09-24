// Root widget: desktop chrome (minimal title bar + command palette) wrapped
// around the authentication gate and workspace.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_ui_desktop/firewood_ui_desktop.dart';

import 'providers.dart';
import 'screens/auth_screens.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
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

class _DesktopFrame extends StatelessWidget {
  final Widget child;
  const _DesktopFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Material(
          color: AppColors.coal,
          child: Column(
            children: [
              HearthTitleBar(
              logo: Image.asset('assets/FWS.png', width: 22, height: 22),
            ),
              Expanded(child: child),
            ],
          ),
        ),
        const DesktopCommandPalette(),
      ],
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(authProvider) != null;
    final vaults = ref.watch(vaultServiceProvider);

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
