// Slim desktop navigation rail with an ember active indicator.

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_design/firewood_design.dart';

class HearthRailDestination {
  final List<List<dynamic>> icon;
  final String label;
  const HearthRailDestination(this.icon, this.label);
}

class HearthRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCommand;
  final VoidCallback onLock;

  static const List<HearthRailDestination> destinations = [
    HearthRailDestination(
        HugeIcons.strokeRoundedLayoutDashboard, AppStrings.dashboard),
    HearthRailDestination(HugeIcons.strokeRoundedShield01, AppStrings.vault),
    HearthRailDestination(
        HugeIcons.strokeRoundedMagicWand01, AppStrings.generator),
    HearthRailDestination(
        HugeIcons.strokeRoundedSettings01, AppStrings.settings),
    HearthRailDestination(HugeIcons.strokeRoundedBluetooth, AppStrings.sharing),
  ];

  const HearthRail({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.onCommand,
    required this.onLock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizes.railWidth,
      decoration: const BoxDecoration(
        color: AppColors.coalSoft,
        border: Border(right: BorderSide(color: AppColors.hearthEdge)),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.md),
          _RailButton(
            icon: HugeIcons.strokeRoundedSearch01,
            tooltip: 'Command palette (Ctrl+K)',
            onTap: onCommand,
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(height: 1, width: 36, color: AppColors.hearthEdge),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < destinations.length; i++)
            _RailButton(
              icon: destinations[i].icon,
              tooltip: destinations[i].label,
              selected: currentIndex == i,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          _RailButton(
            icon: HugeIcons.strokeRoundedPower,
            tooltip: AppStrings.lockVault,
            onTap: onLock,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _RailButton extends StatefulWidget {
  final List<List<dynamic>> icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            width: 44,
            height: 44,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: active
                  ? AppColors.ember.withValues(alpha: 0.14)
                  : _hover
                      ? AppColors.hearthRaised
                      : Colors.transparent,
              borderRadius: AppRadii.mdAll,
              border: Border.all(
                color: active
                    ? AppColors.ember.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
            child: Center(
              child: HugeIcon(
                icon: widget.icon,
                size: 20,
                color: active ? AppColors.emberBright : AppColors.ashMuted,
                strokeWidth: 1.8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
