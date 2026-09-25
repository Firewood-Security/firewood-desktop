// Single source of truth for on-device, zero-knowledge security findings.
// Deterministic Mini ML advisor for evaluating vault security posture.

import 'package:firewood_core/firewood_core.dart';

const int kWeakCriticalBelow = 8;
const int kWeakWarnBelow = 12;
const int kStaleAfterDays = 120;
const int kTotpPenaltyMinLogins = 3;

enum SecurityTipCategory {
  weakPasswords,
  reusedPasswords,
  missing2FA,
  staleCredentials,
  backupDisabled,
  optimalHealth,
}

enum SecuritySeverity { critical, warn, info }

int severityRank(SecuritySeverity s) => switch (s) {
      SecuritySeverity.critical => 0,
      SecuritySeverity.warn => 1,
      SecuritySeverity.info => 2,
    };

class SecurityTip {
  final String title;
  final String message;
  final SecurityTipCategory category;
  final String actionLabel;

  SecurityTip({
    required this.title,
    required this.message,
    required this.category,
    required this.actionLabel,
  });
}

class AdvisorIssue {
  final SecurityTipCategory category;
  final SecuritySeverity severity;
  final DecryptedItem item;
  final String detail;

  const AdvisorIssue({
    required this.category,
    required this.severity,
    required this.item,
    required this.detail,
  });
}

class SecurityFindingGroup {
  final SecurityTipCategory category;
  final SecuritySeverity severity;
  final String headline;
  final String advice;
  final List<AdvisorIssue> issues;

  const SecurityFindingGroup({
    required this.category,
    required this.severity,
    required this.headline,
    required this.advice,
    required this.issues,
  });

  int get count => issues.length;
}

class VaultAdvisory {
  final int score;
  final SecuritySeverity overallSeverity;
  final SecurityTip? headlineTip;
  final List<SecurityFindingGroup> findingGroups;
  final int totalItems;
  final int strongCount;
  final int weakCount;
  final int reusedCount;
  final int missing2FACount;
  final int staleCount;
  final int totalLogins;

  const VaultAdvisory({
    required this.score,
    required this.overallSeverity,
    required this.headlineTip,
    required this.findingGroups,
    required this.totalItems,
    required this.strongCount,
    required this.weakCount,
    required this.reusedCount,
    required this.missing2FACount,
    required this.staleCount,
    required this.totalLogins,
  });

  bool get hasIssues => findingGroups.isNotEmpty;
  int get totalIssueCount =>
      findingGroups.fold(0, (acc, g) => acc + g.issues.length);
}

class SecurityAdvisorEngine {
  SecurityAdvisorEngine._();

  static VaultAdvisory analyze(
    List<DecryptedItem> items, {
    bool hasRecentBackup = true,
  }) {
    if (items.isEmpty) {
      return const VaultAdvisory(
        score: 100,
        overallSeverity: SecuritySeverity.info,
        headlineTip: null,
        findingGroups: [],
        totalItems: 0,
        strongCount: 0,
        weakCount: 0,
        reusedCount: 0,
        missing2FACount: 0,
        staleCount: 0,
        totalLogins: 0,
      );
    }

    final weakIssues = <AdvisorIssue>[];
    final staleIssues = <AdvisorIssue>[];
    final missing2FAIssues = <AdvisorIssue>[];
    final passwordMap = <String, List<DecryptedItem>>{};

    int totalLogins = 0;
    int strongCount = 0;
    final now = DateTime.now();

    for (final item in items) {
      final isLogin = item.type.toLowerCase() == 'login';
      final password = item.fields['password']?.toString() ?? '';
      final totp = (item.fields['totp_secret'] ?? item.fields['totpSecret'])?.toString() ?? '';

      if (isLogin) {
        totalLogins++;

        // 1. Password strength evaluation
        if (password.isNotEmpty) {
          passwordMap.putIfAbsent(password, () => []).add(item);

          if (password.length < kWeakCriticalBelow) {
            weakIssues.add(AdvisorIssue(
              category: SecurityTipCategory.weakPasswords,
              severity: SecuritySeverity.critical,
              item: item,
              detail: '${password.length} characters (critical: min 8 required)',
            ));
          } else if (password.length < kWeakWarnBelow ||
              !_hasGoodEntropy(password)) {
            weakIssues.add(AdvisorIssue(
              category: SecurityTipCategory.weakPasswords,
              severity: SecuritySeverity.warn,
              item: item,
              detail: '${password.length} chars (recommend 16+ with mixed chars)',
            ));
          } else {
            strongCount++;
          }
        }

        // 2. Missing 2FA
        if (totp.isEmpty) {
          missing2FAIssues.add(AdvisorIssue(
            category: SecurityTipCategory.missing2FA,
            severity: SecuritySeverity.info,
            item: item,
            detail: 'No TOTP 2FA secret configured',
          ));
        }
      }

      // 3. Stale credentials
      final age = now.difference(item.updatedAt).inDays;
      if (age > kStaleAfterDays) {
        staleIssues.add(AdvisorIssue(
          category: SecurityTipCategory.staleCredentials,
          severity: SecuritySeverity.info,
          item: item,
          detail: 'Last modified $age days ago',
        ));
      }
    }

    // 4. Reused passwords
    final reusedIssues = <AdvisorIssue>[];
    passwordMap.forEach((_, list) {
      if (list.length > 1) {
        for (final item in list) {
          reusedIssues.add(AdvisorIssue(
            category: SecurityTipCategory.reusedPasswords,
            severity: SecuritySeverity.critical,
            item: item,
            detail: 'Reused across ${list.length} different accounts',
          ));
        }
      }
    });

    final groups = <SecurityFindingGroup>[];

    if (weakIssues.isNotEmpty) {
      weakIssues.sort((a, b) =>
          severityRank(a.severity).compareTo(severityRank(b.severity)));
      groups.add(SecurityFindingGroup(
        category: SecurityTipCategory.weakPasswords,
        severity: weakIssues.first.severity,
        headline: '${weakIssues.length} Weak ${weakIssues.length == 1 ? "Password" : "Passwords"}',
        advice: 'Upgrade to 16+ character high-entropy randomized credentials',
        issues: weakIssues,
      ));
    }

    if (reusedIssues.isNotEmpty) {
      groups.add(SecurityFindingGroup(
        category: SecurityTipCategory.reusedPasswords,
        severity: SecuritySeverity.critical,
        headline: '${reusedIssues.length} Reused ${reusedIssues.length == 1 ? "Password" : "Passwords"}',
        advice: 'Generate unique credentials per service to prevent credential stuffing',
        issues: reusedIssues,
      ));
    }

    if (missing2FAIssues.isNotEmpty) {
      groups.add(SecurityFindingGroup(
        category: SecurityTipCategory.missing2FA,
        severity: SecuritySeverity.info,
        headline: '${missing2FAIssues.length} Accounts Without 2FA',
        advice: 'Add TOTP authenticator secrets to protect against unauthorized logins',
        issues: missing2FAIssues,
      ));
    }

    if (staleIssues.isNotEmpty) {
      groups.add(SecurityFindingGroup(
        category: SecurityTipCategory.staleCredentials,
        severity: SecuritySeverity.info,
        headline: '${staleIssues.length} Stale Credentials',
        advice: 'Rotate credentials that have not been refreshed in over 120 days',
        issues: staleIssues,
      ));
    }

    // Calculate score 0-100
    int score = 100;
    score -= (weakIssues.where((i) => i.severity == SecuritySeverity.critical).length * 15);
    score -= (weakIssues.where((i) => i.severity == SecuritySeverity.warn).length * 5);
    score -= (reusedIssues.length * 10);
    if (totalLogins >= kTotpPenaltyMinLogins) {
      score -= (missing2FAIssues.length * 3);
    }
    score -= (staleIssues.length * 2);
    if (!hasRecentBackup && items.isNotEmpty) score -= 10;
    if (score < 0) score = 0;

    var overallSev = SecuritySeverity.info;
    if (groups.any((g) => g.severity == SecuritySeverity.critical)) {
      overallSev = SecuritySeverity.critical;
    } else if (groups.any((g) => g.severity == SecuritySeverity.warn)) {
      overallSev = SecuritySeverity.warn;
    }

    SecurityTip? headlineTip;
    if (groups.isNotEmpty) {
      final firstGroup = groups.first;
      headlineTip = SecurityTip(
        title: firstGroup.headline,
        message: firstGroup.advice,
        category: firstGroup.category,
        actionLabel: 'Review Findings',
      );
    }

    return VaultAdvisory(
      score: score,
      overallSeverity: overallSev,
      headlineTip: headlineTip,
      findingGroups: groups,
      totalItems: items.length,
      strongCount: strongCount,
      weakCount: weakIssues.length,
      reusedCount: reusedIssues.length,
      missing2FACount: missing2FAIssues.length,
      staleCount: staleIssues.length,
      totalLogins: totalLogins,
    );
  }

  static bool _hasGoodEntropy(String password) {
    if (password.length < 12) return false;
    bool hasUpper = password.contains(RegExp(r'[A-Z]'));
    bool hasLower = password.contains(RegExp(r'[a-z]'));
    bool hasDigit = password.contains(RegExp(r'[0-9]'));
    bool hasSpecial = password.contains(RegExp(r'[^A-Za-z0-9]'));
    int classes = (hasUpper ? 1 : 0) +
        (hasLower ? 1 : 0) +
        (hasDigit ? 1 : 0) +
        (hasSpecial ? 1 : 0);
    return classes >= 3;
  }
}
