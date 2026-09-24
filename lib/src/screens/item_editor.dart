// Add/edit dialog for vault items: title + kind + dynamic key/value fields.
// The caller encrypts and persists the returned draft via firewood_core.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_ui_desktop/firewood_ui_desktop.dart';

class ItemDraft {
  final String title;
  final String type;
  final Map<String, dynamic> fields;

  const ItemDraft({required this.title, required this.type, required this.fields});
}

class ItemEditorDialog extends StatefulWidget {
  final DecryptedItem? initial;

  const ItemEditorDialog({super.key, this.initial});

  @override
  State<ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<ItemEditorDialog> {
  late final TextEditingController _title;
  late ItemType _type;
  final List<_FieldRow> _rows = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _type = initial == null ? ItemType.login : ItemTypeExt.fromString(initial.type);

    if (initial != null) {
      initial.fields.forEach((k, v) {
        if (k == 'created_at') return;
        _rows.add(_FieldRow(k, v.toString()));
      });
    } else {
      _rows.addAll([_FieldRow('username', ''), _FieldRow('password', '')]);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    final fields = <String, dynamic>{};
    for (final row in _rows) {
      final key = row.key.text.trim();
      final value = row.value.text;
      if (key.isNotEmpty && value.isNotEmpty) fields[key] = value;
    }
    Navigator.of(context).pop(
      ItemDraft(title: _title.text.trim(), type: _type.label, fields: fields),
    );
  }

  List<List<dynamic>> _typeIcon(ItemType t) {
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

  bool _isSecret(String key) {
    final k = key.toLowerCase();
    return k.contains('password') ||
        k.contains('secret') ||
        k.contains('cvv') ||
        k.contains('pin') ||
        k.contains('token') ||
        k.contains('private');
  }

  /// Value input; secret fields are masked and get inline view / copy /
  /// generate controls.
  Widget _buildValueField(int i) {
    final row = _rows[i];
    final secret = _isSecret(row.key.text);

    return TextField(
      controller: row.value,
      obscureText: secret && row.obscure,
      decoration: InputDecoration(
        labelText: 'Value',
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: secret
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SuffixIcon(
                    icon: row.obscure
                        ? HugeIcons.strokeRoundedView
                        : HugeIcons.strokeRoundedViewOff,
                    tooltip: row.obscure ? 'Show' : 'Hide',
                    onTap: () => setState(() => row.obscure = !row.obscure),
                  ),
                  _SuffixIcon(
                    icon: HugeIcons.strokeRoundedCopy01,
                    tooltip: AppStrings.copy,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: row.value.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(AppStrings.copied)),
                      );
                    },
                  ),
                  _SuffixIcon(
                    icon: HugeIcons.strokeRoundedMagicWand01,
                    tooltip: 'Generate password',
                    onTap: () => setState(() {
                      row.value.text = GeneratorService.generatePassword(length: 20);
                      row.obscure = false;
                    }),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceZinc,
      title: Text(widget.initial == null ? AppStrings.newItem : AppStrings.edit,
          style: const TextStyle(color: AppColors.offWhite, fontSize: 16)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text('Type',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(height: AppSpacing.sm),
              HearthDropdown<ItemType>(
                value: _type,
                width: double.infinity,
                items: [
                  for (final t in ItemType.values)
                    HearthDropdownItem(value: t, label: t.label, icon: _typeIcon(t)),
                ],
                onChanged: (v) => setState(() => _type = v),
              ),
              const SizedBox(height: AppSpacing.md),
              for (var i = 0; i < _rows.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _rows[i].key,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'Field'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 3,
                        child: _buildValueField(i),
                      ),
                      IconButton(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedDelete02,
                          size: 18,
                          color: AppColors.textMuted,
                          strokeWidth: 1.8,
                        ),
                        onPressed: () => setState(() => _rows.removeAt(i).dispose()),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _rows.add(_FieldRow('', ''))),
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedAdd01,
                    size: 16,
                    color: AppColors.emberBright,
                    strokeWidth: 1.8,
                  ),
                  label: const Text('Add field'),
                ),
              ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: AppColors.roseAccent, fontSize: 12)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
        FirewoodButton(
          label: AppStrings.save,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _FieldRow {
  final TextEditingController key;
  final TextEditingController value;
  bool obscure = true;
  _FieldRow(String k, String v)
      : key = TextEditingController(text: k),
        value = TextEditingController(text: v);

  void dispose() {
    key.dispose();
    value.dispose();
  }
}

/// Compact hover-aware icon button used inside input suffixes.
class _SuffixIcon extends StatefulWidget {
  final List<List<dynamic>> icon;
  final String tooltip;
  final VoidCallback onTap;

  const _SuffixIcon({required this.icon, required this.tooltip, required this.onTap});

  @override
  State<_SuffixIcon> createState() => _SuffixIconState();
}

class _SuffixIconState extends State<_SuffixIcon> {
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
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? AppColors.hearthRaised : Colors.transparent,
              borderRadius: AppRadii.smAll,
            ),
            child: HugeIcon(
              icon: widget.icon,
              size: 16,
              color: _hover ? AppColors.emberBright : AppColors.textMuted,
              strokeWidth: 1.8,
            ),
          ),
        ),
      ),
    );
  }
}
