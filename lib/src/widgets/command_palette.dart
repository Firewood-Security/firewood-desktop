// Ctrl/Cmd+K command palette: navigate, create, lock, and jump to items.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';

import '../providers.dart';

class DesktopCommandPalette extends ConsumerStatefulWidget {
  const DesktopCommandPalette({super.key});

  @override
  ConsumerState<DesktopCommandPalette> createState() => _DesktopCommandPaletteState();
}

class _DesktopCommandPaletteState extends ConsumerState<DesktopCommandPalette> {
  final _controller = TextEditingController();
  List<DecryptedItem> _items = [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _index = 0));
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = ref.read(authProvider);
    if (key == null) return;
    try {
      final items = await ref.read(itemServiceProvider).getAllItems(key);
      if (mounted) setState(() => _items = items);
    } catch (_) {}
  }

  void _close() {
    ref.read(commandPaletteOpenProvider.notifier).state = false;
    _controller.clear();
    _index = 0;
  }

  void _run(VoidCallback action) {
    _close();
    action();
  }

  List<_Entry> _entries() {
    final entries = <_Entry>[
      _Entry(AppStrings.goToDashboard, HugeIcons.strokeRoundedLayoutDashboard, const ['home'],
          () => ref.read(desktopTabProvider.notifier).state = 0),
      _Entry(AppStrings.goToVault, HugeIcons.strokeRoundedShield01, const ['items', 'passwords'],
          () => ref.read(desktopTabProvider.notifier).state = 1),
      _Entry(AppStrings.goToGenerator, HugeIcons.strokeRoundedMagicWand01, const ['password'],
          () => ref.read(desktopTabProvider.notifier).state = 2),
      _Entry(AppStrings.goToSettings, HugeIcons.strokeRoundedSettings01, const ['preferences'],
          () => ref.read(desktopTabProvider.notifier).state = 3),
      _Entry('Go to Sharing', HugeIcons.strokeRoundedBluetooth, const ['bluetooth', 'send', 'receive'],
          () => ref.read(desktopTabProvider.notifier).state = 4),
      _Entry(AppStrings.lockVault, HugeIcons.strokeRoundedPower, const ['logout'],
          () => ref.read(authProvider.notifier).state = null),
    ];
    for (final item in _items) {
      entries.add(_Entry(item.title, HugeIcons.strokeRoundedKey01, [item.type], () {
        ref.read(desktopTabProvider.notifier).state = 1;
        ref.read(selectedItemIdProvider.notifier).state = item.itemId;
      }));
    }
    return entries;
  }

  List<_Entry> get _filtered {
    final q = _controller.text.trim().toLowerCase();
    final all = _entries();
    if (q.isEmpty) return all;
    return all.where((e) =>
        e.label.toLowerCase().contains(q) ||
        e.keywords.any((k) => k.toLowerCase().contains(q))).toList();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final filtered = _filtered;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _index = (_index + 1).clamp(0, filtered.length - 1));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      setState(() => _index = (_index - 1).clamp(0, filtered.length - 1));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter) {
      if (filtered.isNotEmpty) _run(filtered[_index.clamp(0, filtered.length - 1)].action);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(commandPaletteOpenProvider)) return const SizedBox.shrink();
    final filtered = _filtered;
    final selected = filtered.isEmpty ? -1 : _index.clamp(0, filtered.length - 1);

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            onTap: _close,
            child: Container(color: Colors.black.withValues(alpha: 0.55)),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 90),
              child: Focus(
                onKeyEvent: _onKey,
                child: Container(
                  width: 620,
                  constraints: const BoxConstraints(maxHeight: 440),
                  decoration: BoxDecoration(
                    color: AppColors.hearth,
                    borderRadius: AppRadii.lgAll,
                    border: Border.all(color: AppColors.ember.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          style: const TextStyle(color: AppColors.ash, fontSize: 15),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: AppStrings.commandHint,
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.hearthEdge),
                      Flexible(
                        child: filtered.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(AppSpacing.xxl),
                                child: Text(AppStrings.noMatches,
                                    style: TextStyle(color: AppColors.textMuted)),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: filtered.length,
                                itemBuilder: (context, i) {
                                  final entry = filtered[i];
                                  final isSel = i == selected;
                                  return GestureDetector(
                                    onTap: () => _run(entry.action),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.sm, vertical: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.md, vertical: AppSpacing.md),
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? AppColors.ember.withValues(alpha: 0.12)
                                            : Colors.transparent,
                                        borderRadius: AppRadii.mdAll,
                                      ),
                                      child: Row(
                                        children: [
                                          HugeIcon(
                                            icon: entry.icon,
                                            size: AppSizes.iconSm,
                                            color: isSel
                                                ? AppColors.emberBright
                                                : AppColors.ashMuted,
                                            strokeWidth: 1.8,
                                          ),
                                          const SizedBox(width: AppSpacing.md),
                                          Expanded(
                                            child: Text(entry.label,
                                                style: const TextStyle(
                                                    color: AppColors.offWhite, fontSize: 13)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry {
  final String label;
  final List<List<dynamic>> icon;
  final List<String> keywords;
  final VoidCallback action;
  _Entry(this.label, this.icon, this.keywords, this.action);
}
