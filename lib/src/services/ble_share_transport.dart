// Real Bluetooth Low Energy transport for the desktop app (central role).
//
// The Firewood peer (e.g. the Android app) advertises the Firewood GATT service
// and exposes a single file characteristic. This transport scans for it,
// connects, and streams the encrypted `.firewood` payload in MTU-sized chunks
// using a tiny framing protocol (4-byte total length + 2-byte name length +
// name bytes + payload). Receiving subscribes to characteristic notifications.
//
// On Linux the plugin talks to BlueZ; on macOS/iOS to CoreBluetooth; on
// Windows the winrt implementation is used. When no adapter/backend is present
// isAvailable() returns false and the UI reports the transport as unavailable.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:firewood_core/firewood_core.dart';

class BleShareTransport implements ShareTransport {
  /// GATT service advertised by a Firewood peer (matches Android native UUIDs).
  static final Guid serviceUuid = Guid('0000ff00-0000-1000-8000-00805f9b34fb');

  /// Characteristic carrying the framed file (write + notify).
  static final Guid fileCharUuid = Guid('0000ff01-0000-1000-8000-00805f9b34fb');

  final List<int> _incoming = [];
  BluetoothDevice? _device;
  BluetoothCharacteristic? _char;
  StreamSubscription<List<int>>? _sub;
  bool _listening = false;

  @override
  String get name => 'Bluetooth LE';

  @override
  Future<bool> isAvailable() async {
    try {
      if (!await FlutterBluePlus.isSupported) return false;
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isListening() async => _listening;

  Future<BluetoothDevice> _findPeer(
      {Duration timeout = const Duration(seconds: 12)}) async {
    await FlutterBluePlus.startScan(withServices: [serviceUuid], timeout: timeout);
    final result = await FlutterBluePlus.onScanResults
        .where((r) => r.isNotEmpty)
        .map((r) => r.last)
        .first
        .timeout(timeout);
    await FlutterBluePlus.stopScan();
    return result.device;
  }

  Future<BluetoothCharacteristic> _connectAndDiscover(BluetoothDevice device) async {
    // flutter_blue_plus requires a license declaration. `nonprofit` covers
    // personal/nonprofit use; a commercial license is required for for-profit use.
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 15),
    );
    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid == serviceUuid) {
        for (final c in service.characteristics) {
          if (c.uuid == fileCharUuid) return c;
        }
      }
    }
    throw const ShareException('Firewood BLE service not found on the peer');
  }

  @override
  Future<void> send({required String fileName, required List<int> bytes}) async {
    if (!await isAvailable()) {
      throw const ShareException('Bluetooth is turned off or unavailable');
    }
    final device = await _findPeer();
    final characteristic = await _connectAndDiscover(device);

    final nameBytes = utf8.encode(fileName);
    final header = <int>[
      ..._u32(bytes.length),
      ..._u16(nameBytes.length),
      ...nameBytes,
    ];

    final mtu = device.mtuNow > 23 ? device.mtuNow : 23;
    final chunk = mtu - 3;

    await characteristic.write(header, withoutResponse: false);
    for (var i = 0; i < bytes.length; i += chunk) {
      final end = (i + chunk < bytes.length) ? i + chunk : bytes.length;
      await characteristic.write(bytes.sublist(i, end), withoutResponse: false);
    }

    await device.disconnect();
  }

  @override
  Future<void> startListening() async {
    if (_listening) return;
    if (!await isAvailable()) {
      throw const ShareException('Bluetooth is turned off or unavailable');
    }
    final device = await _findPeer();
    final characteristic = await _connectAndDiscover(device);
    _incoming.clear();
    _sub = characteristic.onValueReceived.listen(_incoming.addAll);
    await characteristic.setNotifyValue(true);
    _device = device;
    _char = characteristic;
    _listening = true;
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _char?.setNotifyValue(false);
    } catch (_) {}
    try {
      await _device?.disconnect();
    } catch (_) {}
    _char = null;
    _device = null;
  }

  @override
  Future<SentFile?> receive() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final parsed = _tryParse();
      if (parsed != null) return parsed;
      await Future.delayed(const Duration(milliseconds: 150));
    }
    return null;
  }

  SentFile? _tryParse() {
    if (_incoming.length < 6) return null;
    final total = (_incoming[0] << 24) |
        (_incoming[1] << 16) |
        (_incoming[2] << 8) |
        _incoming[3];
    final nameLength = (_incoming[4] << 8) | _incoming[5];
    if (_incoming.length < 6 + nameLength + total) return null;
    final name = utf8.decode(_incoming.sublist(6, 6 + nameLength));
    final data = _incoming.sublist(6 + nameLength, 6 + nameLength + total);
    return SentFile(fileName: name, bytes: data);
  }

  @override
  Future<void> dispose() => stopListening();

  List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
  List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
}
