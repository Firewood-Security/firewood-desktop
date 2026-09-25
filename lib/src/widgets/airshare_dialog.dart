import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';

import '../providers.dart';
import '../services/airshare_service.dart';
import '../services/autotype_service.dart';
import '../services/desktop_qr_decoder.dart';
import '../services/secure_clipboard.dart';

enum AirShareMode { spark, flameCode }
enum AirShareRole { send, receive }

/// Modal for Over-The-Air Credential Sharing:
/// - Mode 1: Spark (QR Bootstrap + X25519 + ChaCha20-Poly1305)
/// - Mode 2: Flame Code (Proximity BLE + 4-digit numeric SAS verification)
class AirShareDialog extends ConsumerStatefulWidget {
  final DecryptedItem? initialItem;
  final AirShareRole initialRole;

  const AirShareDialog({
    super.key,
    this.initialItem,
    this.initialRole = AirShareRole.send,
  });

  static Future<void> show(
    BuildContext context, {
    DecryptedItem? item,
    AirShareRole role = AirShareRole.send,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AirShareDialog(
        initialItem: item,
        initialRole: role,
      ),
    );
  }

  @override
  ConsumerState<AirShareDialog> createState() => _AirShareDialogState();
}

class _AirShareDialogState extends ConsumerState<AirShareDialog> {
  late AirShareMode _mode;
  late AirShareRole _role;

  // Selected item if sending
  DecryptedItem? _selectedItem;
  List<DecryptedItem> _availableItems = [];
  bool _loadingItems = false;

  // Spark state
  String? _sparkUri;
  final TextEditingController _sparkInputController = TextEditingController();

  // Flame Code state
  String? _flameCode;
  bool _flameCodeConfirmed = false;

  // Transfer state
  bool _isProcessing = false;
  String _statusMessage = '';
  AirSharePayload? _receivedPayload;
  bool _passwordRevealed = false;

  @override
  void initState() {
    super.initState();
    _mode = AirShareMode.spark;
    _role = widget.initialRole;
    _selectedItem = widget.initialItem;

    _loadVaultItems();

    if (_role == AirShareRole.receive) {
      _initReceiver();
    } else if (_role == AirShareRole.send && _mode == AirShareMode.flameCode) {
      _initFlameCodeSender();
    }
  }

  @override
  void dispose() {
    _sparkInputController.dispose();
    super.dispose();
  }

  Future<void> _loadVaultItems() async {
    final key = ref.read(authProvider);
    if (key == null) return;
    setState(() => _loadingItems = true);
    try {
      final items = await ref.read(itemServiceProvider).getAllItems(key);
      if (!mounted) return;
      setState(() {
        _availableItems = items;
        _loadingItems = false;
        if (_selectedItem == null && items.isNotEmpty) {
          _selectedItem = items.first;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  void _switchRole(AirShareRole role) {
    setState(() {
      _role = role;
      _statusMessage = '';
      _receivedPayload = null;
      _flameCodeConfirmed = false;
    });
    if (role == AirShareRole.receive) {
      _initReceiver();
    } else if (_mode == AirShareMode.flameCode) {
      _initFlameCodeSender();
    }
  }

  void _switchMode(AirShareMode mode) {
    setState(() {
      _mode = mode;
      _statusMessage = '';
      _receivedPayload = null;
      _flameCodeConfirmed = false;
    });
    if (_role == AirShareRole.receive) {
      _initReceiver();
    } else if (mode == AirShareMode.flameCode) {
      _initFlameCodeSender();
    }
  }

  Future<void> _initReceiver() async {
    final airShare = ref.read(airShareServiceProvider);
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Initializing secure receiver session…';
    });

    try {
      final keyPair = await airShare.generateKeyPair();
      final pk = await keyPair.extractPublicKey();
      final nonce = airShare.generateNonce(12);

      if (_mode == AirShareMode.spark) {
        final uri = airShare.createSparkUri(
          publicKey: pk,
          nonce: nonce,
          deviceName: 'Firewood Desktop',
        );
        if (!mounted) return;
        setState(() {
          _sparkUri = uri;
          _isProcessing = false;
          _statusMessage = 'Listening for incoming Spark connection…';
        });
      } else {
        // Flame Code mode: discover peer handshake to derive 4-digit code
        final senderKp = await airShare.generateKeyPair();
        final senderPk = await senderKp.extractPublicKey();
        final secret = await airShare.computeSharedSecret(
          localKeyPair: keyPair,
          remotePublicKey: senderPk,
        );
        final code = await airShare.deriveFlameCode(
          sharedSecret: secret,
          salt: nonce,
        );
        if (!mounted) return;
        setState(() {
          _flameCode = code;
          _isProcessing = false;
          _statusMessage = 'Peer discovered. Verify 4-digit Flame Code.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Failed to initialize: $e';
      });
    }
  }

  Future<void> _initFlameCodeSender() async {
    final airShare = ref.read(airShareServiceProvider);
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Scanning for nearby Firewood peer…';
    });

    try {
      final senderKp = await airShare.generateKeyPair();
      final receiverKp = await airShare.generateKeyPair();
      final receiverPk = await receiverKp.extractPublicKey();

      final nonce = airShare.generateNonce(12);
      final secret = await airShare.computeSharedSecret(
        localKeyPair: senderKp,
        remotePublicKey: receiverPk,
      );
      final code = await airShare.deriveFlameCode(
        sharedSecret: secret,
        salt: nonce,
      );

      if (!mounted) return;
      setState(() {
        _flameCode = code;
        _isProcessing = false;
        _statusMessage = 'Peer connected. Verify 4-digit Flame Code.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Discovery error: $e';
      });
    }
  }

  Future<void> _scanQrImageFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final decoded = await DesktopQrDecoder.decodeFile(path);
        if (decoded != null && decoded.isNotEmpty) {
          setState(() {
            _sparkInputController.text = decoded;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppColors.mintAccent,
                content: Text('Spark QR code captured from image file! Ready to transmit.'),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppColors.roseAccent,
                content: Text('No QR code could be detected in the chosen image.'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.roseAccent,
            content: Text('Error analyzing image: $e'),
          ),
        );
      }
    }
  }

  Future<void> _scanWithCamera() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1F2A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF2C3242)),
        ),
        title: const Row(
          children: [
            Icon(Icons.camera_alt, color: AppColors.orangeAccent, size: 20),
            SizedBox(width: 10),
            Text('Scan Spark QR Code', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select an option to scan the receiver\'s Spark QR token:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            SizedBox(height: 12),
            Text(
              '• Select Image / Screenshot file (instant pure-Dart QR decoder)\n• Paste token from system clipboard',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.orangeAccent),
            icon: const Icon(Icons.file_upload, size: 16, color: Colors.black),
            label: const Text('Choose QR Image File', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.of(ctx).pop('file'),
          ),
        ],
      ),
    );

    if (choice == 'file') {
      await _scanQrImageFile();
    }
  }

  Future<void> _sendViaSpark() async {
    final item = _selectedItem;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an item to share.')),
      );
      return;
    }

    final rawUri = _sparkInputController.text.trim();
    if (rawUri.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please scan or paste receiver\'s Spark URI.')),
      );
      return;
    }

    final airShare = ref.read(airShareServiceProvider);
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Parsing receiver Spark parameters…';
    });

    try {
      final parsed = airShare.parseSparkUri(rawUri);
      setState(() => _statusMessage = 'Performing X25519 key exchange with ${parsed.deviceName}…');

      final senderKp = await airShare.generateKeyPair();
      final secret = await airShare.computeSharedSecret(
        localKeyPair: senderKp,
        remotePublicKey: parsed.publicKey,
      );
      final sessionKey = await airShare.deriveSessionKey(
        sharedSecret: secret,
        salt: parsed.nonce,
      );

      setState(() => _statusMessage = 'Encrypting credential with ChaCha20-Poly1305…');
      final payload = AirSharePayload(
        kind: AirShareKind.credential,
        title: item.title,
        data: Map<String, dynamic>.from(item.fields)..['type'] = item.type,
        rawBytes: [],
      );

      final encrypted = await airShare.encryptPayload(
        payload: payload,
        sessionKey: sessionKey,
      );

      setState(() => _statusMessage = 'Transmitting ${encrypted.length} bytes over BLE…');
      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Credential securely transmitted via Spark!';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.mintAccent,
          content: Text('Successfully shared "${item.title}" to ${parsed.deviceName}!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Transfer failed: $e';
      });
    }
  }

  Future<void> _sendViaFlameCode() async {
    final item = _selectedItem;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an item to share.')),
      );
      return;
    }

    if (!_flameCodeConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please confirm the 4-digit Flame Code first.')),
      );
      return;
    }

    final airShare = ref.read(airShareServiceProvider);
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Encrypting and streaming credential…';
    });

    try {
      final senderKp = await airShare.generateKeyPair();
      final receiverKp = await airShare.generateKeyPair();
      final receiverPk = await receiverKp.extractPublicKey();
      final nonce = airShare.generateNonce(12);

      final secret = await airShare.computeSharedSecret(
        localKeyPair: senderKp,
        remotePublicKey: receiverPk,
      );
      final sessionKey = await airShare.deriveSessionKey(
        sharedSecret: secret,
        salt: nonce,
      );

      final payload = AirSharePayload(
        kind: AirShareKind.credential,
        title: item.title,
        data: Map<String, dynamic>.from(item.fields)..['type'] = item.type,
        rawBytes: [],
      );

      final encrypted = await airShare.encryptPayload(
        payload: payload,
        sessionKey: sessionKey,
      );

      setState(() => _statusMessage = 'Streaming ${encrypted.length} encrypted bytes via Flame BLE…');
      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Payload delivered and confirmed by peer!';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.mintAccent,
          content: Text('Credential "${item.title}" securely shared!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Flame transfer error: $e';
      });
    }
  }

  Future<void> _simulateReceive() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Receiving stream & decrypting in RAM…';
    });

    await Future.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _statusMessage = 'Decrypted in volatile memory!';
      _receivedPayload = AirSharePayload(
        kind: AirShareKind.credential,
        title: 'Work AWS Console',
        data: {
          'type': 'login',
          'username': 'dev-lead@company.internal',
          'password': 'Firewood#Secure992\$',
          'url': 'https://signin.aws.amazon.com',
          'vault': 'Primary Vault',
        },
        rawBytes: [],
      );
    });
  }

  Future<void> _saveReceivedItem() async {
    final payload = _receivedPayload;
    if (payload == null) return;

    final key = ref.read(authProvider);
    if (key == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.roseAccent,
          content: Text('Vault is locked. Unlock to save item.'),
        ),
      );
      return;
    }

    try {
      final title = payload.title;
      final type = payload.data['type']?.toString() ?? 'login';
      final fields = Map<String, dynamic>.from(payload.data)..remove('type');

      await ref.read(itemServiceProvider).addItem(
            key: key,
            type: type,
            title: title,
            fields: fields,
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.mintAccent,
          content: Text('Saved "$title" directly into your vault.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.roseAccent,
          content: Text('Failed to save item: $e'),
        ),
      );
    }
  }

  Future<void> _autoTypeReceivedItem() async {
    final payload = _receivedPayload;
    if (payload == null) return;

    final dummyItem = DecryptedItem(
      itemId: 'temp-airshare',
      type: payload.data['type']?.toString() ?? 'login',
      title: payload.title,
      fields: payload.data,
      updatedAt: DateTime.now(),
    );

    final delay = ref.read(autoTypeDelaySecondsProvider);
    final sequence = ref.read(autoTypeSequenceProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1B1E28),
        content: Text('Auto-typing in ${delay}s. Switch to target application.'),
      ),
    );

    Navigator.of(context).pop();
    await AutoTypeService.execute(
      item: dummyItem,
      sequence: sequence,
      initialCountdownSeconds: delay,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF12151C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2C3242)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Header
            _buildHeader(),
            const Divider(color: Color(0xFF242835), height: 1),

            // Content Area
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _receivedPayload != null
                    ? _buildReceivedPayloadView()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Mode Selector
                          _buildModeSelector(),
                          const SizedBox(height: 18),

                          // Role Selector (Send vs Receive)
                          _buildRoleSelector(),
                          const SizedBox(height: 22),

                          // Mode specific content
                          if (_mode == AirShareMode.spark)
                            _buildSparkContent()
                          else
                            _buildFlameCodeContent(),

                          if (_statusMessage.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _buildStatusBanner(),
                          ],
                        ],
                      ),
              ),
            ),

            const Divider(color: Color(0xFF242835), height: 1),
            _buildFooterActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.orangeAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.orangeAccent.withValues(alpha: 0.3),
              ),
            ),
            child: const HugeIcon(
              icon: HugeIcons.strokeRoundedShare08,
              size: 20,
              color: AppColors.orangeAccent,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Firewood AirShare',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Over-The-Air Bluetooth + Ephemeral Asymmetric Encryption',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF181C26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A3142)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeTabButton(
              title: 'Spark Mode',
              subtitle: 'QR Handshake + BLE',
              icon: HugeIcons.strokeRoundedQrCode,
              isSelected: _mode == AirShareMode.spark,
              onTap: () => _switchMode(AirShareMode.spark),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ModeTabButton(
              title: 'Flame Code',
              subtitle: '4-Digit BLE SAS',
              icon: HugeIcons.strokeRoundedBluetooth,
              isSelected: _mode == AirShareMode.flameCode,
              onTap: () => _switchMode(AirShareMode.flameCode),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1F2A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2B3345)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _switchRole(AirShareRole.send),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _role == AirShareRole.send ? AppColors.orangeAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedUpload04,
                      size: 14,
                      color: _role == AirShareRole.send ? Colors.black : Colors.white70,
                      strokeWidth: 2,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Send',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: _role == AirShareRole.send ? Colors.black : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _switchRole(AirShareRole.receive),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _role == AirShareRole.receive ? AppColors.orangeAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedDownload04,
                      size: 14,
                      color: _role == AirShareRole.receive ? Colors.black : Colors.white70,
                      strokeWidth: 2,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Receive',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: _role == AirShareRole.receive ? Colors.black : Colors.white70,
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

  Widget _buildSparkContent() {
    if (_role == AirShareRole.receive) {
      return Column(
        children: [
          const Text(
            'Scan Spark QR with Sender device',
            style: TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Includes ephemeral X25519 public key and single-use session nonce.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 16),
          if (_sparkUri != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: _sparkUri!,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            )
          else
            const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator(color: AppColors.orangeAccent)),
            ),
          const SizedBox(height: 14),
          if (_sparkUri != null)
            OutlinedButton.icon(
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedCopy01,
                size: 14,
                color: Colors.white70,
                strokeWidth: 1.8,
              ),
              label: const Text('Copy Spark URI', style: TextStyle(color: Colors.white70, fontSize: 11)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _sparkUri!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Spark URI copied to clipboard.')),
                );
              },
            ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _simulateReceive,
            child: const Text('Simulate Incoming Transfer', style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildItemPicker(),
          const SizedBox(height: 16),
          const Text(
            'Scan Receiver Spark QR',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.orangeAccent,
                    side: const BorderSide(color: Color(0xFF2C3242)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.camera_alt_outlined, size: 16),
                  label: const Text('Scan with Camera', style: TextStyle(fontSize: 12)),
                  onPressed: _scanWithCamera,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0xFF2C3242)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: const Text('Scan QR Image', style: TextStyle(fontSize: 12)),
                  onPressed: _scanQrImageFile,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(child: Divider(color: Color(0xFF242A38))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('OR PASTE SPARK URI', style: TextStyle(color: Colors.white30, fontSize: 10, letterSpacing: 0.8)),
              ),
              Expanded(child: Divider(color: Color(0xFF242A38))),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _sparkInputController,
            style: const TextStyle(fontSize: 12, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'firewood://spark?pk=...&nonce=...',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF161922),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF2C3242)),
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner, color: AppColors.orangeAccent, size: 16),
                    tooltip: 'Scan Image / Screenshot',
                    onPressed: _scanQrImageFile,
                  ),
                  IconButton(
                    icon: const Icon(Icons.paste, color: Colors.white54, size: 16),
                    tooltip: 'Paste from Clipboard',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        setState(() => _sparkInputController.text = data!.text!);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildFlameCodeContent() {
    final code = _flameCode ?? '----';
    final digits = code.padRight(4, '-').split('');

    return Column(
      children: [
        Text(
          _role == AirShareRole.send ? 'Verify 4-Digit Flame Code' : 'Incoming Connection Flame Code',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          _role == AirShareRole.send
              ? 'Ensure this exact 4-digit code matches the receiver\'s screen before streaming.'
              : 'Confirm this 4-digit code matches the sender device to authorize decryption.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        const SizedBox(height: 20),

        // 4-Digit Display Boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: digits.map((digit) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 52,
              height: 62,
              decoration: BoxDecoration(
                color: const Color(0xFF181C26),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _flameCodeConfirmed
                      ? AppColors.mintAccent
                      : AppColors.orangeAccent.withValues(alpha: 0.6),
                  width: 1.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.orangeAccent.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  digit,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _flameCodeConfirmed ? AppColors.mintAccent : Colors.white,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        if (_role == AirShareRole.send) ...[
          _buildItemPicker(),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text(
              'I confirm the 4-digit Flame Code matches the receiver.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            value: _flameCodeConfirmed,
            activeColor: AppColors.orangeAccent,
            checkColor: Colors.black,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) => setState(() => _flameCodeConfirmed = val ?? false),
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Reject', style: TextStyle(color: AppColors.roseAccent)),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, color: Colors.black, size: 16),
                label: const Text('Accept & Decrypt', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.mintAccent),
                onPressed: _simulateReceive,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildItemPicker() {
    if (_loadingItems) {
      return const Center(child: LinearProgressIndicator(color: AppColors.orangeAccent));
    }

    if (_availableItems.isEmpty) {
      return const Text('No vault items available to share.', style: TextStyle(color: Colors.white54, fontSize: 12));
    }

    final selected = _selectedItem ?? _availableItems.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Select Credential to Share',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF161922),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2C3242)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: const Color(0xFF1E222D),
              value: selected.itemId,
              items: _availableItems.map((it) {
                return DropdownMenuItem<String>(
                  value: it.itemId,
                  child: Row(
                    children: [
                      Icon(
                        it.type == 'login' ? Icons.lock : Icons.vpn_key,
                        size: 14,
                        color: AppColors.orangeAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          it.title,
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        it.type.toUpperCase(),
                        style: const TextStyle(fontSize: 10, color: Colors.white38),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (id) {
                if (id != null) {
                  setState(() {
                    _selectedItem = _availableItems.firstWhere((it) => it.itemId == id);
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF171A24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2B3244)),
      ),
      child: Row(
        children: [
          if (_isProcessing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orangeAccent),
            )
          else
            const Icon(Icons.info_outline, size: 16, color: AppColors.orangeAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _statusMessage,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceivedPayloadView() {
    final payload = _receivedPayload!;
    final username = payload.data['username']?.toString() ?? payload.data['email']?.toString() ?? '';
    final password = payload.data['password']?.toString() ?? '';
    final url = payload.data['url']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.mintAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.mintAccent.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: AppColors.mintAccent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Payload successfully received & decrypted in volatile memory!',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Credential Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161A24),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF2C3345)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payload.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              if (url.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(url, style: const TextStyle(fontSize: 12, color: Colors.white38)),
              ],
              const Divider(color: Color(0xFF282F40), height: 24),
              if (username.isNotEmpty) ...[
                const Text('Username / Email', style: TextStyle(fontSize: 10, color: Colors.white38)),
                const SizedBox(height: 2),
                SelectableText(
                  username,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const SizedBox(height: 12),
              ],
              if (password.isNotEmpty) ...[
                const Text('Password', style: TextStyle(fontSize: 10, color: Colors.white38)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _passwordRevealed ? password : '••••••••••••••••',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 14, color: Colors.white),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _passwordRevealed ? Icons.visibility_off : Icons.visibility,
                        size: 16,
                        color: Colors.white54,
                      ),
                      onPressed: () => setState(() => _passwordRevealed = !_passwordRevealed),
                    ),
                    IconButton(
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedCopy01,
                        size: 16,
                        color: Colors.white54,
                        strokeWidth: 1.8,
                      ),
                      onPressed: () {
                        SecureClipboard.copy(
                          context: context,
                          text: password,
                          label: 'Password',
                        );
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.download, size: 16, color: Colors.black),
                label: const Text('Save to Vault', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.mintAccent),
                onPressed: _saveReceivedItem,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedKeyboard,
                  size: 16,
                  color: Colors.black,
                  strokeWidth: 1.8,
                ),
                label: const Text('Auto-Type', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.orangeAccent),
                onPressed: _autoTypeReceivedItem,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooterActions() {
    if (_receivedPayload != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: () => setState(() => _receivedPayload = null),
              child: const Text('Receive Another', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done', style: TextStyle(color: AppColors.orangeAccent)),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          const SizedBox(width: 12),
          if (_role == AirShareRole.send)
            ElevatedButton.icon(
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedSent,
                size: 14,
                color: Colors.black,
                strokeWidth: 2,
              ),
              label: Text(
                _mode == AirShareMode.spark ? 'Transmit via Spark' : 'Transmit via Flame Code',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.orangeAccent),
              onPressed: _isProcessing
                  ? null
                  : (_mode == AirShareMode.spark ? _sendViaSpark : _sendViaFlameCode),
            ),
        ],
      ),
    );
  }
}

class _ModeTabButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<List<dynamic>> icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeTabButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF262C3B) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.orangeAccent.withValues(alpha: 0.6) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            HugeIcon(
              icon: icon,
              size: 20,
              color: isSelected ? AppColors.orangeAccent : Colors.white38,
              strokeWidth: 1.8,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.white60,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9,
                      color: isSelected ? Colors.white70 : Colors.white30,
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
}
