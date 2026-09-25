// Full desktop settings page mirroring the Android app sections, plus a
// Bluetooth sharing capability built on the core sharing pipeline.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_ui_desktop/firewood_ui_desktop.dart';

import '../providers.dart';
import '../services/autotype_service.dart';
import '../services/browser_bridge_service.dart';

class SettingsSection extends ConsumerStatefulWidget {
  const SettingsSection({super.key});

  @override
  ConsumerState<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends ConsumerState<SettingsSection> {
  bool _busy = false;
  int _burnerRefresh = 0;

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.roseAccent : AppColors.surfaceZinc,
    ));
  }

  Future<String?> _promptPassword(String title) async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceZinc,
        title: Text(title, style: const TextStyle(color: AppColors.offWhite, fontSize: 16)),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: AppStrings.masterPassword),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(AppStrings.cancel)),
          FirewoodButton(
            label: 'Confirm',
            onPressed: () => Navigator.pop(ctx, controller.text),
          ),
        ],
      ),
    );
    return (password == null || password.isEmpty) ? null : password;
  }

  // --- Backup & recovery ---

  Future<void> _exportVault() async {
    final password = await _promptPassword(AppStrings.exportVault);
    if (password == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(backupServiceProvider).exportVault(password);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save .firewood backup',
        fileName: 'firewood-backup.firewood',
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes, flush: true);
      _snack('Vault exported to $path');
    } catch (e) {
      _snack('Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importVault() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return;

    final password = await _promptPassword(AppStrings.importVault);
    if (password == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      await ref.read(backupServiceProvider).importVault(bytes, password);
      _snack('Vault imported. Unlock again with the imported password.');
      ref.read(authProvider.notifier).state = null;
    } catch (e) {
      _snack('Import failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromOtherVault() async {
    final key = ref.read(authProvider);
    if (key == null) {
      _snack('Vault must be unlocked to import items', error: true);
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'csv'],
      dialogTitle: 'Select Bitwarden JSON, 1Password, or CSV Export',
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    setState(() => _busy = true);
    try {
      final content = await File(path).readAsString();
      final items = VaultImporter.parse(content);
      if (items.isEmpty) {
        _snack('No valid items found in the selected file.', error: true);
        return;
      }

      final itemService = ref.read(itemServiceProvider);
      int count = 0;
      for (final it in items) {
        await itemService.addItem(
          key: key,
          type: it.type,
          title: it.title,
          fields: it.fields,
        );
        count++;
      }
      _snack('Successfully imported $count credential${count == 1 ? '' : 's'} into your vault!');
    } catch (e) {
      _snack('Import failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _encryptFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final file = picked?.files.single;
    final path = file?.path;
    if (path == null || file == null) return;

    final password = await _promptPassword(AppStrings.encryptFile);
    if (password == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final out = await ref.read(fileCryptoServiceProvider).encryptFile(
            password: password,
            bytes: bytes,
            fileName: file.name,
            mimeType: _mimeFor(file.name),
          );
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save encrypted file',
        fileName: '${file.name}.firewood',
      );
      if (savePath == null) return;
      await File(savePath).writeAsBytes(out, flush: true);
      _snack('Encrypted to $savePath');
    } catch (e) {
      _snack('Encryption failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEncryptedFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return;

    final password = await _promptPassword(AppStrings.openEncryptedFile);
    if (password == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final result = await ref
          .read(fileCryptoServiceProvider)
          .decryptFile(password: password, bytes: bytes);
      final fileName = result.metadata['fileName']?.toString() ?? 'decrypted.bin';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save decrypted file',
        fileName: fileName,
      );
      if (savePath == null) return;
      await File(savePath).writeAsBytes(result.bytes, flush: true);
      _snack('Decrypted to $savePath');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- Burner ---

  Future<void> _addBurner() async {
    final password = await _promptPassword('Add Burner Password');
    if (password == null) return;
    try {
      await ref.read(burnerServiceProvider).addBurnerPassword(password, label: 'Duress Code');
      _snack('Burner password added');
      setState(() => _burnerRefresh++);
    } catch (e) {
      _snack('$e', error: true);
    }
  }

  Future<void> _removeBurner(int id) async {
    await ref.read(burnerServiceProvider).removeBurner(id);
    setState(() => _burnerRefresh++);
  }

  // --- Danger zone ---

  Future<void> _deleteVault() async {
    final password = await _promptPassword('Delete Vault Data');
    if (password == null) return;
    try {
      await ref.read(vaultServiceProvider).unlock(password); // verify password
    } catch (_) {
      _snack('Incorrect master password', error: true);
      return;
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceZinc,
        title: const Text('Delete Vault Data?',
            style: TextStyle(color: AppColors.roseAccent, fontSize: 16)),
        content: const Text(
          'This permanently wipes the local vault and all items. This cannot be undone.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text(AppStrings.cancel)),
          FirewoodButton(
            label: 'Delete',
            variant: FirewoodButtonVariant.danger,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(secretStoreProvider).clearAll();
    ref.read(authProvider.notifier).state = null;
  }

  String _mimeFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentKey = ref.read(authProvider);
    if (currentKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please unlock vault first.')),
      );
      return;
    }

    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    String? dialogError;
    bool busy = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF161922),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF262C3A)),
          ),
          title: const Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedLockPassword,
                color: AppColors.orangeAccent,
                size: 22,
              ),
              SizedBox(width: 12),
              Text(
                'Change Master Password',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Envelope Encryption rotates the Master Encryption Key wrapper instantly. '
                  'Individual vault records are preserved without re-encryption.',
                  style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: currentController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Current Master Password',
                    filled: true,
                    fillColor: const Color(0xFF1B1E29),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'New Master Password',
                    filled: true,
                    fillColor: const Color(0xFF1B1E29),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    filled: true,
                    fillColor: const Color(0xFF1B1E29),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    dialogError!,
                    style: const TextStyle(color: AppColors.roseAccent, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orangeAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: busy
                  ? null
                  : () async {
                      if (newController.text.length < 8) {
                        setDialogState(() => dialogError = 'New password must be at least 8 characters');
                        return;
                      }
                      if (newController.text != confirmController.text) {
                        setDialogState(() => dialogError = 'New passwords do not match');
                        return;
                      }

                      setDialogState(() {
                        busy = true;
                        dialogError = null;
                      });

                      try {
                        final vaultService = ref.read(vaultServiceProvider);
                        // Verify current password
                        await vaultService.unlock(currentController.text);

                        // Rotate password via envelope MEK re-wrapping
                        await vaultService.changePassword(
                          currentMek: currentKey,
                          newPassword: newController.text,
                        );

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Master password successfully rotated! Records preserved intact.'),
                              backgroundColor: Color(0xFF1A2E22),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() {
                          busy = false;
                          dialogError = e.toString().replaceAll('VaultException: ', '');
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('Rotate Password', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manageQuickUnlock() async {
    final quickUnlock = ref.read(quickUnlockServiceProvider);
    final isEnabled = await quickUnlock.isEnabled();
    final hasBiometrics = await quickUnlock.isBiometricHardwareAvailable();

    if (!mounted) return;

    if (isEnabled) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceZinc,
          title: const Text('Quick Unlock Enabled', style: TextStyle(color: AppColors.offWhite, fontSize: 16)),
          content: const Text(
            'Quick Unlock is active. You can unlock your vault rapidly using your PIN without re-entering your master password.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Close'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.roseAccent),
              onPressed: () => Navigator.pop(ctx, 'disable'),
              child: const Text('Disable Quick Unlock'),
            ),
            FirewoodButton(
              label: 'Change PIN',
              onPressed: () => Navigator.pop(ctx, 'change'),
            ),
          ],
        ),
      );

      if (action == 'disable') {
        await quickUnlock.disableQuickUnlock();
        _snack('Quick Unlock disabled.');
        setState(() {});
      } else if (action == 'change') {
        _promptSetupQuickUnlock(hasBiometrics);
      }
    } else {
      _promptSetupQuickUnlock(hasBiometrics);
    }
  }

  Future<void> _promptSetupQuickUnlock(bool hasBiometrics) async {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    bool requireBio = false;
    String? dialogError;
    bool busy = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceZinc,
          title: const Text('Setup Quick Unlock', style: TextStyle(color: AppColors.offWhite, fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Set a 4 to 8-digit PIN to quickly unlock your vault after idle timeout without typing your full master password.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Quick Unlock PIN (4-8 digits)'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Confirm PIN'),
                ),
                if (hasBiometrics) ...[
                  const SizedBox(height: AppSpacing.md),
                  CheckboxListTile(
                    title: const Text('Require Fingerprint Verification', style: TextStyle(color: Colors.white, fontSize: 13)),
                    subtitle: const Text('Prompts system biometric sensor on quick unlock', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    value: requireBio,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppColors.orangeAccent,
                    onChanged: (v) => setDialogState(() => requireBio = v ?? false),
                  ),
                ],
                if (dialogError != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(dialogError!, style: const TextStyle(color: AppColors.roseAccent, fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FirewoodButton(
              label: 'Enable Quick Unlock',
              isLoading: busy,
              onPressed: () async {
                final pin = pinController.text.trim();
                final confirm = confirmController.text.trim();
                if (pin.length < 4 || pin.length > 8) {
                  setDialogState(() => dialogError = 'PIN must be between 4 and 8 digits');
                  return;
                }
                if (pin != confirm) {
                  setDialogState(() => dialogError = 'PINs do not match');
                  return;
                }

                final mek = ref.read(authProvider);
                if (mek == null) {
                  setDialogState(() => dialogError = 'Vault is locked. Unlock first.');
                  return;
                }

                setDialogState(() => busy = true);
                try {
                  await ref.read(quickUnlockServiceProvider).enableQuickUnlock(
                    currentMek: mek,
                    pin: pin,
                    requireBiometric: requireBio,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _snack('Quick Unlock successfully enabled!');
                  setState(() {});
                } catch (e) {
                  setDialogState(() {
                    busy = false;
                    dialogError = e.toString().replaceAll('VaultException: ', '');
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _manageBrowserIntegration() async {
    final status = await BrowserBridgeService.getManifestStatus();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final installedCount = status.values.where((v) => v).length;
          return AlertDialog(
            backgroundColor: AppColors.surfaceZinc,
            title: const Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedGlobe02,
                  color: AppColors.orangeAccent,
                  size: 22,
                  strokeWidth: 1.8,
                ),
                SizedBox(width: 10),
                Text(
                  'Browser Integration & Autofill',
                  style: TextStyle(color: AppColors.offWhite, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Connect your desktop browsers to Firewood for instant zero-knowledge password and 2FA TOTP autofill. Credentials remain securely locked in memory until accessed.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.coal,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderZinc),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'IPC SOCKET:',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: ref.watch(browserBridgeEnabledProvider)
                                    ? AppColors.mintAccent.withOpacity(0.15)
                                    : AppColors.textMuted.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ref.watch(browserBridgeEnabledProvider) ? 'LISTENING' : 'DISABLED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: ref.watch(browserBridgeEnabledProvider)
                                      ? AppColors.mintAccent
                                      : AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          BrowserBridgeService.defaultSocketPath,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppColors.offWhite,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'DETECTED BROWSERS:',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...status.entries.map((e) {
                    final configured = e.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            configured ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                            size: 16,
                            color: configured ? AppColors.mintAccent : AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            e.key,
                            style: const TextStyle(color: AppColors.offWhite, fontSize: 13),
                          ),
                          const Spacer(),
                          Text(
                            configured ? 'Configured' : 'Not installed',
                            style: TextStyle(
                              color: configured ? AppColors.mintAccent : AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: configured ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              if (installedCount > 0)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.roseAccent),
                  onPressed: () async {
                    await BrowserBridgeService.uninstallManifests();
                    final updated = await BrowserBridgeService.getManifestStatus();
                    setDialogState(() {
                      status.clear();
                      status.addAll(updated);
                    });
                    _snack('Browser integration manifests uninstalled.');
                    setState(() {});
                  },
                  child: const Text('Uninstall Manifests'),
                ),
              FirewoodButton(
                label: installedCount > 0 ? 'Reinstall Manifests' : 'Install Browser Integration',
                icon: HugeIcons.strokeRoundedDownload04,
                onPressed: () async {
                  final paths = await BrowserBridgeService.installManifests();
                  final updated = await BrowserBridgeService.getManifestStatus();
                  setDialogState(() {
                    status.clear();
                    status.addAll(updated);
                  });
                  _snack('Installed ${paths.length} browser native messaging manifests!');
                  setState(() {});
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAutoTypeTester() async {
    final available = await AutoTypeService.isAvailable();
    final testInputController = TextEditingController();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surfaceZinc,
            title: const Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedKeyboard,
                  color: AppColors.orangeAccent,
                  size: 22,
                  strokeWidth: 1.8,
                ),
                SizedBox(width: 10),
                Text(
                  'AutoType Diagnostic Tester',
                  style: TextStyle(
                    color: AppColors.offWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    available
                        ? 'Simulate typing into any focused window or into the test scratchpad below.'
                        : 'xdotool is not detected on this Linux system. Synthetic typing is unavailable until xdotool is installed.',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.coal,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderZinc),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'BACKEND STATUS:',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: available
                                    ? AppColors.mintAccent.withOpacity(0.15)
                                    : AppColors.roseAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                available ? 'AVAILABLE (xdotool)' : 'UNAVAILABLE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: available
                                      ? AppColors.mintAccent
                                      : AppColors.roseAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Test Input Scratchpad:',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: testInputController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Click here before testing typing...',
                            filled: true,
                            fillColor: const Color(0xFF13151D),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: Color(0xFF2C3243)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              if (available)
                FirewoodButton(
                  label: 'Simulate Keystrokes',
                  icon: HugeIcons.strokeRoundedPlay,
                  onPressed: () async {
                    final item = DecryptedItem(
                      itemId: 'test-item',
                      type: 'login',
                      title: 'Test',
                      fields: {
                        'username': 'firewood-user',
                        'password': 'test-pass-secret',
                      },
                      updatedAt: DateTime.now(),
                    );
                    _snack('Typing test sequence in 2s...');
                    await AutoTypeService.execute(
                      item: item,
                      sequence: '{USERNAME}{TAB}{PASSWORD}',
                      initialCountdownSeconds: 2,
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddVaultDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceZinc,
        title: const Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedFolder01,
              color: AppColors.orangeAccent,
              size: 22,
              strokeWidth: 1.8,
            ),
            SizedBox(width: 10),
            Text(
              'Add New Vault',
              style: TextStyle(
                color: AppColors.offWhite,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create a separate vault partition to organize your credentials (e.g. Work, Clients, Personal).',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Vault Name',
                  hintText: 'e.g. Work, Finance, Clients',
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
          FirewoodButton(
            label: 'Add Vault',
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final currentList = ref.read(availableVaultsProvider);
      if (!currentList.contains(name)) {
        ref.read(availableVaultsProvider.notifier).state = [...currentList, name];
        _snack('Added vault "$name"');
      }
    }
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceZinc,
        title: const Text(AppStrings.appName,
            style: TextStyle(color: AppColors.offWhite, fontSize: 16)),
        content: const Text(
          'Offline-first, zero-knowledge vault.\n\n'
          'Secrets are encrypted with Argon2id + XChaCha20-Poly1305. '
          'Your master password never touches disk. Android and desktop share '
          'the same .firewood format.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
        ),
        actions: [
          FirewoodButton(label: 'Close', variant: FirewoodButtonVariant.secondary, onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final autoLock = ref.watch(autoLockEnabledProvider);
    final minutes = ref.watch(autoLockMinutesProvider);
    final clipboardClear = ref.watch(clipboardClearProvider);
    final bluetooth = ref.watch(bluetoothEnabledProvider);
    final accent = ref.watch(accentColorProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.dashboardMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Settings',
                  style: TextStyle(
                      color: AppColors.offWhite, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text('Security, backups, sharing and app information',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: AppSpacing.xl),

              // --- APPEARANCE ---
              const _SectionHeader('APPEARANCE & ACCENT COLOR'),
              _Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      for (final option in _accentOptions)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.md),
                          child: _AccentSwatch(
                            color: option,
                            selected: accent == option,
                            onTap: () => ref.read(accentColorProvider.notifier).state = option,
                          ),
                        ),
                      const Spacer(),
                      const Text('Accent', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ),

              // --- SECURITY ---
              const _SectionHeader('VAULT SECURITY & AUTO-LOCK'),
              _Card(
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: HugeIcons.strokeRoundedSquareLock02,
                      title: 'Auto-Lock Vault',
                      subtitle: 'Lock when idle or the window loses focus',
                      value: autoLock,
                      onChanged: (v) => ref.read(autoLockEnabledProvider.notifier).state = v,
                    ),
                    if (autoLock)
                      _Tile(
                        icon: HugeIcons.strokeRoundedTimer01,
                        title: 'Auto-Lock Timeout',
                        trailing: HearthDropdown<int>(
                          value: minutes,
                          width: 130,
                          items: const [
                            HearthDropdownItem(value: 1, label: '1 minute', icon: HugeIcons.strokeRoundedTimer01),
                            HearthDropdownItem(value: 5, label: '5 minutes', icon: HugeIcons.strokeRoundedTimer01),
                            HearthDropdownItem(value: 15, label: '15 minutes', icon: HugeIcons.strokeRoundedTimer01),
                            HearthDropdownItem(value: 30, label: '30 minutes', icon: HugeIcons.strokeRoundedTimer01),
                          ],
                          onChanged: (v) =>
                              ref.read(autoLockMinutesProvider.notifier).state = v,
                        ),
                      ),
                    _SwitchRow(
                      icon: HugeIcons.strokeRoundedClipboard,
                      title: 'Clipboard Auto-Clear',
                      subtitle: 'Wipe copied secrets shortly after a copy',
                      value: clipboardClear,
                      onChanged: (v) => ref.read(clipboardClearProvider.notifier).state = v,
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedLockPassword,
                      title: 'Change Master Password',
                      subtitle: 'Rotate master password instantly via Envelope MEK re-wrapping',
                      onTap: _showChangePasswordDialog,
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedPower,
                      title: 'Lock Vault Now',
                      subtitle: 'Immediately clear the secret key from memory',
                      onTap: () => ref.read(authProvider.notifier).state = null,
                    ),
                    FutureBuilder<bool>(
                      future: ref.read(quickUnlockServiceProvider).isEnabled(),
                      builder: (context, snapshot) {
                        final enabled = snapshot.data ?? false;
                        return _Tile(
                          icon: HugeIcons.strokeRoundedFingerPrint,
                          title: 'Quick Unlock (PIN & Biometrics)',
                          subtitle: enabled
                              ? 'Active: Fast PIN & biometric unlock enabled'
                              : 'Set a rapid PIN & fingerprint unlock after idle lock',
                          trailing: enabled
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.mintAccent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.mintAccent.withOpacity(0.4)),
                                  ),
                                  child: const Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.mintAccent,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: _manageQuickUnlock,
                        );
                      },
                    ),
                    const _DisabledTile(
                      icon: HugeIcons.strokeRoundedCamera01,
                      title: 'Allow Screenshots',
                      subtitle: 'Mobile only',
                    ),
                  ],
                ),
              ),

              // --- BURNER ---
              const _SectionHeader('BURNER / DURESS PASSWORD'),
              _Card(
                child: Column(
                  children: [
                    FutureBuilder<List<StoredBurner>>(
                      key: ValueKey(_burnerRefresh),
                      future: ref.read(secretStoreProvider).getBurners(),
                      builder: (context, snapshot) {
                        final burners = snapshot.data ?? const <StoredBurner>[];
                        if (burners.isEmpty) {
                          return const _Tile(
                            icon: HugeIcons.strokeRoundedAlert02,
                            title: 'No burner passwords',
                            subtitle: 'A duress code destroys the vault on unlock',
                          );
                        }
                        return Column(
                          children: [
                            for (final b in burners)
                              _Tile(
                                icon: HugeIcons.strokeRoundedAlert02,
                                title: b.label,
                                subtitle: 'Created ${DateTime.now().difference(b.createdAt).inDays}d ago',
                                onTap: () => _removeBurner(b.id),
                              ),
                          ],
                        );
                      },
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedAdd01,
                      title: 'Add Burner Password',
                      subtitle: 'Entering it on unlock destroys all vault data',
                      danger: true,
                      onTap: _addBurner,
                    ),
                  ],
                ),
              ),

              // --- BROWSER INTEGRATION ---
              const _SectionHeader('BROWSER INTEGRATION & AUTOFILL'),
              _Card(
                child: Column(
                  children: [
                    Consumer(
                      builder: (context, ref, _) {
                        final enabled = ref.watch(browserBridgeEnabledProvider);
                        return _SwitchRow(
                          icon: HugeIcons.strokeRoundedGlobe02,
                          title: 'Autofill IPC Bridge',
                          subtitle: enabled
                              ? 'Active: Local domain socket listening'
                              : 'Disabled: Browser communication stopped',
                          value: enabled,
                          onChanged: (val) {
                            ref.read(browserBridgeEnabledProvider.notifier).state = val;
                          },
                        );
                      },
                    ),
                    FutureBuilder<Map<String, bool>>(
                      future: BrowserBridgeService.getManifestStatus(),
                      builder: (context, snapshot) {
                        final status = snapshot.data ?? {};
                        final installedCount = status.values.where((v) => v).length;
                        return _Tile(
                          icon: HugeIcons.strokeRoundedBrowser,
                          title: 'Browser Extension Host',
                          subtitle: installedCount > 0
                              ? 'Configured for $installedCount browser(s)'
                              : 'Install native messaging manifests for Chrome, Brave, Firefox',
                          trailing: installedCount > 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.mintAccent.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.mintAccent.withOpacity(0.4)),
                                  ),
                                  child: Text(
                                    '$installedCount BROWSERS',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.mintAccent,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: _manageBrowserIntegration,
                        );
                      },
                    ),
                  ],
                ),
              ),

              // --- GLOBAL AUTOTYPE & DESKTOP SHELL ---
              const _SectionHeader('GLOBAL AUTOTYPE & DESKTOP SHELL'),
              _Card(
                child: Column(
                  children: [
                    FutureBuilder<String>(
                      future: AutoTypeService.getBackendName(),
                      builder: (context, snapshot) {
                        final backend = snapshot.data ?? 'Detecting...';
                        final isAvail = backend.contains('xdotool');
                        return _Tile(
                          icon: HugeIcons.strokeRoundedKeyboard,
                          title: 'AutoType Engine',
                          subtitle: 'Zero-knowledge synthetic typing via $backend',
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isAvail
                                  ? AppColors.mintAccent.withOpacity(0.15)
                                  : AppColors.roseAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isAvail
                                    ? AppColors.mintAccent.withOpacity(0.4)
                                    : AppColors.roseAccent.withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              isAvail ? 'AVAILABLE' : 'INSTALL XDOTOOL',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isAvail ? AppColors.mintAccent : AppColors.roseAccent,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedSlidersHorizontal,
                      title: 'Default Keystroke Sequence',
                      subtitle: 'Format used when triggering AutoType on logins',
                      trailing: HearthDropdown<String>(
                        value: ref.watch(autoTypeSequenceProvider),
                        width: 230,
                        items: const [
                          HearthDropdownItem(
                            value: '{USERNAME}{TAB}{PASSWORD}{ENTER}',
                            label: 'User + Tab + Pass + Enter',
                            icon: HugeIcons.strokeRoundedKeyboard,
                          ),
                          HearthDropdownItem(
                            value: '{USERNAME}{TAB}{PASSWORD}',
                            label: 'User + Tab + Pass',
                            icon: HugeIcons.strokeRoundedKeyboard,
                          ),
                          HearthDropdownItem(
                            value: '{PASSWORD}{ENTER}',
                            label: 'Password + Enter',
                            icon: HugeIcons.strokeRoundedKeyboard,
                          ),
                        ],
                        onChanged: (v) => ref.read(autoTypeSequenceProvider.notifier).state = v,
                      ),
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedTimer01,
                      title: 'Focus Switch Delay',
                      subtitle: 'Countdown before typing begins, allowing target window switch',
                      trailing: HearthDropdown<int>(
                        value: ref.watch(autoTypeDelaySecondsProvider),
                        width: 130,
                        items: const [
                          HearthDropdownItem(value: 1, label: '1 second', icon: HugeIcons.strokeRoundedTimer01),
                          HearthDropdownItem(value: 2, label: '2 seconds', icon: HugeIcons.strokeRoundedTimer01),
                          HearthDropdownItem(value: 3, label: '3 seconds', icon: HugeIcons.strokeRoundedTimer01),
                          HearthDropdownItem(value: 5, label: '5 seconds', icon: HugeIcons.strokeRoundedTimer01),
                        ],
                        onChanged: (v) => ref.read(autoTypeDelaySecondsProvider.notifier).state = v,
                      ),
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final minimize = ref.watch(minimizeToTrayProvider);
                        return _SwitchRow(
                          icon: HugeIcons.strokeRoundedMinimize01,
                          title: 'Keep Running in Background',
                          subtitle: 'Minimize to background when window is closed to maintain IPC socket',
                          value: minimize,
                          onChanged: (v) => ref.read(minimizeToTrayProvider.notifier).state = v,
                        );
                      },
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedPlay,
                      title: 'Test AutoType Simulator',
                      subtitle: 'Open scratchpad to test synthetic keystroke injection',
                      onTap: _showAutoTypeTester,
                    ),
                  ],
                ),
              ),

              // --- MULTI-VAULT MANAGEMENT ---
              const _SectionHeader('MULTI-VAULT PARTITIONS'),
              _Card(
                child: Column(
                  children: [
                    Consumer(
                      builder: (context, ref, _) {
                        final vaults = ref.watch(availableVaultsProvider);
                        return Column(
                          children: [
                            for (final v in vaults)
                              _Tile(
                                icon: HugeIcons.strokeRoundedFolder01,
                                title: v,
                                subtitle: 'Partitioned credential store',
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1F2432),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFF2C3446)),
                                  ),
                                  child: const Text(
                                    'VAULT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.orangeAccent,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedAdd01,
                      title: 'Add New Vault Partition',
                      subtitle: 'Create a new named partition to organize credentials',
                      onTap: _showAddVaultDialog,
                    ),
                  ],
                ),
              ),

              // --- BACKUP ---
              const _SectionHeader('AUTOMATED BACKUP & RECOVERY'),
              _Card(
                child: Column(
                  children: [
                    _Tile(
                      icon: HugeIcons.strokeRoundedUpload01,
                      title: AppStrings.exportVault,
                      subtitle: 'Write an authenticated .firewood backup',
                      enabled: !_busy,
                      onTap: _exportVault,
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedDownload01,
                      title: AppStrings.importVault,
                      subtitle: 'Restore from a .firewood file',
                      enabled: !_busy,
                      onTap: _importVault,
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedFolderTransfer,
                      title: 'Import from Other Vaults',
                      subtitle: 'Import Bitwarden JSON, 1Password, or CSV records',
                      enabled: !_busy,
                      onTap: _importFromOtherVault,
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedFileKey,
                      title: AppStrings.encryptFile,
                      subtitle: 'Wrap any file + metadata in a .firewood container',
                      enabled: !_busy,
                      onTap: _encryptFile,
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedSquareUnlock02,
                      title: AppStrings.openEncryptedFile,
                      subtitle: 'Decrypt a single-file .firewood container',
                      enabled: !_busy,
                      onTap: _openEncryptedFile,
                    ),
                    const _DisabledTile(
                      icon: HugeIcons.strokeRoundedCalendar01,
                      title: 'Scheduled Auto-Backup',
                      subtitle: 'Mobile only',
                    ),
                  ],
                ),
              ),

              // --- BLUETOOTH SHARING ---
              const _SectionHeader('BLUETOOTH SHARING'),
              _Card(
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: HugeIcons.strokeRoundedBluetooth,
                      title: 'Enable Bluetooth Sharing',
                      subtitle: 'Transfer encrypted .firewood files with a paired Android device',
                      value: bluetooth,
                      onChanged: (v) => ref.read(bluetoothEnabledProvider.notifier).state = v,
                    ),
                    if (bluetooth) ...[
                      FutureBuilder<bool>(
                        future: ref.read(bluetoothTransportProvider).isAvailable(),
                        builder: (context, snapshot) {
                          final available = snapshot.data ?? false;
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(
                                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                            child: Row(
                              children: [
                                HugeIcon(
                                  icon: available
                                      ? HugeIcons.strokeRoundedCheckmarkCircle01
                                      : HugeIcons.strokeRoundedInformationCircle,
                                  size: 15,
                                  color: available ? AppColors.mintAccent : AppColors.textMuted,
                                  strokeWidth: 1.8,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    available
                                        ? 'Bluetooth adapter ready'
                                        : 'No BLE adapter in this build yet — the encrypted pipeline is ready.',
                                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      _Tile(
                        icon: HugeIcons.strokeRoundedBluetooth,
                        title: 'Open Bluetooth Sharing',
                        subtitle: 'Send or receive .firewood files app-to-app',
                        onTap: () => ref.read(desktopTabProvider.notifier).state = 4,
                      ),
                    ],
                  ],
                ),
              ),

              // --- APP INFO ---
              const _SectionHeader('APP INFO & UPDATES'),
              _Card(
                child: Column(
                  children: [
                    const _Tile(
                      icon: HugeIcons.strokeRoundedInformationCircle,
                      title: 'Version',
                      subtitle: '1.0.0 · desktop',
                    ),
                    _Tile(
                      icon: HugeIcons.strokeRoundedFire,
                      title: 'About Firewood & Developers',
                      subtitle: 'Zero-knowledge architecture & app specs',
                      onTap: _showAbout,
                    ),
                  ],
                ),
              ),

              // --- DANGER ZONE ---
              const _SectionHeader('DANGER ZONE'),
              _Card(
                child: _Tile(
                  icon: HugeIcons.strokeRoundedDelete02,
                  title: 'Delete Vault Data',
                  subtitle: 'Permanently wipe the local database and reset the vault',
                  danger: true,
                  enabled: !_busy,
                  onTap: _deleteVault,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

const List<Color> _accentOptions = [
  AppColors.orangeAccent,
  AppColors.ember,
  AppColors.periwinkleAccent,
  AppColors.mintAccent,
  AppColors.roseAccent,
];

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xl, 0, AppSpacing.sm),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceZinc,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: AppColors.borderZinc),
      ),
      child: child,
    );
  }
}

class _Tile extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;
  final bool enabled;

  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.danger = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger ? AppColors.roseAccent : AppColors.emberBright;
    return MouseRegion(
      cursor: onTap != null && enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                HugeIcon(icon: icon, size: AppSizes.iconMd, color: fg, strokeWidth: 1.8),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: danger ? AppColors.roseAccent : AppColors.offWhite,
                              fontSize: 14)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (onTap != null)
                  const HugeIcon(
                    icon: HugeIcons.strokeRoundedChevronRight,
                    size: 18,
                    color: AppColors.textMuted,
                    strokeWidth: 1.8,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _Tile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        activeColor: AppColors.ember,
        onChanged: onChanged,
      ),
    );
  }
}

class _DisabledTile extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String title;
  final String subtitle;
  const _DisabledTile({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return _Tile(icon: icon, title: title, subtitle: subtitle, enabled: false);
  }
}

class _AccentSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AccentSwatch({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.offWhite : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12),
            ],
          ),
          child: selected
              ? const HugeIcon(
                  icon: HugeIcons.strokeRoundedTick02,
                  size: 16,
                  color: Colors.white,
                  strokeWidth: 2.2,
                )
              : null,
        ),
      ),
    );
  }
}
