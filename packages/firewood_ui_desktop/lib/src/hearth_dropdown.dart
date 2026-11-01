// Styled dropdown for selecting a category/type: soft matte panel, HugeIcons,
// chevron affordance and a themed popup menu.

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_design/firewood_design.dart';

class HearthDropdownItem<T> {
  final T value;
  final String label;
  final List<List<dynamic>> icon;
  const HearthDropdownItem(
      {required this.value, required this.label, required this.icon});
}

class HearthDropdown<T> extends StatelessWidget {
  final T value;
  final List<HearthDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final double? width;
  final String? placeholder;

  const HearthDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final selected = items
        .where((i) => i.value == value)
        .cast<HearthDropdownItem<T>?>()
        .firstOrNull;

    return PopupMenuButton<T>(
      tooltip: '',
      color: AppColors.surfaceZinc,
      elevation: 8,
      offset: const Offset(0, 6),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.mdAll,
        side: const BorderSide(color: AppColors.borderZinc),
      ),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final item in items)
          PopupMenuItem<T>(
            value: item.value,
            height: 44,
            child: Row(
              children: [
                HugeIcon(
                  icon: item.icon,
                  size: 17,
                  color: item.value == value
                      ? AppColors.emberBright
                      : AppColors.textMuted,
                  strokeWidth: 1.8,
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  item.label,
                  style: TextStyle(
                    color: AppColors.offWhite,
                    fontSize: 13,
                    fontWeight:
                        item.value == value ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (item.value == value) ...[
                  const Spacer(),
                  const HugeIcon(
                    icon: HugeIcons.strokeRoundedTick02,
                    size: 15,
                    color: AppColors.emberBright,
                    strokeWidth: 2.0,
                  ),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        width: width,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.hearthRaised, AppColors.hearth],
          ),
          borderRadius: AppRadii.mdAll,
          border: Border.all(color: AppColors.borderZinc),
        ),
        child: Row(
          mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
          children: [
            if (selected != null)
              HugeIcon(
                icon: selected.icon,
                size: 16,
                color: AppColors.emberBright,
                strokeWidth: 1.8,
              ),
            if (selected != null) const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                selected?.label ?? placeholder ?? 'Select',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.offWhite, fontSize: 13),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            HugeIcon(
              icon: HugeIcons.strokeRoundedChevronDown,
              size: 16,
              color: AppColors.textMuted,
              strokeWidth: 1.8,
            ),
          ],
        ),
      ),
    );
  }
}
