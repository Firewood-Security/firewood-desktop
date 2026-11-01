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
          width: 600,
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

  String _totpCoverage(VaultAdvisory a) {
    if (a.totalLogins <= 0) return '100%';
    final covered =
        ((a.totalLogins - a.missing2FACount) / a.totalLogins * 100).round();
    return '$covered%';
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Security advisor',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'On-device vault health review · ${advisory.totalItems} credentials evaluated',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                tooltip: 'Close',
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

        // Stat cards: Strong / Weak / Reused / 2FA.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            children: [
              _AdvisorStatCard(
                label: 'Strong',
                value: '${advisory.strongCount}',
                color: AppColors.mintAccent,
              ),
              const SizedBox(width: 8),
              _AdvisorStatCard(
                label: 'Weak',
                value: '${advisory.weakCount}',
                color: advisory.weakCount > 0
                    ? AppColors.roseAccent
                    : Colors.white38,
              ),
              const SizedBox(width: 8),
              _AdvisorStatCard(
                label: 'Reused',
                value: '${advisory.reusedCount}',
                color: advisory.reusedCount > 0
                    ? const Color(0xFFF59E0B)
                    : Colors.white38,
              ),
              const SizedBox(width: 8),
              _AdvisorStatCard(
                label: '2FA',
                value: _totpCoverage(advisory),
                color: AppColors.orangeAccent,
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
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                          ),
                        ),
                        title: Text(
                          group.headline,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                            color: Color(0xFFF4F4F5),
                          ),
                        ),
                        subtitle: Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF13151A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF262A33)),
                          ),
                          child: Text(
                            group.advice,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ),
                        children: group.issues.map((issue) {
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 4),
                            leading:
                                const AppIcon(AppIcons.categoryLogin, size: 24),
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
                              label: const Text('Resolve',
                                  style: TextStyle(fontSize: 12)),
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

class _AdvisorStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AdvisorStatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF181B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF262A33)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
