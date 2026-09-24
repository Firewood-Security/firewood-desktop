// Desktop splash — mirrors the mobile app's logo reveal exactly:
//   * 500 ms AnimationController with a Curves.easeOut fade
//   * the FWS.png logo in a circular orange border
// The logo asset is also used as the full-bleed background of the splash.

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:firewood_design/firewood_design.dart';

class SplashScreen extends StatefulWidget {
  /// Reveal animation duration — matches the mobile app (500 ms, easeOut).
  final Duration reveal;

  /// How long the revealed splash stays before handing off to the app.
  final Duration hold;

  final VoidCallback? onFinished;

  const SplashScreen({
    super.key,
    this.reveal = const Duration(milliseconds: 500),
    this.hold = const Duration(milliseconds: 1500),
    this.onFinished,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.reveal, vsync: this);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
    _timer = Timer(widget.hold, () => widget.onFinished?.call());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Background matches the mobile splash (android launch_background_color #1A1A1A).
    return ColoredBox(
      color: const Color(0xFF1A1A1A),
      child: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.orangeAccent.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/FWS.png',
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Firewood',
                style: TextStyle(
                  color: AppColors.offWhite,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Offline-first, zero-knowledge vault',
                style: TextStyle(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
