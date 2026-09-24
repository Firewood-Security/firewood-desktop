// Dedicated Bluetooth sharing page: two cards (Send / Receive) that start an
// app-to-app transfer, then a processing panel showing live transfer steps.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_ui_desktop/firewood_ui_desktop.dart';

import '../providers.dart';

enum _Stage { idle, working, done, error }

class SharingPage extends ConsumerStatefulWidget {
  const SharingPage({super.key});

  @override
  ConsumerState<SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends ConsumerState<SharingPage> {
  _Stage _stage = _Stage.idle;
  String _title = '';
  String _step = '';
  String _result = '';

  void _reset() => setState(() {
        _stage = _Stage.idle;
        _title = '';
        _step = '';
        _result = '';
      });

  Future<String?> _promptPassword() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceZinc,
        title: const Text('Encrypt for transfer',
            style: TextStyle(color: AppColors.offWhite, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The receiver opens it with this password. App-to-app only.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: AppStrings.masterPassword),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text(AppStrings.cancel)),
          FirewoodButton(label: 'Start', onPressed: () => Navigator.pop(ctx, controller.text)),
        ],
      ),
    );
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> _sendVault() async {
    final password = await _promptPassword();
    if (password == null || !mounted) return;

    setState(() {
      _stage = _Stage.working;
      _title = 'Sending vault';
      _step = 'Encrypting package…';
    });

    try {
      final bytes = await ref.read(backupServiceProvider).exportVault(password);
      if (!mounted) return;
      setState(() => _step = 'Searching for a nearby Firewood device…');
      await ref.read(bluetoothTransportProvider).send(
            fileName: 'firewood-vault.firewood',
            bytes: bytes,
          );
      setState(() {
        _stage = _Stage.done;
        _result = 'Vault sent to the paired device.';
      });
    } catch (e) {
      setState(() {
        _stage = _Stage.error;
        _result = '$e';
      });
    }
  }

  Future<void> _sendFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final file = picked?.files.single;
    final path = file?.path;
    if (path == null || file == null || !mounted) return;

    final password = await _promptPassword();
    if (password == null || !mounted) return;

    setState(() {
      _stage = _Stage.working;
      _title = 'Sending file';
      _step = 'Encrypting ${file.name}…';
    });

    try {
      final bytes = await File(path).readAsBytes();
      final packed = await ref.read(fileCryptoServiceProvider).encryptFile(
            password: password,
            bytes: bytes,
            fileName: file.name,
          );
      if (!mounted) return;
      setState(() => _step = 'Searching for a nearby Firewood device…');
      await ref.read(bluetoothTransportProvider).send(
            fileName: '${file.name}.firewood',
            bytes: packed,
          );
      setState(() {
        _stage = _Stage.done;
        _result = '${file.name} sent.';
      });
    } catch (e) {
      setState(() {
        _stage = _Stage.error;
        _result = '$e';
      });
    }
  }

  Future<void> _receive() async {
    setState(() {
      _stage = _Stage.working;
      _title = 'Receiving';
      _step = 'Waiting for an incoming app-to-app transfer…';
    });

    final transport = ref.read(bluetoothTransportProvider);
    try {
      await transport.startListening();
      final sent = await transport.receive();
      await transport.stopListening();

      if (sent == null) {
        setState(() {
          _stage = _Stage.error;
          _result = 'No incoming transfer was received.';
        });
        return;
      }

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save received .firewood',
        fileName: sent.fileName,
      );
      if (savePath == null) {
        _reset();
        return;
      }
      await File(savePath).writeAsBytes(sent.bytes, flush: true);
      setState(() {
        _stage = _Stage.done;
        _result = 'Saved to $savePath';
      });
    } catch (e) {
      setState(() {
        _stage = _Stage.error;
        _result = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.dashboardMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bluetooth Sharing',
                  style: TextStyle(
                      color: AppColors.offWhite, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.xs),
              const Text('Device-to-device transfer of encrypted .firewood files',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: AppSpacing.xl),

              Row(
                children: [
                  Expanded(
                    child: _RoleCard(
                      icon: HugeIcons.strokeRoundedShare08,
                      title: 'Sender',
                      description: 'Encrypt and send your vault or a file to a nearby '
                          'Firewood app.',
                      actions: [
                        FirewoodButton(
                          label: 'Send Vault',
                          icon: HugeIcons.strokeRoundedSquareLock02,
                          fullWidth: true,
                          onPressed: _sendVault,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        FirewoodButton(
                          label: 'Send File',
                          icon: HugeIcons.strokeRoundedFileKey,
                          variant: FirewoodButtonVariant.secondary,
                          fullWidth: true,
                          onPressed: _sendFile,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: _RoleCard(
                      icon: HugeIcons.strokeRoundedDownload04,
                      title: 'Receiver',
                      description: 'Listen for an incoming encrypted transfer and '
                          'save it as a .firewood file.',
                      actions: [
                        FirewoodButton(
                          label: 'Receive',
                          icon: HugeIcons.strokeRoundedBluetooth,
                          fullWidth: true,
                          onPressed: _receive,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              const Row(
                children: [
                  HugeIcon(
                    icon: HugeIcons.strokeRoundedInformationCircle,
                    size: 15,
                    color: AppColors.textMuted,
                    strokeWidth: 1.8,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'App-to-app only — the other device must be running Firewood '
                      'with Bluetooth sharing enabled.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),

              if (_stage != _Stage.idle) ...[
                const SizedBox(height: AppSpacing.xl),
                _ProcessingPanel(
                  stage: _stage,
                  title: _title,
                  step: _step,
                  result: _result,
                  onDone: _reset,
                  onRetry: _reset,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final List<List<dynamic>> icon;
  final String title;
  final String description;
  final List<Widget> actions;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceZinc,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: AppColors.borderZinc),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.ember.withValues(alpha: 0.12),
              borderRadius: AppRadii.mdAll,
              border: Border.all(color: AppColors.ember.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: HugeIcon(
                icon: icon,
                size: 24,
                color: AppColors.emberBright,
                strokeWidth: 1.8,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(title,
              style: const TextStyle(
                  color: AppColors.offWhite, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.xs),
          Text(description,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4)),
          const SizedBox(height: AppSpacing.xl),
          ...actions,
        ],
      ),
    );
  }
}

class _ProcessingPanel extends StatelessWidget {
  final _Stage stage;
  final String title;
  final String step;
  final String result;
  final VoidCallback onDone;
  final VoidCallback onRetry;

  const _ProcessingPanel({
    required this.stage,
    required this.title,
    required this.step,
    required this.result,
    required this.onDone,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isWorking = stage == _Stage.working;
    final isDone = stage == _Stage.done;
    final color = isDone
        ? AppColors.mintAccent
        : stage == _Stage.error
            ? AppColors.roseAccent
            : AppColors.emberBright;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceZinc,
        borderRadius: AppRadii.lgAll,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          if (isWorking)
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.emberBright),
            )
          else
            HugeIcon(
              icon: isDone
                  ? HugeIcons.strokeRoundedCheckmarkCircle01
                  : HugeIcons.strokeRoundedAlert02,
              size: 26,
              color: color,
              strokeWidth: 1.8,
            ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWorking ? title : (isDone ? 'Transfer complete' : 'Transfer failed'),
                  style: const TextStyle(
                      color: AppColors.offWhite, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  isWorking ? step : result,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!isWorking)
            FirewoodButton(
              label: isDone ? 'Done' : 'Close',
              variant: FirewoodButtonVariant.secondary,
              onPressed: isDone ? onDone : onRetry,
            ),
        ],
      ),
    );
  }
}
