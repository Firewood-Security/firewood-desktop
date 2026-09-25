// Strict single-instance enforcement for Firewood Desktop.
// Prevents duplicate processes from competing for database locks, memory, or IPC sockets.
// If an instance is already running, it brings the existing window to the foreground.

import 'dart:convert';
import 'dart:io';
import 'package:window_manager/window_manager.dart';

class SingleInstanceLock {
  SingleInstanceLock._();

  static ServerSocket? _server;

  static String get lockSocketPath {
    final xdg = Platform.environment['XDG_RUNTIME_DIR'];
    if (xdg != null && Directory(xdg).existsSync()) {
      return '$xdg/firewood-app.sock';
    }
    final uid = Platform.environment['USER'] ?? 'user';
    return '/tmp/firewood-$uid-app.sock';
  }

  /// Attempts to acquire the single-instance lock.
  ///
  /// Returns `true` if this is the primary instance and startup should continue.
  /// Returns `false` if another instance is already running (after requesting it to focus).
  static Future<bool> acquireOrFocus() async {
    if (!Platform.isLinux && !Platform.isMacOS) {
      // Unix domain sockets for Linux/macOS
      return true;
    }

    final sockPath = lockSocketPath;
    final sockFile = File(sockPath);

    if (sockFile.existsSync()) {
      try {
        final client = await Socket.connect(
          InternetAddress(sockPath, type: InternetAddressType.unix),
          0,
          timeout: const Duration(milliseconds: 350),
        );

        // Connected to running instance – ask it to focus
        client.write('${jsonEncode({'action': 'focus'})}\n');
        await client.flush();
        await client.close();
        return false;
      } catch (_) {
        // Stale socket from ungraceful shutdown
        try {
          sockFile.deleteSync();
        } catch (_) {}
      }
    }

    // Bind server socket for this instance
    try {
      _server = await ServerSocket.bind(
        InternetAddress(sockPath, type: InternetAddressType.unix),
        0,
      );

      // Lock down permissions (0600)
      try {
        Process.runSync('chmod', ['0600', sockPath]);
      } catch (_) {}

      _server?.listen((client) {
        client.listen((data) async {
          try {
            final raw = utf8.decode(data).trim();
            final msg = jsonDecode(raw) as Map<String, dynamic>;
            if (msg['action'] == 'focus') {
              await windowManager.show();
              await windowManager.focus();
              if (await windowManager.isMinimized()) {
                await windowManager.restore();
              }
            }
          } catch (_) {}
          try {
            client.destroy();
          } catch (_) {}
        });
      });

      return true;
    } catch (_) {
      return true;
    }
  }

  /// Releases the single-instance lock on shutdown
  static Future<void> release() async {
    await _server?.close();
    _server = null;
    final file = File(lockSocketPath);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }
}
