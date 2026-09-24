// Layout, radius, size and motion tokens. Replace magic numbers everywhere.

import 'package:flutter/material.dart';

/// Spacing scale (logical pixels).
class AppSpacing {
  AppSpacing._();
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

/// Corner radii.
class AppRadii {
  AppRadii._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

/// Fixed dimensions and icon sizes.
class AppSizes {
  AppSizes._();

  // Icons
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 32;

  // Forms
  static const double authMaxWidth = 340;

  // Dashboard
  static const double dashboardMaxWidth = 960;
  static const double inputHeight = 48;

  // Desktop chrome
  static const double titleBarHeight = 42;
  static const double railWidth = 72;
  static const double listPaneDefault = 360;
  static const double listPaneMin = 260;
  static const double listPaneMax = 560;
}

/// Responsive breakpoints.
class AppBreakpoints {
  AppBreakpoints._();
  static const double compact = 600;
  static const double wide = 900;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;
}

/// Window sizing for desktop shells (logical pixels).
class AppWindow {
  AppWindow._();
  static const Size defaultSize = Size(1200, 800);
  static const Size minimumSize = Size(960, 640);
}

/// Animation durations.
class AppDurations {
  AppDurations._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}
