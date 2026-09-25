// Desktop Modal Dialog for Security Advisor & Health Analytics
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';
import 'package:hugeicons/hugeicons.dart';
import '../services/mini_ml_advisor.dart';
import '../theme/app_icons.dart';

class SecurityAdvisorDialog extends StatelessWidget {
  final VaultAdvisory advisory;
  final SecretKey sessionKey;
  final Function(DecryptedItem item) onOpenItem;

  const SecurityAdvisorDialog({
    super.key,
    required this.advisory,
    required this.sessionKey,
    required this.onOpenItem,
  });

  static Future<void> show(
    BuildContext context, {
    required VaultAdvisory advisory,
    required SecretKey key,
    required Function(DecryptedItem item) onOpenItem,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 720,
          height: 600,
          decoration: BoxDecoration(
            color: const Color(0xFF13151A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF262A33), width: 1),
          ),
          child: SecurityAdvisorDialog(
            advisory: advisory,
            sessionKey: key,
            onOpenItem: (item) {
              Navigator.of(ctx).pop();
              onOpenItem(item);
            },
          ),
        ),
      ),
    );
  }

  Color _severityColor(SecuritySeverity s) => switch (s) {
        SecuritySeverity.critical => AppColors.roseAccent,
        SecuritySeverity.warn => const Color(0xFFF59E0B),
        SecuritySeverity.info => AppColors.periwinkleAccent,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF20232B))),
          ),
          child: Row(
            children: [
              const AppIcon(AppIcons.shieldCheck, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI SECURITY ADVISOR',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Zero-Knowledge On-Device ML Analysis (${advisory.totalItems} credentials evaluated)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: advisory.score >= 80
                      ? AppColors.mintAccent.withOpacity(0.12)
                      : (advisory.score >= 50
                          ? const Color(0xFFF59E0B).withOpacity(0.12)
                          : AppColors.roseAccent.withOpacity(0.12)),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: advisory.score >= 80
                        ? AppColors.mintAccent
                        : (advisory.score >= 50
                            ? const Color(0xFFF59E0B)
                            : AppColors.roseAccent),
                    width: 1,
                  ),
                ),
                child: Text(
                  'HEALTH SCORE: ${advisory.score}/100',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: advisory.score >= 80
                        ? AppColors.mintAccent
                        : (advisory.score >= 50
                            ? const Color(0xFFF59E0B)
                            : AppColors.roseAccent),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  color: Colors.white60,
                  size: 20,
                  strokeWidth: 1.8,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),

        // Findings List
        Expanded(
          child: advisory.findingGroups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppIcon(AppIcons.shieldCheck, size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'Vault Posture Optimal',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'All passwords meet high-entropy standards and 2FA policies.',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: advisory.findingGroups.length,
                  itemBuilder: (ctx, idx) {
                    final group = advisory.findingGroups[idx];
                    final color = _severityColor(group.severity);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181B22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF262A33)),
                      ),
                      child: ExpansionTile(
                        initiallyExpanded: true,
                        shape: const Border(),
                        leading: Container(
                          width: 8,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              group.headline,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                group.severity.name.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          group.advice,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                        children: group.issues.map((issue) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 4),
                            leading: const AppIcon(AppIcons.categoryLogin, size: 24),
                            title: Text(
                              issue.item.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            subtitle: Text(
                              issue.detail,
                              style: TextStyle(
                                fontSize: 11,
                                color: color.withOpacity(0.9),
                              ),
                            ),
                            trailing: TextButton.icon(
                              icon: const HugeIcon(
                                icon: HugeIcons.strokeRoundedEdit02,
                                size: 14,
                                color: AppColors.orangeAccent,
                                strokeWidth: 1.8,
                              ),
                              label: const Text('Resolve', style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.orangeAccent,
                              ),
                              onPressed: () => onOpenItem(issue.item),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
