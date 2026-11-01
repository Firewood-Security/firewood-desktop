// Multi-form category-tailored credential editor for Firewood Desktop
// Supports Login, Card, Identity, Secure Note, and Developer Secret with dedicated form fields.

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';

import '../theme/app_icons.dart';
import '../services/bundle_service.dart';
import '../widgets/generator_dialog.dart';

class ItemDraft {
  final String title;
  final String type;
  final Map<String, dynamic> fields;

  const ItemDraft({
    required this.title,
    required this.type,
    required this.fields,
  });
}

class ItemEditorDialog extends StatefulWidget {
  final DecryptedItem? initial;
  final String? initialBundle;

  const ItemEditorDialog({super.key, this.initial, this.initialBundle});

  @override
  State<ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<ItemEditorDialog> {
  late final TextEditingController _title;
  late ItemType _selectedType;

  // Category specific controllers
  final _vaultController = TextEditingController();
  final _bundleController = TextEditingController();

  // Login
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();
  final _totpController = TextEditingController();

  // Card
  final _cardholderController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _pinController = TextEditingController();
  final _zipController = TextEditingController();

  // Identity
  final _fullNameController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _passportController = TextEditingController();
  final _licenseController = TextEditingController();
  final _dobController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  // Note
  final _noteController = TextEditingController();

  // Developer Secret
  final _secretKeyController = TextEditingController();
  final _publicKeyController = TextEditingController();
  final _configController = TextEditingController();

  // Custom Extra Fields
  final List<_CustomFieldRow> _customRows = [];

  bool _obscurePassword = true;
  bool _obscureCvv = true;
  bool _obscurePin = true;
  bool _obscureSecretKey = true;
  String? _error;
  List<String> _knownBundles = [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _vaultController.text =
        (initial?.fields['vault'] ?? 'Primary Vault').toString();
    _bundleController.text =
        (initial?.fields['bundle'] ?? widget.initialBundle ?? '').toString();
    _selectedType =
        initial == null ? ItemType.login : ItemTypeExt.fromString(initial.type);
    _loadKnownBundles();

    if (initial != null) {
      final f = initial.fields;
      // Login
      _usernameController.text = (f['username'] ?? f['email'] ?? '').toString();
      _passwordController.text = (f['password'] ?? '').toString();
      _urlController.text = (f['url'] ?? f['website'] ?? '').toString();
      _totpController.text =
          (f['totp_secret'] ?? f['totpSecret'] ?? '').toString();

      // Card
      _cardholderController.text = (f['cardholder'] ?? '').toString();
      _cardNumberController.text =
          (f['card_number'] ?? f['number'] ?? '').toString();
      _expiryController.text = (f['expiry'] ?? '').toString();
      _cvvController.text = (f['cvv'] ?? '').toString();
      _pinController.text = (f['pin'] ?? '').toString();
      _zipController.text = (f['zip'] ?? '').toString();

      // Identity
      _fullNameController.text = (f['full_name'] ?? '').toString();
      _idNumberController.text = (f['id_number'] ?? '').toString();
      _passportController.text = (f['passport'] ?? '').toString();
      _licenseController.text = (f['license'] ?? '').toString();
      _dobController.text = (f['dob'] ?? '').toString();
      _addressController.text = (f['address'] ?? '').toString();
      _phoneController.text = (f['phone'] ?? '').toString();

      // Note
      _noteController.text =
          (f['content'] ?? f['notes'] ?? f['note'] ?? f['body'] ?? '')
              .toString();

      // Developer Secret
      _secretKeyController.text =
          (f['secret_key'] ?? f['token'] ?? '').toString();
      _publicKeyController.text = (f['public_key'] ?? '').toString();
      _configController.text =
          (f['config_data'] ?? f['config'] ?? '').toString();

      // Load remaining custom fields
      const standardKeys = {
        'bundle',
        'vault',
        'username',
        'email',
        'password',
        'url',
        'website',
        'totp_secret',
        'totpSecret',
        'cardholder',
        'card_number',
        'number',
        'expiry',
        'cvv',
        'pin',
        'zip',
        'full_name',
        'id_number',
        'passport',
        'license',
        'dob',
        'address',
        'phone',
        'note',
        'notes',
        'content',
        'body',
        'secret_key',
        'token',
        'public_key',
        'config',
        'config_data',
        'created_at',
      };
      f.forEach((k, v) {
        if (!standardKeys.contains(k)) {
          _customRows.add(_CustomFieldRow(k, v.toString()));
        }
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _vaultController.dispose();
    _bundleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _totpController.dispose();
    _cardholderController.dispose();
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _pinController.dispose();
    _zipController.dispose();
    _fullNameController.dispose();
    _idNumberController.dispose();
    _passportController.dispose();
    _licenseController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    _secretKeyController.dispose();
    _publicKeyController.dispose();
    _configController.dispose();
    for (final r in _customRows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadKnownBundles() async {
    try {
      final registered = await BundleService.getRegisteredBundles();
      final set = <String>{};
      for (final b in registered) {
        final clean = b.trim();
        if (clean.isNotEmpty) set.add(clean);
      }
      final current = _bundleController.text.trim();
      if (current.isNotEmpty) set.add(current);
      if (!mounted) return;
      setState(() {
        _knownBundles = set.toList()..sort();
      });
    } catch (_) {}
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }

    final fields = <String, dynamic>{};

    switch (_selectedType) {
      case ItemType.login:
        if (_usernameController.text.isNotEmpty) {
          fields['username'] = _usernameController.text.trim();
        }
        if (_passwordController.text.isNotEmpty) {
          fields['password'] = _passwordController.text;
        }
        if (_urlController.text.isNotEmpty) {
          fields['url'] = _urlController.text.trim();
        }
        if (_totpController.text.isNotEmpty) {
          fields['totp_secret'] = _totpController.text.trim();
        }
        break;

      case ItemType.card:
        if (_cardholderController.text.isNotEmpty) {
          fields['cardholder'] = _cardholderController.text.trim();
        }
        if (_cardNumberController.text.isNotEmpty) {
          fields['card_number'] = _cardNumberController.text.trim();
          fields['number'] = _cardNumberController.text.trim();
        }
        if (_expiryController.text.isNotEmpty) {
          fields['expiry'] = _expiryController.text.trim();
        }
        if (_cvvController.text.isNotEmpty) {
          fields['cvv'] = _cvvController.text.trim();
        }
        if (_pinController.text.isNotEmpty) {
          fields['pin'] = _pinController.text.trim();
        }
        if (_zipController.text.isNotEmpty) {
          fields['zip'] = _zipController.text.trim();
        }
        break;

      case ItemType.identity:
        if (_fullNameController.text.isNotEmpty) {
          fields['full_name'] = _fullNameController.text.trim();
        }
        if (_idNumberController.text.isNotEmpty) {
          fields['id_number'] = _idNumberController.text.trim();
        }
        if (_passportController.text.isNotEmpty) {
          fields['passport'] = _passportController.text.trim();
        }
        if (_licenseController.text.isNotEmpty) {
          fields['license'] = _licenseController.text.trim();
        }
        if (_dobController.text.isNotEmpty) {
          fields['dob'] = _dobController.text.trim();
        }
        if (_addressController.text.isNotEmpty) {
          fields['address'] = _addressController.text.trim();
        }
        if (_phoneController.text.isNotEmpty) {
          fields['phone'] = _phoneController.text.trim();
        }
        break;

      case ItemType.note:
        if (_noteController.text.isNotEmpty) {
          fields['content'] = _noteController.text;
          fields['notes'] = _noteController.text;
          fields['note'] = _noteController.text;
        }
        break;

      case ItemType.developerSecret:
        if (_secretKeyController.text.isNotEmpty) {
          fields['secret_key'] = _secretKeyController.text;
        }
        if (_publicKeyController.text.isNotEmpty) {
          fields['public_key'] = _publicKeyController.text.trim();
        }
        if (_configController.text.isNotEmpty) {
          fields['config_data'] = _configController.text;
          fields['config'] = _configController.text;
        }
        break;
    }

    // Add custom key/values
    for (final row in _customRows) {
      final k = row.key.text.trim();
      final v = row.value.text;
      if (k.isNotEmpty && v.isNotEmpty) {
        fields[k] = v;
      }
    }

    final vaultVal = _vaultController.text.trim();
    fields['vault'] = vaultVal.isEmpty ? 'Primary Vault' : vaultVal;

    final bundleVal = _bundleController.text.trim();
    if (bundleVal.isNotEmpty) {
      fields['bundle'] = bundleVal;
    }

    Navigator.of(context).pop(
      ItemDraft(
        title: _title.text.trim(),
        type: _selectedType.name,
        fields: fields,
      ),
    );
  }

  String _iconPathForType(ItemType type) {
    switch (type) {
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
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 680,
        height: 720,
        decoration: BoxDecoration(
          color: const Color(0xFF111318),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF262A34), width: 1),
        ),
        child: Column(
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF222631))),
              ),
              child: Row(
                children: [
                  AppIcon(_iconPathForType(_selectedType), size: 48),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.initial == null
                              ? 'NEW CREDENTIAL'
                              : 'EDIT CREDENTIAL',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Category: ${_selectedType.label.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      color: Colors.white60,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Category Segmented Tabs
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: const Color(0xFF141720),
              child: Row(
                children: ItemType.values.map((type) {
                  final selected = type == _selectedType;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () => setState(() => _selectedType = type),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.orangeAccent.withOpacity(0.18)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? AppColors.orangeAccent
                                  : const Color(0xFF242835),
                            ),
                          ),
                          child: Column(
                            children: [
                              AppIcon(_iconPathForType(type), size: 28),
                              const SizedBox(height: 4),
                              Text(
                                type.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color:
                                      selected ? Colors.white : Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Form Fields Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Item Title
                    _buildInputField(
                      controller: _title,
                      label: 'Title',
                      hint: 'e.g. GitHub, Netflix, Work AWS',
                      prefixIcon: AppInputIcons.title,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),

                    // Vault Assignment
                    _buildInputField(
                      controller: _vaultController,
                      label: 'Vault',
                      hint: 'Primary Vault, Work, Personal...',
                      prefixIcon: HugeIcons.strokeRoundedFolder01,
                    ),
                    const SizedBox(height: 16),

                    // Bundle (Heterogeneous Group) Assignment
                    _buildInputField(
                      controller: _bundleController,
                      label: 'Bundle (Group)',
                      hint: 'e.g. Housework, Mom, Personal, Work',
                      prefixIcon: HugeIcons.strokeRoundedFolder01,
                      suffixButtons: [
                        if (_knownBundles.isNotEmpty)
                          PopupMenuButton<String>(
                            tooltip: 'Choose bundle',
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowDown01,
                              color: Colors.white60,
                              size: 18,
                            ),
                            color: const Color(0xFF1A1D26),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0xFF272C3A)),
                            ),
                            onSelected: (val) {
                              setState(() => _bundleController.text = val);
                            },
                            itemBuilder: (ctx) => [
                              if (_bundleController.text.trim().isNotEmpty)
                                const PopupMenuItem<String>(
                                  value: '',
                                  height: 40,
                                  child: Text(
                                    'No bundle',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ),
                              ..._knownBundles.map(
                                (b) => PopupMenuItem<String>(
                                  value: b,
                                  height: 40,
                                  child: Row(
                                    children: [
                                      HugeIcon(
                                        icon: HugeIcons.strokeRoundedFolder01,
                                        size: 14,
                                        color: _bundleController.text
                                                    .trim()
                                                    .toLowerCase() ==
                                                b.toLowerCase()
                                            ? AppColors.orangeAccent
                                            : Colors.white38,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          b,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: _bundleController.text
                                                        .trim()
                                                        .toLowerCase() ==
                                                    b.toLowerCase()
                                                ? AppColors.orangeAccent
                                                : Colors.white,
                                            fontWeight: _bundleController.text
                                                        .trim()
                                                        .toLowerCase() ==
                                                    b.toLowerCase()
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Dedicated Category Form
                    _buildCategoryForm(),

                    const SizedBox(height: 24),

                    // Custom Extra Fields Section
                    Row(
                      children: [
                        const Text(
                          'CUSTOM FIELDS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: Colors.white54,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedPlusSign,
                            color: AppColors.orangeAccent,
                            size: 16,
                          ),
                          label: const Text(
                            'Add Field',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.orangeAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _customRows.add(_CustomFieldRow('', ''));
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    for (int i = 0; i < _customRows.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildInputField(
                                controller: _customRows[i].key,
                                label: 'Field Name',
                                prefixIcon: AppInputIcons.hash,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: _buildInputField(
                                controller: _customRows[i].value,
                                label: 'Value',
                                prefixIcon: AppInputIcons.file,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove field',
                              icon: const HugeIcon(
                                icon: HugeIcons.strokeRoundedDelete02,
                                color: AppColors.roseAccent,
                                size: 18,
                              ),
                              onPressed: () {
                                setState(() {
                                  _customRows.removeAt(i);
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.roseAccent,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Modal Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF222631))),
              ),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      color: Colors.white70,
                      size: 16,
                    ),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF2F3544)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedTick01,
                      color: Colors.black,
                      size: 18,
                    ),
                    label: const Text('Save Record'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orangeAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryForm() {
    switch (_selectedType) {
      case ItemType.login:
        return Column(
          children: [
            _buildInputField(
              controller: _usernameController,
              label: 'Username / Email',
              hint: 'username or user@domain.com',
              prefixIcon: AppInputIcons.user,
            ),
            const SizedBox(height: 16),
            _buildInputField(
              controller: _passwordController,
              label: 'Password',
              prefixIcon: AppInputIcons.lock,
              isSecret: true,
              isObscured: _obscurePassword,
              onToggleObscure: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              suffixButtons: [
                IconButton(
                  tooltip: 'Generate Strong Password',
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedAiMagic,
                    color: AppColors.orangeAccent,
                    size: 18,
                  ),
                  onPressed: () {
                    PasswordGeneratorDialog.show(context, onUsePassword: (pwd) {
                      setState(() {
                        _passwordController.text = pwd;
                        _obscurePassword = false;
                      });
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInputField(
              controller: _urlController,
              label: 'Website URL',
              hint: 'https://example.com/login',
              prefixIcon: AppInputIcons.link,
            ),
            const SizedBox(height: 16),
            _buildInputField(
              controller: _totpController,
              label: 'Authenticator 2FA Secret Key',
              hint: 'Base32 secret (e.g. JBSWY3DPEHPK3PXP)',
              prefixIcon: AppInputIcons.shieldKey,
            ),
          ],
        );

      case ItemType.card:
        return Column(
          children: [
            _buildInputField(
              controller: _cardholderController,
              label: 'Cardholder Name',
              hint: 'e.g. JOHN DOE',
              prefixIcon: AppInputIcons.user,
            ),
            const SizedBox(height: 16),
            _buildInputField(
              controller: _cardNumberController,
              label: 'Card Number',
              hint: '•••• •••• •••• ••••',
              prefixIcon: AppInputIcons.categoryCard,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInputField(
                    controller: _expiryController,
                    label: 'Expiry (MM/YY)',
                    hint: '12/28',
                    prefixIcon: AppInputIcons.calendar,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInputField(
                    controller: _cvvController,
                    label: 'CVV / CVC',
                    hint: '•••',
                    prefixIcon: AppInputIcons.shield,
                    isSecret: true,
                    isObscured: _obscureCvv,
                    onToggleObscure: () =>
                        setState(() => _obscureCvv = !_obscureCvv),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInputField(
                    controller: _pinController,
                    label: 'Card PIN',
                    hint: '••••',
                    prefixIcon: AppInputIcons.hash,
                    isSecret: true,
                    isObscured: _obscurePin,
                    onToggleObscure: () =>
                        setState(() => _obscurePin = !_obscurePin),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInputField(
              controller: _zipController,
              label: 'Billing ZIP / Postal Code',
              prefixIcon: AppInputIcons.location,
            ),
          ],
        );

      case ItemType.identity:
        return Column(
          children: [
            _buildInputField(
              controller: _fullNameController,
              label: 'Full Legal Name',
              prefixIcon: AppInputIcons.user,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInputField(
                    controller: _idNumberController,
                    label: 'National ID / SSN',
                    prefixIcon: AppInputIcons.hash,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInputField(
                    controller: _passportController,
                    label: 'Passport Number',
                    prefixIcon: AppInputIcons.categoryIdentity,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInputField(
                    controller: _licenseController,
                    label: "Driver's License",
                    prefixIcon: AppInputIcons.car,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInputField(
                    controller: _dobController,
                    label: 'Date of Birth (YYYY-MM-DD)',
                    prefixIcon: AppInputIcons.calendar,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInputField(
              controller: _addressController,
              label: 'Address',
              prefixIcon: AppInputIcons.home,
            ),
            const SizedBox(height: 16),
            _buildInputField(
              controller: _phoneController,
              label: 'Phone Number',
              prefixIcon: AppInputIcons.hash,
            ),
          ],
        );

      case ItemType.note:
        return TextField(
          controller: _noteController,
          maxLines: 8,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Secure Note Body',
            alignLabelWithHint: true,
            hintText:
                'Enter sensitive recovery keys, codes, or private notes...',
            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 110),
              child: HugeIcon(
                icon: AppInputIcons.note,
                color: Colors.white54,
                size: 20,
              ),
            ),
            filled: true,
            fillColor: const Color(0xFF161922),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF272C3A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF272C3A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.orangeAccent),
            ),
          ),
        );

      case ItemType.developerSecret:
        return Column(
          children: [
            _buildInputField(
              controller: _secretKeyController,
              label: 'Private Secret Key / API Token',
              prefixIcon: AppInputIcons.key,
              isSecret: true,
              isObscured: _obscureSecretKey,
              onToggleObscure: () =>
                  setState(() => _obscureSecretKey = !_obscureSecretKey),
              suffixButtons: [
                IconButton(
                  tooltip: 'Generate Secret Token',
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedAiMagic,
                    color: AppColors.orangeAccent,
                    size: 18,
                  ),
                  onPressed: () {
                    PasswordGeneratorDialog.show(context, onUsePassword: (pwd) {
                      setState(() {
                        _secretKeyController.text = pwd;
                        _obscureSecretKey = false;
                      });
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInputField(
              controller: _publicKeyController,
              label: 'Public Key / Client ID',
              prefixIcon: AppInputIcons.globe,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _configController,
              maxLines: 4,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.white,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                labelText: 'Config / Environment Payload (JSON, YAML, .env)',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 50),
                  child: HugeIcon(
                    icon: AppInputIcons.file,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
                filled: true,
                fillColor: const Color(0xFF161922),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF272C3A)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF272C3A)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.orangeAccent),
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required List<List<dynamic>> prefixIcon,
    bool isSecret = false,
    bool isObscured = false,
    VoidCallback? onToggleObscure,
    List<Widget>? suffixButtons,
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isSecret && isObscured,
      autofocus: autofocus,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: HugeIcon(
            icon: prefixIcon,
            color: Colors.white60,
            size: 18,
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSecret && onToggleObscure != null)
              IconButton(
                tooltip: isObscured ? 'Reveal' : 'Mask',
                icon: HugeIcon(
                  icon: isObscured
                      ? HugeIcons.strokeRoundedView
                      : HugeIcons.strokeRoundedViewOff,
                  color: Colors.white60,
                  size: 18,
                ),
                onPressed: onToggleObscure,
              ),
            if (suffixButtons != null) ...suffixButtons,
          ],
        ),
        filled: true,
        fillColor: const Color(0xFF161922),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF272C3A)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF272C3A)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.orangeAccent),
        ),
      ),
    );
  }
}

class _CustomFieldRow {
  final TextEditingController key;
  final TextEditingController value;

  _CustomFieldRow(String k, String v)
      : key = TextEditingController(text: k),
        value = TextEditingController(text: v);

  void dispose() {
    key.dispose();
    value.dispose();
  }
}
