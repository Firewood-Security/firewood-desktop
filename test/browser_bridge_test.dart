// Unit & integration tests for BrowserBridgeService & Native Messaging IPC

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:firewood_core/firewood_core.dart';
import 'package:firewood_desktop/src/providers.dart';
import 'package:firewood_desktop/src/services/browser_bridge_service.dart';

class _FakeSecretStore implements SecretStore {
  StoredVault? _vault;
  final List<StoredItem> _items = [];

  @override
  Future<StoredVault?> getVault() async => _vault;

  @override
  Future<void> putVault(StoredVault vault) async {
    _vault = vault;
  }

  @override
  Future<void> deleteVault() async {
    _vault = null;
  }

  @override
  Future<List<StoredItem>> getItems() async => List.unmodifiable(_items);

  @override
  Future<StoredItem?> getItem(String itemId) async {
    try {
      return _items.firstWhere((i) => i.itemId == itemId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> putItem(StoredItem item) async {
    _items.removeWhere((i) => i.itemId == item.itemId);
    _items.add(item);
  }

  @override
  Future<void> deleteItem(String itemId) async {
    _items.removeWhere((i) => i.itemId == itemId);
  }

  @override
  Future<void> clearAll() async {
    _vault = null;
    _items.clear();
  }

  @override
  Future<List<StoredBurner>> getBurners() async => [];

  @override
  Future<void> putBurner(StoredBurner burner) async {}

  @override
  Future<void> deleteBurner(int id) async {}
}

void main() {
  group('BrowserBridgeService', () {
    late String tempSocketPath;
    late ProviderContainer container;
    late _FakeSecretStore fakeStore;

    setUp(() {
      tempSocketPath = '${Directory.systemTemp.path}/test-firewood-ipc-${DateTime.now().millisecondsSinceEpoch}.sock';
      fakeStore = _FakeSecretStore();
      container = ProviderContainer(
        overrides: [
          secretStoreProvider.overrideWithValue(fakeStore),
        ],
      );
    });

    tearDown(() async {
      final bridge = container.read(browserBridgeServiceProvider);
      await bridge.stopServer(customSocketPath: tempSocketPath);
      container.dispose();
      final f = File(tempSocketPath);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    });

    test('starts server and responds to ping', () async {
      final bridge = container.read(browserBridgeServiceProvider);
      await bridge.startServer(reader: container.read, customSocketPath: tempSocketPath);
      expect(bridge.isListening, isTrue);

      final socket = await Socket.connect(
        InternetAddress(tempSocketPath, type: InternetAddressType.unix),
        0,
      );

      final completer = Completer<String>();
      final buffer = StringBuffer();
      socket.listen((data) {
        buffer.write(utf8.decode(data));
        if (buffer.toString().contains('\n')) {
          completer.complete(buffer.toString().trim());
        }
      });

      socket.write('{"action":"ping"}\n');
      await socket.flush();

      final resStr = await completer.future.timeout(const Duration(seconds: 2));
      final res = jsonDecode(resStr) as Map<String, dynamic>;

      expect(res['status'], equals('ok'));
      expect(res['app'], equals('Firewood Desktop'));
      expect(res['unlocked'], isFalse);

      await socket.close();
      await bridge.stopServer(customSocketPath: tempSocketPath);
    });

    test('query_credentials returns locked when vault is not unlocked', () async {
      final bridge = container.read(browserBridgeServiceProvider);
      await bridge.startServer(reader: container.read, customSocketPath: tempSocketPath);

      final socket = await Socket.connect(
        InternetAddress(tempSocketPath, type: InternetAddressType.unix),
        0,
      );

      final completer = Completer<String>();
      socket.listen((data) {
        completer.complete(utf8.decode(data).trim());
      });

      socket.write('{"action":"query_credentials","url":"https://github.com/login"}\n');
      await socket.flush();

      final resStr = await completer.future.timeout(const Duration(seconds: 2));
      final res = jsonDecode(resStr) as Map<String, dynamic>;

      expect(res['status'], equals('locked'));
      await socket.close();
      await bridge.stopServer(customSocketPath: tempSocketPath);
    });

    test('generate_password produces requested length', () async {
      final bridge = container.read(browserBridgeServiceProvider);
      await bridge.startServer(reader: container.read, customSocketPath: tempSocketPath);

      final socket = await Socket.connect(
        InternetAddress(tempSocketPath, type: InternetAddressType.unix),
        0,
      );

      final completer = Completer<String>();
      socket.listen((data) {
        completer.complete(utf8.decode(data).trim());
      });

      socket.write('{"action":"generate_password","length":28}\n');
      await socket.flush();

      final resStr = await completer.future.timeout(const Duration(seconds: 2));
      final res = jsonDecode(resStr) as Map<String, dynamic>;

      expect(res['status'], equals('success'));
      expect((res['password'] as String).length, equals(28));

      await socket.close();
      await bridge.stopServer(customSocketPath: tempSocketPath);
    });

    test('manifest install and status detection', () async {
      final statusBefore = await BrowserBridgeService.getManifestStatus();
      expect(statusBefore, isNotNull);

      final installed = await BrowserBridgeService.installManifests(
        customHostPath: '/usr/local/bin/firewood-native-host',
      );
      expect(installed, isNotEmpty);

      final statusAfter = await BrowserBridgeService.getManifestStatus();
      expect(statusAfter.values.any((exists) => exists), isTrue);

      final removed = await BrowserBridgeService.uninstallManifests();
      expect(removed, isNotEmpty);
    });
  });
}
