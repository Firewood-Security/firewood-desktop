// Centralized icon system for Firewood Desktop.
// Display icons use 3D PNG assets (assets/icons/cutouts_dark/*.png);
// navigation and input chrome use HugeIcons line icons.

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class AppIcons {
  AppIcons._();

  static const _cut = 'assets/icons/cutouts_dark';

  // Navigation
  static const String home = '$_cut/home.png';
  static const String vault = '$_cut/vault-lock.png';
  static const String generate = '$_cut/password-generator.png';
  static const String settings = '$_cut/settings-gear.png';
  static const String analytics = '$_cut/shield-check.png';

  // Categories & Item Types
  static const String categoryLogin = '$_cut/user-login.png';
  static const String categoryCard = '$_cut/credit-card.png';
  static const String categoryIdentity = '$_cut/passport.png';
  static const String categoryNote = '$_cut/secure-note.png';
  static const String typeDeveloperSecret = '$_cut/api-key.png';

  static const String typeLogin = '$_cut/user-login.png';
  static const String typeCard = '$_cut/credit-card.png';
  static const String typeIdentity = '$_cut/passport.png';
  static const String typeNote = '$_cut/secure-note.png';

  // Core Actions & Security
  static const String lock = '$_cut/lock.png';
  static const String unlock = '$_cut/unlock-open.png';
  static const String shield = '$_cut/shield.png';
  static const String shieldCheck = '$_cut/shield-check.png';
  static const String shieldKey = '$_cut/shield-key.png';
  static const String fingerprint = '$_cut/fingerprint.png';
  static const String fire = '$_cut/fire-flame.png';
  static const String key = '$_cut/api-key.png';
  static const String timer = '$_cut/timer-clock.png';

  // Interactions
  static const String search = '$_cut/search.png';
  static const String copy = '$_cut/copy.png';
  static const String edit = '$_cut/edit-pencil.png';
  static const String delete = '$_cut/trash-delete.png';
  static const String trash = '$_cut/trash-delete.png';
  static const String eye = '$_cut/eye-view.png';
  static const String eyeOff = '$_cut/eye-off.png';
  static const String check = '$_cut/checkmark.png';
  static const String close = '$_cut/close-x.png';
  static const String refresh = '$_cut/refresh.png';
  static const String share = '$_cut/share.png';
  static const String qrCode = '$_cut/qr-code.png';
  static const String alert = '$_cut/warning-triangle.png';
  static const String info = '$_cut/info.png';
  static const String sort = '$_cut/sort-arrows.png';
  static const String filter = '$_cut/filter-funnel.png';
  static const String history = '$_cut/history-clock.png';
  static const String download = '$_cut/download.png';
  static const String upload = '$_cut/upload.png';
  static const String palette = '$_cut/artist-palette.png';

  // HugeIcons Line Icons
  static const add = HugeIcons.strokeRoundedPlusSign;
  static const addCircle = HugeIcons.strokeRoundedPlusSignCircle;
  static const magic = HugeIcons.strokeRoundedAiMagic;
  static const sparkles = HugeIcons.strokeRoundedSparkles;
  static const star = HugeIcons.strokeRoundedStar;
  static const starFilled = Icons.star;
  static const arrowBack = HugeIcons.strokeRoundedArrowLeft01;
  static const arrowRight = HugeIcons.strokeRoundedArrowRight01;
  static const chevronRight = HugeIcons.strokeRoundedArrowRight01;
  static const chevronDown = HugeIcons.strokeRoundedArrowDown01;
  static const chevronUp = HugeIcons.strokeRoundedArrowUp01;
}

/// Line-icon set reserved for text-input chrome.
class AppInputIcons {
  AppInputIcons._();

  static const title = HugeIcons.strokeRoundedText;
  static const user = HugeIcons.strokeRoundedUser;
  static const lock = HugeIcons.strokeRoundedLockPassword;
  static const lockClock = HugeIcons.strokeRoundedClock01;
  static const link = HugeIcons.strokeRoundedLink01;
  static const shieldKey = HugeIcons.strokeRoundedShieldKey;
  static const note = HugeIcons.strokeRoundedNote;
  static const categoryCard = HugeIcons.strokeRoundedCreditCard;
  static const calendar = HugeIcons.strokeRoundedCalendar03;
  static const shield = HugeIcons.strokeRoundedShield01;
  static const hash = HugeIcons.strokeRoundedPinCode;
  static const location = HugeIcons.strokeRoundedLocation01;
  static const categoryIdentity = HugeIcons.strokeRoundedPassport;
  static const car = HugeIcons.strokeRoundedCar01;
  static const home = HugeIcons.strokeRoundedHome01;
  static const folder = HugeIcons.strokeRoundedFolder01;
  static const key = HugeIcons.strokeRoundedKey01;
  static const globe = HugeIcons.strokeRoundedGlobe02;
  static const search = HugeIcons.strokeRoundedSearch01;
  static const close = HugeIcons.strokeRoundedCancel01;
  static const copy = HugeIcons.strokeRoundedCopy01;
  static const refresh = HugeIcons.strokeRoundedRefresh;
  static const view = HugeIcons.strokeRoundedEye;
  static const viewOff = HugeIcons.strokeRoundedViewOff;
  static const eye = HugeIcons.strokeRoundedEye;
  static const eyeOff = HugeIcons.strokeRoundedViewOff;
  static const delete = HugeIcons.strokeRoundedDelete02;
  static const upload = HugeIcons.strokeRoundedUpload01;
  static const alertCircle = HugeIcons.strokeRoundedAlertCircle;
  static const file = HugeIcons.strokeRoundedFile01;
}

/// Unified icon rendering widget for Firewood Desktop.
class AppIcon extends StatelessWidget {
  final dynamic icon;
  final Color? color;
  final double size;
  final double strokeWidth;

  const AppIcon(
    this.icon, {
    super.key,
    this.color,
    this.size = 20,
    this.strokeWidth = 1.6,
  });

  static List<List<dynamic>> _fallbackHugeIcon(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('vault') || lower.contains('safe')) {
      return HugeIcons.strokeRoundedSafeBox;
    } else if (lower.contains('user') || lower.contains('login')) {
      return HugeIcons.strokeRoundedUser;
    } else if (lower.contains('credit') || lower.contains('card')) {
      return HugeIcons.strokeRoundedCreditCard;
    } else if (lower.contains('passport') || lower.contains('identity')) {
      return HugeIcons.strokeRoundedPassport;
    } else if (lower.contains('note')) {
      return HugeIcons.strokeRoundedNote;
    } else if (lower.contains('key') || lower.contains('api')) {
      return HugeIcons.strokeRoundedKey01;
    } else if (lower.contains('generator') || lower.contains('wand')) {
      return HugeIcons.strokeRoundedMagicWand01;
    } else if (lower.contains('settings') || lower.contains('gear')) {
      return HugeIcons.strokeRoundedSettings01;
    } else if (lower.contains('shield-check')) {
      return HugeIcons.strokeRoundedShieldCheck;
    } else if (lower.contains('shield-key')) {
      return HugeIcons.strokeRoundedShieldKey;
    } else if (lower.contains('shield')) {
      return HugeIcons.strokeRoundedShield01;
    } else if (lower.contains('alert') || lower.contains('warning')) {
      return HugeIcons.strokeRoundedAlert02;
    } else if (lower.contains('copy')) {
      return HugeIcons.strokeRoundedCopy01;
    } else if (lower.contains('clock') ||
        lower.contains('history') ||
        lower.contains('timer')) {
      return HugeIcons.strokeRoundedClock01;
    } else if (lower.contains('search')) {
      return HugeIcons.strokeRoundedSearch01;
    } else if (lower.contains('edit')) {
      return HugeIcons.strokeRoundedEdit02;
    } else if (lower.contains('delete') || lower.contains('trash')) {
      return HugeIcons.strokeRoundedDelete02;
    } else if (lower.contains('lock')) {
      return HugeIcons.strokeRoundedLockPassword;
    } else if (lower.contains('unlock')) {
      return HugeIcons.strokeRoundedSquareUnlock02;
    } else if (lower.contains('fire')) {
      return HugeIcons.strokeRoundedFire;
    } else if (lower.contains('fingerprint')) {
      return HugeIcons.strokeRoundedFingerPrint;
    }
    return HugeIcons.strokeRoundedShield01;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? IconTheme.of(context).color ?? Colors.white;

    final Widget glyph;
    if (icon is String) {
      final double displaySize = size;
      final rawPath = (icon as String).trim();
      final assetPath =
          rawPath.startsWith('/') ? rawPath.substring(1) : rawPath;

      glyph = SizedBox(
        width: displaySize,
        height: displaySize,
        child: Image.asset(
          assetPath,
          width: displaySize,
          height: displaySize,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return HugeIcon(
              icon: _fallbackHugeIcon(assetPath),
              color: effectiveColor,
              size: displaySize,
              strokeWidth: strokeWidth,
            );
          },
        ),
      );
    } else if (icon is List<List<dynamic>>) {
      glyph = SizedBox(
        width: size,
        height: size,
        child: HugeIcon(
          icon: icon as List<List<dynamic>>,
          color: effectiveColor,
          size: size,
          strokeWidth: strokeWidth,
        ),
      );
    } else if (icon is IconData) {
      glyph = SizedBox(
        width: size,
        height: size,
        child: Icon(
          icon as IconData,
          color: effectiveColor,
          size: size,
        ),
      );
    } else if (icon is Widget) {
      return icon as Widget;
    } else {
      return const SizedBox.shrink();
    }

    return Center(widthFactor: 1.0, heightFactor: 1.0, child: glyph);
  }
}
