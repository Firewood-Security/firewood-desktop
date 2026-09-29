import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';

import '../providers.dart';
import '../services/bundle_service.dart';

class BundleSettingsDialog extends ConsumerStatefulWidget {
  final String bundleName;
  final List<DecryptedItem> items;
  final ValueChanged<String>? onRenamed;
  final VoidCallback? onEmptied;
  final VoidCallback? onDeleted;

  const BundleSettingsDialog({
    super.key,
    required this.bundleName,
    required this.items,
    this.onRenamed,
    this.onEmptied,
    this.onDeleted,
  });

  static Future<void> show(
    BuildContext context, {
    required String bundleName,
    required List<DecryptedItem> items,
    ValueChanged<String>? onRenamed,
    VoidCallback? onEmptied,
    VoidCallback? onDeleted,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => BundleSettingsDialog(
        bundleName: bundleName,
        items: items,
        onRenamed: onRenamed,
        onEmptied: onEmptied,
        onDeleted: onDeleted,
      ),
    );
  }

  @override
  ConsumerState<BundleSettingsDialog> createState() =>
      _BundleSettingsDialogState();
}

class _BundleSettingsDialogState extends ConsumerState<BundleSettingsDialog> {
  late String _currentName;
  late List<DecryptedItem> _currentItems;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _currentName = widget.bundleName;
    _currentItems = List.from(widget.items);
  }

  Future<void> _renameBundle() async {
    final controller = TextEditingController(text: _currentName);
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
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
              icon: HugeIcons.strokeRoundedEdit02,
              color: AppColors.orangeAccent,
              size: 20,
              strokeWidth: 1.8,
            ),
            SizedBox(width: 10),
            Text(
              'Rename Bundle',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter a new name for this credential bundle. All assigned items will be updated automatically.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Bundle Name',
                    filled: true,
                    fillColor: const Color(0xFF0F1117),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF262C3A)),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Bundle name cannot be empty';
                    }
                    if (val.trim().toLowerCase() ==
                        _currentName.toLowerCase()) {
                      return 'Enter a different name';
                    }
                    return null;
                  },
                ),
              ],
            ),
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
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('Save Name'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && mounted) {
      final key = ref.read(authProvider);
      if (key == null) return;
      setState(() => _isProcessing = true);
      try {
        await BundleService.renameBundle(_currentName, newName);

        // Update items
        for (final item in _currentItems) {
          final updated = Map<String, dynamic>.from(item.fields);
          updated['bundle'] = newName;
          await ref.read(itemServiceProvider).updateItem(
                key: key,
                itemId: item.itemId,
                newFields: updated,
              );
        }

        if (mounted) {
          setState(() {
            _currentName = newName;
            _isProcessing = false;
          });
          widget.onRenamed?.call(newName);
        }
      } catch (e) {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _emptyBundle() async {
    final count = _currentItems.length;
    final confirmed = await showDialog<bool>(
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
              icon: HugeIcons.strokeRoundedFolderMinus,
              color: AppColors.orangeAccent,
              size: 20,
              strokeWidth: 1.8,
            ),
            SizedBox(width: 10),
            Text(
              'Empty Bundle',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Text(
            'Are you sure you want to unassign all $count credentials from "$_currentName"?\n\n'
            'The credentials will remain safe in your vault. Their bundle tag will be removed so this bundle becomes empty and eligible for deletion.',
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orangeAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Empty Bundle'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final key = ref.read(authProvider);
      if (key == null) return;
      setState(() => _isProcessing = true);
      try {
        for (final item in _currentItems) {
          final updated = Map<String, dynamic>.from(item.fields);
          updated['bundle'] = '';
          await ref.read(itemServiceProvider).updateItem(
                key: key,
                itemId: item.itemId,
                newFields: updated,
              );
        }

        if (mounted) {
          setState(() {
            _currentItems.clear();
            _isProcessing = false;
          });
          widget.onEmptied?.call();
        }
      } catch (e) {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _deleteBundle() async {
    // ENFORCE RULE: Bundle MUST be empty to delete
    if (_currentItems.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161922),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.roseAccent),
          ),
          title: const Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedAlert02,
                color: AppColors.roseAccent,
                size: 20,
                strokeWidth: 1.8,
              ),
              SizedBox(width: 10),
              Text(
                'Deletion Blocked',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Text(
              'Rule Violation: A bundle must be completely empty before it can be deleted.\n\n'
              'Bundle "$_currentName" currently contains ${_currentItems.length} credential(s).\n\n'
              'Please click "Empty Bundle" to unassign them, or remove them manually first.',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    // Bundle is empty, proceed with deletion confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.roseAccent),
        ),
        title: const Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedDelete02,
              color: AppColors.roseAccent,
              size: 20,
              strokeWidth: 1.8,
            ),
            SizedBox(width: 10),
            Text(
              'Delete Bundle',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Text(
            'Are you sure you want to permanently delete the empty bundle "$_currentName"?\n\n'
            'This action cannot be undone.',
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.roseAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isProcessing = true);
      try {
        await BundleService.deleteBundle(_currentName);
        if (mounted) {
          Navigator.pop(context); // Close dialog
          widget.onDeleted?.call();
        }
      } catch (e) {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _currentItems.isEmpty;

    return Dialog(
      backgroundColor: const Color(0xFF141720),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFF2A3040)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: title + subtitle (no leading icon).
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'BUNDLE SETTINGS • ZERO-KNOWLEDGE ENCRYPTED',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close,
                        color: Colors.white60, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Status Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isEmpty
                      ? AppColors.mintAccent.withOpacity(0.08)
                      : const Color(0xFF1E1A17),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isEmpty
                        ? AppColors.mintAccent.withOpacity(0.3)
                        : AppColors.orangeAccent.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        HugeIcon(
                          icon: isEmpty
                              ? HugeIcons.strokeRoundedCheckmarkCircle02
                              : HugeIcons.strokeRoundedInformationCircle,
                          size: 16,
                          color: isEmpty
                              ? AppColors.mintAccent
                              : AppColors.orangeAccent,
                          strokeWidth: 1.8,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isEmpty
                              ? 'STATUS: EMPTY BUNDLE (0 ITEMS)'
                              : 'STATUS: ACTIVE (${_currentItems.length} ITEMS)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: isEmpty
                                ? AppColors.mintAccent
                                : AppColors.orangeAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isEmpty
                          ? 'This bundle is currently empty. It meets the deletion rule and can be safely deleted.'
                          : 'Security Rule: A bundle must be empty (0 items) before it can be deleted. Use "Empty Bundle" below to unassign all credentials without deleting them.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              if (_isProcessing)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(
                        color: AppColors.orangeAccent),
                  ),
                )
              else ...[
                // Option 1: Rename Bundle
                _DesktopActionTile(
                  icon: HugeIcons.strokeRoundedEdit02,
                  iconColor: AppColors.orangeAccent,
                  title: 'Rename Bundle',
                  subtitle:
                      'Change bundle name across all assigned credentials',
                  onTap: _renameBundle,
                ),
                const SizedBox(height: 10),

                // Option 2: Empty Bundle
                if (!isEmpty) ...[
                  _DesktopActionTile(
                    icon: HugeIcons.strokeRoundedFolderMinus,
                    iconColor: AppColors.orangeAccent,
                    title: 'Empty Bundle',
                    subtitle:
                        'Unassign ${_currentItems.length} items (credentials stay safe in vault)',
                    onTap: _emptyBundle,
                  ),
                  const SizedBox(height: 10),
                ],

                // Option 3: Delete Bundle
                _DesktopActionTile(
                  icon: isEmpty
                      ? HugeIcons.strokeRoundedDelete02
                      : HugeIcons.strokeRoundedLockKey,
                  iconColor: isEmpty ? AppColors.roseAccent : Colors.white38,
                  title: 'Delete Bundle',
                  subtitle: isEmpty
                      ? 'Permanently delete this empty bundle'
                      : 'Locked: Must be empty before deletion (Contains ${_currentItems.length} items)',
                  isDestructive: isEmpty,
                  onTap: _deleteBundle,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopActionTile extends StatelessWidget {
  final dynamic icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  const _DesktopActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDestructive
              ? AppColors.roseAccent.withOpacity(0.3)
              : const Color(0xFF282E3E),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: icon,
                      size: 18,
                      color: iconColor,
                      strokeWidth: 1.8,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isDestructive
                              ? AppColors.roseAccent
                              : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: isDestructive ? AppColors.roseAccent : Colors.white38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
