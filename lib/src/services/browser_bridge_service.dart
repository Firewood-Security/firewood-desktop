// Browser Native Messaging Host IPC Bridge & Autofill Service
// Establishes a zero-knowledge local Unix Domain Socket (UDS) server
// for native messaging hosts (Chrome, Firefox, Brave, Edge).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:otp/otp.dart';
import 'package:window_manager/window_manager.dart';
import 'package:firewood_core/firewood_core.dart';

import '../providers.dart';

class BrowserBridgeService {
  ServerSocket? _server;
  StreamSubscription<Socket>? _serverSubscription;
  bool _isListening = false;

  bool get isListening => _isListening;

  static String get defaultSocketPath {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtimeDir != null && Directory(runtimeDir).existsSync()) {
      return '$runtimeDir/firewood-ipc.sock';
    }
    final user = Platform.environment['USER'] ?? 'user';
    return '/tmp/firewood-ipc-$user.sock';
  }

  static String get defaultHostBinaryPath {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.local/bin/firewood-native-host';
  }

  /// Starts the IPC Unix Domain Socket server
  Future<void> startServer({
    required T Function<T>(ProviderListenable<T>) reader,
    String? customSocketPath,
  }) async {
    if (_isListening) return;

    final socketPath = customSocketPath ?? defaultSocketPath;
    final socketFile = File(socketPath);

    // Clean up stale socket file if it exists
    if (socketFile.existsSync()) {
      try {
        final probe = await Socket.connect(
          InternetAddress(socketPath, type: InternetAddressType.unix),
          0,
          timeout: const Duration(milliseconds: 300),
        );
        // Another instance is actively listening!
        await probe.close();
        return;
      } catch (_) {
        // Socket file exists but nobody is listening: safe to remove
        try {
          socketFile.deleteSync();
        } catch (_) {}
      }
    }

    try {
      _server = await ServerSocket.bind(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );

      // Enforce 0600 permissions on the created socket
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          await Process.run('chmod', ['600', socketPath]);
        } catch (_) {}
      }

      _isListening = true;

      _serverSubscription = _server!.listen(
        (socket) => _handleClient(socket, reader),
        onError: (err) {
          _isListening = false;
        },
        onDone: () {
          _isListening = false;
        },
      );
    } catch (_) {
      _isListening = false;
    }
  }

  /// Stops the IPC server and cleans up socket file
  Future<void> stopServer({String? customSocketPath}) async {
    _isListening = false;
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _server?.close();
    _server = null;

    final socketPath = customSocketPath ?? defaultSocketPath;
    final socketFile = File(socketPath);
    if (socketFile.existsSync()) {
      try {
        socketFile.deleteSync();
      } catch (_) {}
    }
  }

  void _handleClient(Socket socket, T Function<T>(ProviderListenable<T>) reader) {
    final buffer = StringBuffer();

    socket.listen(
      (data) async {
        buffer.write(utf8.decode(data));
        final content = buffer.toString();

        if (content.contains('\n')) {
          final lines = content.split('\n');
          // Keep trailing remainder in buffer
          buffer.clear();
          buffer.write(lines.last);

          for (var i = 0; i < lines.length - 1; i++) {
            final line = lines[i].trim();
            if (line.isEmpty) continue;

            final response = await _dispatchCommand(line, reader);
            socket.write('${jsonEncode(response)}\n');
            await socket.flush();
          }
        }
      },
      onError: (err) {
        socket.destroy();
      },
      onDone: () {
        socket.destroy();
      },
      cancelOnError: true,
    );
  }

  Future<Map<String, dynamic>> _dispatchCommand(
    String rawJson,
    T Function<T>(ProviderListenable<T>) reader,
  ) async {
    try {
      final message = jsonDecode(rawJson) as Map<String, dynamic>;
      final action = message['action']?.toString() ?? 'ping';

      switch (action) {
        case 'ping':
        case 'status':
          return _handleStatus(reader);

        case 'focus':
        case 'show':
          try {
            await windowManager.show();
            await windowManager.focus();
            if (await windowManager.isMinimized()) {
              await windowManager.restore();
            }
          } catch (_) {}
          return {'status': 'ok', 'action': 'focused'};

        case 'query_credentials':
        case 'get_credentials':
          return await _handleQueryCredentials(message, reader);

        case 'save_credential':
        case 'add_credential':
          return await _handleSaveCredential(message, reader);

        case 'generate_password':
          return _handleGeneratePassword(message);

        default:
          return {
            'status': 'error',
            'error': 'Unknown action: $action',
          };
      }
    } catch (e) {
      return {
        'status': 'error',
        'error': 'Failed to process request: $e',
      };
    }
  }

  Map<String, dynamic> _handleStatus(T Function<T>(ProviderListenable<T>) reader) {
    final key = reader(authProvider);
    final isUnlocked = key != null;

    return {
      'status': 'ok',
      'app': 'Firewood Desktop',
      'version': '1.0.0',
      'unlocked': isUnlocked,
      'protocol_version': 1,
    };
  }

  Future<Map<String, dynamic>> _handleQueryCredentials(
    Map<String, dynamic> message,
    T Function<T>(ProviderListenable<T>) reader,
  ) async {
    final key = reader(authProvider);
    if (key == null) {
      return {
        'status': 'locked',
        'error': 'Vault is locked. Unlock Firewood desktop app to autofill.',
      };
    }

    final requestedUrl = message['url']?.toString() ?? '';
    final requestedDomain = message['domain']?.toString() ?? '';

    if (requestedUrl.isEmpty && requestedDomain.isEmpty) {
      return {
        'status': 'error',
        'error': 'Missing url or domain parameter',
      };
    }

    final cleanDomain = _extractCleanDomain(
      requestedDomain.isNotEmpty ? requestedDomain : requestedUrl,
    );

    final itemService = reader(itemServiceProvider);
    final allItems = await itemService.getAllItems(key);

    final matchingCredentials = <Map<String, dynamic>>[];

    for (final item in allItems) {
      if (item.type != ItemType.login.label && item.type != 'login') {
        continue;
      }

      final itemUrl = (item.fields['url'] ?? item.fields['website'] ?? '').toString();
      final itemTitle = item.title;

      if (_matchesDomain(itemUrl, itemTitle, cleanDomain)) {
        final username = (item.fields['username'] ?? item.fields['email'] ?? '').toString();
        final password = (item.fields['password'] ?? '').toString();
        final totpSecret = (item.fields['totp_secret'] ?? item.fields['totpSecret'] ?? '').toString();

        String? liveTotp;
        if (totpSecret.trim().isNotEmpty) {
          try {
            final now = DateTime.now().millisecondsSinceEpoch;
            liveTotp = OTP.generateTOTPCodeString(
              totpSecret.trim().replaceAll(' ', '').toUpperCase(),
              now,
              length: 6,
              interval: 30,
              algorithm: Algorithm.SHA1,
              isGoogle: true,
            );
          } catch (_) {}
        }

        matchingCredentials.add({
          'id': item.itemId,
          'title': itemTitle,
          'username': username,
          'password': password,
          'totp': liveTotp ?? '',
          'url': itemUrl,
        });
      }
    }

    return {
      'status': 'success',
      'query': cleanDomain,
      'credentials': matchingCredentials,
    };
  }

  Future<Map<String, dynamic>> _handleSaveCredential(
    Map<String, dynamic> message,
    T Function<T>(ProviderListenable<T>) reader,
  ) async {
    final key = reader(authProvider);
    if (key == null) {
      return {
        'status': 'locked',
        'error': 'Vault is locked. Unlock Firewood desktop app to save credentials.',
      };
    }

    final title = (message['title'] ?? '').toString().trim();
    final url = (message['url'] ?? '').toString().trim();
    final username = (message['username'] ?? '').toString().trim();
    final password = (message['password'] ?? '').toString();
    final totpSecret = (message['totp_secret'] ?? '').toString().trim();

    final effectiveTitle = title.isNotEmpty
        ? title
        : (_extractCleanDomain(url).isNotEmpty
            ? _extractCleanDomain(url)
            : 'New Login');

    final itemService = reader(itemServiceProvider);

    final fields = <String, dynamic>{
      'username': username,
      'password': password,
      'url': url,
    };
    if (totpSecret.isNotEmpty) {
      fields['totp_secret'] = totpSecret;
    }

    try {
      final itemId = await itemService.addItem(
        key: key,
        type: ItemType.login.label,
        title: effectiveTitle,
        fields: fields,
      );

      return {
        'status': 'success',
        'id': itemId,
        'title': effectiveTitle,
      };
    } catch (e) {
      return {
        'status': 'error',
        'error': 'Failed to save credential: $e',
      };
    }
  }

  Map<String, dynamic> _handleGeneratePassword(Map<String, dynamic> message) {
    final length = (message['length'] as num?)?.toInt() ?? 20;
    final useSymbols = message['symbols'] as bool? ?? true;
    final useNumbers = message['numbers'] as bool? ?? true;
    final useUpper = message['uppercase'] as bool? ?? true;
    final useLower = message['lowercase'] as bool? ?? true;

    const lowerChars = 'abcdefghjkmnpqrstuvwxyz';
    const upperChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const numberChars = '23456789';
    const symbolChars = '!@#\$%^&*()-_=+[]{}|;:,.<>?';

    var pool = '';
    if (useLower) pool += lowerChars;
    if (useUpper) pool += upperChars;
    if (useNumbers) pool += numberChars;
    if (useSymbols) pool += symbolChars;

    if (pool.isEmpty) pool = lowerChars + upperChars + numberChars;

    final rand = Random.secure();
    final chars = List.generate(
      length,
      (_) => pool[rand.nextInt(pool.length)],
    );

    return {
      'status': 'success',
      'password': chars.join(),
    };
  }

  /// Cleans domains and URLs to eTLD or host (e.g. https://login.github.com/auth -> github.com)
  static String _extractCleanDomain(String input) {
    var s = input.trim().toLowerCase();
    if (s.isEmpty) return '';

    // Strip scheme
    if (s.contains('://')) {
      s = s.substring(s.indexOf('://') + 3);
    }

    // Strip path and query
    if (s.contains('/')) {
      s = s.substring(0, s.indexOf('/'));
    }
    if (s.contains('?')) {
      s = s.substring(0, s.indexOf('?'));
    }
    if (s.contains(':')) {
      s = s.substring(0, s.indexOf(':'));
    }

    // Strip common prefixes
    if (s.startsWith('www.')) {
      s = s.substring(4);
    }

    return s;
  }

  /// Checks if stored item's URL or title matches the requested target domain
  static bool _matchesDomain(String itemUrl, String itemTitle, String targetDomain) {
    if (targetDomain.isEmpty) return false;

    final cleanItemDomain = _extractCleanDomain(itemUrl);
    final cleanTitle = itemTitle.trim().toLowerCase();
    final cleanTarget = targetDomain.toLowerCase();

    // Exact domain match
    if (cleanItemDomain == cleanTarget) return true;

    // Subdomain match: item is github.com, target is auth.github.com
    if (cleanTarget.endsWith('.$cleanItemDomain')) return true;

    // Reverse subdomain: item is auth.github.com, target is github.com
    if (cleanItemDomain.endsWith('.$cleanTarget')) return true;

    // Title contains target or target contains title (e.g. Title "GitHub", Target "github.com")
    final targetBase = cleanTarget.contains('.')
        ? cleanTarget.substring(0, cleanTarget.indexOf('.'))
        : cleanTarget;

    if (targetBase.length >= 3) {
      if (cleanTitle == targetBase || cleanTitle.contains(targetBase)) {
        return true;
      }
    }

    return false;
  }

  // --- Browser Native Messaging Manifest Management ---

  static const String hostIdentifier = 'net.firewood.browser_host';

  static Map<String, String> get browserManifestDirectories {
    final home = Platform.environment['HOME'] ?? '';
    return {
      'Google Chrome': '$home/.config/google-chrome/NativeMessagingHosts',
      'Chromium': '$home/.config/chromium/NativeMessagingHosts',
      'Brave': '$home/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts',
      'Microsoft Edge': '$home/.config/microsoft-edge/NativeMessagingHosts',
      'Mozilla Firefox': '$home/.mozilla/native-messaging-hosts',
    };
  }

  /// Installs Native Messaging manifests for detected desktop browsers
  static Future<List<String>> installManifests({String? customHostPath}) async {
    final binaryPath = customHostPath ?? defaultHostBinaryPath;
    final installedPaths = <String>[];

    final chromeManifest = {
      'name': hostIdentifier,
      'description': 'Firewood Password Manager Native Messaging Host',
      'path': binaryPath,
      'type': 'stdio',
      'allowed_origins': [
        'chrome-extension://*/',
      ],
    };

    final firefoxManifest = {
      'name': hostIdentifier,
      'description': 'Firewood Password Manager Native Messaging Host',
      'path': binaryPath,
      'type': 'stdio',
      'allowed_extensions': [
        'firewood-extension@firewood.security',
        'firewood@firewood.net',
      ],
    };

    final dirs = browserManifestDirectories;

    for (final entry in dirs.entries) {
      final browserName = entry.key;
      final dirPath = entry.value;

      try {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }

        final manifestPath = '$dirPath/$hostIdentifier.json';
        final isFirefox = browserName.contains('Firefox');
        final content = isFirefox ? firefoxManifest : chromeManifest;

        final file = File(manifestPath);
        file.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(content),
          flush: true,
        );
        installedPaths.add('$browserName ($manifestPath)');
      } catch (_) {}
    }

    return installedPaths;
  }

  /// Removes Native Messaging manifests
  static Future<List<String>> uninstallManifests() async {
    final removed = <String>[];
    for (final entry in browserManifestDirectories.entries) {
      final filePath = '${entry.value}/$hostIdentifier.json';
      final file = File(filePath);
      if (file.existsSync()) {
        try {
          file.deleteSync();
          removed.add('${entry.key} ($filePath)');
        } catch (_) {}
      }
    }
    return removed;
  }

  /// Returns map of browser name -> manifest exists
  static Future<Map<String, bool>> getManifestStatus() async {
    final status = <String, bool>{};
    for (final entry in browserManifestDirectories.entries) {
      final filePath = '${entry.value}/$hostIdentifier.json';
      status[entry.key] = File(filePath).existsSync();
    }
    return status;
  }
}
