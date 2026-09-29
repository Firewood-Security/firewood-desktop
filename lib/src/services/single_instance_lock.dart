// Strict single-instance enforcement for Firewood Desktop.
// Prevents duplicate processes from competing for database locks, memory, or IPC sockets.
// If an instance is already running, it brings the existing window to the foreground.

import 'dart:convert';
import 'dart:io';
import 'package:window_manager/window_manager.dart';

class SingleInstanceLock {
  SingleInstanceLock._();

  static ServerSocket? _server;

  /// Private directory for the lock socket — mirrors the bridge's
  /// `BrowserBridgeService._ipcDir`. Never `/tmp`: its world-writable
  /// sticky namespace lets another local user pre-create this path and
  /// hijack or deny the lock (V-023).
  static String? get _ipcDir {
    final xdg = Platform.environment['XDG_RUNTIME_DIR'];
    if (xdg != null && Directory(xdg).existsSync()) return xdg; // 0700
    if (Platform.isMacOS) {
      final tmp = Platform.environment['TMPDIR'];
      if (tmp != null && Directory(tmp).existsSync()) return tmp; // 0700
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

  static String? get lockSocketPath {
    final dir = _ipcDir;
    return dir == null ? null : '$dir/firewood-app.sock';
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
    if (sockPath == null) {
      // V-024: without a private runtime directory we cannot guarantee
      // exclusivity — fail closed instead of risking duplicate instances
      // corrupting the database.
      stderr.writeln(
          'Firewood: no private runtime directory for the instance lock — aborting.');
      return false;
    }
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
    ServerSocket server;
    try {
      server = await ServerSocket.bind(
        InternetAddress(sockPath, type: InternetAddressType.unix),
        0,
      );
    } catch (_) {
      // V-024: bind failed — either another instance won the race or the
      // permissions are wrong. Never fail open as "primary": a duplicate
      // instance would corrupt the database.
      stderr
          .writeln('Firewood: could not acquire the instance lock — exiting.');
      return false;
    }
    _server = server;

    // Lock down permissions (0600) — verified, fail closed (V-002/V-023).
    if (Platform.isLinux || Platform.isMacOS) {
      final res = Process.runSync('chmod', ['0600', sockPath]);
      if (res.exitCode != 0) {
        await server.close();
        _server = null;
        try {
          sockFile.deleteSync();
        } catch (_) {}
        return false;
      }
    }

    server.listen((client) {
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
  }

  /// Releases the single-instance lock on shutdown
  static Future<void> release() async {
    await _server?.close();
    _server = null;
    final path = lockSocketPath;
    if (path == null) return;
    final file = File(path);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }
}
