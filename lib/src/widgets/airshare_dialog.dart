import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:cryptography/cryptography.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_design/firewood_design.dart';
import 'package:firewood_ui_desktop/firewood_ui_desktop.dart';

import '../providers.dart';
import '../services/airshare_service.dart';
import '../services/autotype_service.dart';
import '../services/desktop_qr_decoder.dart';
import '../services/secure_clipboard.dart';
import 'animated_qr_display.dart';

enum AirShareRole { send, receive }

/// Modal for Over-The-Air Credential Sharing:
/// Exclusively Local QR P2P (Bootstrap via QR + X25519 + ChaCha20-Poly1305 over Wi-Fi)
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
  late AirShareRole _role;

  // Selected item if sending
  DecryptedItem? _selectedItem;
  List<DecryptedItem> _availableItems = [];
  bool _loadingItems = false;

  // QR state
  String? _sparkUri;
  final TextEditingController _sparkInputController = TextEditingController();

  // Receiver network state
  HttpServer? _receiverServer;

  /// V-005: per-session token the sender must present (x-firewood-token).
  String _sessionToken = '';

  /// V-005: exactly one payload may ever be accepted per listener session.
  bool _transferAccepted = false;

  // Transfer state
  bool _isProcessing = false;
  String _statusMessage = '';
  AirSharePayload? _receivedPayload;
  bool _passwordRevealed = false;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _selectedItem = widget.initialItem;

    _loadVaultItems();

    if (_role == AirShareRole.receive) {
      _initReceiver();
    }
  }

  @override
  void dispose() {
    _sparkInputController.dispose();
    _stopReceiverServer();
    super.dispose();
  }

  Future<void> _stopReceiverServer() async {
    try {
      await _receiverServer?.close(force: true);
    } catch (_) {}
    _receiverServer = null;
  }

  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.')) {
            return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
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
          _selectedItem = widget.initialItem ?? items.first;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  void _switchRole(AirShareRole role) {
    if (_role == role) return;
    setState(() {
      _role = role;
      _statusMessage = '';
      _receivedPayload = null;
    });

    if (role == AirShareRole.receive) {
      _initReceiver();
    } else {
      _stopReceiverServer();
    }
  }

  /// Constant-time comparison of the presented transfer token (V-005).
  static bool _tokensMatch(String a, String b) {
    if (a.isEmpty || a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < b.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _initReceiver() async {
    final airShare = ref.read(airShareServiceProvider);
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Starting local P2P listener…';
    });

    try {
      final keyPair = await airShare.generateKeyPair();
      final pk = await keyPair.extractPublicKey();
      final nonce = airShare.generateNonce(12);

      // V-005: mint a fresh 32-byte session token for this receiver session.
      // It travels only inside the scanned QR (firewood://spark?tkn=…), so a
      // passive LAN sniffer who only sees the POST cannot replay it.
      final rng = Random.secure();
      _sessionToken =
          base64UrlEncode(List<int>.generate(32, (_) => rng.nextInt(256)));
      _transferAccepted = false;

      await _stopReceiverServer();
      // V-022: bind ONLY the address that will be advertised in the QR —
      // never the wildcard, which would expose every NIC (cellular/VPN
      // included). With no LAN the helper returns 127.0.0.1: that loopback
      // listener is unreachable across devices and parseSparkUri filters
      // loopback addresses, so the sender gets an honest "no reachable
      // address" instead of a listener on every interface.
      final localIp = await _getLocalIpAddress();
      _receiverServer = await HttpServer.bind(InternetAddress(localIp), 0);
      final port = _receiverServer!.port;

      _receiverServer!.listen((HttpRequest request) async {
        if (request.method == 'POST') {
          // V-022: exactly one documented endpoint exists. Other POST
          // paths get a generic 404 before any parsing or auth feedback.
          if (request.uri.path != '/airshare/transfer') {
            request.response
              ..statusCode = HttpStatus.notFound
              ..close();
            return;
          }
          // V-005: authenticate the sender — constant-time token compare.
          final provided = request.headers.value('x-firewood-token') ?? '';
          if (!_tokensMatch(provided, _sessionToken)) {
            request.response
              ..statusCode = HttpStatus.unauthorized
              ..write('unauthorized')
              ..close();
            return;
          }

          // V-005: single-shot — first accepted payload wins; everything
          // after it is refused so a second device cannot overwrite or
          // race the accepted credential.
          if (_transferAccepted) {
            request.response
              ..statusCode = HttpStatus.conflict
              ..write('transfer already completed')
              ..close();
            return;
          }
          _transferAccepted = true;

          try {
            // V-022: 64 KB cap, counted while streaming — neither a lying
            // content-length nor chunked encoding can exhaust memory
            // (credentials payloads are a few hundred bytes).
            const maxBodyBytes = 64 * 1024;
            if (request.contentLength > maxBodyBytes) {
              throw const _OversizedBody();
            }
            final builder = <int>[];
            var received = 0;
            await for (final chunk in request) {
              received += chunk.length;
              if (received > maxBodyBytes) {
                throw const _OversizedBody();
              }
              builder.addAll(chunk);
            }
            final content = utf8.decode(builder);
            final data = jsonDecode(content) as Map<String, dynamic>;
            final senderPkBase64 = data['senderPk'] as String;
            final cipherTextBase64 = data['ciphertext'] as String;

            final senderPk = SimplePublicKey(
              base64Url.decode(senderPkBase64),
              type: KeyPairType.x25519,
            );
            final encryptedBytes = base64Decode(cipherTextBase64);

            final secret = await airShare.computeSharedSecret(
              localKeyPair: keyPair,
              remotePublicKey: senderPk,
            );
            final sessionKey = await airShare.deriveSessionKey(
              sharedSecret: secret,
              salt: nonce,
            );

            final payload = await airShare.decryptPayload(
              encryptedBytes: encryptedBytes,
              sessionKey: sessionKey,
            );

            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'ok'}))
              ..close();

            if (!mounted) return;
            setState(() {
              _receivedPayload = payload;
              _statusMessage =
                  'Credential "${payload.title}" received and decrypted in RAM!';
            });
          } on _OversizedBody {
            // Over-limit bodies never consume the single-shot slot.
            _transferAccepted = false;
            request.response
              ..statusCode = HttpStatus.requestEntityTooLarge
              ..write('payload too large')
              ..close();
          } catch (e) {
            // Failed attempt does not consume the single-shot slot.
            _transferAccepted = false;
            // V-042: never echo exception internals to the network peer.
            debugPrint('AirShare receive failed: $e');
            request.response
              ..statusCode = HttpStatus.badRequest
              ..write('bad request')
              ..close();
          }
        } else {
          request.response
            ..statusCode = HttpStatus.methodNotAllowed
            ..close();
        }
      });

      final uri = airShare.createSparkUri(
        publicKey: pk,
        nonce: nonce,
        deviceName: 'Firewood Desktop',
        host: localIp,
        port: port,
        token: _sessionToken,
      );

      if (!mounted) return;
      setState(() {
        _sparkUri = uri;
        _isProcessing = false;
        _statusMessage = 'Listening on $localIp:$port';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Failed to initialize receiver: $e';
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
                content: Text(
                    'QR code captured from image file! Ready to transmit.'),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: AppColors.roseAccent,
                content:
                    Text('No QR code could be detected in the chosen image.'),
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
        const SnackBar(
            content: Text('Please scan or paste the receiver QR URI.')),
      );
      return;
    }

    final airShare = ref.read(airShareServiceProvider);
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Parsing receiver QR parameters…';
    });

    try {
      final parsed = airShare.parseSparkUri(rawUri);
      setState(() => _statusMessage =
          'Performing X25519 key exchange with ${parsed.deviceName}…');

      final senderKp = await airShare.generateKeyPair();
      final secret = await airShare.computeSharedSecret(
        localKeyPair: senderKp,
        remotePublicKey: parsed.publicKey,
      );
      final sessionKey = await airShare.deriveSessionKey(
        sharedSecret: secret,
        salt: parsed.nonce,
      );

      setState(() =>
          _statusMessage = 'Encrypting credential with ChaCha20-Poly1305…');
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

      final senderPk = await senderKp.extractPublicKey();
      final senderPkBase64 = base64UrlEncode(senderPk.bytes);
      final cipherTextBase64 = base64Encode(encrypted);

      if (parsed.host != null && parsed.port != null) {
        setState(() => _statusMessage =
            'Connecting to ${parsed.host}:${parsed.port} over local network…');
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 6);
        final request =
            await client.post(parsed.host!, parsed.port!, '/airshare/transfer');
        request.headers.contentType = ContentType.json;
        // V-005: present the receiver's per-session token from the QR.
        request.headers.set('x-firewood-token', parsed.token ?? '');
        request.write(jsonEncode({
          'senderPk': senderPkBase64,
          'ciphertext': cipherTextBase64,
        }));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
              'Receiver rejected payload: HTTP ${response.statusCode}');
        }
      } else {
        setState(
            () => _statusMessage = 'Transmitting ${encrypted.length} bytes…');
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage =
            'Credential securely transmitted to ${parsed.deviceName}!';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.mintAccent,
          content: Text(
              'Successfully shared "${item.title}" to ${parsed.deviceName}!'),
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
      final title = payload.title.trim();
      final type = payload.data['type']?.toString() ?? 'login';
      final fields = Map<String, dynamic>.from(payload.data)..remove('type');

      final allItems = await ref.read(itemServiceProvider).getAllItems(key);
      DecryptedItem? conflict;
      for (final it in allItems) {
        if (it.title.trim().toLowerCase() == title.toLowerCase()) {
          conflict = it;
          break;
        }
      }

      if (conflict != null && mounted) {
        final resolution = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surfaceZinc,
            title: const Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedAlertCircle,
                  color: AppColors.orangeAccent,
                  size: 20,
                  strokeWidth: 2,
                ),
                SizedBox(width: 10),
                Text(
                  'Credential Conflict',
                  style: TextStyle(color: AppColors.offWhite, fontSize: 16),
                ),
              ],
            ),
            content: Text(
              'An item named "$title" already exists in your vault.\n\nOverride existing, save as copy, or cancel?',
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
              FirewoodButton(
                label: 'Save as Copy',
                variant: FirewoodButtonVariant.secondary,
                height: 36,
                onPressed: () => Navigator.pop(ctx, 'copy'),
              ),
              FirewoodButton(
                label: 'Override',
                variant: FirewoodButtonVariant.primary,
                height: 36,
                onPressed: () => Navigator.pop(ctx, 'override'),
              ),
            ],
          ),
        );

        if (resolution == null || resolution == 'cancel' || !mounted) {
          return;
        }

        if (resolution == 'override') {
          await ref.read(itemServiceProvider).updateItem(
                key: key,
                itemId: conflict.itemId,
                newFields: fields,
                newTitle: title,
              );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.mintAccent,
              content: Text('Overrode existing "$title" with received data.'),
            ),
          );
          Navigator.of(context).pop();
          return;
        } else if (resolution == 'copy') {
          final copyTitle = '$title (Shared)';
          await ref.read(itemServiceProvider).addItem(
                key: key,
                type: type,
                title: copyTitle,
                fields: fields,
              );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.mintAccent,
              content: Text('Saved as "$copyTitle" directly into your vault.'),
            ),
          );
          Navigator.of(context).pop();
          return;
        }
      }

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
        content:
            Text('Auto-typing in ${delay}s. Switch to target application.'),
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
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
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
                padding: const EdgeInsets.all(22),
                child: _receivedPayload != null
                    ? _buildReceivedPayloadView()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Role Switcher: Send vs Receive
                          _buildRoleSelector(),
                          const SizedBox(height: 20),

                          if (_role == AirShareRole.send)
                            _buildSendContent()
                          else
                            _buildReceiveContent(),

                          if (_statusMessage.isNotEmpty) ...[
                            const SizedBox(height: 16),
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
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
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
              icon: HugeIcons.strokeRoundedQrCode,
              size: 20,
              color: AppColors.orangeAccent,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'AirShare',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.orangeAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.orangeAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        'Local QR P2P',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppColors.orangeAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'End-to-end encrypted transfer over local Wi-Fi (X25519 + ChaCha20-Poly1305)',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            onPressed: () => Navigator.of(context).pop(),
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _role == AirShareRole.send
                      ? AppColors.orangeAccent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedUpload04,
                      size: 14,
                      color: _role == AirShareRole.send
                          ? Colors.black
                          : Colors.white70,
                      strokeWidth: 2,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Send',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: _role == AirShareRole.send
                            ? Colors.black
                            : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _switchRole(AirShareRole.receive),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _role == AirShareRole.receive
                      ? AppColors.orangeAccent
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedDownload04,
                      size: 14,
                      color: _role == AirShareRole.receive
                          ? Colors.black
                          : Colors.white70,
                      strokeWidth: 2,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Receive',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: _role == AirShareRole.receive
                            ? Colors.black
                            : Colors.white70,
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

  /// Short user-facing receive state for the pill under the QR.
  /// The verbose "Listening on …" detail stays only in the bottom
  /// status banner, so it is deliberately never shown here.
  String _receivePillStatus() {
    final msg = _statusMessage;
    if (msg.contains('received and decrypted')) return msg;
    if (msg.contains('Failed to initialize receiver')) {
      return 'Receiver error — see details below';
    }
    if (msg.contains('Starting local P2P')) {
      return 'Starting…';
    }
    return 'Ready to receive';
  }

  Widget _buildReceiveContent() {
    return Column(
      children: [
        const Text(
          'Display this QR code to the sender device',
          style: TextStyle(
              fontSize: 13, color: Colors.white70, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Target device must be on the same local network to transmit.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.white38),
        ),
        const SizedBox(height: 16),

        if (_sparkUri != null)
          DesktopAnimatedQrDisplay(
            qrData: _sparkUri!,
            size: 190,
          )
        else
          const SizedBox(
            height: 190,
            child: Center(
                child:
                    CircularProgressIndicator(color: AppColors.orangeAccent)),
          ),
        const SizedBox(height: 14),

        // Live status pill (short receive status only — the verbose
        // "Listening on …" detail lives in the bottom status banner).
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF171A24),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2B3244)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.mintAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _receivePillStatus(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        if (_sparkUri != null)
          TextButton.icon(
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedCopy01,
              size: 13,
              color: Colors.white38,
              strokeWidth: 1.8,
            ),
            label: const Text('Copy QR URI',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _sparkUri!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  duration: Duration(seconds: 2),
                  content: Text('AirShare URI copied to clipboard.'),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSendContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Select Credential
        _buildItemPicker(),
        const SizedBox(height: 16),

        // 2. Select Receiver QR
        const Text(
          'Provide Receiver QR Code',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text('Scan QR Image / Screenshot',
                    style: TextStyle(fontSize: 12)),
                onPressed: _scanQrImageFile,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Color(0xFF2C3242)),
                padding:
                    const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.paste, size: 14),
              label: const Text('Paste', style: TextStyle(fontSize: 12)),
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) {
                  setState(() => _sparkInputController.text = data!.text!);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _sparkInputController,
          style: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'firewood://spark?pk=...&host=...&port=...',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
            filled: true,
            fillColor: const Color(0xFF161922),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2C3242)),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildItemPicker() {
    if (_loadingItems) {
      return const Center(
          child: LinearProgressIndicator(color: AppColors.orangeAccent));
    }

    if (_availableItems.isEmpty) {
      return const Text('No vault items available to share.',
          style: TextStyle(color: Colors.white54, fontSize: 12));
    }

    final selected = _selectedItem ?? _availableItems.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Credential to Share',
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
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
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        it.type.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white38),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (id) {
                if (id != null) {
                  setState(() {
                    _selectedItem =
                        _availableItems.firstWhere((it) => it.itemId == id);
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
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.orangeAccent),
            )
          else
            const Icon(Icons.info_outline,
                size: 16, color: AppColors.orangeAccent),
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
    final username = payload.data['username']?.toString() ??
        payload.data['email']?.toString() ??
        '';
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
            border:
                Border.all(color: AppColors.mintAccent.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: AppColors.mintAccent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Payload successfully received & decrypted in volatile memory!',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
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
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              if (url.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(url,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white38)),
              ],
              const Divider(color: Color(0xFF282F40), height: 24),
              if (username.isNotEmpty) ...[
                const Text('Username / Email',
                    style: TextStyle(fontSize: 10, color: Colors.white38)),
                const SizedBox(height: 2),
                SelectableText(
                  username,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
                const SizedBox(height: 12),
              ],
              if (password.isNotEmpty) ...[
                const Text('Password',
                    style: TextStyle(fontSize: 10, color: Colors.white38)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _passwordRevealed ? password : '••••••••••••••••',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            color: Colors.white),
                      ),
                    ),
                    IconButton(
                      tooltip: _passwordRevealed
                          ? 'Hide password'
                          : 'Reveal password',
                      icon: Icon(
                        _passwordRevealed
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 16,
                        color: Colors.white54,
                      ),
                      onPressed: () => setState(
                          () => _passwordRevealed = !_passwordRevealed),
                    ),
                    IconButton(
                      tooltip: 'Copy password',
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
                label: const Text('Save to Vault',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.mintAccent),
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
                label: const Text('Auto-Type',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orangeAccent),
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
              child: const Text('Receive Another',
                  style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done',
                  style: TextStyle(color: AppColors.orangeAccent)),
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
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          if (_role == AirShareRole.send) ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedSent,
                size: 14,
                color: Colors.black,
                strokeWidth: 2,
              ),
              label: const Text(
                'Transmit Credential',
                style:
                    TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orangeAccent),
              onPressed:
                  _isProcessing || _sparkInputController.text.trim().isEmpty
                      ? null
                      : _sendViaSpark,
            ),
          ],
        ],
      ),
    );
  }
}

/// V-022: signals a request body beyond the 64 KB receiver cap.
class _OversizedBody implements Exception {
  const _OversizedBody();
}
