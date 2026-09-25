// Desktop workspace: rail + section content with rich analytics,
// Mini ML Security Advisor, and master-detail credential manager.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:otp/otp.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_ui_desktop/firewood_ui_desktop.dart';
import 'package:hugeicons/hugeicons.dart';

import '../providers.dart';
import '../services/autotype_service.dart';
import '../services/mini_ml_advisor.dart';
import '../services/secure_clipboard.dart';
import '../theme/app_icons.dart';
import '../widgets/airshare_dialog.dart';
import '../widgets/generator_dialog.dart';
import '../widgets/security_advisor_dialog.dart';
import 'item_editor.dart';
import 'package:window_manager/window_manager.dart';
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
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
              ref.read(commandPaletteOpenProvider.notifier).state = true,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
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
                onSelect: (i) =>
                    ref.read(desktopTabProvider.notifier).state = i,
                onCommand: () =>
                    ref.read(commandPaletteOpenProvider.notifier).state = true,
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

// ==========================================
// 1. DASHBOARD SECTION WITH MINI ML ADVISOR
// ==========================================

class _DashboardSection extends ConsumerStatefulWidget {
  const _DashboardSection();

  @override
  ConsumerState<_DashboardSection> createState() => _DashboardSectionState();
}

class _DashboardSectionState extends ConsumerState<_DashboardSection> {
  List<DecryptedItem> _items = [];
  bool _loading = true;
  ItemType? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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

  Future<void> _addNewItem() async {
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
    await _load();
  }

  String _iconForType(String type) {
    switch (ItemTypeExt.fromString(type)) {
      case ItemType.login:
        return AppIcons.categoryLogin;
      case ItemType.card:
        return AppIcons.categoryCard;
      case ItemType.identity:
        return AppIcons.categoryIdentity;
      case ItemType.note:
        return AppIcons.categoryNote;
      case ItemType.developerSecret:
        return AppIcons.key;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.orangeAccent),
      );
    }

    final advisory = SecurityAdvisorEngine.analyze(_items);
    final key = ref.read(authProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E12),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar
            Row(
              children: [
                const AppIcon(AppIcons.vault, size: 48),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FIREWOOD VAULT',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Zero-Knowledge End-to-End Encrypted (AES-256-GCM)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedMagicWand01,
                    size: 18,
                    color: Colors.white,
                    strokeWidth: 1.8,
                  ),
                  label: const Text('Generator'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF2E333F)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onPressed: () => PasswordGeneratorDialog.show(context),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedAdd01,
                    size: 18,
                    color: Colors.black,
                    strokeWidth: 2.2,
                  ),
                  label: const Text('New Item'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orangeAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _addNewItem,
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Top Hero Card: Mini ML Security Advisor
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF191C24),
                    advisory.score >= 80
                        ? const Color(0xFF13201B)
                        : (advisory.score >= 50
                            ? const Color(0xFF221C14)
                            : const Color(0xFF261418)),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: advisory.score >= 80
                      ? AppColors.mintAccent.withOpacity(0.3)
                      : (advisory.score >= 50
                          ? const Color(0xFFF59E0B).withOpacity(0.3)
                          : AppColors.roseAccent.withOpacity(0.3)),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // Health Gauge
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF111317),
                      border: Border.all(
                        color: advisory.score >= 80
                            ? AppColors.mintAccent
                            : (advisory.score >= 50
                                ? const Color(0xFFF59E0B)
                                : AppColors.roseAccent),
                        width: 4,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${advisory.score}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'HEALTH',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),

                  // Finding details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'AI SECURITY ADVISOR',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (advisory.score >= 80
                                        ? AppColors.mintAccent
                                        : (advisory.score >= 50
                                            ? const Color(0xFFF59E0B)
                                            : AppColors.roseAccent))
                                    .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                advisory.score >= 80
                                    ? 'SECURE'
                                    : (advisory.score >= 50
                                        ? 'NEEDS ATTENTION'
                                        : 'CRITICAL RISKS'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: advisory.score >= 80
                                      ? AppColors.mintAccent
                                      : (advisory.score >= 50
                                          ? const Color(0xFFF59E0B)
                                          : AppColors.roseAccent),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          advisory.headlineTip?.title ??
                              'All Credentials Meeting Zero-Knowledge Standards',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          advisory.headlineTip?.message ??
                              'Deterministic on-device evaluation detected zero entropy vulnerabilities or password reuse across your vault.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),

                  // Button to view details
                  ElevatedButton.icon(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedShieldCheck,
                      size: 18,
                      color: Colors.white,
                      strokeWidth: 1.8,
                    ),
                    label: const Text('Review Findings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF262B36),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      side: const BorderSide(color: Color(0xFF3B4254)),
                    ),
                    onPressed: () {
                      if (key != null) {
                        SecurityAdvisorDialog.show(
                          context,
                          advisory: advisory,
                          key: key,
                          onOpenItem: (item) {
                            ref.read(selectedItemIdProvider.notifier).state =
                                item.itemId;
                            ref.read(desktopTabProvider.notifier).state = 1;
                          },
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Analytics Grid
            Row(
              children: [
                _buildStatCard(
                  icon: AppIcons.vault,
                  title: 'Total Items',
                  value: '${advisory.totalItems}',
                  color: Colors.white,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  icon: AppIcons.shieldCheck,
                  title: 'Strong Passwords',
                  value: '${advisory.strongCount}',
                  color: AppColors.mintAccent,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  icon: AppIcons.alert,
                  title: 'Weak Passwords',
                  value: '${advisory.weakCount}',
                  color: advisory.weakCount > 0
                      ? AppColors.roseAccent
                      : Colors.white60,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  icon: AppIcons.copy,
                  title: 'Reused Passwords',
                  value: '${advisory.reusedCount}',
                  color: advisory.reusedCount > 0
                      ? AppColors.roseAccent
                      : Colors.white60,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  icon: AppIcons.shieldKey,
                  title: 'Missing 2FA',
                  value: '${advisory.missing2FACount}',
                  color: advisory.missing2FACount > 0
                      ? const Color(0xFFF59E0B)
                      : Colors.white60,
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  icon: AppIcons.history,
                  title: 'Stale (>120d)',
                  value: '${advisory.staleCount}',
                  color: advisory.staleCount > 0
                      ? const Color(0xFFF59E0B)
                      : Colors.white60,
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Category Filter Pills
            Row(
              children: [
                _buildCategoryPill(
                  label: 'All Items',
                  icon: AppIcons.vault,
                  count: _items.length,
                  selected: _selectedCategory == null,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                const SizedBox(width: 10),
                _buildCategoryPill(
                  label: 'Logins',
                  icon: AppIcons.categoryLogin,
                  count: _items
                      .where((i) =>
                          ItemTypeExt.fromString(i.type) == ItemType.login)
                      .length,
                  selected: _selectedCategory == ItemType.login,
                  onTap: () => setState(() => _selectedCategory = ItemType.login),
                ),
                const SizedBox(width: 10),
                _buildCategoryPill(
                  label: 'Credit Cards',
                  icon: AppIcons.categoryCard,
                  count: _items
                      .where((i) =>
                          ItemTypeExt.fromString(i.type) == ItemType.card)
                      .length,
                  selected: _selectedCategory == ItemType.card,
                  onTap: () => setState(() => _selectedCategory = ItemType.card),
                ),
                const SizedBox(width: 10),
                _buildCategoryPill(
                  label: 'Identities',
                  icon: AppIcons.categoryIdentity,
                  count: _items
                      .where((i) =>
                          ItemTypeExt.fromString(i.type) == ItemType.identity)
                      .length,
                  selected: _selectedCategory == ItemType.identity,
                  onTap: () => setState(() => _selectedCategory = ItemType.identity),
                ),
                const SizedBox(width: 10),
                _buildCategoryPill(
                  label: 'Secure Notes',
                  icon: AppIcons.categoryNote,
                  count: _items
                      .where((i) =>
                          ItemTypeExt.fromString(i.type) == ItemType.note)
                      .length,
                  selected: _selectedCategory == ItemType.note,
                  onTap: () => setState(() => _selectedCategory = ItemType.note),
                ),
                const SizedBox(width: 10),
                _buildCategoryPill(
                  label: 'API Keys',
                  icon: AppIcons.key,
                  count: _items
                      .where((i) =>
                          ItemTypeExt.fromString(i.type) ==
                          ItemType.developerSecret)
                      .length,
                  selected: _selectedCategory == ItemType.developerSecret,
                  onTap: () =>
                      setState(() => _selectedCategory = ItemType.developerSecret),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Filtered Items Grid / List
            _buildItemsGrid(
              _items.where((i) {
                if (_selectedCategory != null) {
                  return ItemTypeExt.fromString(i.type) == _selectedCategory;
                }
                return true;
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required dynamic icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF15181F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF242833)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIcon(icon, size: 28),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryPill({
    required String label,
    required dynamic icon,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.orangeAccent.withOpacity(0.18)
              : const Color(0xFF161921),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.orangeAccent
                : const Color(0xFF262B36),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? Colors.white : Colors.white70,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.orangeAccent
                    : const Color(0xFF242934),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: selected ? Colors.black : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsGrid(List<DecryptedItem> visibleItems) {
    if (visibleItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF14171E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF222630)),
        ),
        child: Column(
          children: [
            const AppIcon(AppIcons.vault, size: 64),
            const SizedBox(height: 12),
            const Text(
              'No credentials in this category',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Click "+ New Item" above to create your first encrypted record.',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final crossAxisCount = (constraints.maxWidth / 320).floor().clamp(1, 4);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisExtent: 110,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: visibleItems.length,
          itemBuilder: (ctx, idx) {
            final item = visibleItems[idx];
            final username = item.fields['username'] ??
                item.fields['email'] ??
                item.fields['cardholder'] ??
                item.fields['number'] ??
                '';

            return InkWell(
              onTap: () {
                ref.read(selectedItemIdProvider.notifier).state = item.itemId;
                ref.read(desktopTabProvider.notifier).state = 1;
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161921),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF262B36)),
                ),
                child: Row(
                  children: [
                    AppIcon(_iconForType(item.type), size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            username.isNotEmpty
                                ? username.toString()
                                : item.type.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      color: Colors.white30,
                      size: 18,
                      strokeWidth: 1.8,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ==========================================
// 2. VAULT MASTER-DETAIL TWO-PANE WORKSPACE
// ==========================================

class _VaultWorkspace extends ConsumerStatefulWidget {
  const _VaultWorkspace();

  @override
  ConsumerState<_VaultWorkspace> createState() => _VaultWorkspaceState();
}

class _VaultWorkspaceState extends ConsumerState<_VaultWorkspace> {
  List<DecryptedItem> _items = [];
  ItemType? _filterType;
  bool _viewingTrash = false;
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
    final itemService = ref.read(itemServiceProvider);
    final items = _viewingTrash
        ? await itemService.getTrashItems(key)
        : await itemService.getAllItems(key);
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

  Future<void> _editItem(DecryptedItem item) async {
    final key = ref.read(authProvider);
    if (key == null) return;
    final payload = await showDialog<ItemDraft>(
      context: context,
      builder: (_) => ItemEditorDialog(initial: item),
    );
    if (payload == null) return;
    await ref.read(itemServiceProvider).updateItem(
          key: key,
          itemId: item.itemId,
          newTitle: payload.title,
          newFields: payload.fields,
        );
    if (payload.type != item.type) {
      final store = ref.read(secretStoreProvider);
      final stored = await store.getItem(item.itemId);
      if (stored != null) {
        await store.putItem(StoredItem(
          itemId: stored.itemId,
          vaultId: stored.vaultId,
          encryptedData: stored.encryptedData,
          nonce: stored.nonce,
          type: payload.type,
          title: payload.title,
          updatedAt: DateTime.now(),
        ));
      }
    }
    await _reload();
  }

  Future<void> _deleteItem(DecryptedItem item) async {
    final key = ref.read(authProvider);
    if (key == null) return;

    if (_viewingTrash) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF181B22),
          title: const Text('Delete Permanently?'),
          content: Text('Permanently destroy "${item.title}"? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.roseAccent),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete Permanently'),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      await ref.read(itemServiceProvider).deleteItem(item.itemId);
    } else {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF181B22),
          title: const Text('Move to Trash?'),
          content: Text('Move "${item.title}" to the Trash? You can restore it anytime.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.roseAccent),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Move to Trash'),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      await ref.read(itemServiceProvider).moveToTrash(key, item.itemId);
    }

    if (ref.read(selectedItemIdProvider) == item.itemId) {
      ref.read(selectedItemIdProvider.notifier).state = null;
    }
    await _reload();
  }

  Future<void> _restoreItem(DecryptedItem item) async {
    final key = ref.read(authProvider);
    if (key == null) return;
    await ref.read(itemServiceProvider).restoreFromTrash(key, item.itemId);
    if (ref.read(selectedItemIdProvider) == item.itemId) {
      ref.read(selectedItemIdProvider.notifier).state = null;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${item.title}" restored to vault'),
          backgroundColor: const Color(0xFF1A2E22),
        ),
      );
    }
    await _reload();
  }

  Future<void> _emptyTrash() async {
    final key = ref.read(authProvider);
    if (key == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181B22),
        title: const Text('Empty Trash?'),
        content: const Text(
          'Permanently delete all items in the Trash? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.roseAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Empty Trash Now'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final count = await ref.read(itemServiceProvider).emptyTrash(key);
    ref.read(selectedItemIdProvider.notifier).state = null;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Purged $count items permanently.'),
          backgroundColor: AppColors.surfaceZinc,
        ),
      );
    }
    await _reload();
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap, {bool isDanger = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDanger ? AppColors.roseAccent : AppColors.orangeAccent)
                : const Color(0xFF181B24),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? (isDanger ? AppColors.roseAccent : AppColors.orangeAccent)
                  : const Color(0xFF2A2F3D),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.black : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  String _iconForType(String type) {
    switch (ItemTypeExt.fromString(type)) {
      case ItemType.login:
        return AppIcons.categoryLogin;
      case ItemType.card:
        return AppIcons.categoryCard;
      case ItemType.identity:
        return AppIcons.categoryIdentity;
      case ItemType.note:
        return AppIcons.categoryNote;
      case ItemType.developerSecret:
        return AppIcons.key;
    }
  }

  Future<void> _createNewVaultPrompt() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF2B3141)),
        ),
        title: const Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedFolder01,
              color: AppColors.orangeAccent,
              size: 20,
              strokeWidth: 1.8,
            ),
            SizedBox(width: 10),
            Text(
              'Create New Vault',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Group credentials into separate vaults (e.g. Work, Clients, Personal).',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Vault Name (e.g. Work, Finance)',
                  filled: true,
                  fillColor: const Color(0xFF0F1117),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF262C3A)),
                  ),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orangeAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final currentList = ref.read(availableVaultsProvider);
      if (!currentList.contains(name)) {
        ref.read(availableVaultsProvider.notifier).state = [...currentList, name];
      }
      ref.read(activeVaultFilterProvider.notifier).state = name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedItemIdProvider);
    final selected = _items.where((i) => i.itemId == selectedId).firstOrNull;
    final query = _query.trim().toLowerCase();
    final activeVault = ref.watch(activeVaultFilterProvider);
    final availableVaults = ref.watch(availableVaultsProvider);
    final visible = _items.where((i) {
      if (activeVault != null) {
        final itemVault = (i.fields['vault'] ?? 'Primary Vault').toString();
        if (itemVault != activeVault) return false;
      }
      if (_filterType != null &&
          ItemTypeExt.fromString(i.type) != _filterType) {
        return false;
      }
      if (query.isEmpty) return true;
      if (i.title.toLowerCase().contains(query)) return true;
      return i.fields.values
          .any((v) => v.toString().toLowerCase().contains(query));
    }).toList();

    return Row(
      children: [
        // Left Master Pane: Filter & List
        Container(
          width: 380,
          decoration: const BoxDecoration(
            color: Color(0xFF101217),
            border: Border(right: BorderSide(color: Color(0xFF222631))),
          ),
          child: Column(
            children: [
              // Vault Selector Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF13151D),
                  border: Border(bottom: BorderSide(color: Color(0xFF222631))),
                ),
                child: Row(
                  children: [
                    const HugeIcon(
                      icon: HugeIcons.strokeRoundedFolder01,
                      color: AppColors.orangeAccent,
                      size: 16,
                      strokeWidth: 1.8,
                    ),
                    const SizedBox(width: 8),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: activeVault,
                        isDense: true,
                        dropdownColor: const Color(0xFF181B24),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowDown01,
                          size: 14,
                          color: Colors.white70,
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All Vaults'),
                          ),
                          ...availableVaults.map(
                            (v) => DropdownMenuItem<String?>(
                              value: v,
                              child: Text(v),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          ref.read(activeVaultFilterProvider.notifier).state = val;
                        },
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedAdd01,
                        size: 16,
                        color: Colors.white60,
                        strokeWidth: 1.8,
                      ),
                      tooltip: 'New Vault',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      onPressed: _createNewVaultPrompt,
                    ),
                  ],
                ),
              ),

              // Search & Add Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF222631))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: 'Search vault...',
                          prefixIcon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedSearch01,
                            size: 18,
                            color: Colors.white60,
                            strokeWidth: 1.8,
                          ),
                          filled: true,
                          fillColor: const Color(0xFF181B24),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFF2A2F3D)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFF2A2F3D)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (!_viewingTrash)
                      IconButton(
                        tooltip: 'New Item',
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedAddCircle,
                          color: AppColors.orangeAccent,
                          size: 24,
                          strokeWidth: 1.8,
                        ),
                        onPressed: _addItem,
                      ),
                  ],
                ),
              ),

              // Filter Category Chips
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF222631))),
                ),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildFilterChip('All', !_viewingTrash && _filterType == null, () {
                      setState(() {
                        _viewingTrash = false;
                        _filterType = null;
                        _loading = true;
                      });
                      _reload();
                    }),
                    _buildFilterChip('Logins', !_viewingTrash && _filterType == ItemType.login, () {
                      setState(() {
                        _viewingTrash = false;
                        _filterType = ItemType.login;
                        _loading = true;
                      });
                      _reload();
                    }),
                    _buildFilterChip('Cards', !_viewingTrash && _filterType == ItemType.card, () {
                      setState(() {
                        _viewingTrash = false;
                        _filterType = ItemType.card;
                        _loading = true;
                      });
                      _reload();
                    }),
                    _buildFilterChip('Notes', !_viewingTrash && _filterType == ItemType.note, () {
                      setState(() {
                        _viewingTrash = false;
                        _filterType = ItemType.note;
                        _loading = true;
                      });
                      _reload();
                    }),
                    _buildFilterChip('IDs', !_viewingTrash && _filterType == ItemType.identity, () {
                      setState(() {
                        _viewingTrash = false;
                        _filterType = ItemType.identity;
                        _loading = true;
                      });
                      _reload();
                    }),
                    _buildFilterChip('Trash', _viewingTrash, () {
                      setState(() {
                        _viewingTrash = true;
                        _filterType = null;
                        _loading = true;
                      });
                      _reload();
                    }, isDanger: true),
                  ],
                ),
              ),

              // Trash Action Header if in Trash view
              if (_viewingTrash)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppColors.roseAccent.withOpacity(0.08),
                  child: Row(
                    children: [
                      Text(
                        'Trash (${_items.length})',
                        style: const TextStyle(
                          color: AppColors.roseAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      if (_items.isNotEmpty)
                        TextButton.icon(
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedDelete02,
                            size: 14,
                            color: AppColors.roseAccent,
                            strokeWidth: 1.8,
                          ),
                          label: const Text(
                            'Empty Trash',
                            style: TextStyle(color: AppColors.roseAccent, fontSize: 12),
                          ),
                          onPressed: _emptyTrash,
                        ),
                    ],
                  ),
                ),

              // Item List
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.orangeAccent))
                    : (visible.isEmpty
                        ? Center(
                            child: Text(
                              _viewingTrash ? 'Trash is empty' : 'No credentials found',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.5)),
                            ),
                          )
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (ctx, idx) {
                              final item = visible[idx];
                              final isSelected = item.itemId == selectedId;
                              final sub = item.fields['username'] ??
                                  item.fields['email'] ??
                                  item.fields['cardholder'] ??
                                  '';

                              return ListTile(
                                selected: isSelected,
                                selectedTileColor:
                                    AppColors.orangeAccent.withOpacity(0.12),
                                leading:
                                    AppIcon(_iconForType(item.type), size: 36),
                                title: Text(
                                  item.title,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                subtitle: Text(
                                  sub.isNotEmpty
                                      ? sub.toString()
                                      : item.type.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                ),
                                onTap: () {
                                  ref
                                      .read(selectedItemIdProvider.notifier)
                                      .state = item.itemId;
                                },
                              );
                            },
                          )),
              ),
            ],
          ),
        ),

        // Right Detail Pane
        Expanded(
          child: selected == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppIcon(AppIcons.vault, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        _viewingTrash ? 'Select a deleted item to inspect or restore' : 'Select a credential to inspect',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _viewingTrash ? 'Items in trash can be restored or deleted permanently.' : 'Or press "+ New Item" to create a new record.',
                        style: TextStyle(color: Colors.white.withOpacity(0.4)),
                      ),
                    ],
                  ),
                )
              : _CredentialDetailPane(
                  item: selected,
                  onEdit: () => _editItem(selected),
                  onDelete: () => _deleteItem(selected),
                  onRestore: () => _restoreItem(selected),
                ),
        ),
      ],
    );
  }
}

// ==========================================
// 3. CREDENTIAL DETAIL PANE WITH TOTP TIMER
// ==========================================

class _CredentialDetailPane extends ConsumerStatefulWidget {
  final DecryptedItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onRestore;

  const _CredentialDetailPane({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    this.onRestore,
  });

  @override
  ConsumerState<_CredentialDetailPane> createState() => _CredentialDetailPaneState();
}

class _CredentialDetailPaneState extends ConsumerState<_CredentialDetailPane> {
  bool _revealPassword = false;
  Timer? _totpTimer;
  String _totpCode = '';
  int _totpSecondsLeft = 30;

  Future<void> _triggerAutoType(DecryptedItem item) async {
    final available = await AutoTypeService.isAvailable();
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.roseAccent,
          content: Text(
            'AutoType requires xdotool on Linux. Please install xdotool.',
          ),
        ),
      );
      return;
    }

    final delay = ref.read(autoTypeDelaySecondsProvider);
    final sequence = ref.read(autoTypeSequenceProvider);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1B1E28),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.orangeAccent),
        ),
        duration: Duration(seconds: delay + 1),
        content: Row(
          children: [
            const HugeIcon(
              icon: HugeIcons.strokeRoundedKeyboard,
              size: 20,
              color: AppColors.orangeAccent,
              strokeWidth: 1.8,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Auto-typing into active window in ${delay}s... Switch to your target app.',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Minimize window so previous target window gains focus
    await windowManager.minimize();

    final result = await AutoTypeService.execute(
      item: item,
      sequence: sequence,
      initialCountdownSeconds: delay,
    );

    if (!result.success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.roseAccent,
          content: Text(result.message),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _startTotp();
  }

  @override
  void didUpdateWidget(covariant _CredentialDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.itemId != widget.item.itemId) {
      _revealPassword = false;
      _startTotp();
    }
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
    super.dispose();
  }

  void _startTotp() {
    _totpTimer?.cancel();
    final secret = widget.item.fields['totp_secret'] ??
        widget.item.fields['totpSecret'] ??
        '';
    if (secret.isEmpty) return;

    _updateTotp(secret.toString());
    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateTotp(secret.toString());
    });
  }

  void _updateTotp(String secret) {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final code = OTP.generateTOTPCodeString(
        secret.replaceAll(' ', ''),
        now,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true,
      );
      final sec = 30 - ((now ~/ 1000) % 30);
      setState(() {
        _totpCode = code;
        _totpSecondsLeft = sec;
      });
    } catch (_) {
      setState(() => _totpCode = '');
    }
  }

  void _copy(String text, String label) {
    SecureClipboard.copy(
      context: context,
      text: text,
      label: label,
      timeoutSeconds: 30,
    );
  }

  void _showPasswordHistoryDialog(BuildContext context, DecryptedItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        title: Row(
          children: [
            const HugeIcon(
              icon: HugeIcons.strokeRoundedClock01,
              color: AppColors.orangeAccent,
              size: 22,
              strokeWidth: 1.8,
            ),
            const SizedBox(width: 10),
            Text(
              'Password History (${item.passwordHistory.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: item.passwordHistory.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No previous passwords recorded.',
                    style: TextStyle(color: Colors.white60),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: item.passwordHistory.length,
                  separatorBuilder: (_, __) => const Divider(
                    color: Color(0xFF242835),
                    height: 16,
                  ),
                  itemBuilder: (ctx, idx) {
                    final entry = item.passwordHistory[idx];
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                entry.password,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Changed: ${DateFormat.yMMMd().add_jm().format(entry.changedAt)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy Previous Password',
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedCopy01,
                            size: 18,
                            color: Colors.white70,
                            strokeWidth: 1.8,
                          ),
                          onPressed: () {
                            _copy(entry.password, 'Previous Password');
                          },
                        ),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _iconForType(String type) {
    switch (ItemTypeExt.fromString(type)) {
      case ItemType.login:
        return AppIcons.categoryLogin;
      case ItemType.card:
        return AppIcons.categoryCard;
      case ItemType.identity:
        return AppIcons.categoryIdentity;
      case ItemType.note:
        return AppIcons.categoryNote;
      case ItemType.developerSecret:
        return AppIcons.key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final password = item.fields['password']?.toString() ?? '';
    final username = (item.fields['username'] ?? item.fields['email'])?.toString() ?? '';
    final url = (item.fields['url'] ?? item.fields['website'])?.toString() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0C0E12),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Action Header
            Row(
              children: [
                AppIcon(_iconForType(item.type), size: 56),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            'Type: ${item.type.toUpperCase()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B1E29),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF2C3345)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const HugeIcon(
                                  icon: HugeIcons.strokeRoundedFolder01,
                                  size: 11,
                                  color: AppColors.orangeAccent,
                                  strokeWidth: 1.8,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  (item.fields['vault'] ?? 'Primary Vault').toString(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (item.isDeleted) ...[
                  if (widget.onRestore != null)
                    ElevatedButton.icon(
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedRefresh,
                        size: 16,
                        color: Colors.black,
                        strokeWidth: 1.8,
                      ),
                      label: const Text('Restore to Vault'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.mintAccent,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: widget.onRestore,
                    ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedDelete02,
                      size: 16,
                      color: AppColors.roseAccent,
                      strokeWidth: 1.8,
                    ),
                    label: const Text('Delete Permanently'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.roseAccent,
                      side: BorderSide(
                          color: AppColors.roseAccent.withOpacity(0.5)),
                    ),
                    onPressed: widget.onDelete,
                  ),
                ] else ...[
                  if (item.type == 'login') ...[
                    ElevatedButton.icon(
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedKeyboard,
                        size: 16,
                        color: Colors.white,
                        strokeWidth: 1.8,
                      ),
                      label: const Text('Auto-Type'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.orangeAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _triggerAutoType(item),
                    ),
                    const SizedBox(width: 12),
                  ],
                  ElevatedButton.icon(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedEdit02,
                      size: 16,
                      color: Colors.white,
                      strokeWidth: 1.8,
                    ),
                    label: const Text('Edit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF262C38),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: widget.onEdit,
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedShare08,
                      size: 16,
                      color: AppColors.orangeAccent,
                      strokeWidth: 1.8,
                    ),
                    label: const Text('AirShare'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F2430),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => AirShareDialog.show(
                      context,
                      item: item,
                      role: AirShareRole.send,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedDelete02,
                      size: 16,
                      color: AppColors.roseAccent,
                      strokeWidth: 1.8,
                    ),
                    label: const Text('Move to Trash'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.roseAccent,
                      side: BorderSide(
                          color: AppColors.roseAccent.withOpacity(0.5)),
                    ),
                    onPressed: widget.onDelete,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),

            // Trash Banner
            if (item.isDeleted) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.roseAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.roseAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const HugeIcon(
                      icon: HugeIcons.strokeRoundedAlert02,
                      color: AppColors.roseAccent,
                      size: 20,
                      strokeWidth: 1.8,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This item is in the Trash${item.deletedAt != null ? ' (deleted ${DateFormat.yMMMd().add_jm().format(item.deletedAt!)})' : ''}. You can restore it or permanently delete it.',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Username Field
            if (username.isNotEmpty) ...[
              _buildFieldCard(
                label: 'USERNAME / EMAIL',
                value: username,
                onCopy: () => _copy(username, 'Username'),
              ),
              const SizedBox(height: 16),
            ],

            // Password Field
            if (password.isNotEmpty) ...[
              _buildFieldCard(
                label: 'PASSWORD',
                value: _revealPassword ? password : '••••••••••••••••',
                isSecret: true,
                onToggleReveal: () =>
                    setState(() => _revealPassword = !_revealPassword),
                isRevealed: _revealPassword,
                onCopy: () => _copy(password, 'Password'),
                trailingAction: item.passwordHistory.isNotEmpty
                    ? IconButton(
                        tooltip: 'Password History (${item.passwordHistory.length})',
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedClock01,
                          color: AppColors.orangeAccent,
                          size: 20,
                          strokeWidth: 1.8,
                        ),
                        onPressed: () => _showPasswordHistoryDialog(context, item),
                      )
                    : null,
              ),
              const SizedBox(height: 16),
            ],

            // TOTP Authenticator 2FA Card
            if (_totpCode.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF161A23),
                      AppColors.mintAccent.withOpacity(0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.mintAccent.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const AppIcon(AppIcons.shieldKey, size: 40),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ONE-TIME PASSWORD (2FA / TOTP)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                              color: AppColors.mintAccent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            _totpCode,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4.0,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          '${_totpSecondsLeft}s',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.mintAccent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        IconButton(
                          tooltip: 'Copy Code',
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedCopy01,
                            size: 18,
                            color: AppColors.mintAccent,
                            strokeWidth: 1.8,
                          ),
                          onPressed: () => _copy(_totpCode, '2FA Code'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Website URL
            if (url.isNotEmpty) ...[
              _buildFieldCard(
                label: 'WEBSITE URL',
                value: url,
                onCopy: () => _copy(url, 'URL'),
              ),
              const SizedBox(height: 16),
            ],

            // Other Custom Fields
            for (final entry in item.fields.entries)
              if (entry.key != 'username' &&
                  entry.key != 'email' &&
                  entry.key != 'password' &&
                  entry.key != 'totp_secret' &&
                  entry.key != 'totpSecret' &&
                  entry.key != 'url' &&
                  entry.key != 'website' &&
                  entry.key != 'created_at') ...[
                _buildFieldCard(
                  label: entry.key.toUpperCase(),
                  value: entry.value.toString(),
                  onCopy: () => _copy(entry.value.toString(), entry.key),
                ),
                const SizedBox(height: 16),
              ],

            // Metadata footer
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF13151B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    'Last Updated: ${DateFormat.yMMMd().add_jm().format(item.updatedAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Item ID: ${item.itemId.substring(0, 8)}...',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldCard({
    required String label,
    required String value,
    bool isSecret = false,
    bool isRevealed = false,
    VoidCallback? onToggleReveal,
    required VoidCallback onCopy,
    Widget? trailingAction,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF151821),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF242835)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontFamily: isSecret && !isRevealed ? 'monospace' : null,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (trailingAction != null) trailingAction,
          if (isSecret && onToggleReveal != null)
            IconButton(
              tooltip: isRevealed ? 'Hide' : 'Reveal',
              icon: HugeIcon(
                icon: isRevealed
                    ? HugeIcons.strokeRoundedViewOffSlash
                    : HugeIcons.strokeRoundedView,
                color: Colors.white60,
                size: 20,
                strokeWidth: 1.8,
              ),
              onPressed: onToggleReveal,
            ),
          IconButton(
            tooltip: 'Copy',
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedCopy01,
              color: Colors.white70,
              size: 20,
              strokeWidth: 1.8,
            ),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 4. GENERATOR TAB SECTION
// ==========================================

class _GeneratorSection extends StatelessWidget {
  const _GeneratorSection();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E12),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF13151A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF242834)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const PasswordGeneratorDialog(isDialog: false),
          ),
        ),
      ),
    );
  }
}
