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
  String? _sessionToken;

  bool get isListening => _isListening;

  /// Per-session token every bridge command must present (V-002).
  /// Written to `<socket>.token` (0600) for the native host to read.
  String? get sessionToken => _sessionToken;

  /// Private directory for IPC sockets. Never `/tmp`: its world-writable
  /// sticky namespace lets another local user pre-create our socket path and
  /// hijack or deny the bridge (V-023). Returns null when no private
  /// directory is available — the bridge then stays disabled (fail closed).
  static String? get _ipcDir {
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtimeDir != null && Directory(runtimeDir).existsSync()) {
      return runtimeDir; // systemd: mode 0700
    }
    if (Platform.isMacOS) {
      // macOS $TMPDIR is a per-user private (0700) directory.
      final tmp = Platform.environment['TMPDIR'];
      if (tmp != null && Directory(tmp).existsSync()) return tmp;
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    final dir = Directory('$home/.cache/firewood');
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final res = Process.runSync('chmod', ['700', dir.path]);
      return res.exitCode == 0 ? dir.path : null;
    } catch (_) {
      return null;
    }
  }

  static String? get defaultSocketPath {
    final dir = _ipcDir;
    return dir == null ? null : '$dir/firewood-ipc.sock';
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
    if (socketPath == null) {
      // V-002: no private runtime directory → do not expose the bridge.
      return;
    }
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
    } catch (_) {
      _isListening = false;
      return;
    }

    // V-002/V-023: lock down permissions and FAIL CLOSED if we cannot —
    // never continue with an umask-permissive socket.
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final res = await Process.run('chmod', ['600', socketPath]);
        if (res.exitCode != 0) {
          await _server!.close();
          _server = null;
          try {
            socketFile.deleteSync();
          } catch (_) {}
          _isListening = false;
          return;
        }
      } catch (_) {
        await _server!.close();
        _server = null;
        _isListening = false;
        return;
      }
    }

    // V-002: mint a per-session token; every command must present it.
    // The token file lives beside the socket (0600 inside a private dir),
    // where the native host can read it but nothing outside our user can.
    try {
      final rnd = Random.secure();
      final token = List<int>.generate(32, (_) => rnd.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final tokenFile = File('$socketPath.token');
      tokenFile.writeAsStringSync(token, flush: true);
      if (Platform.isLinux || Platform.isMacOS) {
        final res = await Process.run('chmod', ['600', tokenFile.path]);
        if (res.exitCode != 0) throw Exception('chmod token failed');
      }
      _sessionToken = token;
    } catch (_) {
      await _server!.close();
      _server = null;
      try {
        socketFile.deleteSync();
      } catch (_) {}
      _isListening = false;
      return;
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
  }

  /// Stops the IPC server and cleans up socket file
  Future<void> stopServer({String? customSocketPath}) async {
    _isListening = false;
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _server?.close();
    _server = null;
    _sessionToken = null;

    final socketPath = customSocketPath ?? defaultSocketPath;
    if (socketPath == null) return;
    for (final path in [socketPath, '$socketPath.token']) {
      final socketFile = File(path);
      if (socketFile.existsSync()) {
        try {
          socketFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  void _handleClient(
      Socket socket, T Function<T>(ProviderListenable<T>) reader) {
    final buffer = StringBuffer();

    socket.listen(
      (data) async {
        buffer.write(utf8.decode(data));
        final content = buffer.toString();

        // V-048: cap message size — never buffer unbounded input from a
        // socket peer, even one that passed the token check.
        if (content.length > 10 * 1024 * 1024) {
          socket.destroy();
          return;
        }

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

      // V-002: every command must present this session's token. The token
      // file sits inside a private (0700) directory, so only our own user's
      // native host can obtain it; anything else gets a bare refusal.
      if (!_authOk(message['auth']?.toString())) {
        return {'status': 'error', 'error': 'unauthorized'};
      }

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

  /// Constant-time comparison of the presented token against this session's
  /// token (V-002). Returns false for null/empty/wrong-length input.
  bool _authOk(String? presented) {
    final expected = _sessionToken;
    if (expected == null || presented == null || presented.isEmpty) {
      return false;
    }
    if (presented.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= presented.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return diff == 0;
  }

  Map<String, dynamic> _handleStatus(
      T Function<T>(ProviderListenable<T>) reader) {
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

      final itemUrl =
          (item.fields['url'] ?? item.fields['website'] ?? '').toString();
      final itemTitle = item.title;

      if (_matchesDomain(itemUrl, cleanDomain)) {
        final username =
            (item.fields['username'] ?? item.fields['email'] ?? '').toString();
        final password = (item.fields['password'] ?? '').toString();
        final totpSecret =
            (item.fields['totp_secret'] ?? item.fields['totpSecret'] ?? '')
                .toString();

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
        'error':
            'Vault is locked. Unlock Firewood desktop app to save credentials.',
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

  /// Checks if the stored item's URL is the same site as the requested host.
  ///
  /// V-014: strict matching only —
  ///  * the item must have a URL (URL-less items never match),
  ///  * match on exact host equality, or
  ///  * equality of registrable domains (approximate eTLD+1), which covers
  ///    subdomains in BOTH directions without reaching other sites.
  /// Title text is never consulted: a title containing "mail" must not
  /// authorize a fetch of credentials for mail.google.com.
  static bool _matchesDomain(String itemUrl, String targetDomain) {
    if (targetDomain.isEmpty) return false;
    final itemHost = _extractCleanDomain(itemUrl);
    if (itemHost.isEmpty) return false; // no URL stored → no match

    final target = targetDomain.toLowerCase();
    if (itemHost == target) return true;

    final itemReg = _registrableDomain(itemHost);
    final targetReg = _registrableDomain(target);
    if (itemReg.isEmpty || targetReg.isEmpty) return false;
    return itemReg == targetReg;
  }

  /// Approximate registrable domain (eTLD+1) for a host.
  ///
  /// Uses the last two labels, or the last three when the TLD is a
  /// two-letter country code with a common second-level registry label
  /// (github.co.uk → github.co.uk, not co.uk). Pure-numeric hosts (IPv4)
  /// and single-label hosts are returned unchanged so they only ever match
  /// exactly.
  static String _registrableDomain(String host) {
    if (host.isEmpty) return '';
    final labels =
        host.split('.').where((l) => l.isNotEmpty).toList(growable: false);
    if (labels.length <= 2) return host;

    final last = labels[labels.length - 1];
    final isIp = labels.every((l) => int.tryParse(l) != null);
    if (isIp) return host;

    const secondLevelRegistry = {
      'co',
      'com',
      'org',
      'net',
      'gov',
      'ac',
      'edu',
      'mil',
      'nom',
      'web',
    };
    if (last.length == 2 &&
        secondLevelRegistry.contains(labels[labels.length - 2])) {
      return labels.sublist(labels.length - 3).join('.');
    }
    return labels.sublist(labels.length - 2).join('.');
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
      // V-001: pinned to the Firewood extension ID only (derived from
      // firewood-browser-extension/extension_key.pem). A wildcard here would
      // let ANY installed extension query plaintext credentials.
      'allowed_origins': [
        'chrome-extension://ifmolflcokffbmccpbkgeoakmgbpboep/',
      ],
    };

    final firefoxManifest = {
      'name': hostIdentifier,
      'description': 'Firewood Password Manager Native Messaging Host',
      'path': binaryPath,
      'type': 'stdio',
      // Matches browser_specific_settings.gecko.id in manifest.json (V-046).
      'allowed_extensions': [
        'firewood@firewood.security',
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
