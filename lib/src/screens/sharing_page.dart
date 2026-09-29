// AirShare page: two clean action cards (Sender + Receiver).
// Guide information moved to a dedicated Guide dialog button.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_ui_desktop/firewood_ui_desktop.dart';

import '../providers.dart';
import '../services/ble_share_transport.dart';
import '../widgets/airshare_dialog.dart';

class SharingPage extends ConsumerStatefulWidget {
  const SharingPage({super.key});

  @override
  ConsumerState<SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends ConsumerState<SharingPage> {
  bool _senderBusy = false;
  bool _receiverBusy = false;

  @override
  void initState() {
    super.initState();
    // V-012: the BLE transport must never pick a peer on its own — route
    // every connection through an explicit user confirmation.
    (ref.read(bluetoothTransportProvider) as BleShareTransport).peerConfirmer =
        _confirmBlePeer;
  }

  /// V-012: presents the peers advertising the Firewood service and returns
  /// the one the user picked, or null when they cancel (fails closed).
  Future<BluetoothDevice?> _confirmBlePeer(
      List<BlePeerCandidate> candidates) async {
    if (!mounted) return null;
    return showDialog<BluetoothDevice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceZinc,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderZinc),
        ),
        title: const Text('Confirm the peer device',
            style: TextStyle(color: AppColors.offWhite, fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Only continue if you recognise the other device — a nearby '
                'attacker can advertise this service too.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.lg),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (ctx, i) {
                    final c = candidates[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.bluetooth,
                          color: AppColors.orangeAccent),
                      title: Text(c.name,
                          style: const TextStyle(
                              color: AppColors.offWhite, fontSize: 14)),
                      subtitle: Text('${c.device.remoteId} · ${c.rssi} dBm',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                      onTap: () => Navigator.of(ctx).pop(c.device),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text(AppStrings.cancel),
          ),
        ],
      ),
    );
  }

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
              decoration:
                  const InputDecoration(labelText: AppStrings.masterPassword),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(AppStrings.cancel)),
          FirewoodButton(
              label: 'Start',
              onPressed: () => Navigator.pop(ctx, controller.text)),
        ],
      ),
    );
    return (value == null || value.isEmpty) ? null : value;
  }

  void _showGuide() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceZinc,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderZinc),
        ),
        title: Row(
          children: [
            const HugeIcon(
              icon: HugeIcons.strokeRoundedInformationCircle,
              size: 20,
              color: AppColors.orangeAccent,
              strokeWidth: 1.8,
            ),
            const SizedBox(width: 10),
            Text('AirShare Guide',
                style: GoogleFonts.syncopate(
                    color: AppColors.offWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _guideStep(
                '1',
                'Prepare Devices',
                'Open Firewood on both devices and connect to the same local Wi-Fi or Bluetooth range.',
              ),
              _guideStep(
                '2',
                'Select Transfer Role',
                'Choose "Send Credentials" on the sender and "Receive Credentials" on the receiver.',
              ),
              _guideStep(
                '3',
                'Scan or Pair',
                'Scan the animated QR code on screen or establish an encrypted direct Bluetooth session.',
              ),
              _guideStep(
                '4',
                'Zero Cloud Security',
                'Payload is encrypted point-to-point (X25519 + ChaCha20-Poly1305). Zero cloud, zero servers.',
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.orangeAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.orangeAccent.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedShieldCheck,
                      size: 16,
                      color: AppColors.orangeAccent,
                      strokeWidth: 1.8,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'App-to-app only — zero cloud, zero servers. Your data never leaves your devices.',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          FirewoodButton(label: 'Got it', onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  Widget _guideStep(String step, String title, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardZinc,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderZinc.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.orangeAccent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.orangeAccent.withValues(alpha: 0.4),
              ),
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: AppColors.orangeAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.offWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendVault() async {
    final password = await _promptPassword();
    if (password == null || !mounted) return;
    setState(() => _senderBusy = true);
    try {
      final bytes = await ref.read(backupServiceProvider).exportVault(password);
      if (!mounted) return;
      await ref.read(bluetoothTransportProvider).send(
            fileName: 'firewood-vault.firewood',
            bytes: bytes,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vault sent successfully'),
          backgroundColor: Color(0xFF1A2E22),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Transfer failed: $e'),
          backgroundColor: AppColors.roseAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _senderBusy = false);
    }
  }

  Future<void> _sendFile() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final file = picked?.files.single;
    final path = file?.path;
    if (path == null || file == null || !mounted) return;

    final password = await _promptPassword();
    if (password == null || !mounted) return;

    setState(() => _senderBusy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final packed = await ref.read(fileCryptoServiceProvider).encryptFile(
            password: password,
            bytes: bytes,
            fileName: file.name,
          );
      if (!mounted) return;
      await ref.read(bluetoothTransportProvider).send(
            fileName: '${file.name}.firewood',
            bytes: packed,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${file.name} sent successfully'),
          backgroundColor: const Color(0xFF1A2E22),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Transfer failed: $e'),
          backgroundColor: AppColors.roseAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _senderBusy = false);
    }
  }

  Future<void> _receive() async {
    setState(() => _receiverBusy = true);
    final transport = ref.read(bluetoothTransportProvider);
    try {
      await transport.startListening();
      final SentFile? sent;
      try {
        // V-012/V-047: receive() can now fail closed (hostile frame header,
        // unconfirmed peer) — always tear the listener down, or the next
        // attempt would start on a half-open session.
        sent = await transport.receive();
      } finally {
        await transport.stopListening();
      }

      if (sent == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No incoming transfer received'),
            backgroundColor: AppColors.roseAccent,
          ));
        }
        return;
      }

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save received .firewood',
        fileName: sent.fileName,
      );
      if (savePath == null) return;
      await File(savePath).writeAsBytes(sent.bytes, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved to $savePath'),
          backgroundColor: const Color(0xFF1A2E22),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Receive failed: $e'),
          backgroundColor: AppColors.roseAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _receiverBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0E12),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AIRSHARE',
                          style: GoogleFonts.syncopate(
                            color: AppColors.offWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Encrypted device-to-device credential transfer',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _showGuide,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceZinc,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                AppColors.orangeAccent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedInformationCircle,
                              size: 15,
                              color: AppColors.orangeAccent,
                              strokeWidth: 2,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Guide',
                              style: TextStyle(
                                color: AppColors.offWhite,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),

                // ── Two cards ────────────────────────────────────────────────
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Sender
                      Expanded(
                        child: _ShareCard(
                          icon: HugeIcons.strokeRoundedUpload04,
                          accentColor: AppColors.orangeAccent,
                          label: 'SENDER',
                          title: 'Send Credentials',
                          description:
                              'Share credentials via QR or whole vault over Bluetooth',
                          busy: _senderBusy,
                          actions: [
                            _ShareAction(
                              icon: HugeIcons.strokeRoundedQrCode,
                              label: 'Send via AirShare (QR)',
                              isPrimary: true,
                              onPressed: () => AirShareDialog.show(
                                context,
                                role: AirShareRole.send,
                              ),
                            ),
                            _ShareAction(
                              icon: HugeIcons.strokeRoundedSquareLock02,
                              label: 'Send Vault (Bluetooth)',
                              onPressed: _sendVault,
                            ),
                          ],
                          auxiliaryAction: TextButton.icon(
                            onPressed: _senderBusy ? null : _sendFile,
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedFileKey,
                              size: 13,
                              color: AppColors.textMuted,
                              strokeWidth: 1.6,
                            ),
                            label: const Text(
                              'Send encrypted file instead',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xl),
                      // Receiver
                      Expanded(
                        child: _ShareCard(
                          icon: HugeIcons.strokeRoundedDownload04,
                          accentColor: AppColors.orangeAccent,
                          label: 'RECEIVER',
                          title: 'Receive Credentials',
                          description:
                              'Accept incoming transfers from nearby Firewood devices',
                          busy: _receiverBusy,
                          actions: [
                            _ShareAction(
                              icon: HugeIcons.strokeRoundedQrCode,
                              label: 'Receive via AirShare (QR)',
                              isPrimary: true,
                              onPressed: () => AirShareDialog.show(
                                context,
                                role: AirShareRole.receive,
                              ),
                            ),
                            _ShareAction(
                              icon: HugeIcons.strokeRoundedBluetooth,
                              label: 'Receive Vault (Bluetooth)',
                              onPressed: _receive,
                            ),
                          ],
                          auxiliaryAction: const SizedBox(height: 32),
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
    );
  }
}

// ─── Share Card ───────────────────────────────────────────────────────────────

class _ShareCard extends StatelessWidget {
  final List<List<dynamic>> icon;
  final Color accentColor;
  final String label;
  final String title;
  final String description;
  final bool busy;
  final List<_ShareAction> actions;
  final Widget? auxiliaryAction;

  const _ShareCard({
    required this.icon,
    required this.accentColor,
    required this.label,
    required this.title,
    required this.description,
    required this.busy,
    required this.actions,
    this.auxiliaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceZinc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.borderZinc.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceZinc,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.borderZinc.withValues(alpha: 0.5),
                  ),
                ),
                child: Center(
                  child: HugeIcon(
                    icon: icon,
                    size: 22,
                    color: accentColor,
                    strokeWidth: 2,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.syncopate(
                        color: accentColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.offWhite,
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.orangeAccent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(
              height: 1,
              thickness: 1,
              color: AppColors.borderZinc.withValues(alpha: 0.35),
            ),
          ),
          for (int i = 0; i < actions.length; i++) ...[
            _ShareActionButton(action: actions[i], accentColor: accentColor),
            if (i < actions.length - 1) const SizedBox(height: AppSpacing.sm),
          ],
          if (auxiliaryAction != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Center(child: auxiliaryAction!),
          ],
        ],
      ),
    );
  }
}

// ─── Action data model ────────────────────────────────────────────────────────

class _ShareAction {
  final List<List<dynamic>> icon;
  final String label;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _ShareAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });
}

// ─── Action button ────────────────────────────────────────────────────────────

class _ShareActionButton extends StatelessWidget {
  final _ShareAction action;
  final Color accentColor;

  const _ShareActionButton({required this.action, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    if (action.isPrimary) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: HugeIcon(
            icon: action.icon,
            size: 16,
            color: Colors.black,
            strokeWidth: 2,
          ),
          label: Text(
            action.label,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          onPressed: action.onPressed,
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: HugeIcon(
          icon: action.icon,
          size: 16,
          color: AppColors.offWhite,
          strokeWidth: 1.8,
        ),
        label: Text(
          action.label,
          style: const TextStyle(
            color: AppColors.offWhite,
            fontWeight: FontWeight.w600,
            fontSize: 12.5,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: AppColors.borderZinc.withValues(alpha: 0.75),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        onPressed: action.onPressed,
      ),
    );
  }
}
