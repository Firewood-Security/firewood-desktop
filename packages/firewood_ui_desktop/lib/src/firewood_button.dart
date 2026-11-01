// Desktop button mirroring the Android app's soft matte 3D gradient style:
// a subtle top-to-bottom shade, 1px border, soft drop shadow and bold label.

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_design/firewood_design.dart';

enum FirewoodButtonVariant {
  primary,
  secondary,
  danger,
  success,
  soft,
  outline
}

class FirewoodButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final List<List<dynamic>>? icon;
  final FirewoodButtonVariant variant;
  final bool fullWidth;
  final bool isLoading;
  final double height;

  const FirewoodButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = FirewoodButtonVariant.primary,
    this.fullWidth = false,
    this.isLoading = false,
    this.height = 42,
  });

  @override
  Widget build(BuildContext context) {
    Gradient? gradient;
    late Color borderColor;
    late Color textColor;
    late Color lipColor;

    switch (variant) {
      case FirewoodButtonVariant.primary:
        gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.orangeAccent,
            AppColors.shade(AppColors.orangeAccent, -0.08)
          ],
        );
        borderColor = AppColors.orangeDark;
        textColor = Colors.white;
        lipColor = AppColors.shade(AppColors.orangeAccent, -0.18);
        break;
      case FirewoodButtonVariant.secondary:
        gradient = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.hearthRaised, AppColors.hearth],
        );
        borderColor = AppColors.hearthEdge;
        textColor = AppColors.ash;
        lipColor = const Color(0xFF27272A);
        break;
      case FirewoodButtonVariant.danger:
        gradient = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
        );
        borderColor = const Color(0xFFB91C1C);
        textColor = Colors.white;
        lipColor = const Color(0xFF7F1D1D);
        break;
      case FirewoodButtonVariant.success:
        gradient = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.mintAccent, Color(0xFF15803D)],
        );
        borderColor = const Color(0xFF15803D);
        textColor = Colors.white;
        lipColor = const Color(0xFF14532D);
        break;
      case FirewoodButtonVariant.soft:
        gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.orangeAccent.withValues(alpha: 0.25),
            AppColors.orangeAccent.withValues(alpha: 0.12),
          ],
        );
        borderColor = AppColors.orangeAccent.withValues(alpha: 0.4);
        textColor = AppColors.ash;
        lipColor = AppColors.orangeDark;
        break;
      case FirewoodButtonVariant.outline:
        gradient = null;
        borderColor = AppColors.hearthEdge;
        textColor = AppColors.ash;
        lipColor = const Color(0xFF27272A);
        break;
    }

    final isDisabled = onPressed == null && !isLoading;

    final content = AnimatedSwitcher(
      duration: AppDurations.fast,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: isLoading
          ? SizedBox(
              key: const ValueKey('spinner'),
              width: 16,
              height: 16,
              child:
                  CircularProgressIndicator(strokeWidth: 2.2, color: textColor),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  HugeIcon(
                      icon: icon!,
                      size: 16,
                      color: textColor,
                      strokeWidth: 2.0),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
    );

    return AnimatedOpacity(
      duration: AppDurations.fast,
      // Loading keeps the button fully lit; only a truly disabled button dims.
      opacity: isDisabled ? 0.55 : 1.0,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: isDisabled ? null : gradient,
          color: isDisabled
              ? AppColors.hearth
              : (gradient == null ? AppColors.hearth : null),
          borderRadius: AppRadii.mdAll,
          border: Border.all(color: borderColor),
          boxShadow: isDisabled
              ? null
              : [
                  BoxShadow(
                    color: lipColor,
                    offset: const Offset(0, 3),
                    blurRadius: 0,
                    spreadRadius: 0,
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadii.mdAll,
            onTap: (isDisabled || isLoading) ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );
  }
}
