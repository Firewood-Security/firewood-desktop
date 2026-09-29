// Desktop security metrics mirroring the Android dashboard: item categories,
// password strength distribution and 2FA coverage, computed offline.

import 'package:firewood_core/firewood_core.dart';

class DesktopSecurityReport {
  final int total;
  final int logins;
  final int cards;
  final int identities;
  final int notes;
  final int developerSecrets;

  final int strong;
  final int weak;
  final int reused;
  final int totpActive;

  final int score; // 0..100
  final double totpCoverage; // 0..100
  final List<DecryptedItem> recent;

  const DesktopSecurityReport({
    required this.total,
    required this.logins,
    required this.cards,
    required this.identities,
    required this.notes,
    required this.developerSecrets,
    required this.strong,
    required this.weak,
    required this.reused,
    required this.totpActive,
    required this.score,
    required this.totpCoverage,
    required this.recent,
  });

  static DesktopSecurityReport from(List<DecryptedItem> items) {
    int logins = 0, cards = 0, identities = 0, notes = 0, devSecrets = 0;
    final passwords = <String>[];
    final seen = <String, int>{};
    int totpActive = 0;

    for (final item in items) {
      switch (ItemTypeExt.fromString(item.type)) {
        case ItemType.login:
          logins++;
          final pw = item.fields['password']?.toString() ?? '';
          if (pw.isNotEmpty) {
            passwords.add(pw);
            seen[pw] = (seen[pw] ?? 0) + 1;
          }
          if ((item.fields['totp_secret']?.toString() ?? '')
              .trim()
              .isNotEmpty) {
            totpActive++;
          }
          break;
        case ItemType.card:
          cards++;
          break;
        case ItemType.identity:
          identities++;
          break;
        case ItemType.note:
          notes++;
          break;
        case ItemType.developerSecret:
          devSecrets++;
          break;
      }
    }

    int strong = 0, weak = 0;
    for (final pw in passwords) {
      final s = GeneratorService.calculateStrength(pw);
      if (s >= 3) {
        strong++;
      } else if (s <= 1) {
        weak++;
      }
    }
    final reused =
        seen.values.where((c) => c > 1).fold<int>(0, (sum, c) => sum + c);

    final int score;
    if (passwords.isEmpty) {
      score = 100;
    } else {
      final raw = 100 - (weak * 12 + reused * 8);
      score = raw.clamp(0, 100);
    }

    final sorted = [...items]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return DesktopSecurityReport(
      total: items.length,
      logins: logins,
      cards: cards,
      identities: identities,
      notes: notes,
      developerSecrets: devSecrets,
      strong: strong,
      weak: weak,
      reused: reused,
      totpActive: totpActive,
      score: score,
      totpCoverage: logins == 0 ? 0 : (totpActive / logins) * 100,
      recent: sorted.take(5).toList(),
    );
  }

  String get scoreLabel {
    if (score >= 80) return 'Optimal Protection';
    if (score >= 50) return 'Attention Recommended';
    return 'Action Required';
  }
}
