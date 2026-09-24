// Desktop button mirroring the Android app's soft matte 3D gradient style:
// a subtle top-to-bottom shade, 1px border, soft drop shadow and bold label.

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_design/firewood_design.dart';

enum FirewoodButtonVariant { primary, secondary, danger, success, soft, outline }

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

    switch (variant) {
      case FirewoodButtonVariant.primary:
        gradient = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.emberBright, AppColors.emberDeep],
        );
        borderColor = AppColors.ember;
        textColor = Colors.white;
        break;
      case FirewoodButtonVariant.secondary:
        gradient = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.hearthRaised, AppColors.hearth],
        );
        borderColor = AppColors.hearthEdge;
        textColor = AppColors.ash;
        break;
      case FirewoodButtonVariant.danger:
        gradient = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEF4444), Color(0xFFB91C1C)],
        );
        borderColor = AppColors.roseAccent;
        textColor = Colors.white;
        break;
      case FirewoodButtonVariant.success:
        gradient = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.mintAccent, Color(0xFF15803D)],
        );
        borderColor = AppColors.mintAccent;
        textColor = Colors.white;
        break;
      case FirewoodButtonVariant.soft:
        gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.ember.withValues(alpha: 0.25),
            AppColors.ember.withValues(alpha: 0.12),
          ],
        );
        borderColor = AppColors.ember.withValues(alpha: 0.4);
        textColor = AppColors.ash;
        break;
      case FirewoodButtonVariant.outline:
        gradient = null;
        borderColor = AppColors.hearthEdge;
        textColor = AppColors.ash;
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
              child: CircularProgressIndicator(strokeWidth: 2.2, color: textColor),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  HugeIcon(icon: icon!, size: 16, color: textColor, strokeWidth: 2.0),
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
                  const BoxShadow(
                    color: Colors.black45,
                    offset: Offset(0, 2),
                    blurRadius: 4,
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
