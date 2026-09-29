// Ctrl/Cmd+K command palette: navigate, search credentials, lock, and jump to items.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';

import '../providers.dart';
import '../services/secure_clipboard.dart';

class DesktopCommandPalette extends ConsumerStatefulWidget {
  const DesktopCommandPalette({super.key});

  @override
  ConsumerState<DesktopCommandPalette> createState() =>
      _DesktopCommandPaletteState();
}

class _DesktopCommandPaletteState extends ConsumerState<DesktopCommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  List<DecryptedItem> _items = [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _index = 0));
    _focusNode.onKeyEvent = _onKey;
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = ref.read(authProvider);
    if (key == null) return;
    try {
      final items = await ref.read(itemServiceProvider).getAllItems(key);
      if (mounted) {
        setState(() {
          _items = items;
          _index = 0;
        });
      }
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

  dynamic _iconForType(String type) {
    switch (ItemTypeExt.fromString(type)) {
      case ItemType.login:
        return HugeIcons.strokeRoundedSquareLock02;
      case ItemType.card:
        return HugeIcons.strokeRoundedCreditCard;
      case ItemType.identity:
        return HugeIcons.strokeRoundedUser;
      case ItemType.note:
        return HugeIcons.strokeRoundedNote01;
      case ItemType.developerSecret:
        return HugeIcons.strokeRoundedKey01;
    }
  }

  List<_Entry> _entries() {
    final entries = <_Entry>[
      _Entry(
        label: 'Vault Credentials',
        subtitle: 'View and manage all encrypted records',
        badge: 'VIEW',
        icon: HugeIcons.strokeRoundedShield01,
        keywords: const ['items', 'passwords', 'vault', 'credentials'],
        action: () => ref.read(desktopTabProvider.notifier).state = 1,
      ),
      _Entry(
        label: 'Password Generator',
        subtitle: 'Create strong random passwords & tokens',
        badge: 'TOOL',
        icon: HugeIcons.strokeRoundedMagicWand01,
        keywords: const ['generator', 'password', 'token', 'random'],
        action: () => ref.read(desktopTabProvider.notifier).state = 2,
      ),
      _Entry(
        label: 'Dashboard & Security',
        subtitle: 'Analytics and Mini ML Advisor',
        badge: 'VIEW',
        icon: HugeIcons.strokeRoundedLayoutDashboard,
        keywords: const ['home', 'dashboard', 'security', 'score', 'advisor'],
        action: () => ref.read(desktopTabProvider.notifier).state = 0,
      ),
      _Entry(
        label: 'Settings & Backups',
        subtitle: 'Master password, auto-lock, imports & exports',
        badge: 'SYSTEM',
        icon: HugeIcons.strokeRoundedSettings01,
        keywords: const [
          'settings',
          'preferences',
          'backup',
          'import',
          'export',
          'password'
        ],
        action: () => ref.read(desktopTabProvider.notifier).state = 3,
      ),
      _Entry(
        label: 'Bluetooth Sharing',
        subtitle: 'Air-drop credentials to nearby devices',
        badge: 'SHARE',
        icon: HugeIcons.strokeRoundedBluetooth,
        keywords: const ['bluetooth', 'share', 'send', 'receive'],
        action: () => ref.read(desktopTabProvider.notifier).state = 4,
      ),
      _Entry(
        label: 'Lock Vault',
        subtitle: 'Immediately wipe decryption key from memory',
        badge: 'SECURITY',
        icon: HugeIcons.strokeRoundedPower,
        keywords: const ['lock', 'logout', 'exit'],
        action: () => ref.read(authProvider.notifier).state = null,
      ),
    ];

    for (final item in _items) {
      final user = item.fields['username'] ??
          item.fields['email'] ??
          item.fields['cardholder'] ??
          '';
      final url = item.fields['url'] ?? item.fields['website'] ?? '';
      final sub = [
        if (user.toString().isNotEmpty) user.toString(),
        if (url.toString().isNotEmpty) url.toString(),
      ].join(' · ');

      entries.add(_Entry(
        label: item.title,
        subtitle: sub.isNotEmpty ? sub : null,
        badge: item.type.toUpperCase(),
        icon: _iconForType(item.type),
        item: item,
        keywords: [
          item.type,
          if (user.toString().isNotEmpty) user.toString(),
          if (url.toString().isNotEmpty) url.toString(),
          ...item.fields.values.map((v) => v.toString()),
        ],
        action: () {
          ref.read(desktopTabProvider.notifier).state = 1;
          ref.read(selectedItemIdProvider.notifier).state = item.itemId;
        },
      ));
    }

    return entries;
  }

  List<_Entry> get _filtered {
    final q = _controller.text.trim().toLowerCase();
    final all = _entries();
    if (q.isEmpty) return all;
    return all
        .where((e) =>
            e.label.toLowerCase().contains(q) ||
            (e.subtitle != null && e.subtitle!.toLowerCase().contains(q)) ||
            e.keywords.any((k) => k.toLowerCase().contains(q)))
        .toList();
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    const itemHeight = 64.0;
    final targetOffset = index * itemHeight;
    final currentOffset = _scrollController.offset;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final viewportHeight = _scrollController.position.viewportDimension;
    if (targetOffset < currentOffset) {
      _scrollController.jumpTo(targetOffset.clamp(0.0, maxOffset));
    } else if (targetOffset + itemHeight > currentOffset + viewportHeight) {
      _scrollController.jumpTo(
          (targetOffset + itemHeight - viewportHeight).clamp(0.0, maxOffset));
    }
  }

  String _dossierUser(DecryptedItem item) {
    return (item.fields['username'] ??
            item.fields['email'] ??
            item.fields['cardholder'] ??
            item.fields['key_name'] ??
            '')
        .toString();
  }

  bool _hasTotp(DecryptedItem item) {
    return ((item.fields['totp_secret'] ?? item.fields['totpSecret'] ?? '')
            .toString()
            .trim()
            .isNotEmpty);
  }

  String _bundleName(DecryptedItem item) {
    return (item.fields['bundle'] ?? '').toString().trim();
  }

  String _dossierContentLine(DecryptedItem item) {
    final type = ItemTypeExt.fromString(item.type);
    final user = _dossierUser(item);
    switch (type) {
      case ItemType.card:
        return user.isNotEmpty
            ? 'Card: $user · CVV: ••••'
            : 'CVV: ••••';
      case ItemType.identity:
        return user.isNotEmpty ? 'ID: $user' : 'ID record';
      case ItemType.note:
        return user.isNotEmpty ? 'Note: $user' : 'Secure note';
      case ItemType.developerSecret:
        return user.isNotEmpty
            ? 'Key: $user · Secret: ••••'
            : 'Secret: ••••';
      case ItemType.login:
        return user.isNotEmpty ? 'User: $user · Pass: ••••' : 'Pass: ••••';
    }
  }

  Widget _buildTypeBadge(DecryptedItem item) {
    final color = _badgeColor(item.type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: _iconForType(item.type),
            size: 10,
            color: color,
            strokeWidth: 2,
          ),
          const SizedBox(width: 4),
          Text(
            item.type.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildDossierRow(_Entry entry, bool isSel) {
    final item = entry.item!;
    final bundle = _bundleName(item);
    final hasTotp = _hasTotp(item);
    final badgeColor = _badgeColor(item.type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title row: type-badge pill + bold title + 2FA/bundle mini-badges.
        Row(
          children: [
            _buildTypeBadge(item),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight:
                      isSel ? FontWeight.bold : FontWeight.w700,
                ),
              ),
            ),
            if (bundle.isNotEmpty) ...[
              const SizedBox(width: 6),
              _buildMiniBadge(bundle, Colors.white54),
            ],
            if (hasTotp) ...[
              const SizedBox(width: 6),
              _buildMiniBadge('2FA', badgeColor),
            ],
            if ((entry.item!.fields['password']?.isNotEmpty ?? false)) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Copy password to clipboard',
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    final pw = entry.item!.fields['password']!;
                    SecureClipboard.copy(
                      context: context,
                      text: pw,
                      label: '${entry.item!.title} password',
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2432),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF2E3649)),
                    ),
                    child: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCopy01,
                      size: 14,
                      color: Colors.white70,
                      strokeWidth: 1.8,
                    ),
                  ),
                ),
              ),
            ],
            if (isSel) ...[
              const SizedBox(width: 8),
              const HugeIcon(
                icon: HugeIcons.strokeRoundedArrowRight01,
                size: 16,
                color: AppColors.orangeAccent,
                strokeWidth: 2,
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        // One-line labeled content beneath.
        Text(
          _dossierContentLine(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
  Color _badgeColor(String? badge) {
    if (badge == null) return Colors.white54;
    switch (badge.toUpperCase()) {
      case 'LOGIN':
        return AppColors.mintAccent;
      case 'CARD':
        return AppColors.periwinkleAccent;
      case 'NOTE':
        return const Color(0xFFFBBF24); // Amber
      case 'IDENTITY':
        return const Color(0xFF38BDF8); // Sky
      case 'DEVELOPERSECRET':
        return const Color(0xFFA855F7); // Purple
      case 'SECURITY':
        return AppColors.roseAccent;
      case 'TOOL':
        return AppColors.orangeAccent;
      case 'SHARE':
        return AppColors.orangeBright;
      case 'VIEW':
      case 'SYSTEM':
      default:
        return Colors.white70;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final filtered = _filtered;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _index =
            (_index + 1).clamp(0, filtered.isEmpty ? 0 : filtered.length - 1);
      });
      _scrollToIndex(_index);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _index =
            (_index - 1).clamp(0, filtered.isEmpty ? 0 : filtered.length - 1);
      });
      _scrollToIndex(_index);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter) {
      if (filtered.isNotEmpty) {
        _run(filtered[_index.clamp(0, filtered.length - 1)].action);
      }
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
    final isOpen = ref.watch(commandPaletteOpenProvider);
    ref.listen(commandPaletteOpenProvider, (prev, now) {
      if (now == true) {
        _load();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }
    });

    if (!isOpen) return const SizedBox.shrink();
    final filtered = _filtered;
    final selected =
        filtered.isEmpty ? -1 : _index.clamp(0, filtered.length - 1);

    return Positioned.fill(
      child: Stack(
        children: [
          // Backdrop
          GestureDetector(
            onTap: _close,
            child: Container(color: Colors.black.withOpacity(0.65)),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Container(
                width: 580,
                constraints: const BoxConstraints(maxHeight: 500),
                decoration: BoxDecoration(
                  color: const Color(0xFF13151D),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: const Color(0xFF262C3A), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search Bar Header
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      child: Row(
                        children: [
                          const HugeIcon(
                            icon: HugeIcons.strokeRoundedSearch01,
                            size: 20,
                            color: AppColors.orangeAccent,
                            strokeWidth: 1.8,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              autofocus: true,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                hintText:
                                    'Search credentials, commands, or settings...',
                                hintStyle: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 15,
                                ),
                              ),
                              onSubmitted: (_) {
                                if (filtered.isNotEmpty) {
                                  _run(filtered[
                                          _index.clamp(0, filtered.length - 1)]
                                      .action);
                                }
                              },
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F2430),
                              borderRadius: BorderRadius.circular(4),
                              border:
                                  Border.all(color: const Color(0xFF2C3345)),
                            ),
                            child: const Text(
                              'ESC',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFF222633)),

                    // Results List
                    Flexible(
                      child: filtered.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  HugeIcon(
                                    icon: HugeIcons.strokeRoundedSearch01,
                                    size: 32,
                                    color: Colors.white24,
                                    strokeWidth: 1.5,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'No matching credentials or commands',
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final entry = filtered[i];
                                final isSel = i == selected;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => _run(entry.action),
                                  child: Container(
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? AppColors.orangeAccent
                                              .withOpacity(0.12)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSel
                                            ? AppColors.orangeAccent
                                                .withOpacity(0.35)
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: entry.item != null
                                        ? _buildDossierRow(entry, isSel)
                                        : Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isSel
                                                ? AppColors.orangeAccent
                                                    .withOpacity(0.2)
                                                : const Color(0xFF1A1E29),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: HugeIcon(
                                            icon: entry.icon,
                                            size: 18,
                                            color: isSel
                                                ? AppColors.orangeAccent
                                                : Colors.white70,
                                            strokeWidth: 1.8,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry.label,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: isSel
                                                      ? FontWeight.bold
                                                      : FontWeight.w600,
                                                ),
                                              ),
                                              if (entry.subtitle != null) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  entry.subtitle!,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withOpacity(0.45),
                                                    fontSize: 12,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (entry.badge != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2.5),
                                            decoration: BoxDecoration(
                                              color: _badgeColor(entry.badge)
                                                  .withOpacity(0.14),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                color: _badgeColor(entry.badge)
                                                    .withOpacity(0.35),
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Text(
                                              entry.badge!,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: _badgeColor(entry.badge),
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ),
                                        if (entry.item != null &&
                                            (entry.item!.fields['password']
                                                    ?.isNotEmpty ??
                                                false)) ...[
                                          const SizedBox(width: 8),
                                          Tooltip(
                                            message:
                                                'Copy password to clipboard',
                                            child: InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              onTap: () {
                                                final pw = entry
                                                    .item!.fields['password']!;
                                                SecureClipboard.copy(
                                                  context: context,
                                                  text: pw,
                                                  label:
                                                      '${entry.item!.title} password',
                                                );
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(5),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFF1F2432),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                      color: const Color(
                                                          0xFF2E3649)),
                                                ),
                                                child: const HugeIcon(
                                                  icon: HugeIcons
                                                      .strokeRoundedCopy01,
                                                  size: 14,
                                                  color: Colors.white70,
                                                  strokeWidth: 1.8,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (isSel) ...[
                                          const SizedBox(width: 8),
                                          const HugeIcon(
                                            icon: HugeIcons
                                                .strokeRoundedArrowRight01,
                                            size: 16,
                                            color: AppColors.orangeAccent,
                                            strokeWidth: 2,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),

                    // Footer Keyboard Shortcuts Hint
                    const Divider(height: 1, color: Color(0xFF222633)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      child: Row(
                        children: [
                          _buildHintKey('↑↓', 'Navigate'),
                          const SizedBox(width: 14),
                          _buildHintKey('↵', 'Select'),
                          const SizedBox(width: 14),
                          _buildHintKey('ESC', 'Close'),
                          const Spacer(),
                          Text(
                            '${filtered.length} match${filtered.length == 1 ? '' : 'es'}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHintKey(String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF1C202B),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFF2B3244)),
          ),
          child: Text(
            key,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.4),
          ),
        ),
      ],
    );
  }
}

class _Entry {
  final String label;
  final String? subtitle;
  final String? badge;
  final dynamic icon;
  final DecryptedItem? item;
  final List<String> keywords;
  final VoidCallback action;

  _Entry({
    required this.label,
    this.subtitle,
    this.badge,
    required this.icon,
    this.item,
    required this.keywords,
    required this.action,
  });
}
