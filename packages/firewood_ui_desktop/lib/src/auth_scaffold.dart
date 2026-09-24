// Minimal, centred authentication layout shared by setup and unlock.
// Narrow by design (see AppSizes.authMaxWidth) so inputs stay compact.

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_design/firewood_design.dart';

class AuthScaffold extends StatelessWidget {
  final Widget? logo;
  final List<List<dynamic>>? icon;
  final String title;
  final String subtitle;
  final Widget child;

  const AuthScaffold({
    super.key,
    this.logo,
    this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundZinc,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSizes.authMaxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (logo != null)
                  Center(child: logo!)
                else if (icon != null)
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.cardZinc,
                        border: Border.all(color: AppColors.borderZinc),
                      ),
                      child: Center(
                        child: HugeIcon(
                          icon: icon!,
                          color: AppColors.emberBright,
                          size: 26,
                          strokeWidth: 2.0,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.offWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceZinc,
                    borderRadius: AppRadii.lgAll,
                    border: Border.all(color: AppColors.borderZinc),
                  ),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
