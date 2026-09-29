import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:firewood_design/firewood_design.dart';

/// Desktop-compatible Custom Animated QR Code widget built using CustomPainter.
/// It dynamically animates & draws the actual QR code matrix blocks using Deep Orange and Slate Gray tiles!
class DesktopAnimatedQrDisplay extends StatefulWidget {
  final String qrData;
  final double size;

  const DesktopAnimatedQrDisplay({
    super.key,
    required this.qrData,
    this.size = 220,
  });

  @override
  State<DesktopAnimatedQrDisplay> createState() =>
      _DesktopAnimatedQrDisplayState();
}

class _DesktopAnimatedQrDisplayState extends State<DesktopAnimatedQrDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  QrCode? _qrCode;
  bool _isBuildingQr = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _generateQrMatrix();
  }

  void _generateQrMatrix() {
    try {
      final qr = QrCode.fromData(
        data: widget.qrData,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      _qrCode = qr;
      _isBuildingQr = false;
      _controller.forward(from: 0.0);
    } catch (_) {
      if (mounted) setState(() => _isBuildingQr = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _replayAnimation() {
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_isBuildingQr || _qrCode == null) {
      return SizedBox(
        width: widget.size + 28,
        height: widget.size + 28,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _replayAnimation,
          child: Container(
            width: widget.size + 28,
            height: widget.size + 28,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0E0E12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.orangeAccent.withValues(alpha: 0.7),
                width: 1.8,
              ),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _DesktopQrMatrixPainter(
                    qrCode: _qrCode!,
                    progress: _controller.value,
                    orangeColor: AppColors.orangeAccent,
                    grayColor: const Color(0xFF383845),
                    lightGrayColor: const Color(0xFF8E8E9F),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopQrMatrixPainter extends CustomPainter {
  final QrCode qrCode;
  final double progress;
  final Color orangeColor;
  final Color grayColor;
  final Color lightGrayColor;

  _DesktopQrMatrixPainter({
    required this.qrCode,
    required this.progress,
    required this.orangeColor,
    required this.grayColor,
    required this.lightGrayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final qrImage = QrImage(qrCode);
    final moduleCount = qrCode.moduleCount;
    final tileSize = size.width / moduleCount;

    final orangePaint = Paint()..color = orangeColor;
    final grayPaint = Paint()..color = grayColor;
    final lightGrayPaint = Paint()..color = lightGrayColor;
    final darkBgPaint = Paint()..color = const Color(0xFF09090C);

    // Draw background without outer glow
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(12),
      ),
      darkBgPaint,
    );

    for (int r = 0; r < moduleCount; r++) {
      for (int c = 0; c < moduleCount; c++) {
        final isDark = qrImage.isDark(r, c);

        final isTopLeftEye = (r < 7 && c < 7);
        final isTopRightEye = (r < 7 && c >= moduleCount - 7);
        final isBottomLeftEye = (r >= moduleCount - 7 && c < 7);
        final isEyePattern = isTopLeftEye || isTopRightEye || isBottomLeftEye;

        final diagonalIndex = (r + c) / ((moduleCount * 2) - 2);
        final moduleProgress =
            ((progress - (diagonalIndex * 0.65)) / 0.35).clamp(0.0, 1.0);

        if (moduleProgress <= 0.0) continue;

        final x = c * tileSize;
        final y = r * tileSize;
        final moduleRect = Rect.fromLTWH(
          x + (tileSize * (1 - moduleProgress) * 0.5),
          y + (tileSize * (1 - moduleProgress) * 0.5),
          tileSize * moduleProgress,
          tileSize * moduleProgress,
        );

        if (isEyePattern) {
          if (isDark) {
            canvas.drawRect(moduleRect, orangePaint);
          } else {
            canvas.drawRect(moduleRect, grayPaint);
          }
        } else if (isDark) {
          final isOrangeBlock = (r + c) % 3 == 0 || (r * c) % 5 == 0;
          canvas.drawRect(
              moduleRect, isOrangeBlock ? orangePaint : lightGrayPaint);
        } else {
          if (progress < 0.9) {
            final alphaVal = (1.0 - progress) * 0.4;
            final dimGray = Paint()
              ..color = grayColor.withValues(alpha: alphaVal);
            canvas.drawRect(moduleRect, dimGray);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DesktopQrMatrixPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.qrCode != qrCode;
  }
}
