// screens/splash_screen.dart
// Cinematic 3-second splash screen with 3D glass cube matrix artwork, dark vignette shading, and bottom-left logo.
// Replicates the mobile version identically for desktop.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firewood_design/firewood_design.dart';
import '../theme/app_icons.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback? onComplete;
  final VoidCallback? onFinished;
  final Duration hold;

  const SplashScreen({
    super.key,
    this.onComplete,
    this.onFinished,
    this.hold = const Duration(seconds: 3),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();

    // 3-second display duration
    _timer = Timer(widget.hold, () {
      if (mounted) {
        widget.onComplete?.call();
        widget.onFinished?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF0C0C0E),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0C0C0E),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Background Layer: Procedural 3D isometric glass cube matrix (blocks)
            const _ProceduralCubeMatrixBackground(),

            // 2. Subtle Dark Shading Overlay (Fades upwards to reveal 3D cubes on middle-top & top-right)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  stops: const [0.0, 0.45, 0.8, 1.0],
                  colors: [
                    const Color(0xFF0C0C0E).withValues(alpha: 0.98),
                    const Color(0xFF0C0C0E).withValues(alpha: 0.80),
                    const Color(0xFF0C0C0E).withValues(alpha: 0.35),
                    Colors.transparent,
                  ],
                ),
              ),
            ),

            // 3. Dark Vignette at Corners
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.4, -0.2),
                  radius: 1.25,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.4),
                    const Color(0xFF0C0C0E).withValues(alpha: 0.9),
                  ],
                  stops: const [0.3, 0.7, 1.0],
                ),
              ),
            ),

            // 4. Logo & App Identity placed cleanly on the BOTTOM-LEFT Corner
            Positioned(
              left: 36,
              bottom: 40,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Bare logo, no container or outline
                    Image.asset(
                      'assets/FWS.png',
                      width: 64,
                      height: 64,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Firewood',
                      style: TextStyle(
                        color: AppColors.offWhite,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          AppIcons.shield,
                          color: AppColors.orangeAccent,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Zero-Knowledge Vault',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Procedural 3D Isometric Glass Cube Matrix Canvas rendered dynamically
class _ProceduralCubeMatrixBackground extends StatelessWidget {
  const _ProceduralCubeMatrixBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CubeMatrixPainter(),
      size: Size.infinite,
    );
  }
}

class _CubeMatrixPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF0A0A0D);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Origin centered near top-right quadrant
    final centerX = size.width * 0.72;
    final centerY = size.height * 0.32;
    const cubeSize = 48.0;

    // Isometric projection matrix
    const gridCols = 10;
    const gridRows = 10;

    final rand = Random(42);

    for (int r = 0; r < gridRows; r++) {
      for (int c = 0; c < gridCols; c++) {
        final heightOffset =
            (sin(r * 0.8) * cos(c * 0.8) * 35 + rand.nextDouble() * 25).abs();

        final isoX = centerX + (c - r) * (cubeSize * 0.866);
        final isoY = centerY + (c + r) * (cubeSize * 0.5) - heightOffset;

        // Draw 3D Isometric Cube (Top, Left, Right faces)
        _drawIsometricCube(canvas, isoX, isoY, cubeSize, r, c);
      }
    }
  }

  void _drawIsometricCube(
      Canvas canvas, double x, double y, double size, int r, int c) {
    final w = size * 0.866;
    final h = size * 0.5;
    final depth = size * 0.9;

    final orangeIntensity = ((r + c) / 14).clamp(0.2, 1.0);
    const baseOrange = Color(0xFFFF6A00);

    // Top Face (Light reflective glass)
    final topPath = Path()
      ..moveTo(x, y - h)
      ..lineTo(x + w, y)
      ..lineTo(x, y + h)
      ..lineTo(x - w, y)
      ..close();

    final topPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          baseOrange.withValues(alpha: 0.35 * orangeIntensity),
          const Color(0xFFFFB300).withValues(alpha: 0.55 * orangeIntensity),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(x - w, y - h, w * 2, h * 2))
      ..style = PaintingStyle.fill;

    canvas.drawPath(topPath, topPaint);

    // Top Face Border
    final topBorderPaint = Paint()
      ..color = const Color(0xFFFFD54F).withValues(alpha: 0.6 * orangeIntensity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(topPath, topBorderPaint);

    // Left Face (Medium shade glass)
    final leftPath = Path()
      ..moveTo(x - w, y)
      ..lineTo(x, y + h)
      ..lineTo(x, y + h + depth)
      ..lineTo(x - w, y + depth)
      ..close();

    final leftPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          baseOrange.withValues(alpha: 0.25 * orangeIntensity),
          const Color(0xFFBF360C).withValues(alpha: 0.40 * orangeIntensity),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(x - w, y, w, h + depth))
      ..style = PaintingStyle.fill;

    canvas.drawPath(leftPath, leftPaint);

    // Right Face (Deep shaded glass with amber glow)
    final rightPath = Path()
      ..moveTo(x, y + h)
      ..lineTo(x + w, y)
      ..lineTo(x + w, y + depth)
      ..lineTo(x, y + h + depth)
      ..close();

    final rightPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFE65100).withValues(alpha: 0.30 * orangeIntensity),
          const Color(0xFF3E2723).withValues(alpha: 0.50 * orangeIntensity),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(x, y, w, h + depth))
      ..style = PaintingStyle.fill;

    canvas.drawPath(rightPath, rightPaint);

    // Subtle edge highlight
    final edgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3 * orangeIntensity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawPath(leftPath, edgePaint);
    canvas.drawPath(rightPath, edgePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
