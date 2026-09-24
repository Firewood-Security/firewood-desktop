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
                      icon: HugeIcons.strokeRoundedPower,
                      title: 'Lock Vault Now',
                      subtitle: 'Immediately clear the secret key from memory',
                      onTap: () => ref.read(authProvider.notifier).state = null,
                    ),
                    const _DisabledTile(
                      icon: HugeIcons.strokeRoundedFingerPrint,
                      title: 'Biometric Vault Unlock',
                      subtitle: 'Mobile only',
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
