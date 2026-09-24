// Desktop workspace: rail + section content. The vault is a master-detail
// two-pane (list left, detail right).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_ui_desktop/firewood_ui_desktop.dart';

import '../data/security_report.dart';
import '../providers.dart';
import 'item_editor.dart';
import 'settings_section.dart';
import 'sharing_page.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _autoLockTimer;

  @override
  void initState() {
    super.initState();
    _resetAutoLock();
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    super.dispose();
  }

  void _resetAutoLock() {
    _autoLockTimer?.cancel();
    if (!ref.read(autoLockEnabledProvider)) return;
    final minutes = ref.read(autoLockMinutesProvider);
    _autoLockTimer = Timer(Duration(minutes: minutes), () {
      ref.read(authProvider.notifier).state = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(desktopTabProvider);
    ref.listen(autoLockEnabledProvider, (_, __) => _resetAutoLock());
    ref.listen(autoLockMinutesProvider, (_, __) => _resetAutoLock());

    Widget content;
    switch (tab) {
      case 1:
        content = const _VaultWorkspace();
      case 2:
        content = const _GeneratorSection();
      case 3:
        content = const SettingsSection();
      case 4:
        content = const SharingPage();
      default:
        content = const _DashboardSection();
    }

    return Listener(
      onPointerDown: (_) => _resetAutoLock(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              ref.read(commandPaletteOpenProvider.notifier).state = true,
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              ref.read(commandPaletteOpenProvider.notifier).state = true,
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
              ref.read(authProvider.notifier).state = null,
          const SingleActivator(LogicalKeyboardKey.keyL, meta: true): () =>
              ref.read(authProvider.notifier).state = null,
          for (var i = 1; i <= 5; i++)
            SingleActivator(
              [
                LogicalKeyboardKey.digit1,
                LogicalKeyboardKey.digit2,
                LogicalKeyboardKey.digit3,
                LogicalKeyboardKey.digit4,
                LogicalKeyboardKey.digit5,
              ][i - 1],
              control: true,
            ): () => ref.read(desktopTabProvider.notifier).state = i - 1,
        },
        child: Focus(
          autofocus: true,
          child: Row(
            children: [
              HearthRail(
                currentIndex: tab,
                onSelect: (i) => ref.read(desktopTabProvider.notifier).state = i,
                onCommand: () => ref.read(commandPaletteOpenProvider.notifier).state = true,
                onLock: () => ref.read(authProvider.notifier).state = null,
              ),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Vault master-detail ---

class _VaultWorkspace extends ConsumerStatefulWidget {
  const _VaultWorkspace();

  @override
  ConsumerState<_VaultWorkspace> createState() => _VaultWorkspaceState();
}

class _VaultWorkspaceState extends ConsumerState<_VaultWorkspace> {
  List<DecryptedItem> _items = [];
  ItemType? _filterType;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final key = ref.read(authProvider);
    if (key == null) return;
    final items = await ref.read(itemServiceProvider).getAllItems(key);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _addItem() async {
    final key = ref.read(authProvider);
    if (key == null) return;
    final payload = await showDialog<ItemDraft>(
      context: context,
      builder: (_) => const ItemEditorDialog(),
    );
    if (payload == null) return;
    await ref.read(itemServiceProvider).addItem(
          key: key,
          type: payload.type,
          title: payload.title,
          fields: payload.fields,
        );
    await _reload();
  }

  Future<void> _deleteItem(DecryptedItem item) async {
    await ref.read(itemServiceProvider).deleteItem(item.itemId);
    if (ref.read(selectedItemIdProvider) == item.itemId) {
      ref.read(selectedItemIdProvider.notifier).state = null;
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedItemIdProvider);
    final selected = _items.where((i) => i.itemId == selectedId).firstOrNull;
    final query = _query.trim().toLowerCase();
    final visible = _items.where((i) {
      if (_filterType != null && ItemTypeExt.fromString(i.type) != _filterType) return false;
      if (query.isEmpty) return true;
      if (i.title.toLowerCase().contains(query)) return true;
      return i.fields.values.any((v) => v.toString().toLowerCase().contains(query));
    }).toList();

    return Column(
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.hearthEdge)),
          ),
          child: Row(
            children: [
              const Text(AppStrings.vault,
                  style: TextStyle(color: AppColors.offWhite, fontWeight: FontWeight.bold)),
              const SizedBox(width: AppSpacing.lg),
              HearthDropdown<ItemType?>(
                value: _filterType,
                width: 180,
                placeholder: AppStrings.allCategories,
                items: [
                  HearthDropdownItem(
                    value: null,
                    label: AppStrings.allCategories,
                    icon: HugeIcons.strokeRoundedGrid,
                  ),
                  for (final t in ItemType.values)
                    HearthDropdownItem(value: t, label: t.label, icon: _itemTypeIcon(t)),
                ],
                onChanged: (v) => setState(() => _filterType = v),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 240,
                height: 40,
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(color: AppColors.offWhite, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search vault…',
                    prefixIcon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedSearch01,
                      size: 16,
                      color: AppColors.textMuted,
                      strokeWidth: 1.8,
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 36, minHeight: 0),
                    suffixIcon: _query.isEmpty
                        ? null
                        : GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            child: const HugeIcon(
                              icon: HugeIcons.strokeRoundedCancel01,
                              size: 15,
                              color: AppColors.textMuted,
                              strokeWidth: 1.8,
                            ),
                          ),
                    suffixIconConstraints:
                        const BoxConstraints(minWidth: 32, minHeight: 0),
                    contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    fillColor: AppColors.inputZinc,
                  ),
                ),
              ),
              const Spacer(),
              FirewoodButton(
                label: AppStrings.newItem,
                icon: HugeIcons.strokeRoundedAdd01,
                onPressed: _addItem,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.ember))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: AppSizes.listPaneDefault,
                      child: visible.isEmpty
                          ? (_items.isEmpty ? const _EmptyVault() : const _NoResults())
                          : ListView.builder(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              itemCount: visible.length,
                              itemBuilder: (context, i) {
                                final item = visible[i];
                                return _VaultTile(
                                  item: item,
                                  selected: item.itemId == selectedId,
                                  onTap: () => ref
                                      .read(selectedItemIdProvider.notifier)
                                      .state = item.itemId,
                                  onDelete: () => _deleteItem(item),
                                );
                              },
                            ),
                    ),
                    const VerticalDivider(width: 1, color: AppColors.hearthEdge),
                    Expanded(
                      child: selected == null
                          ? const _SelectPrompt()
                          : _ItemDetail(
                              item: selected,
                              onEdit: () async {
                                final payload = await showDialog<ItemDraft>(
                                  context: context,
                                  builder: (_) => ItemEditorDialog(initial: selected),
                                );
                                if (payload == null) return;
                                final key = ref.read(authProvider);
                                if (key == null) return;
                                await ref.read(itemServiceProvider).updateItem(
                                      key: key,
                                      itemId: selected.itemId,
                                      newFields: {...selected.fields, ...payload.fields},
                                      newTitle: payload.title,
                                    );
                                await _reload();
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _VaultTile extends StatelessWidget {
  final DecryptedItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _VaultTile({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? AppColors.hearthRaised : AppColors.hearth,
            borderRadius: AppRadii.mdAll,
            border: Border.all(
              color: selected ? AppColors.ember : AppColors.hearthEdge,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.offWhite, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(ItemTypeExt.fromString(item.type).label,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  size: 18,
                  color: AppColors.textMuted,
                  strokeWidth: 1.8,
                ),
                tooltip: AppStrings.deleteItem,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemDetail extends StatefulWidget {
  final DecryptedItem item;
  final VoidCallback onEdit;

  const _ItemDetail({required this.item, required this.onEdit});

  @override
  State<_ItemDetail> createState() => _ItemDetailState();
}

class _ItemDetailState extends State<_ItemDetail> {
  final Set<String> _revealed = {};

  bool _isSecret(String key) {
    final k = key.toLowerCase();
    return k.contains('password') ||
        k.contains('secret') ||
        k.contains('cvv') ||
        k.contains('pin') ||
        k.contains('token') ||
        k.contains('private');
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.title,
                    style: const TextStyle(
                        color: AppColors.offWhite, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              FirewoodButton(
                label: AppStrings.edit,
                icon: HugeIcons.strokeRoundedEdit02,
                variant: FirewoodButtonVariant.secondary,
                onPressed: widget.onEdit,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: ListView(
              children: [
                for (final entry in item.fields.entries)
                  if (entry.key != 'created_at')
                    _detailTile(entry.key, entry.value.toString()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailTile(String key, String value) {
    final secret = _isSecret(key);
    final revealed = _revealed.contains(key);
    final display = secret && !revealed ? '••••••••••' : value;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.hearth,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: AppColors.hearthEdge),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(key, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                const SizedBox(height: 4),
                SelectableText(display,
                    style: const TextStyle(color: AppColors.offWhite, fontSize: 14)),
              ],
            ),
          ),
          if (secret)
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              icon: HugeIcon(
                icon: revealed ? HugeIcons.strokeRoundedView : HugeIcons.strokeRoundedViewOff,
                size: 16,
                color: AppColors.textMuted,
                strokeWidth: 1.8,
              ),
              tooltip: revealed ? 'Hide' : 'Show',
              onPressed: () => setState(() {
                if (revealed) {
                  _revealed.remove(key);
                } else {
                  _revealed.add(key);
                }
              }),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedCopy01,
              size: 16,
              color: AppColors.emberBright,
              strokeWidth: 1.8,
            ),
            tooltip: AppStrings.copy,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(AppStrings.copied)),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedShield01,
            size: 40,
            color: AppColors.textMuted,
            strokeWidth: 1.6,
          ),
          SizedBox(height: AppSpacing.sm),
          Text(AppStrings.vaultEmpty,
              style: TextStyle(color: AppColors.offWhite, fontWeight: FontWeight.bold)),
          SizedBox(height: AppSpacing.xs),
          Text(AppStrings.vaultEmptyHint,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SelectPrompt extends StatelessWidget {
  const _SelectPrompt();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedFire,
            size: 44,
            color: AppColors.emberBright,
            strokeWidth: 1.6,
          ),
          SizedBox(height: AppSpacing.md),
          Text(AppStrings.selectItem,
              style: TextStyle(color: AppColors.offWhite, fontWeight: FontWeight.w600)),
          SizedBox(height: AppSpacing.xs),
          Text(AppStrings.selectItemHint,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}

// --- Other sections ---

class _DashboardSection extends ConsumerWidget {
  const _DashboardSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ref.watch(authProvider);
    return FutureBuilder<List<DecryptedItem>>(
      future: key == null
          ? Future.value(const <DecryptedItem>[])
          : ref.read(itemServiceProvider).getAllItems(key),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <DecryptedItem>[];
        final report = DesktopSecurityReport.from(items);
        final scoreColor = report.score >= 80
            ? AppColors.mintAccent
            : report.score >= 50
                ? const Color(0xFFF59E0B)
                : AppColors.roseAccent;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppSizes.dashboardMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Dashboard',
                  style: TextStyle(
                      color: AppColors.offWhite, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text('Your vault at a glance',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  const Text('SECURITY OVERVIEW',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: AppColors.textMuted)),
                  const Spacer(),
                  Text('${report.total} items',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Security score + 2FA coverage
              Row(
                children: [
                  Expanded(
                    child: _PanelCard(
                      child: Row(
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedShield01,
                            size: 22,
                            color: scoreColor,
                            strokeWidth: 1.8,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('SECURITY HEALTH',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                        color: AppColors.textMuted)),
                                Text(report.scoreLabel,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: scoreColor)),
                              ],
                            ),
                          ),
                          Text('${report.score}%',
                              style: TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.bold, color: scoreColor)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _PanelCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('2FA COVERAGE',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                      color: AppColors.textMuted)),
                              const Spacer(),
                              Text('${report.totpCoverage.round()}%',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.emberBright)),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          ClipRRect(
                            borderRadius: AppRadii.pillAll,
                            child: LinearProgressIndicator(
                              value: report.totpCoverage / 100,
                              minHeight: 6,
                              backgroundColor: AppColors.backgroundZinc,
                              valueColor:
                                  const AlwaysStoppedAnimation(AppColors.ember),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text('${report.totpActive} of ${report.logins} logins',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Advisor metrics
              Row(
                children: [
                  Expanded(child: _MetricChip('Strong', '${report.strong}', AppColors.mintAccent)),
                  Expanded(
                      child: _MetricChip('Weak', '${report.weak}',
                          report.weak > 0 ? AppColors.roseAccent : AppColors.textMuted)),
                  Expanded(
                      child: _MetricChip('Reused', '${report.reused}',
                          report.reused > 0 ? const Color(0xFFF59E0B) : AppColors.textMuted)),
                  Expanded(
                      child: _MetricChip('2FA', '${report.totpActive}',
                          report.totpActive > 0 ? AppColors.emberBright : AppColors.textMuted)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Categories
              const Text('CREDENTIAL CATEGORIES',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: AppColors.textMuted)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: _CategoryCard('Passwords', report.logins, HugeIcons.strokeRoundedKey01)),
                  Expanded(child: _CategoryCard('Cards', report.cards, HugeIcons.strokeRoundedCreditCard)),
                  Expanded(child: _CategoryCard('Identity', report.identities, HugeIcons.strokeRoundedIdentityCard)),
                  Expanded(child: _CategoryCard('API Keys', report.developerSecrets, HugeIcons.strokeRoundedCode)),
                  Expanded(child: _CategoryCard('Notes', report.notes, HugeIcons.strokeRoundedNote)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Recent
              const Text('RECENT CREDENTIALS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: AppColors.textMuted)),
              const SizedBox(height: AppSpacing.sm),
              if (report.recent.isEmpty)
                const _PanelCard(
                  child: Text('Nothing here yet — add your first item.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                )
              else
                for (final item in report.recent)
                  _RecentTile(
                    item: item,
                    onTap: () {
                      ref.read(desktopTabProvider.notifier).state = 1;
                      ref.read(selectedItemIdProvider.notifier).state = item.itemId;
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PanelCard extends StatelessWidget {
  final Widget child;
  const _PanelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceZinc,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: AppColors.borderZinc),
      ),
      child: child,
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MetricChip(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceZinc,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: AppColors.borderZinc),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String label;
  final int count;
  final List<List<dynamic>> icon;
  const _CategoryCard(this.label, this.count, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceZinc,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: AppColors.borderZinc),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HugeIcon(icon: icon, size: 18, color: AppColors.emberBright, strokeWidth: 1.8),
          const SizedBox(height: AppSpacing.md),
          Text('$count',
              style: const TextStyle(
                  color: AppColors.offWhite, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  final DecryptedItem item;
  final VoidCallback onTap;
  const _RecentTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceZinc,
            borderRadius: AppRadii.mdAll,
            border: Border.all(color: AppColors.borderZinc),
          ),
          child: Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedKey01,
                size: 16,
                color: AppColors.textMuted,
                strokeWidth: 1.8,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.offWhite, fontWeight: FontWeight.w600)),
              ),
              Text(ItemTypeExt.fromString(item.type).label,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GeneratorSection extends StatefulWidget {
  const _GeneratorSection();

  @override
  State<_GeneratorSection> createState() => _GeneratorSectionState();
}

class _GeneratorSectionState extends State<_GeneratorSection> {
  String _password = GeneratorService.generatePassword();
  int _length = 20;

  @override
  Widget build(BuildContext context) {
    final strength = GeneratorService.calculateStrength(_password);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: SizedBox(
          width: 520,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(AppStrings.generatePassword,
                style: TextStyle(color: AppColors.offWhite, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.hearth,
                borderRadius: AppRadii.mdAll,
                border: Border.all(color: AppColors.hearthEdge),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(_password,
                        style: const TextStyle(color: AppColors.offWhite, fontSize: 18)),
                  ),
                  IconButton(
                    tooltip: AppStrings.copy,
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedCopy01,
                      size: 18,
                      color: AppColors.emberBright,
                      strokeWidth: 1.8,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _password));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(AppStrings.copied)),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('${AppStrings.strength}: ${GeneratorService.getStrengthLabel(strength)}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: AppSpacing.sm),
            Slider(
              value: _length.toDouble(),
              min: 8,
              max: 64,
              divisions: 56,
              label: '$_length',
              onChanged: (v) => setState(() {
                _length = v.round();
                _password = GeneratorService.generatePassword(length: _length);
              }),
            ),
            FirewoodButton(
              label: AppStrings.regenerate,
              icon: HugeIcons.strokeRoundedRefresh,
              onPressed: () =>
                  setState(() => _password = GeneratorService.generatePassword(length: _length)),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// Icon for an item category, shared by the filter dropdown.
List<List<dynamic>> _itemTypeIcon(ItemType t) {
  switch (t) {
    case ItemType.login:
      return HugeIcons.strokeRoundedUser;
    case ItemType.card:
      return HugeIcons.strokeRoundedCreditCard;
    case ItemType.identity:
      return HugeIcons.strokeRoundedIdentityCard;
    case ItemType.note:
      return HugeIcons.strokeRoundedNote;
    case ItemType.developerSecret:
      return HugeIcons.strokeRoundedCode;
  }
}

/// Shown when a search/filter returns no results (but the vault is not empty).
class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedSearch01,
            size: 34,
            color: AppColors.textMuted,
            strokeWidth: 1.6,
          ),
          SizedBox(height: AppSpacing.md),
          Text(AppStrings.noMatchingItems,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}
