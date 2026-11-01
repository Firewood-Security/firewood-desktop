// Minimal desktop title bar: brand + drag region + window controls only.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:window_manager/window_manager.dart';

import 'package:firewood_design/firewood_design.dart';

class HearthTitleBar extends StatefulWidget {
  /// Optional brand mark shown in place of the default title icon.
  final Widget? logo;

  const HearthTitleBar({super.key, this.logo});

  @override
  State<HearthTitleBar> createState() => _HearthTitleBarState();
}

class _HearthTitleBarState extends State<HearthTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    try {
      windowManager.isMaximized().then((v) {
        if (mounted) setState(() => _maximized = v);
      }).catchError((_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.coal,
      child: Container(
        height: AppSizes.titleBarHeight,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.hearthEdge)),
        ),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.md),
            widget.logo ??
                HugeIcon(
                  icon: HugeIcons.strokeRoundedFire,
                  size: 20,
                  color: AppColors.ember,
                  strokeWidth: 2.0,
                ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              AppStrings.appName.toUpperCase(),
              style: GoogleFonts.syncopate(
                color: AppColors.ash,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: _toggleMaximize,
                child: const SizedBox.expand(),
              ),
            ),
            _WindowButton(
              icon: HugeIcons.strokeRoundedMinusSign,
              tooltip: 'Minimize',
              onTap: () => windowManager.minimize(),
            ),
            _WindowButton(
              icon: _maximized
                  ? HugeIcons.strokeRoundedMinimize01
                  : HugeIcons.strokeRoundedMaximize01,
              tooltip: _maximized ? 'Restore' : 'Maximize',
              onTap: _toggleMaximize,
            ),
            _WindowButton(
              icon: HugeIcons.strokeRoundedCancel01,
              tooltip: 'Close',
              danger: true,
              onTap: () => windowManager.close(),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final List<List<dynamic>> icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 38,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: _hover
                  ? (widget.danger
                      ? AppColors.roseAccent
                      : AppColors.hearthRaised)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: HugeIcon(
                icon: widget.icon,
                size: 14,
                color: _hover ? Colors.white : AppColors.ashFaint,
                strokeWidth: 1.8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
