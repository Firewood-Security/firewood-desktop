// Firewood Password Manager - Native Messaging Host
// Connects Web Extensions (Chrome, Chromium, Brave, Edge, Firefox)
// to the running Firewood Desktop application over a secure Unix Domain Socket.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const String hostIdentifier = 'net.firewood.browser_host';

/// Private IPC directory. Mirrors `BrowserBridgeService._ipcDir` in the
/// desktop app — both sides must agree. Never `/tmp`: world-writable sticky
/// namespace lets another local user pre-create the socket path (V-023).
String? get ipcDir {
  final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
  if (runtimeDir != null && Directory(runtimeDir).existsSync()) {
    return runtimeDir; // systemd: mode 0700
  }
  if (Platform.isMacOS) {
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

String? get defaultSocketPath {
  final dir = ipcDir;
  return dir == null ? null : '$dir/firewood-ipc.sock';
}

/// V-002: read the desktop app's per-session bridge token (0600 file beside
/// the socket, inside the private IPC directory).
String? readBridgeToken(String socketPath) {
  try {
    final f = File('$socketPath.token');
    if (!f.existsSync()) return null;
    final t = f.readAsStringSync().trim();
    return t.isEmpty ? null : t;
  } catch (_) {
    return null;
  }
}

String get defaultHostBinaryPath {
  final home = Platform.environment['HOME'] ?? '';
  return '$home/.local/bin/firewood-native-host';
}

Map<String, String> get browserManifestDirectories {
  final home = Platform.environment['HOME'] ?? '';
  return {
    'Google Chrome': '$home/.config/google-chrome/NativeMessagingHosts',
    'Chromium': '$home/.config/chromium/NativeMessagingHosts',
    'Brave': '$home/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts',
    'Microsoft Edge': '$home/.config/microsoft-edge/NativeMessagingHosts',
    'Mozilla Firefox': '$home/.mozilla/native-messaging-hosts',
  };
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  if (args.contains('--install')) {
    await _installManifests();
    return;
  }

  if (args.contains('--uninstall')) {
    await _uninstallManifests();
    return;
  }

  if (args.contains('--status') || args.contains('--test')) {
    await _checkStatus();
    return;
  }

  // Native Messaging loop via stdio
  await _runNativeMessagingLoop();
}

void _printUsage() {
  stdout.writeln('Firewood Native Messaging Host ($hostIdentifier)');
  stdout.writeln('Usage:');
  stdout.writeln('  firewood-native-host               Run in native messaging stdio mode (invoked by browser)');
  stdout.writeln('  firewood-native-host --install     Install manifests for detected browsers');
  stdout.writeln('  firewood-native-host --uninstall   Remove installed browser manifests');
  stdout.writeln('  firewood-native-host --status      Test IPC connection to Firewood desktop app');
}

Future<void> _installManifests() async {
  stdout.writeln('Installing Firewood Native Messaging Host manifests...');
  final binaryPath = defaultHostBinaryPath;

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

  var count = 0;
  for (final entry in browserManifestDirectories.entries) {
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
      stdout.writeln('  ✓ $browserName: $manifestPath');
      count++;
    } catch (e) {
      stderr.writeln('  ✗ $browserName: Failed ($e)');
    }
  }

  stdout.writeln('Done. Installed $count manifest(s).');
}

Future<void> _uninstallManifests() async {
  stdout.writeln('Uninstalling Firewood Native Messaging Host manifests...');
  var count = 0;
  for (final entry in browserManifestDirectories.entries) {
    final filePath = '${entry.value}/$hostIdentifier.json';
    final file = File(filePath);
    if (file.existsSync()) {
      try {
        file.deleteSync();
        stdout.writeln('  ✓ Removed: $filePath');
        count++;
      } catch (e) {
        stderr.writeln('  ✗ Failed to delete $filePath: $e');
      }
    }
  }
  stdout.writeln('Done. Removed $count manifest(s).');
}

Future<void> _checkStatus() async {
  final socketPath = defaultSocketPath;
  if (socketPath == null) {
    stdout.writeln(
        'Socket Path: unavailable (no private runtime directory)');
    return;
  }
  stdout.writeln('Socket Path: $socketPath');

  try {
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 2),
    );

    final ping = <String, dynamic>{'action': 'ping'};
    final token = readBridgeToken(socketPath);
    if (token != null) ping['auth'] = token;
    socket.write('${jsonEncode(ping)}\n');
    await socket.flush();

    final responseCompleter = Completer<String>();
    final buffer = StringBuffer();

    socket.listen(
      (data) {
        buffer.write(utf8.decode(data));
        if (buffer.toString().contains('\n')) {
          if (!responseCompleter.isCompleted) {
            responseCompleter.complete(buffer.toString().trim());
          }
        }
      },
      onError: (e) {
        if (!responseCompleter.isCompleted) responseCompleter.completeError(e);
      },
      onDone: () {
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(buffer.toString().trim());
        }
      },
    );

    final response = await responseCompleter.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => '{"error":"timed out"}',
    );
    await socket.close();

    stdout.writeln('Connected to Firewood Desktop Application!');
    stdout.writeln('Response: $response');
  } catch (e) {
    stdout.writeln('Firewood Desktop Application is NOT running or unreachable ($e).');
  }
}

/// Standard Chrome / Firefox Native Messaging binary loop over stdin / stdout
Future<void> _runNativeMessagingLoop() async {
  final stdinStream = stdin;

  while (true) {
    // 1. Read 4 bytes of length prefix (32-bit unsigned integer, native endian)
    final lengthBytes = <int>[];
    while (lengthBytes.length < 4) {
      final b = stdinStream.readByteSync();
      if (b == -1) {
        // EOF: Browser closed the native messaging pipe
        return;
      }
      lengthBytes.add(b);
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(lengthBytes));
    final messageLength = byteData.getUint32(0, Endian.host);

    if (messageLength == 0 || messageLength > 10 * 1024 * 1024) {
      // Invalid message size (>10MB safety cap)
      return;
    }

    // 2. Read message payload of length messageLength
    final payloadBytes = <int>[];
    for (var i = 0; i < messageLength; i++) {
      final b = stdinStream.readByteSync();
      if (b == -1) {
        return;
      }
      payloadBytes.add(b);
    }

    final rawJson = utf8.decode(payloadBytes);

    // 3. Dispatch to Firewood Desktop App via Unix Domain Socket
    final responseJson = await _queryDesktopApp(rawJson);

    // 4. Send length-prefixed response to stdout
    final responsePayload = utf8.encode(responseJson);
    final header = ByteData(4)..setUint32(0, responsePayload.length, Endian.host);

    stdout.add(header.buffer.asUint8List());
    stdout.add(responsePayload);
    await stdout.flush();
  }
}

Future<String> _queryDesktopApp(String rawJson) async {
  final socketPath = defaultSocketPath;
  if (socketPath == null) {
    return jsonEncode({
      'status': 'error',
      'error': 'No private runtime directory available for IPC',
    });
  }

  // V-002: attach the desktop app's per-session token before forwarding the
  // browser's request. The app rejects any command presented without it.
  var payload = rawJson;
  final token = readBridgeToken(socketPath);
  if (token != null) {
    try {
      final msg = jsonDecode(rawJson) as Map<String, dynamic>;
      msg['auth'] = token;
      payload = jsonEncode(msg);
    } catch (_) {
      // Malformed request — forwarded as-is; the app rejects it.
    }
  }

  try {
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 2),
    );

    socket.write('$payload\n');
    await socket.flush();

    final completer = Completer<String>();
    final buffer = StringBuffer();

    final sub = socket.listen(
      (data) {
        buffer.write(utf8.decode(data));
        final str = buffer.toString();
        if (str.contains('\n')) {
          if (!completer.isCompleted) {
            completer.complete(str.split('\n').first.trim());
          }
        }
      },
      onError: (err) {
        if (!completer.isCompleted) {
          completer.complete(
            jsonEncode({'status': 'error', 'error': 'Socket error: $err'}),
          );
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(buffer.toString().trim());
        }
      },
      cancelOnError: true,
    );

    final res = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        return jsonEncode({
          'status': 'timeout',
          'error': 'Firewood Desktop application timed out',
        });
      },
    );

    await sub.cancel();
    await socket.close();
    return res.isNotEmpty
        ? res
        : jsonEncode({'status': 'error', 'error': 'Empty response from app'});
  } catch (e) {
    return jsonEncode({
      'status': 'disconnected',
      'error': 'Firewood desktop application is not running. Please open Firewood to autofill.',
    });
  }
}
